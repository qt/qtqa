/****************************************************************************
**
** Copyright (C) 2016 The Qt Company Ltd.
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
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
)

func setupEnvironmentForSubmoduleUpdateBot() (cleanupFunction func(), username string, err error) {
	cleanupFunction = func() {}

	submoduleUpdateBotKeyPath := "submodule_update_bot_key_rsa"
	if _, err = os.Stat(submoduleUpdateBotKeyPath); os.IsNotExist(err) {
		err = fmt.Errorf("cannot locate submodule update bot SSH key file. Please copy it from the coin secrets repo into the current directory")
		return
	}

	var sshWrapperScript *os.File

	cleanupFunction = func() {
		if sshWrapperScript != nil {
			os.Remove(sshWrapperScript.Name())
		}
	}

	sshWrapperScript, err = ioutil.TempFile("", "")
	if err != nil {
		err = fmt.Errorf("Error creating temporary SSH wrapper script: %s", err)
		return
	}
	if err = sshWrapperScript.Chmod(0700); err != nil {
		sshWrapperScript.Close()
		err = fmt.Errorf("Error making temporary SSH wrapper script executable: %s", err)
		return
	}
	sshWrapperScript.Close()

	scriptSource := fmt.Sprintf("#!/bin/sh\nexec ssh -i %s \"$@\"", submoduleUpdateBotKeyPath)
	if err = ioutil.WriteFile(sshWrapperScript.Name(), []byte(scriptSource), 0700); err != nil {
		err = fmt.Errorf("Error writing to temporary SSH wrapper script: %s", err)
		return
	}
	os.Setenv("GIT_SSH", sshWrapperScript.Name())
	os.Setenv("GIT_SSH_USER", "qt_submodule_update_bot")

	os.Setenv("GIT_AUTHOR_NAME", "Qt Submodule Update Bot")
	os.Setenv("GIT_COMMITTER_NAME", "Qt Submodule Update Bot")
	os.Setenv("GIT_AUTHOR_EMAIL", "qt_submodule_update_bot@qt-project.org")
	os.Setenv("GIT_COMMITTER_EMAIL", "qt_submodule_update_bot@qt-project.org")

	username = "qt_submodule_update_bot"
	return
}

func appMain() error {
	var product string
	flag.StringVar(&product, "product", "qt/qt5" /*default*/, "Product repository to use as reference and push completed updates to")
	stageAsBot := false
	flag.BoolVar(&stageAsBot, "stage-as-bot", false /*default*/, "Push changes to Gerrit using the submodule update bot account")
	var branch string
	flag.StringVar(&branch, "branch", "", "Branch to update")
	var fetchRef string
	flag.StringVar(&fetchRef, "fetch-ref", "", "Git ref in qt5 to use as basis for a new round of updates")
	manualStage := false
	flag.BoolVar(&manualStage, "manual-stage", false /*default*/, "Do not stage changes automatically")
	summaryOnly := false
	flag.BoolVar(&summaryOnly, "summarize", false /*default*/, "")
	verbose := false
	flag.BoolVar(&verbose, "verbose", false /*default*/, "Enable verbose logging output")
	flag.Parse()

	if !verbose {
		oldWriter := log.Writer()
		defer log.SetOutput(oldWriter)
		log.SetOutput(ioutil.Discard)
	}

	if branch == "" {
		return fmt.Errorf("missing branch. Please specify -branch=<name of branch>")
	}

	var pushUserName string
	if stageAsBot {
		var cleaner func()
		var err error
		cleaner, pushUserName, err = setupEnvironmentForSubmoduleUpdateBot()
		if err != nil {
			return fmt.Errorf("error preparing environment to work as submodule-update user: %s", err)
		}
		defer cleaner()
	}

	batch := &ModuleUpdateBatch{
		Product: product,
		Branch:  branch,
	}
	var err error

	err = batch.loadState()
	if os.IsNotExist(err) {
		err = batch.loadTodoList(fetchRef)
		if err != nil {
			return err
		}
	}

	if summaryOnly {
		batch.PrintSummary()
		return nil
	}

	batch.checkPendingModules()

	if err := batch.scheduleUpdates(pushUserName, manualStage); err != nil {
		return err
	}

	batch.PrintSummary()

	if !batch.isDone() {
		err = batch.saveState()
		if err != nil {
			return err
		}
	} else {
		os.Remove("state.json")

		if batch.FailedModuleCount == 0 {
			fmt.Println("Preparing qt5 update")
			if err = prepareQt5Update(product, batch.Branch, batch.Done, pushUserName, manualStage); err != nil {
				return fmt.Errorf("error preparing qt5 update: %s", err)
			}
		}
	}

	return nil
}

func main() {
	err := appMain()
	if err != nil {
		log.Fatalf("Error: %s\n", err)
	}
}
