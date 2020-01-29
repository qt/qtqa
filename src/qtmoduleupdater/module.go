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
	"fmt"
	"log"
	"path/filepath"
	"sort"
	"strings"

	yaml "gopkg.in/yaml.v2"
)

// Module represents a git repository with a dependencies.yaml file
// that needs updating.
type Module struct {
	RepoPath             string   // relative path in Gerrit, such as qt/qtsvg
	RequiredDependencies []string // Dependencies as per dependencies.yaml
	OptionalDependencies []string // Dependencies as per dependencies.yaml
	Branch               string
	Tip                  OID
}

// YAMLModule for unmarshaling module information from dependencies file.
type YAMLModule struct {
	Ref      string `yaml:"ref"`
	Required bool   `yaml:"required"`
}

// YAMLDependenciesMap is a map from string to YAMLModule but always
// produces a sorted YAML map when serializing
type YAMLDependenciesMap map[string]*YAMLModule

// YAMLDependencies for unmarshaling module information from dependencies file.
type YAMLDependencies struct {
	Dependencies YAMLDependenciesMap `yaml:"dependencies"`
}

// MarshalYAML implements the marshalling of the dependencies while
// making sure the entries are sorted.
func (depMap *YAMLDependenciesMap) MarshalYAML() (interface{}, error) {
	var sortedKeys []string
	for key := range *depMap {
		sortedKeys = append(sortedKeys, key)
	}

	sort.Strings(sortedKeys)

	var result yaml.MapSlice

	for _, key := range sortedKeys {
		entry := (*depMap)[key]
		result = append(result, yaml.MapItem{
			Key:   key,
			Value: entry,
		})
	}

	return result, nil
}

// ToString Converts the yaml dependencies map into its string representation, for storage
// in the dependencies.yaml file, for example.
func (depMap *YAMLDependencies) ToString() (string, error) {
	output := &bytes.Buffer{}
	encoder := yaml.NewEncoder(output)
	if err := encoder.Encode(depMap); err != nil {
		return "", fmt.Errorf("Error encoding YAML dependencies: %s", err)
	}
	encoder.Close()

	return output.String(), nil
}

//go:generate stringer -type=DependenciesUpdateResultEnum

// DependenciesUpdateResultEnum describes the different states after attempting to update the dependencies.yaml for a module.
type DependenciesUpdateResultEnum int

const (
	// DependenciesUpdateDependencyMissing indicates that a dependency is not available yet.
	DependenciesUpdateDependencyMissing DependenciesUpdateResultEnum = iota
	// DependenciesUpdateContentUpToDate indicates that no further updates to dependencies.yaml are required.
	DependenciesUpdateContentUpToDate
	// DependenciesUpdateUpdateScheduled indicates that an update to dependencies.yaml was necessary and has been pushed to Gerrit.
	DependenciesUpdateUpdateScheduled
)

type pathNotExistError struct {
	path string
}

func (p *pathNotExistError) Error() string {
	return fmt.Sprintf("Could not locate %s in git tree", p.path)
}

func readDependenciesYAML(repoPath string, repo Repository, commit OID) (dependencies *YAMLDependencies, err error) {
	path := "dependencies.yaml"

	tree, err := repo.ListTree(commit)
	if err != nil {
		return nil, fmt.Errorf("could not list tree for commit %s: %s", commit, err)
	}

	entry, ok := tree.Entries[path]
	if !ok {
		return nil, &pathNotExistError{path}
	}

	if entry.Type != ObjectBlob {
		return nil, fmt.Errorf("%s is not a file/blob", path)
	}

	blob, err := repo.LookupBlob(entry.ID)
	if err != nil {
		return nil, fmt.Errorf("Error looking up %s blob: %s", path, err)
	}

	yamlData := &YAMLDependencies{}
	err = yaml.Unmarshal(blob, yamlData)
	if err != nil {
		return nil, fmt.Errorf("Error unmarshaling dependencies.yaml: %s", err)
	}

	if yamlData.Dependencies != nil {
		for name, dependency := range yamlData.Dependencies {
			if strings.HasPrefix(name, "/") {
				continue
			}
			absoluteName := filepath.Clean(filepath.Join(repoPath, name))
			delete(yamlData.Dependencies, name)
			yamlData.Dependencies[absoluteName] = dependency
		}
	}

	return yamlData, nil
}

