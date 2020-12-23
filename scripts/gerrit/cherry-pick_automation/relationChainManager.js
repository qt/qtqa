/* eslint-disable no-unused-vars */
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

const safeJsonStringify = require("safe-json-stringify");

const toolbox = require("./toolbox");

class relationChainManager {
  constructor(logger, retryProcessor, requestProcessor) {
    this.logger = logger;
    this.retryProcessor = retryProcessor;
    this.requestProcessor = requestProcessor;
    this.checkLtsTarget = this.checkLtsTarget.bind(this);
    this.requestProcessor.addListener(
      "relationChain_checkLtsTarget",
      this.checkLtsTarget
    );
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

    _this.logger.log(
      `Starting RelationChain Manager process for ${currentJSON.fullChangeID}`,
      "verbose", currentJSON.uuid
    );

    // Determine if this change is the top-level change.
    let positionInChain = currentJSON.relatedChanges.findIndex((i) =>
      i.change_id === currentJSON.change.id);
    if (positionInChain === currentJSON.relatedChanges.length - 1) {
      // Since this change does not depend on anything, process it
      // as though it's not part of a chain.
      _this.logger.log(
        `Change ${currentJSON.fullChangeID} is the top level in it's relation chain`,
        "debug", currentJSON.uuid
      );
      _this.requestProcessor.emit("processAsSingleChange", currentJSON, branches);
    } else {
      // This change is dependent on a parent in the chain. Begin the process.
      _this.logger.log(
        `Kicking off the process for each branch in  ${safeJsonStringify(Array.from(branches))}`,
        "verbose", currentJSON.uuid
      );
      branches.forEach(function (branch) {
        _this.requestProcessor.emit(
          "validateBranch", _this.requestProcessor.toolbox.deepCopy(currentJSON), branch,
          "relationChain_checkLtsTarget"
        );
      });
    }
  }

  checkLtsTarget(currentJSON, branch) {
    let _this = this;
    _this.requestProcessor.emit(
      "checkLtsTarget", currentJSON, branch, undefined,
      "relationChain_validBranchVerifyParent"
    );
  }

