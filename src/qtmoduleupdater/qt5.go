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
	"net"
	"net/url"
	"strings"

	"github.com/vaughan0/go-ini"
)

type submodule struct {
	url                  string
	branch               string
	repoType             string
	requiredDependencies []string
	optionalDependencies []string
	headCommit           OID
}

func listSubmodules(repo Repository, repoURL *url.URL, commit OID) (modules map[string]*submodule, err error) {
	tree, err := repo.ListTree(commit)
	if err != nil {
		return
	}

	gitModulesEntry, ok := tree.Entries[".gitmodules"]
	if !ok {
		err = fmt.Errorf("could not locate .gitmodules in git tree")
		return
	}
	if gitModulesEntry.Type != ObjectBlob {
		err = fmt.Errorf(".gitmodules is not a file/blob")
		return
	}
	blob, err := repo.LookupBlob(gitModulesEntry.ID)
	if err != nil {
		err = fmt.Errorf("Error looking up .gitmodules blob: %s", err)
		return
	}

	baseURL := *repoURL
	baseURL.Path = baseURL.Path + "/repo.git"
	baseURL.Scheme = "ssh"
	host, _, err := net.SplitHostPort(baseURL.Host)
	if err != nil {
		err = fmt.Errorf("Error splitting host and port from base url %v", baseURL)
		return
	}
	baseURL.Host = host

	gitModules, err := ini.Load(bytes.NewBuffer(blob))
	for key, values := range gitModules {
		subModule := strings.TrimPrefix(key, `submodule "`)
		if subModule == key {
			continue
		}
		subModule = strings.TrimSuffix(subModule, `"`)

		if status, ok := values["status"]; ok {
			if status == "ignore" {
				continue
			}
		} else if initRepo, ok := values["initrepo"]; ok {
			if initRepo != "true" {
				continue
			}
		}

		module := &submodule{}

		urlString, ok := values["url"]
		if !ok {
			err = fmt.Errorf("could not find submodule URL for submodule %s", subModule)
			return
		}

		var subModuleURL *url.URL
		subModuleURL, err = url.Parse(urlString)
		if err != nil {
			err = fmt.Errorf("Error parsing submodule url %s: %s", values["url"], err)
			return
		}

		if modules == nil {
			modules = make(map[string]*submodule)
		}

		module.url = baseURL.ResolveReference(subModuleURL).String()
		module.branch = values["branch"]

		if repoType, ok := values["repoType"]; ok {
			module.repoType = repoType
		}

		if requiredDependenciesAsString, ok := values["depends"]; ok {

			for _, dep := range strings.Split(requiredDependenciesAsString, " ") {
				module.requiredDependencies = append(module.requiredDependencies, "qt/"+dep)
			}
		}

		if optionalDependenciesAsString, ok := values["recommends"]; ok {
			for _, dep := range strings.Split(optionalDependenciesAsString, " ") {
				module.optionalDependencies = append(module.optionalDependencies, "qt/"+dep)
			}
		}

		if tree.Entries[subModule].Type != ObjectCommit {
			return nil, fmt.Errorf("submodule entry for %s does not point to a commit", subModule)
		}

		module.headCommit = tree.Entries[subModule].ID

		modules["qt/"+subModule] = module
	}
	return
}

func getQt5ProductModules(productProject string, branchOrRef string, productFetchRef string) (modules map[string]*submodule, err error) {
	if productFetchRef == "" {
		productFetchRef = branchOrRef
	}
	if !strings.HasPrefix(productFetchRef, "refs/") {
		productFetchRef = "refs/heads/" + productFetchRef
	}

	productRepoURL, err := RepoURL(productProject)
	if err != nil {
		return nil, fmt.Errorf("Error determining %s repo URL: %s", productProject, err)
	}

	productRepo, err := OpenRepository(productProject)
	if err != nil {
		return nil, fmt.Errorf("Error opening product repo: %s", err)
	}

	productHead, err := productRepo.Fetch(productRepoURL, productFetchRef)
	if err != nil {
		return nil, fmt.Errorf("Error fetching product repo: %s", err)
	}

	return listSubmodules(productRepo, productRepoURL, productHead)
}

func prepareQt5Update(product string, branch string, productFetchRef string, updatedModules map[string]*Module, gerrit *gerritInstance) error {
	productRepoURL, err := RepoURL(product)
	if err != nil {
		return fmt.Errorf("Error determining %s repo URL: %s", product, err)
	}

	productRepo, err := OpenRepository(product)
	if err != nil {
		return fmt.Errorf("Error opening product repo: %s", err)
	}

	productHead, err := productRepo.Fetch(productRepoURL, productFetchRef)
	if err != nil {
		return err
	}

	index, err := productRepo.NewIndex()
	if err != nil {
		return err
	}
	defer index.Free()

	if err = index.ReadTree(productHead); err != nil {
		return err
	}

	qt5Modules, err := listSubmodules(productRepo, productRepoURL, productHead)
	if err != nil {
		return fmt.Errorf("error retrieving list of submodules: %s", err)
	}

	for name, qt5Module := range qt5Modules {
		updatedModule, ok := updatedModules[name]
		if !ok {
			if qt5Module.branch != branch {
				continue
			}
			return fmt.Errorf("could not locate qt5 module %s in map of updated modules", name)
		}

		unprefixedPath := strings.TrimPrefix(name, "qt/")

		updatedEntry := &IndexEntry{
			Permissions: "160000",
			Path:        unprefixedPath,
			ID:          OID(updatedModule.Tip),
		}

		if err = index.Add(updatedEntry); err != nil {
			return fmt.Errorf("could not update submodule index entry for %s: %s", unprefixedPath, err)
		}
	}

	newTree, err := index.WriteTree()
	if err != nil {
		return fmt.Errorf("could not write index with updated submodule sha1s: %s", err)
	}

	changeID, _, _, _, err := getExistingChange(product, branch)
	if err != nil {
		return fmt.Errorf("error looking for an existing change while updating submodules: %s", err)
	}

	if changeID == "" {
		changeID = fmt.Sprintf("I%s", newTree)
	}

	message := fmt.Sprintf("Update submodules on '%s' in %s\n\nChange-Id: %s\n", branch, product, changeID)

	commitOid, err := productRepo.CommitTree(newTree, message, productHead)
	if err != nil {
		return fmt.Errorf("could not create new commit for submodule update: %s", err)
	}

	fmt.Printf("Created new commit for submodule update: %s\n", commitOid)

	if err = gerrit.pushChange(product, branch, commitOid, "Updating all submodules with a new consistent set"); err != nil {
		return fmt.Errorf("Error pushing qt5 change: %s", err)
	}

	if err := gerrit.reviewAndStageChange(product, branch, commitOid, "Updating all submodules with a new consistent set"); err != nil {
		return err
	}
	url := fmt.Sprintf("https://codereview.qt-project.org/#/q/%s,n,z", commitOid)
	postMessageToSlack(fmt.Sprintf("Updating all submodules in qt5 %s with a new consistent set: <%s>", branch, url))
	return nil
}