// NewModule constructs a new module type for a dependencies.yaml update
// from a given qt5 submodule structure.
func NewModule(moduleName string, branch string, qt5Modules map[string]*submodule) (*Module, error) {
	var repoPath string
	if !strings.Contains(moduleName, "/") {
		repoPath = "qt/" + moduleName
	} else {
		repoPath = moduleName
	}

	repo, err := OpenRepository(repoPath)
	if err != nil {
		return nil, fmt.Errorf("Error opening submodule %s: %s", moduleName, err)
	}

	if subModule, ok := qt5Modules[moduleName]; ok {
		branch = subModule.branch
	}
	headRef := "refs/heads/" + branch

	repoURL, err := RepoURL(repoPath)
	if err != nil {
		return nil, fmt.Errorf("could not find fetch url for %s: %s", moduleName, err)
	}

	moduleTipCommit, err := repo.Fetch(repoURL, headRef)
	if err != nil {
		return nil, fmt.Errorf("could not fetch repo tip %s of %s: %s", headRef, moduleName, err)
	}

	yamlDependencies := &YAMLDependencies{}
	yamlDependencies.Dependencies = make(map[string]*YAMLModule)

	subModule, ok := qt5Modules[moduleName]
	if !ok {
		return nil, fmt.Errorf("could not find %s in .gitmodules in qt5.git", moduleName)
	}

	populateDependencies := func(required bool, dependencies []string) {
		for _, dependency := range dependencies {
			_, knownModule := qt5Modules[dependency]
			if !required && !knownModule {
				continue
			}

			var yamlModule YAMLModule
			yamlModule.Required = required
			yamlModule.Ref = string(subModule.headCommit)

			yamlDependencies.Dependencies[dependency] = &yamlModule
		}
	}

	populateDependencies(true, subModule.requiredDependencies)
	populateDependencies(false, subModule.optionalDependencies)

	result := &Module{}
	result.RepoPath = repoPath
	result.Branch = branch
	result.Tip = moduleTipCommit

	for dependency, yamlModule := range yamlDependencies.Dependencies {
		if yamlModule.Required {
			result.RequiredDependencies = append(result.RequiredDependencies, dependency)
		} else {
			result.OptionalDependencies = append(result.OptionalDependencies, dependency)
		}
	}

	return result, nil
}

func (module *Module) hasDependency(dependency string) bool {
	for _, dep := range module.RequiredDependencies {
		if dep == dependency {
			return true
		}
	}
	for _, dep := range module.OptionalDependencies {
		if dep == dependency {
			return true
		}
	}
	return false
}

func (module *Module) refreshTip() error {
	repo, err := OpenRepository(module.RepoPath)
	if err != nil {
		return fmt.Errorf("Error opening submodule %s: %s", module.RepoPath, err)
	}

	headRef := "refs/heads/" + module.Branch

	repoURL, err := RepoURL(module.RepoPath)
	if err != nil {
		return fmt.Errorf("could not find fetch url for %s: %s", module.RepoPath, err)
	}

	moduleTipCommit, err := repo.Fetch(repoURL, headRef)
	if err != nil {
		return fmt.Errorf("could not fetch repo tip %s of %s: %s", headRef, module.RepoPath, err)
	}

	module.Tip = moduleTipCommit
	return nil
}

func (module *Module) maybePrepareUpdatedDependenciesYaml(availableModules map[string]*Module) (yaml *YAMLDependencies, err error) {
	var proposedUpdate YAMLDependencies
	proposedUpdate.Dependencies = make(map[string]*YAMLModule)

	updateDeps := func(required bool, deps []string) (allDependenciesAvailable bool, err error) {
		for _, dep := range deps {
			depModule, ok := availableModules[dep]
			if !ok {
				return false, nil
			}

			yamlModule := &YAMLModule{}
			yamlModule.Required = required
			yamlModule.Ref = string(depModule.Tip)

			path, err := filepath.Rel(module.RepoPath, depModule.RepoPath)
			if err != nil {
				path = module.RepoPath
			}
			proposedUpdate.Dependencies[path] = yamlModule
		}
		return true, nil
	}

	if allDepsOk, err := updateDeps( /*required*/ true, module.RequiredDependencies); err != nil || !allDepsOk {
		return nil, err
	}
	if allDepsOk, err := updateDeps( /*required*/ false, module.OptionalDependencies); err != nil || !allDepsOk {
		return nil, err
	}

	return &proposedUpdate, nil
}

func lookupPathIndexEntry(index *Index, path string) (*IndexEntry, error) {
	for i := 0; i < index.EntryCount(); i++ {
		entry, err := index.EntryByIndex(i)
		if err != nil {
			return nil, err
		}
		if entry.Path == path {
			return entry, nil
		}
	}
	return nil, fmt.Errorf("could not locate path %s in index", path)
}

