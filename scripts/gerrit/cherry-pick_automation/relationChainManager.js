/****************************************************************************
 **
 ** Copyright (C) 2020 The Qt Company Ltd.
 ** Contact: https://www.qt.io/licensing/
 **
 ** This file is part of the qtqa module of the Qt Toolkit.
 **
 ** $QT_BEGIN_LICENSE:LGPL$
 ** Commercial License Usage
 ** Licensees holding valid commercial Qt licenses may use this file in
 ** accordance with the commercial license agreement provided with the
 ** Software or, alternatively, in accordance with the terms contained in
 ** a written agreement between you and The Qt Company. For licensing terms
 ** and conditions see https://www.qt.io/terms-conditions. For further
 ** information use the contact form at https://www.qt.io/contact-us.
 **
 ** GNU Lesser General Public License Usage
 ** Alternatively, this file may be used under the terms of the GNU Lesser
 ** General Public License version 3 as published by the Free Software
 ** Foundation and appearing in the file LICENSE.LGPL3 included in the
 ** packaging of this file. Please review the following information to
 ** ensure the GNU Lesser General Public License version 3 requirements
 ** will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
 **
 ** GNU General Public License Usage
 ** Alternatively, this file may be used under the terms of the GNU
 ** General Public License version 2.0 or (at your option) the GNU General
 ** Public license version 3 or any later version approved by the KDE Free
 ** Qt Foundation. The licenses are as published by the Free Software
 ** Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
 ** included in the packaging of this file. Please review the following
 ** information to ensure the GNU General Public License requirements will
 ** be met: https://www.gnu.org/licenses/gpl-2.0.html and
 ** https://www.gnu.org/licenses/gpl-3.0.html.
 **
 ** $QT_END_LICENSE$
 **
 ****************************************************************************/

exports.id = "relationChainManager";

const toolbox = require("./toolbox");

class relationChainManager {
  constructor(retryProcessor, requestProcessor) {
    this.retryProcessor = retryProcessor;
    this.requestProcessor = requestProcessor;
    this.handleValidBranch = this.handleValidBranch.bind(this);
    this.requestProcessor.addListener(
      "relationChain_validBranchVerifyParent",
      this.handleValidBranch
    );
    this.handleValidBranchReadyForPick = this.handleValidBranchReadyForPick.bind(this);
    this.requestProcessor.addListener(
      "relationChain_validBranchReadyForPick",
      this.handleValidBranchReadyForPick
    );
    this.handleParentNotPicked = this.handleParentNotPicked.bind(this);
    this.requestProcessor.addListener(
      "relationChain_targetParentNotPicked",
      this.handleParentNotPicked
    );
    this.handleNewCherryPick = this.handleNewCherryPick.bind(this);
    this.requestProcessor.addListener("relationChain_newCherryPick", this.handleNewCherryPick);
    this.handleCherryPickDone = this.handleCherryPickDone.bind(this);
    this.requestProcessor.addListener("relationChain_cherryPickDone", this.handleCherryPickDone);
    this.handleStageEligibilityCheck = this.handleStageEligibilityCheck.bind(this);
    this.requestProcessor.addListener(
      "relationChain_checkStageEligibility",
      this.handleStageEligibilityCheck
    );
    this.handleCherrypickReadyForStage = this.handleCherrypickReadyForStage.bind(this);
    this.requestProcessor.addListener(
      "relationChain_cherrypickReadyForStage",
      this.handleCherrypickReadyForStage
    );
    this.handleCherrypickWaitForParent = this.handleCherrypickWaitForParent.bind(this);
    this.requestProcessor.addListener(
      "relationChain_cherrypickWaitParentMergeStage",
      this.handleCherrypickWaitForParent
    );
    this.handleStagingDone = this.handleStagingDone.bind(this);
    this.requestProcessor.addListener("relationChain_stagingDone", this.handleStagingDone);
  }

  start(currentJSON, branches) {
    let _this = this;

    // Determine if this change is the top-level change.
    let positionInChain = currentJSON.relatedChanges.findIndex((i) =>
      i.change_id === currentJSON.change.id);
    if (positionInChain === currentJSON.relatedChanges.length - 1) {
      // Since this change does not depend on anything, process it
      // as though it's not part of a chain.
      _this.requestProcessor.emit("processAsSingleChange", currentJSON, branches);
    } else {
      // This change is dependent on a parent in the chain. Begin the process.
      branches.forEach(function(branch) {
        _this.requestProcessor.emit(
          "validateBranch", currentJSON, branch,
          "relationChain_validBranchVerifyParent"
        );
      });
    }
  }

