/****************************************************************************
**
** Copyright (C) 2019 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the repo tools module of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:GPL-EXCEPT$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 as published by the Free Software
** Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"
)

// PendingUpdate describes that a module needs an updated dependencies.yaml and we are waiting for the change
// to succeed/fail
type PendingUpdate struct {
	Module              *Module
	ChangeID            string
	CommitID            OID
	IntegrationAttempts int
}

// ModuleUpdateBatch is used to serialize and de-serialize the module updating state, used for debugging.
type ModuleUpdateBatch struct {
	Product           string
	ProductRef        string
	Branch            string
	Todo              map[string]*Module
	Done              map[string]*Module
	Pending           []*PendingUpdate
	FailedModuleCount int
}

func newModuleUpdateBatch(product string, branch string, productRef string) (*ModuleUpdateBatch, error) {
	batch := &ModuleUpdateBatch{
		Product:    product,
		ProductRef: productRef,
		Branch:     branch,
	}
	var err error

	err = batch.loadStateFromCommit()
	if os.IsNotExist(err) {
		err = batch.loadTodoList()
		if err != nil {
			return nil, err
		}
	}
	return batch, nil
}

func (batch *ModuleUpdateBatch) scheduleUpdates(gerrit *gerritInstance) error {
	for _, moduleToUpdate := range batch.Todo {
		update, err := moduleToUpdate.updateDependenciesForModule(batch.Done)
		if err != nil {
			return fmt.Errorf("fatal error proposing module update: %s", err)
		}
		log.Printf("Attempting update for module %s resulted in %v\n", moduleToUpdate.RepoPath, update.result)
		if update.result == DependenciesUpdateContentUpToDate {
			batch.Done[moduleToUpdate.RepoPath] = moduleToUpdate
			delete(batch.Todo, moduleToUpdate.RepoPath)
		} else if update.result == DependenciesUpdateDependencyMissing {
			// Nothing to be done, we are waiting for indirect dependencies
		} else if update.result == DependenciesUpdateUpdateScheduled {
			// push and stage
			if err = gerrit.pushChange(moduleToUpdate.RepoPath, moduleToUpdate.Branch, update.commitID, update.summary); err != nil {
				return fmt.Errorf("error pushing change upate: %s", err)
			}

			if err = gerrit.reviewAndStageChange(moduleToUpdate.RepoPath, moduleToUpdate.Branch, update.commitID, update.summary); err != nil {
				return fmt.Errorf("error pushing change upate: %s", err)
			}

			batch.Pending = append(batch.Pending, &PendingUpdate{moduleToUpdate, update.changeID, update.commitID, 0})
			delete(batch.Todo, moduleToUpdate.RepoPath)
		} else {
			return fmt.Errorf("invalid state returned by updateDependenciesForModule for %s", moduleToUpdate.RepoPath)
		}
	}

	return nil
}

func removeAllDirectAndIndirectDependencies(allModules *map[string]*Module, moduleToRemove string) {
	for moduleName, module := range *allModules {
		if module.hasDependency(moduleToRemove) {
			delete(*allModules, moduleName)
			removeAllDirectAndIndirectDependencies(allModules, module.RepoPath)
		}
	}
}

func (batch *ModuleUpdateBatch) checkPendingModules(gerrit *gerritInstance) {
	log.Println("Checking status of pending modules")
	var newPending []*PendingUpdate
	for _, pendingUpdate := range batch.Pending {
		module := pendingUpdate.Module
		status, err := getGerritChangeStatus(module.RepoPath, module.Branch, pendingUpdate.ChangeID)
		if err != nil {
			log.Printf("    status check of %s gave error: %s\n", module.RepoPath, err)
		} else {
			log.Printf("    status of %s: %s\n", module.RepoPath, status)
		}
		if err != nil || status == "STAGED" || status == "INTEGRATING" || status == "STAGING" {
			// no change yet
			newPending = append(newPending, pendingUpdate)
			continue
		} else if status == "MERGED" {
			module.refreshTip()
			batch.Done[module.RepoPath] = module
		} else if (status == "NEW" || status == "OPEN") && len(pendingUpdate.CommitID) > 0 && pendingUpdate.IntegrationAttempts < 3 {
			log.Printf("    %v integration attempts for %s - trying again\n", pendingUpdate.IntegrationAttempts, module.RepoPath)
			pendingUpdate.IntegrationAttempts++
			if err = gerrit.reviewAndStageChange(module.RepoPath, module.Branch, pendingUpdate.CommitID, ""); err != nil {
				log.Printf("error staging change update: %s -- ignoring though", err)
			}
			newPending = append(newPending, pendingUpdate)
		} else {
			// Abandoned or tried too many times possibly -- either way an error integrating the update
			removeAllDirectAndIndirectDependencies(&batch.Todo, module.RepoPath)
			batch.FailedModuleCount++
			url := fmt.Sprintf("https://codereview.qt-project.org/#/q/%s,n,z", pendingUpdate.CommitID)
			postMessageToSlack(fmt.Sprintf("Dependency update to %s in %s failed -- <%s>", module.RepoPath, batch.Branch, url))
		}
	}
	batch.Pending = newPending
}

func loadTodoAndDoneModuleMapFromSubModules(branch string, submodules map[string]*submodule) (todo map[string]*Module, done map[string]*Module, err error) {
	todoModules := make(map[string]*Module)
	doneModules := make(map[string]*Module)

	for name, submodule := range submodules {
		module, err := NewModule(name, branch, submodules)
		if err != nil {
			return nil, nil, fmt.Errorf("could not create internal module structure: %s", err)
		}

		if submodule.repoType == "inherited" || name == "qt/qtbase" || submodule.branch != branch {
			doneModules[module.RepoPath] = module
		} else {
			todoModules[module.RepoPath] = module
		}
	}

	return todoModules, doneModules, nil
}

func (batch *ModuleUpdateBatch) loadTodoList() error {
	log.Printf("Fetching %s modules from %s %s\n", batch.Product, batch.Branch, batch.ProductRef)
	qt5Modules, err := getQt5ProductModules(batch.Product, batch.Branch, batch.ProductRef)
	if err != nil {
		return fmt.Errorf("Error listing qt5 product modules: %s", err)
	}

	batch.Todo, batch.Done, err = loadTodoAndDoneModuleMapFromSubModules(batch.Branch, qt5Modules)
	return err
}

func sanitizeBranchOrRepo(s string) string {
	s = strings.ToLower(s)
	s = strings.ReplaceAll(s, "/", "_")
	s = strings.ReplaceAll(s, "-", "_")
	return s
}

func (batch *ModuleUpdateBatch) stateFileName() string {
	return fmt.Sprintf("state_%s_%s.json", sanitizeBranchOrRepo(batch.Product), sanitizeBranchOrRepo(batch.Branch))
}

func (batch *ModuleUpdateBatch) saveStateAsCommit(gerrit *gerritInstance) error {
	productRepo, err := OpenRepository(batch.Product)
	if err != nil {
		return fmt.Errorf("Error opening product repo: %s", err)
	}

	index, err := productRepo.NewIndex()
	if err != nil {
		return fmt.Errorf("Error creating temporary index for saving batch state: %s", err)
	}
	defer index.Free()

	jsonBuffer := &bytes.Buffer{}
	encoder := json.NewEncoder(jsonBuffer)
	encoder.SetIndent("", "    ")
	if err = encoder.Encode(batch); err != nil {
		return fmt.Errorf("Error serializing module update batch state to json: %s", err)
	}

	indexEntry := &IndexEntry{
		Permissions: "100644",
		Path:        "state.json",
	}

	if err = index.HashObject(indexEntry, jsonBuffer.Bytes()); err != nil {
		return fmt.Errorf("Error adding json serialized module update batch state to git database: %s", err)
	}

	if err = index.Add(indexEntry); err != nil {
		return fmt.Errorf("Error adding json serialized module update batch state to git index: %s", err)
	}

	tree, err := index.WriteTree()
	if err != nil {
		return fmt.Errorf("Error writing tree object with module update batch state: %s", err)
	}

	commit, err := productRepo.CommitTree(tree, "Module update batch state")
	if err != nil {
		return fmt.Errorf("Error writing commit for module update batch state: %s", err)
	}

	log.Println("Module state saved as commit", commit)

	pushURL, err := RepoURL(batch.Product)
	if err != nil {
		return fmt.Errorf("Error determining %s repo URL: %s", batch.Product, err)
	}

	if gerrit.pushUserName != "" {
		pushURL.User = url.User(gerrit.pushUserName)
	}

	targetRef := "refs/personal/" + pushURL.User.Username() + "/state/" + batch.Branch

	log.Printf("Saving batch state to %s\n", targetRef)

	return productRepo.Push(pushURL, []string{"-f"}, commit, targetRef)
}

func (batch *ModuleUpdateBatch) loadStateFromCommit() error {
	productRepo, err := OpenRepository(batch.Product)
	if err != nil {
		return fmt.Errorf("Error opening product repo: %s", err)
	}

	repoURL, err := RepoURL(batch.Product)
	if err != nil {
		return fmt.Errorf("Error determining %s repo URL: %s", batch.Product, err)
	}

	log.Printf("Fetching state.json from personal branch")

	// ### url
	stateCommit, err := productRepo.Fetch(repoURL, "refs/personal/qt_submodule_update_bot/state/"+batch.Branch)
	if err != nil {
		return os.ErrNotExist
	}

	index, err := productRepo.NewIndex()
	if err != nil {
		return fmt.Errorf("Error creating git index when trying to load batch state: %s", err)
	}
	defer index.Free()

	if err = index.ReadTree(stateCommit); err != nil {
		return fmt.Errorf("Error reading tree of state commit %s: %s", stateCommit, err)
	}

	indexEntry, err := lookupPathIndexEntry(index, "state.json")
	if err != nil {
		return fmt.Errorf("Error looking up state.json from index in state commit %s: %s", stateCommit, err)
	}

	stateJSON, err := productRepo.LookupBlob(indexEntry.ID)
	if err != nil {
		return fmt.Errorf("Error reading state json from git db: %s", err)
	}

	decoder := json.NewDecoder(bytes.NewBuffer(stateJSON))
	err = decoder.Decode(batch)
	if err != nil {
		return fmt.Errorf("Error decoding JSON state file: %s", err)
	}

	return nil
}

func (batch *ModuleUpdateBatch) clearStateCommit(gerrit *gerritInstance) error {
	productRepo, err := OpenRepository(batch.Product)
	if err != nil {
		return fmt.Errorf("Error opening product repo: %s", err)
	}

	pushURL, err := RepoURL(batch.Product)
	if err != nil {
		return fmt.Errorf("Error determining %s repo URL: %s", batch.Product, err)
	}

	if gerrit.pushUserName != "" {
		pushURL.User = url.User(gerrit.pushUserName)
	}

	targetRef := "refs/personal/" + pushURL.User.Username() + "/state/" + batch.Branch

	log.Printf("Clearing batch state at %s\n", targetRef)

	return productRepo.Push(pushURL, nil, "", targetRef)
}

func (batch *ModuleUpdateBatch) saveState() error {
	fileName := batch.stateFileName()
	outputFile, err := os.Create(fileName)
	if err != nil {
		return fmt.Errorf("failed to create state file %s: %s", fileName, err)
	}
	defer outputFile.Close()

	encoder := json.NewEncoder(outputFile)
	encoder.SetIndent("", "    ")
	return encoder.Encode(batch)
}

func (batch *ModuleUpdateBatch) loadState() error {
	fileName := batch.stateFileName()
	inputFile, err := os.Open(fileName)
	if err != nil {
		return err
	}
	defer inputFile.Close()

	decoder := json.NewDecoder(inputFile)
	err = decoder.Decode(batch)
	if err != nil {
		return fmt.Errorf("Error decoding JSON state file: %s", err)
	}
	return nil
}

func (batch *ModuleUpdateBatch) clearState() {
	os.Remove(batch.stateFileName())
}

func (batch *ModuleUpdateBatch) isDone() bool {
	return len(batch.Todo) == 0 && len(batch.Pending) == 0
}

func (batch *ModuleUpdateBatch) printSummary() {
	fmt.Fprintf(os.Stdout, "Summary of git repository dependency update for target branch %s based off of %s\n", batch.Branch, batch.Product)

	if batch.isDone() {
		if batch.FailedModuleCount > 0 {
			fmt.Fprintf(os.Stdout, "    %v modules failed to be updated. Check Gerrit for the %s branch\n", batch.FailedModuleCount, batch.Branch)
		} else {
			fmt.Fprintf(os.Stdout, "    No updates are necessary for any modules - everything is up-to-date\n")
		}
		return
	}

	if len(batch.Done) > 0 {
		fmt.Fprintf(os.Stdout, "The following modules have been brought up-to-date:\n")

		for name := range batch.Done {
			fmt.Println("    " + name)
		}
	}

	if len(batch.Pending) > 0 {
		fmt.Fprintf(os.Stdout, "The following modules are current in-progress:\n")

		for _, pending := range batch.Pending {
			fmt.Println("    " + pending.Module.RepoPath)
		}
	}

	fmt.Fprintf(os.Stdout, "The following modules are outdated and are either waiting for one of their dependencies or are ready for an update:\n")
	for name := range batch.Todo {
		fmt.Println("    " + name)
	}

	fmt.Println()
	fmt.Println()
}

func (batch *ModuleUpdateBatch) runOneIteration(gerrit *gerritInstance) error {
	batch.checkPendingModules(gerrit)

	if err := batch.scheduleUpdates(gerrit); err != nil {
		return err
	}

	batch.printSummary()

	if !batch.isDone() {
		err := batch.saveStateAsCommit(gerrit)
		if err != nil {
			return err
		}
	} else {
		if batch.FailedModuleCount == 0 {
			fmt.Println("Preparing qt5 update")
			if err := prepareQt5Update(batch.Product, batch.Branch, batch.ProductRef, batch.Done, gerrit); err != nil {
				return fmt.Errorf("error preparing qt5 update: %s", err)
			}
		}

		batch.clearStateCommit(gerrit)
	}

	return nil
}
