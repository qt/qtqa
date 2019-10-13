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
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/url"
	"os"
	"os/exec"
	"strings"
)

// GerritPatchSet corresponds to the patch set JSON object returned by Gerrit's JSON API.
type GerritPatchSet struct {
	Number         int             `json:"number"`
	Revision       string          `json:"revision"`
	Parents        []string        `json:"parents"`
	Uploader       json.RawMessage `json:"uploader"`
	CreatedOn      uint            `json:"createdOn"`
	Author         json.RawMessage `json:"author"`
	SizeInsertions int             `json:"sizeInsertions"`
	SizeDeletions  int             `json:"sizeDeletions"`
}

// GerritChangeOrStats corresponds to the JSON data returned by Gerrit's Query JSON API.
type GerritChangeOrStats struct {
	Type                string `json:"type"`
	RowCount            int    `json:"rowCount"`
	RunTimeMilliseconds int    `json:"runTimeMilliseconds"`

	Project     string           `json:"project"`
	Branch      string           `json:"branch"`
	ID          string           `json:"id"`
	Number      int              `json:"number"`
	Subject     string           `json:"subject"`
	Owner       json.RawMessage  `json:"owner"`
	URL         string           `json:"url"`
	CreatedOn   uint             `json:"createdOn"`
	LastUpdated uint             `json:"lastUpdated"`
	SortKey     string           `json:"sortKey"`
	Open        bool             `json:"open"`
	Status      string           `json:"status"`
	PatchSets   []GerritPatchSet `json:"patchSets"`
}

func gerritSSHCommand(gerritURL url.URL, arguments ...string) (*exec.Cmd, error) {
	host, port, err := net.SplitHostPort(gerritURL.Host)
	if err != nil {
		return nil, fmt.Errorf("Error splitting host and port from gerrit URL: %s", err)
	}

	userAtHost := host
	if gerritURL.User != nil {
		userAtHost = gerritURL.User.Username() + "@" + host
	}

	newArgs := []string{"-oBatchMode=yes", userAtHost, "-p", port}
	newArgs = append(newArgs, arguments...)
	ssh := os.Getenv("GIT_SSH_COMMAND")
	if ssh != "" {
		commandLine := strings.Split(ssh, " ")
		ssh = commandLine[0]
		newArgs = append(commandLine[1:], newArgs...)
	} else {
		ssh = "ssh"
	}
	log.Printf("Running gerrit ssh command: 'ssh %v'\n", newArgs)
	return exec.Command(ssh, newArgs...), nil
}

func getGerritChangeStatus(project string, branch string, changeID string) (status string, err error) {
	gerritURL, err := RepoPushURL(project)
	if err != nil {
		return "", fmt.Errorf("Error parsing gerrit URL: %s", err)
	}
	queryString := fmt.Sprintf(`project:%s branch:%s %s`, project, branch, changeID)
	cmd, err := gerritSSHCommand(*gerritURL, "gerrit", "query", "--patch-sets", "--format JSON", queryString)
	if err != nil {
		return "", err
	}
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running gerrit query command: %s", err)
	}

	var id string

	for _, line := range strings.Split(string(output), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		var field GerritChangeOrStats
		err = json.Unmarshal([]byte(line), &field)
		if err != nil {
			return "", fmt.Errorf("Error reading gerrit json response: %s:%s", err, string(output))
		}
		if field.Type == "stats" {
			if field.RowCount != 1 {
				return "", fmt.Errorf("unexpected row count %v when querying for existing gerrit change", field.RowCount)
			}
			continue
		}

		if field.Project != project {
			return "", fmt.Errorf("unexpectedly found change for a different project. Received %s, expected %s for %s", field.Project, project, changeID)
		}
		if id != "" {
			return "", fmt.Errorf("unexpectedly found multiple changes for change ID %s", changeID)
		}
		id = field.ID
		status = field.Status
	}
	return status, nil
}