  handleValidBranch(currentJSON, branch, isRetry) {
    let _this = this;
    _this.requestProcessor.emit(
      "verifyParentPickExists", currentJSON, branch,
      "relationChain_validBranchReadyForPick",
      "relationChain_targetParentNotPicked",
      isRetry
    );
  }

  handleValidBranchReadyForPick(currentJSON, branch, detail) {
    let _this = this;
    _this.requestProcessor.emit(
      "validBranchReadyForPick", currentJSON, branch, detail.target,
      "relationChain_newCherryPick"
    );
  }

  handleParentNotPicked(currentJSON, branch, detail) {
    let _this = this;

    function setupListener(event, timeout, messageChangeId, messageOnSetup, messageOnTimeout) {
      // Listen for event only once
      // Cancel the event listener if timeout is set, since leaving listeners
      // is a memory leak, and a manually processed cherry pick MAY not retain
      // the same changeID)

      // Drop the listener after timeout if there's been no event.
      let timeoutHandle;
      if (event && timeout) {
        timeoutHandle = setTimeout(() => {
          _this.requestProcessor.removeAllListeners(event);
          // Post a message to gerrit if available.
          if (messageOnTimeout) {
            _this.requestProcessor.emit(
              "postGerritComment", messageChangeId, undefined, messageOnTimeout,
              "OWNER"
            );
          }
        }, timeout);
      }

      if (event) {
        console.log("Setting up a listener for:", event);
        _this.requestProcessor.once(
          event,
          function() {
            clearTimeout(timeoutHandle);
            setTimeout(function() {
              console.log("Firing delayed event.");
              _this.requestProcessor.emit(
                "relationChain_validBranchVerifyParent",
                currentJSON, branch
              );
            }, 2000);
          },
          1000
        );
      }
      if (messageChangeId && messageOnSetup) {
        _this.requestProcessor.emit(
          "postGerritComment", messageChangeId, undefined, messageOnSetup,
          "OWNER"
        );
      }
    }

    if (["NEW", "STAGED", "INTEGRATING"].some((element) => detail.error == element)) {
      // The parent has not yet been merged. Set up a listener and
      // re-run validation when the merge comes through. Wait for
      // 2 seconds before validating to help avoid a race condition
      // since the new merge will likely create the target cherry-pick
      // we would want to use as the target parent.
      // Also set up an abandoned listener on the parent. If it gets
      // abandoned, re-run the parent validation logic to post the
      // appropriate comment in gerrit.
      setupListener(`merge_${detail.unmergedChangeID}`);
      setupListener(`abandon_${detail.unmergedChangeID}`);
    } else if (detail.error == "notPicked") {
      // The change's parent was merged, but not picked. This could mean
      // that the parent left off pick-to footers, or that the pick hasn't
      // been completed yet.
      let parentCommitMessage =
        detail.parentJSON.revisions[detail.parentJSON.current_revision].commit.message;

      let parentPickBranches = toolbox.findPickToBranches(parentCommitMessage);
      let listenEvent = ``;
      let listenTimeout;
      let gerritMessageChangeID = "";
      let gerritMessage = "";
      let gerritMessageOnTimeout = "";
      if (parentPickBranches.length > 0) {
        // Maybe this is a race condition. The parent has a Pick-to footer
        // and is merged, but we couldn't find the change ID on the target
        // branch.
        if (parentPickBranches.includes(branch)) {
          // The target branch is on the parent as well, so there should
          // be a cherry-pick. Maybe it's not done processing in the bot yet.
          if (!detail.isRetry) {
            // Run the check again in 10 seconds to be sure we didn't just
            // miss close-timing.
            setTimeout(function() {
              _this.requestProcessor.emit(
                "relationChain_validBranchVerifyParent",
                currentJSON, branch, true
              );
            }, 5000);
          } else if (detail.isRetry) {
            // We already retried once. The target isn't going to exist
            // now if didn't on the first retry. Post a comment on gerrit.
            // Also set up a listener to pick up the target branch pick
            // inside 48 hours.
            gerritMessage = `A dependent to this change had a cherry-pick footer for ${branch}, but the pick for this change could not be found on ${branch}.\nIf this change should also be cherry-picked to ${branch}, please do so manually now.\n\nIf this pick to the target branch is completed in the next 48 hours and retains the same changeID, the dependent change will be picked automatically. A follow-up to this message will be posted if the automatic process expires.\n\nDependent change information:\nSubject: ${currentJSON.change.subject}\nChange Number: ${currentJSON.change.number}\nLink: ${currentJSON.change.url}`;
            listenEvent = `cherryPickCreated_${detail.targetPickParent}`;
            listenTimeout = 48 * 60 * 60 * 1000;
            gerritMessageChangeID = detail.parentChangeID;
            gerritMessageOnTimeout = `An automatic pick request for a dependent of this change to ${branch} has expired.\nPlease process the cherry-pick manually if required.\n\nDependent change information:\nSubject: ${currentJSON.change.subject}\nChange Number: ${currentJSON.change.number}\nLink: ${currentJSON.change.url}`;
          }
        } else {
          // The parent had a cherrypick footer, but it didn't have the target
          // branch in it. Alert the owner and set up a 48 hour listener
          // for the cherrypick.
          gerritMessage = `A dependent to this change had a cherry-pick footer for ${branch}, but this change doesn't include that branch. Did you forget to add it?\nIf this change should also be cherry-picked, please do so manually now.\n\nIf this pick to the target branch is completed in the next 48 hours and retains the same changeID, the dependent change will be picked automatically. A follow-up to this message will be posted if the automatic process expires.\n\nDependent change information:\nSubject: ${currentJSON.change.subject}\nChange Number: ${currentJSON.change.number}\nLink: ${currentJSON.change.url}`;
          listenEvent = `cherryPickCreated_${detail.targetPickParent}`;
          listenTimeout = 48 * 60 * 60 * 1000;
          gerritMessageChangeID = detail.parentChangeID;
          gerritMessageOnTimeout = `An automatic pick request for a dependent of this change to ${branch} has expired.\nPlease process the cherry-pick manually if required.\n\nDependent change information:\nSubject: ${currentJSON.change.subject}\nChange Number: ${currentJSON.change.number}\nLink: ${currentJSON.change.url}`;
        }
      } else {
        // Couldn't find any picks on the merged parent's commit message.
        // The user will need to create the cherry pick for the parent manually.
        // Set up a listener for that change ID and resume if we detect a pick.
        // Cancel the listener and post a comment after 48 hours if no pick
        // is detected.
        gerritMessage = `A dependent to this change had a cherry-pick footer for ${branch}, but this change doesn't. Did you forget to add it?\nIf this change should also be cherry-picked, please do so manually now.\n\nIf this pick to the target branch is completed in the next 48 hours and retains the same changeID, the dependent change will be picked automatically. A follow-up to this message will be posted if the automatic process expires.\n\nDependent change information:\nSubject: ${currentJSON.change.subject}\nChange Number: ${currentJSON.change.number}\nLink: ${currentJSON.change.url}`;
        listenEvent = `cherryPickCreated_${detail.targetPickParent}`;
        listenTimeout = 48 * 60 * 60 * 1000;
        gerritMessageChangeID = detail.parentChangeID;
        gerritMessageOnTimeout = `An automatic pick request for a dependent of this change to ${branch} has expired.\nPlease process the cherry-pick manually if required.\n\nDependent change information:\nSubject: ${currentJSON.change.subject}\nChange Number: ${currentJSON.change.number}\nLink: ${currentJSON.change.url}`;
      }
      // Set an event listener to call the verify parent step again when
      // the expected event occurs.
      if (listenEvent || listenTimeout || gerritMessageChangeID ||
          gerritMessage|| gerritMessageOnTimeout
      ) {
        setupListener(
          listenEvent, listenTimeout, gerritMessageChangeID,
          gerritMessage, gerritMessageOnTimeout
        );
      }
    } else if (detail.error == "ABANDONED") {
      // Customization point for additional handling if required.
    }
  }