  handleValidBranch(currentJSON, branch, branchHeadSha, isRetry) {
    let _this = this;
    toolbox.getDBSubState(currentJSON.uuid, branch, (success, state) => {
      if (success) {
        let ignore_states = ["done_", "validateBranch", "checkLtsTarget"]
        if (ignore_states.some(val => state.includes(val))) {
          _this.requestProcessor.emit(
            "verifyParentPickExists", currentJSON, branch,
            "relationChain_validBranchReadyForPick",
            "relationChain_targetParentNotPicked",
            isRetry
          );
        } else {
          _this.logger.log(
            `Ignoring new request to process ${
              branch}. An in-process item already exists with state: ${state}`,
            "info", currentJSON.uuid
          );
        }
      } else {
        _this.requestProcessor.emit(
          "verifyParentPickExists", currentJSON, branch,
          "relationChain_validBranchReadyForPick",
          "relationChain_targetParentNotPicked",
          isRetry
        );
      }
    });
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

    let sanitizedBranch = /(?:tqtc\/lts-)?(.+)/.exec(branch).pop()
    let parentCommitMessage =
      detail.parentJSON.revisions[detail.parentJSON.current_revision].commit.message;
    let parentPickBranches = toolbox.findPickToBranches(currentJSON.uuid, parentCommitMessage);

    let listenEvent = ``;
    let messageTriggerEvent = "";
    let messageCancelTriggerEvent = "";
    let listenTimeout;
    let gerritMessageChangeID = "";
    let gerritMessage = "";
    let gerritMessageOnTimeout = "";
    let pickToNearestParent = false;
    let targetPickID = `${encodeURIComponent(currentJSON.change.project)}~${encodeURIComponent(branch)}~${
      currentJSON.change.id
    }`;

    if (["NEW", "STAGED", "INTEGRATING"].some((element) => detail.error == element)) {
      // The parent has not yet been merged. Set up a listener and
      // re-run validation when the merge comes through. Wait for
      // 2 seconds before validating to help avoid a race condition
      // since the new merge will likely create the target cherry-pick
      // we would want to use as the target parent.
      // Also set up an abandoned listener on the parent. If it gets
      // abandoned, re-run the parent validation logic to post the
      // appropriate comment in gerrit.

      if (parentPickBranches.size > 0) {
        listenEvent = `cherryPickCreated_${detail.targetPickParent}`;
        listenTimeout = 48 * 60 * 60 * 1000;
        gerritMessageChangeID = detail.unmergedChangeID;

        if (parentPickBranches.has(branch)) {
          // The parent is suitable, just needs to be merged so it can be
          // cherry-picked.
          toolbox.setupListener(
            _this.requestProcessor, `merge_${detail.unmergedChangeID}`, undefined, undefined,
            48 * 60 * 60 * 1000, undefined, undefined,
            undefined, undefined,
            undefined,
            undefined, currentJSON.uuid, true
          );
          toolbox.setupListener(
            _this.requestProcessor, `abandon_${detail.unmergedChangeID}`, undefined, undefined,
            48 * 60 * 60 * 1000, undefined, undefined,
            undefined, undefined,
            undefined,
            undefined, currentJSON.uuid, true
          );
        } else {
          // The direct parent doesn't include the branch that this
          // change is supposed to be picked to. Locate the nearest
          // change that does and create a pick with that.
          // Post a comment on gerrit about this if the pick to nearest parent
          // results in a merge conflict and cannot be staged automatically.
          pickToNearestParent = true;
          gerritMessage = `A dependent to this change had a cherry-pick footer for`
          + ` ${sanitizedBranch}, but this change's cherry-pick footer doesn't include that branch.`
          + ` Did you forget to add it?\nIf this change should also be cherry-picked, please`
          + ` update the commit-message footer or create the cherry-pick manually.`
          + `\n\nIf this change is picked to ${branch} in the next 48 hours and retains the same`
          + ` Change-Id, the dependent change's cherry-pick will be reparented automatically if`
          + ` it has not yet been staged/merged.`
          + `\n\nDependent change information:`
          + `\nSubject: ${currentJSON.change.subject}`
          + `\nChange Number: ${currentJSON.change.number}`
          + `\nLink: ${currentJSON.change.url}`;
          messageTriggerEvent = `mergeConflict_${targetPickID}`;
          messageCancelTriggerEvent = `staged_${targetPickID}`;
        }
      } else {
        // The direct parent doesn't include a pick-to footer.
        // Locate the nearest change that does and create a pick with that.
        // Post a comment on gerrit about this.
        pickToNearestParent = true;
        gerritMessage = `A dependent to this change had a cherry-pick footer for`
        + ` ${sanitizedBranch}, but this change doesn't have one. Did you forget to add it?`
        + `\nIf this change should also be cherry-picked, please add a`
        + ` "Pick-to: ${sanitizedBranch}" footer or create the cherry-pick manually.`
        + `\n\nIf this change is picked to ${branch} in the next 48 hours and retains the same`
        + ` Change-Id, the dependent change's cherry-pick will be reparented automatically if`
        + ` it has not yet been staged/merged.`
        + `\n\nDependent change information:`
        + `\nSubject: ${currentJSON.change.subject}`
        + `\nChange Number: ${currentJSON.change.number}`
        + `\nLink: ${currentJSON.change.url}`;
        messageTriggerEvent = `mergeConflict_${targetPickID}`;
        messageCancelTriggerEvent = `staged_${targetPickID}`;
      }
    } else if (detail.error == "notPicked") {
      // The change's parent was merged, but not picked. This could mean
      // that the parent left off pick-to footers, or that the pick hasn't
      // been completed yet.
      if (parentPickBranches.size > 0) {
        // Maybe this is a race condition. The parent has a Pick-to footer
        // and is merged, but we couldn't find the change ID on the target
        // branch.
        if (parentPickBranches.has(sanitizedBranch)) {
          // The target branch is on the parent as well, so there should
          // be a cherry-pick. Maybe it's not done processing in the bot yet.
          if (!detail.isRetry) {
            // Run the check again in 8 seconds to be sure we didn't just
            // miss close-timing.
            setTimeout(function () {
              _this.requestProcessor.emit(
                "verifyParentPickExists", currentJSON, branch,
                "relationChain_validBranchReadyForPick",
                "relationChain_targetParentNotPicked",
                true
              );
            }, 8000);
          } else if (detail.isRetry) {
            // We already retried once. The target isn't going to exist
            // now if didn't on the first retry. Post a comment on gerrit.
            // Also set up a listener to pick up the target branch pick
            // inside 48 hours.
            gerritMessage = `A dependent to this change had a cherry-pick footer for`
            + ` ${sanitizedBranch}, but the pick for this change could not be found on ${branch}.`
            + `\nIf this change should also be cherry-picked to ${branch}, please do so manually`
            + ` now.`
            + `\n\nIf this pick to the target branch is completed in the next 48 hours and retains`
            + ` the same Change-Id, the dependent change's cherry-pick will be reparented`
            + ` automatically if it has not yet been staged/merged. A follow-up to this message`
            + ` will be posted if the automatic process expires.`
            + `\n\nDependent change information:`
            + `\nSubject: ${currentJSON.change.subject}`
            + `\nChange Number: ${currentJSON.change.number}`
            + `\nLink: ${currentJSON.change.url}`;
            listenEvent = `cherryPickCreated_${detail.targetPickParent}`;
            listenTimeout = 48 * 60 * 60 * 1000;
            gerritMessageChangeID = detail.parentChangeID;
            gerritMessageOnTimeout = `An automatic pick request for a dependent of this change to`
            + ` ${sanitizedBranch} has expired.\nPlease process the cherry-pick manually if`
            + ` required.`
            + `\n\nDependent change information:`
            + `\nSubject: ${currentJSON.change.subject}`
            + `\nChange Number: ${currentJSON.change.number}`
            + `\nLink: ${currentJSON.change.url}`;
            messageTriggerEvent = `mergeConflict_${targetPickID}`;
            messageCancelTriggerEvent = `staged_${targetPickID}`;
            // Pretty sure this isn't a race condition, so go ahead and
            // create the pick on the nearest parent with a pick
            // on the target branch.
            pickToNearestParent = true;
          }
        } else {
          // The parent had a cherrypick footer, but it didn't have the target
          // branch in it. Alert the owner and set up a 48 hour listener
          // for the cherrypick.
          gerritMessage = `A dependent to this change had a cherry-pick footer for`
          + ` ${sanitizedBranch}, but this change's cherry-pick footer doesn't include that branch.`
          + ` Did you forget to add it?\nIf this change should also be cherry-picked, please do so`
          + ` manually now.\n\nIf this pick to the target branch is completed in the next 48 hours`
          + ` and retains the same Change-Id, the dependent change's cherry-pick will be reparented`
          + ` automatically if it has not yet been staged/merged. A follow-up to this message will`
          + ` be posted if the automatic process expires.`
          + `\n\nDependent change information:`
          + `\nSubject: ${currentJSON.change.subject}`
          + `\nChange Number: ${currentJSON.change.number}`
          + `\nLink: ${currentJSON.change.url}`;
          listenEvent = `cherryPickCreated_${detail.targetPickParent}`;
          listenTimeout = 48 * 60 * 60 * 1000;
          gerritMessageChangeID = detail.parentChangeID;
          gerritMessageOnTimeout = `An automatic pick request for a dependent of this change to`
          + ` ${sanitizedBranch} has expired.\nPlease process the cherry-pick manually if required.`
          + `\n\nDependent change information:`
          + `\nSubject: ${currentJSON.change.subject}`
          + `\nChange Number: ${currentJSON.change.number}`
          + `\nLink: ${currentJSON.change.url}`;
          messageTriggerEvent = `mergeConflict_${targetPickID}`;
          messageCancelTriggerEvent = `staged_${targetPickID}`;
          // Pick to the nearest parent on the target branch.
          // It'll get updated if the expected target pick is made.
          pickToNearestParent = true;
        }
      } else {
        // Couldn't find any picks on the merged parent's commit message.
        // The user will need to create the cherry pick for the parent manually.
        // Set up a listener for that change ID and resume if we detect a pick.
        // Cancel the listener and post a comment after 48 hours if no pick
        // is detected.
        gerritMessage = `A dependent to this change had a cherry-pick footer for`
        + ` ${sanitizedBranch}, but this change doesn't. Did you forget to add it?`
        + `\nIf this change should also be cherry-picked, please do so manually now.`
        + `\n\nIf this pick to the target branch is completed in the next 48 hours and retains the`
        + ` same Change-Id, the dependent change's cherry-pick will be reparented automatically`
        + ` if it has not yet been staged/merged. A follow-up to this message will be posted if`
        + ` the automatic process expires.`
        + `\n\nDependent change information:`
        + `\nSubject: ${currentJSON.change.subject}`
        + `\nChange Number: ${currentJSON.change.number}`
        + `\nLink: ${currentJSON.change.url}`;
        listenEvent = `cherryPickCreated_${detail.targetPickParent}`;
        listenTimeout = 48 * 60 * 60 * 1000;
        gerritMessageChangeID = detail.parentChangeID;
        gerritMessageOnTimeout = `An automatic pick request for a dependent of this change to`
        + ` ${sanitizedBranch} has expired.\nPlease process the cherry-pick manually if required.`
        + `\n\nDependent change information:`
        + `\nSubject: ${currentJSON.change.subject}`
        + `\nChange Number: ${currentJSON.change.number}`
        + `\nLink: ${currentJSON.change.url}`;
        messageTriggerEvent = `mergeConflict_${targetPickID}`;
        messageCancelTriggerEvent = `staged_${targetPickID}`;
        pickToNearestParent = true;
      }
    } else if (detail.error == "ABANDONED") {
      pickToNearestParent = true;
    }

    // Set an event listener to call the verify parent step again when
    // the expected event occurs.
    if (listenEvent || listenTimeout || gerritMessageChangeID ||
        gerritMessage|| gerritMessageOnTimeout
    ) {
      // set up the listener as requested.
      toolbox.setupListener(
        _this.requestProcessor, listenEvent, messageTriggerEvent, messageCancelTriggerEvent,
        listenTimeout, undefined, gerritMessageChangeID,
        gerritMessage, gerritMessageOnTimeout,
        "relationChain_validBranchVerifyParent",
        [currentJSON, branch], currentJSON.uuid, true
      );
    }

    if (pickToNearestParent) {
      _this.requestProcessor.emit(
        "locateNearestParent", currentJSON, undefined, branch,
        "relationChain_validBranchReadyForPick"
      );
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

    let listenTimeout = 24 * 2 * 60 * 60 * 1000;
    let gerritMessage = "";
    let gerritMessageOnTimeout = "";
    if (parentStatus == "NEW") {
      gerritMessage = `This cherry-pick is ready to be automatically staged, but it's parent is not`
      + ` staged or merged.`
      + `\n\nCherry-pick bot will wait for the parent to stage for the next 48 hours.`
      + `\nIf this window expires, a follow up message will be posted and you will need to`
      + ` stage this pick manually.`;
      gerritMessageOnTimeout =
        "An automatic staging request for this pick has expired because it's parent did not stage"
        + " in a timely manner.\nPlease stage this cherry-pick manually as appropriate.";
      toolbox.setupListener(
        _this.requestProcessor, `staged_${parentChangeID}`, undefined, undefined,
        listenTimeout, undefined, cherryPickJSON.id,
        gerritMessage, gerritMessageOnTimeout,
        "relationChain_checkStageEligibility",
        [originalRequestJSON, cherryPickJSON], originalRequestJSON.uuid, true
      );
    } else if (parentStatus == "INTEGRATING") {
      gerritMessage = `This cherry-pick is ready to be automatically staged, but it's parent is`
      + ` currently integrating.`
      + `\n\nCherry-pick bot will wait for the parent to successfully merge for the next 48 hours.`
      + `\nIf this window expires, a follow up message will be posted and you will need to`
      + ` stage this pick manually.`;
      gerritMessageOnTimeout =
        "An automatic staging request for this pick has expired because it's parent did not merge"
        + " in a timely manner.\nPlease stage this cherry-pick manually as appropriate.";
      toolbox.setupListener(
        _this.requestProcessor, `merge_${parentChangeID}`, undefined, undefined,
        listenTimeout, undefined, cherryPickJSON.id,
        gerritMessage, gerritMessageOnTimeout,
        "relationChain_checkStageEligibility",
        [originalRequestJSON, cherryPickJSON], originalRequestJSON.uuid, true
      );
    }
    toolbox.setupListener(
      _this.requestProcessor, `abandon_${parentChangeID}`, undefined, undefined,
      listenTimeout, undefined, undefined,
      undefined, undefined,
      "relationChain_checkStageEligibility",
      [originalRequestJSON, cherryPickJSON], originalRequestJSON.uuid, true
    );
  }

  handleStagingDone(success, parentJSON, cherryPickJSON) {
    let _this = this;
    // Stub for later expansion.
  }
}
module.exports = relationChainManager;