func (module *Module) generateChangeLogOfDependencies(oldDependencies *YAMLDependencies, newDependencies *YAMLDependencies) string {
	if oldDependencies == nil || newDependencies == nil || oldDependencies.Dependencies == nil || newDependencies.Dependencies == nil {
		log.Printf("Empty set of dependencies for change log update for %s\n", module.RepoPath)
		return ""
	}

	var changeLog []string

	for dependencyName, dependency := range newDependencies.Dependencies {
		dependencyRepoPath := filepath.Clean(filepath.Join(module.RepoPath, dependencyName))
		oldDependency, ok := oldDependencies.Dependencies[dependencyRepoPath]
		if !ok {
			log.Printf("Could not find module %s in the old dependencies table %v\n", dependencyRepoPath, oldDependencies.Dependencies)
			continue
		}
		oldSha1 := oldDependency.Ref
		newSha1 := dependency.Ref

		depRepo, err := OpenRepository(dependencyRepoPath)
		if err != nil {
			log.Printf("Could not open dependency repo %s for changelog analysis: %s", dependencyRepoPath, err)
			continue
		}

		changes, err := depRepo.LogOutput(`--pretty=format:  %m %s`, "--first-parent", string(oldSha1)+".."+string(newSha1))
		if err != nil {
			log.Printf("Oddly git log failed: %s\n", err)
			continue
		}
		changeLog = append(changeLog, fmt.Sprintf("%s %s..%s:", dependencyRepoPath, oldSha1, newSha1))
		changeLog = append(changeLog, changes...)
		changeLog = append(changeLog, "")
	}

	summary := strings.Join(changeLog, "\n  ")
	// Limit due to maximum command line size when talking to gerrit via ssh :(
	if len(summary) > 65000 {
		summary = summary[:65000]
	}
	return summary
}

type dependenciesUpdateResult struct {
	result   DependenciesUpdateResultEnum
	changeID string
	commitID OID
	summary  string
}

func (module *Module) updateDependenciesForModule(availableModules map[string]*Module) (result dependenciesUpdateResult, err error) {
	yamlObject, err := module.maybePrepareUpdatedDependenciesYaml(availableModules)
	if err != nil {
		return dependenciesUpdateResult{}, err
	}
	if yamlObject == nil {
		return dependenciesUpdateResult{result: DependenciesUpdateDependencyMissing}, nil
	}

	repo, err := OpenRepository(module.RepoPath)
	if err != nil {
		return dependenciesUpdateResult{}, fmt.Errorf("Error opening repo to retrieve tip: %s", err)
	}

	index, err := repo.NewIndex()
	if err != nil {
		return dependenciesUpdateResult{}, fmt.Errorf("Error creating temporary git index: %s", err)
	}
	defer index.Free()

	module.refreshTip()

	err = index.ReadTree(module.Tip)
	if err != nil {
		return dependenciesUpdateResult{}, fmt.Errorf("Error populating temporary index from tree: %s", err)
	}

	existingEntry, _ := lookupPathIndexEntry(index, "dependencies.yaml")

	updatedIndexEntryForFile := &IndexEntry{
		Permissions: "100644",
		Path:        "dependencies.yaml",
	}

	yamlStr, err := yamlObject.ToString()
	if err != nil {
		return dependenciesUpdateResult{}, fmt.Errorf("Internal error encoding yaml to string: %s", err)
	}

	if err := index.HashObject(updatedIndexEntryForFile, []byte(yamlStr)); err != nil {
		return dependenciesUpdateResult{}, err
	}

	var summary string

	if existingEntry != nil {
		if updatedIndexEntryForFile.ID == existingEntry.ID {
			return dependenciesUpdateResult{result: DependenciesUpdateContentUpToDate}, nil
		}

		log.Printf("Found existing dependencies file in %s, trying to read it to compare\n", module.RepoPath)
		oldDependenciesFile, err := readDependenciesYAML(module.RepoPath, repo, module.Tip)
		if err != nil {
			log.Printf("Could not decode existing yaml dependencies file for change log generation purposes: %s\n", err)
		} else {
			summary = module.generateChangeLogOfDependencies(oldDependenciesFile, yamlObject)
		}
	}

	if err := index.Add(updatedIndexEntryForFile); err != nil {
		return dependenciesUpdateResult{}, err
	}

	newTree, err := index.WriteTree()
	if err != nil {
		return dependenciesUpdateResult{}, err
	}

	changeID, _, _, status, err := getExistingChange(module.RepoPath, module.Branch)
	if err != nil {
		return dependenciesUpdateResult{}, fmt.Errorf("failure to check for existing change id for module %s: %s", module.RepoPath, err)
	}

	if changeID == "" {
		changeID = fmt.Sprintf("I%s", newTree)
	} else if status == "STAGED" || status == "INTEGRATING" || status == "STAGING" {
		// Assume that this is still work in progress, so try again later.
		return dependenciesUpdateResult{result: DependenciesUpdateDependencyMissing}, nil
	}

	message := fmt.Sprintf("Update dependencies on '%s' in %s\n\nChange-Id: %s\n", module.Branch, module.RepoPath, changeID)

	parentCommit := module.Tip

	commitOid, err := repo.CommitTree(newTree, message, parentCommit)
	if err != nil {
		return dependenciesUpdateResult{}, fmt.Errorf("Error creating git commit for dependencies update in module %s: %s", module.RepoPath, err)
	}

	log.Printf("New update commit created for %s: %s", module.RepoPath, commitOid)

	return dependenciesUpdateResult{
		result:   DependenciesUpdateUpdateScheduled,
		changeID: changeID,
		commitID: commitOid,
		summary:  summary,
	}, nil
}