  handleNewCherryPick(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "newCherryPick", parentJSON, cherryPickJSON,
      "relationChain_cherryPickDone"
    );
  }

  handleCherryPickDone(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "cherryPickDone", parentJSON, cherryPickJSON,
      "relationChain_checkStageEligibility"
    );
  }

  handleStageEligibilityCheck(originalRequestJSON, cherryPickJSON) {
    // Check the new cherry-pick's parent's status. If it is MERGED
    // or STAGED, it can be staged immediately. If it's INTEGRATING,
    // or NEW, Set up appropriate listeners and wait until we can
    // safely stage this pick.

    let _this = this;
    _this.requestProcessor.emit(
      "stageEligibilityCheck", originalRequestJSON, cherryPickJSON,
      "relationChain_cherrypickReadyForStage",
      "relationChain_cherrypickWaitParentMergeStage"
    );
  }

  handleCherrypickReadyForStage(originalRequestJSON, cherryPickJSON, parentChangeID, parentStatus) {
    // The status of the cherry-pick's parent ok. Stage the new cherry-pick.
    let _this = this;
    _this.requestProcessor.emit(
      "cherrypickReadyForStage", originalRequestJSON, cherryPickJSON,
      "relationChain_stagingDone"
    );
  }

  handleCherrypickWaitForParent(originalRequestJSON, cherryPickJSON, parentChangeID, parentStatus) {
    // The cherry-pick's parent is not ready yet. Start wait listeners for it.
    let _this = this;
    function setupListener(event, timeout, messageChangeId, messageOnSetup, messageOnTimeout) {
      // Listen for event only once. The listener is consumed if triggered.
      // Cancel the event listener if timeout is set, since leaving listeners
      // is a memory leak, and a manually processed cherry pick MAY not retain
      // the same changeID)

      // Drop the listener after timeout if there's been no event.
      let timeoutHandle;
      if (event && timeout) {
        timeoutHandle = setTimeout(function() {
          _this.requestProcessor.removeAllListeners(event);
          // Post a message to gerrit if available.
          if (messageOnTimeout) {
            _this.requestProcessor.emit(
              "postGerritComment", messageChangeId, undefined, messageOnTimeout,
              "OWNER"
            );
          }
        }, timeout);
      }

      if (event) {
        _this.requestProcessor.once(event, function() {
          clearTimeout(timeoutHandle);
          setTimeout(function() {
            _this.requestProcessor.emit(
              "relationChain_checkStageEligibility",
              originalRequestJSON, cherryPickJSON
            );
          }, 10000);
        }, 1000);
      }
      if (messageChangeId && messageOnSetup) {
        _this.requestProcessor.emit(
          "postGerritComment", messageChangeId, undefined, messageOnSetup,
          "OWNER"
        );
      }
    }

    let listenTimeout = 24 * 2 * 60 * 60 * 1000;
    let gerritMessage = "";
    let gerritMessageOnTimeout = "";
    if (parentStatus == "NEW") {
      gerritMessage = `This cherry-pick is ready to be automatically staged, but it's parent is not staged or merged.\n\nCherry-pick bot will wait for the parent to stage for the next 48 hours.\nIf this window expires, a follow up message will be posted and you will need to stage this pick manually.`;
      gerritMessageOnTimeout =
        "An automatic staging request for this pick has expired because it's parent did not stage in a timely manner.\nPlease stage this cherry-pick manually as appropriate.";
      console.log("Configured listener for:", `staged_${parentChangeID}`);
      setupListener(
        `staged_${parentChangeID}`,
        listenTimeout, cherryPickJSON.id, gerritMessage, gerritMessageOnTimeout
      );
    } else if (parentStatus == "INTEGRATING") {
      gerritMessage = `This cherry-pick is ready to be automatically staged, but it's parent is currently integrating.\n\nCherry-pick bot will wait for the parent to successfully merge for the next 48 hours.\nIf this window expires, a follow up message will be posted and you will need to stage this pick manually.`;
      gerritMessageOnTimeout =
        "An automatic staging request for this pick has expired because it's parent did not merge in a timely manner.\nPlease stage this cherry-pick manually as appropriate.";
      setupListener(
        `merge_${parentChangeID}`,
        listenTimeout, cherryPickJSON.id, gerritMessage, gerritMessageOnTimeout
      );
    }
    setupListener(`abandon_${parentChangeID}`, listenTimeout);
  }

  handleStagingDone(success, data) {
    let _this = this;
    // Stub for later expansion.
  }
}
module.exports = relationChainManager;