func getExistingChange(project string, branch string) (gerritChangeID string, changeNumber int, patchSetNr int, status string, err error) {
	gerritURL, err := RepoPushURL(project)
	if err != nil {
		return "", 0, 0, "", fmt.Errorf("Error parsing gerrit URL: %s", err)
	}
	queryString := fmt.Sprintf(`project:%s branch:%s NOT(status:merged OR status:abandoned OR status:deferred) owner:self message:{Update dependencies on \'%s\' in %s}`, project, branch, branch, project)
	cmd, err := gerritSSHCommand(*gerritURL, "gerrit", "query", "--patch-sets", "--format JSON", queryString)
	if err != nil {
		return "", 0, 0, "", err
	}
	output, err := cmd.Output()
	if err != nil {
		return "", 0, 0, "", fmt.Errorf("Error running gerrit query command: %s", err)
	}

	var id string

	for _, line := range strings.Split(string(output), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		var field GerritChangeOrStats
		err = json.Unmarshal([]byte(line), &field)
		if err != nil {
			return "", 0, 0, "", fmt.Errorf("Error reading gerrit json response: %s:%s", err, string(output))
		}
		if field.Type == "stats" {
			if field.RowCount == 0 {
				return "", 0, 0, "", nil
			}
			if field.RowCount != 1 {
				return "", 0, 0, "", fmt.Errorf("unexpected row count %v when querying for existing gerrit changes", field.RowCount)
			}
			continue
		}

		if field.Project == project {
			if id != "" {
				return "", 0, 0, "", fmt.Errorf("unexpectedly found multiple changes for submodule updates: Id %s and %s", id, field.ID)
			}
			id = field.ID
			changeNumber = field.Number
			status = field.Status
			patchSetNr = 0
			for _, patchSet := range field.PatchSets {
				if patchSet.Number > patchSetNr {
					patchSetNr = patchSet.Number
				}
			}
			continue
		}
	}
	return id, changeNumber, patchSetNr, status, nil
}

func escapeGerritMessage(message string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `"`, `\"`, `'`, `\'`)
	return `"` + replacer.Replace(message) + `"`
}

type gerritInstance struct {
	pushUserName   string
	disableStaging bool
}

func (instance *gerritInstance) pushChange(repoPath string, branch string, commitID OID, summary string) error {
	repo, err := OpenRepository(repoPath)
	if err != nil {
		return err
	}

	pushURL, err := RepoURL(repoPath)
	if err != nil {
		return err
	}
	if instance.pushUserName != "" {
		pushURL.User = url.User(instance.pushUserName)
	}

	return repo.Push(pushURL, nil, commitID, "refs/for/"+branch)
}

func (instance *gerritInstance) reviewAndStageChange(repoPath string, branch string, commitID OID, summary string) error {
	if instance.disableStaging {
		return nil
	}

	pushURL, err := RepoPushURL(repoPath)
	if err != nil {
		return err
	}
	// Always review/approve as current user as the bot does not have approval rights.
	pushURL.User = nil

	reviewArgs := []string{"gerrit", "review", string(commitID)}

	if summary != "" {
		reviewArgs = append(reviewArgs, "-m", escapeGerritMessage(summary))
	}
	// Pass in sanity review, since the sanity bot runs only after a delay and thus the commit will get refused.
	reviewArgs = append(reviewArgs, "--code-review", "2", "--sanity-review", "1")

	updateCommand, err := gerritSSHCommand(*pushURL, reviewArgs...)
	if err != nil {
		return err
	}
	updateCommand.Stdout = os.Stdout
	updateCommand.Stderr = os.Stderr
	if err = updateCommand.Run(); err != nil {
		return err
	}

	stageArgs := []string{"gerrit-plugin-qt-workflow", "stage", string(commitID)}
	updateCommand, err = gerritSSHCommand(*pushURL, stageArgs...)
	if err != nil {
		return err
	}
	updateCommand.Stdout = os.Stdout
	updateCommand.Stderr = os.Stderr
	if err = updateCommand.Run(); err != nil {
		return err
	}
	return nil
}
