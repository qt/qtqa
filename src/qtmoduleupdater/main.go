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
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
)

func setupEnvironmentForSubmoduleUpdateBot() (username string, err error) {
	submoduleUpdateBotKeyPath := "coin-secrets/submodule_update_bot_key_rsa"
	if _, err = os.Stat(submoduleUpdateBotKeyPath); os.IsNotExist(err) {
		err = fmt.Errorf("cannot locate submodule update bot SSH key file. Please copy it from the coin secrets repo into the current directory")
		return
	}

	os.Setenv("GIT_SSH_COMMAND", fmt.Sprintf("ssh -i %s", submoduleUpdateBotKeyPath))
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
	var productRef string
	flag.StringVar(&productRef, "product-ref", "", "Git ref in qt5 to use as basis for a new round of updates")
	manualStage := false
	flag.BoolVar(&manualStage, "manual-stage", false /*default*/, "Do not stage changes automatically")
	summaryOnly := false
	flag.BoolVar(&summaryOnly, "summarize", false /*default*/, "")
	verbose := false
	flag.BoolVar(&verbose, "verbose", false /*default*/, "Enable verbose logging output")
	reset := false
	flag.BoolVar(&reset, "reset", false, "Reset the batch update state")
	autorun := false
	flag.BoolVar(&autorun, "autorun", false, "Run automatically by reading settings from autorun.json")
	flag.Parse()

	if !verbose {
		oldWriter := log.Writer()
		defer log.SetOutput(oldWriter)
		log.SetOutput(ioutil.Discard)
	}

	if autorun {
		stageAsBot = true
	}

	gerrit := &gerritInstance{}
	gerrit.disableStaging = manualStage

	if stageAsBot {
		var err error
		gerrit.pushUserName, err = setupEnvironmentForSubmoduleUpdateBot()
		if err != nil {
			return fmt.Errorf("error preparing environment to work as submodule-update user: %s", err)
		}
		initSlackIntegration()
	}

	if autorun {
		autorun := &AutoRunSettings{}
		if err := autorun.load(); err != nil {
			return err
		}
		autorun.runUpdates(gerrit)
		return nil
	}

	if branch == "" {
		return fmt.Errorf("missing branch. Please specify -branch=<name of branch>")
	}

	batch, err := newModuleUpdateBatch(product, branch, productRef)
	if err != nil {
		return err
	}

	if summaryOnly {
		batch.printSummary()
		return nil
	}

	if reset {
		batch.clearStateCommit(gerrit)
		return nil
	}

	return batch.runOneIteration(gerrit)
}

func main() {
	err := appMain()
	if err != nil {
		log.Fatalf("Error: %s\n", err)
	}
}
