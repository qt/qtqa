/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "singleRequestManager";

const safeJsonStringify = require("safe-json-stringify");

const { findPickToBranches } = require("./toolbox");
const gerritTools = require("./gerritRESTTools");

// The singleRequestManager processes incoming changes linerally.
// When start() is called, the request progresses through branch
// validation, tries to create a cherry pick, and tries to stage it.
class singleRequestManager {
  constructor(logger, retryProcessor, requestProcessor) {
    this.logger = logger;
    this.retryProcessor = retryProcessor;
    this.requestProcessor = requestProcessor;
    this.handleValidBranch = this.handleValidBranch.bind(this);
    this.requestProcessor.addListener(
      "singleRequest_validBranch",
      this.handleValidBranch
    );
    this.ltsTargetChecked = this.ltsTargetChecked.bind(this);
    this.requestProcessor.addListener(
      "singleRequest_ltsTargetChecked",
      this.ltsTargetChecked
    );
    this.handleNewCherryPick = this.handleNewCherryPick.bind(this);
    this.requestProcessor.addListener("singleRequest_newCherryPick", this.handleNewCherryPick);
    this.handleCherryPickDone = this.handleCherryPickDone.bind(this);
    this.requestProcessor.addListener("singleRequest_cherryPickDone", this.handleCherryPickDone);
    this.handleCherrypickReadyForStage = this.handleCherrypickReadyForStage.bind(this);
    this.requestProcessor.addListener(
      "singleRequest_cherrypickReadyForStage",
      this.handleCherrypickReadyForStage
    );
    this.handleStagingDone = this.handleStagingDone.bind(this);
    this.requestProcessor.addListener("singleRequest_stagingDone", this.handleStagingDone);
  }

  start(parentJSON, picks) {
    let _this = this;

    function emit(parentCopy, branch) {
      _this.requestProcessor.emit(
        "validateBranch", parentCopy, branch,
        "singleRequest_validBranch"
      );
    }
    _this.logger.log(
      `Starting SingleRequest Manager process for ${parentJSON.fullChangeID}`,
      "verbose", parentJSON.uuid
    );
    Object.keys(picks).forEach(function (branch) {
      let parentCopy = _this.requestProcessor.toolbox.deepCopy(parentJSON)
      if (picks[branch].length > 0) {
        const originalPicks = Array.from(findPickToBranches(parentCopy.uuid, parentCopy.change.commitMessage));
        let missing = picks[branch].filter(x => !originalPicks.includes(x));
        // Check the target branch itself since it may not be in originalPicks and could have been
        // added by the bot.
        if (!originalPicks.includes(branch))
          missing.push(branch);
        if (missing.length > 0) {
          gerritTools.locateDefaultAttentionUser(parentJSON.uuid, parentCopy,
            parentJSON.patchSet.uploader.email, function(user) {
              function postComment() {
                const plural = missing.length > 1;
                _this.requestProcessor.gerritCommentHandler(parentCopy.uuid,
                  parentCopy.fullChangeID, undefined,
                  `Automatic cherry-picking detected missing Pick-to targets.`
                  +`\nTarget${plural ? 's' : ''} "${missing.join(", ")}"`
                  + ` ${plural ? "have" : "has"} been automatically added to the`
                  + ` cherry-pick for ${branch}.\nPlease review for correctness.`);
              }

              if (user && user == "copyReviewers") {
                // Do nothing since we don't have a default attention user.
                // This typically means the change was self-approved.
              } else {
                gerritTools.setChangeReviewers(parentJSON.uuid, parentCopy.fullChangeID,
                  [user], undefined, function() {
                    gerritTools.addToAttentionSet(
                      parentJSON.uuid, parentCopy, user, "Relevant user",
                      parentJSON.customGerritAuth,
                      function (success, data) {
                        if (!success) {
                          _this.logger.log(
                            `Failed to add "${safeJsonStringify(parentJSON.change.owner)}" to the`
                            + ` attention set of ${parentCopy.id}\n`
                            + `Reason: ${safeJsonStringify(data)}`,
                            "error", parentJSON.uuid
                          );
                        }
                        postComment();
                      }
                    );
                  });
              }
            });
          }
        parentCopy.change.commitMessage = parentCopy.change.commitMessage
          .replace(/^Pick-to:.+$/gm, `Pick-to: ${picks[branch].join(" ")}`);
        emit(parentCopy, branch);
      } else {
        parentCopy.change.commitMessage = parentCopy.change.commitMessage
          .replace(/^Pick-to:.+$\n/gm, "");
        emit(parentCopy, branch);
      }
    });
  }

  handleValidBranch(parentJSON, branch, newParentRev) {
    let _this = this;
    _this.requestProcessor.emit(
      "checkLtsTarget", parentJSON, branch, newParentRev,
      "singleRequest_ltsTargetChecked"
    );
  }

  ltsTargetChecked(parentJSON, branch, newParentRev) {
    let _this = this;
    _this.requestProcessor.emit(
      "validBranchReadyForPick", parentJSON, branch, newParentRev,
      "singleRequest_newCherryPick"
    );
  }

  handleNewCherryPick(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "newCherryPick", parentJSON, cherryPickJSON,
      "singleRequest_cherryPickDone"
    );
  }

  handleCherryPickDone(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "cherryPickDone", parentJSON, cherryPickJSON,
      "singleRequest_cherrypickReadyForStage"
    );
  }

  handleCherrypickReadyForStage(parentJSON, cherryPickJSON) {
    let _this = this;
    _this.requestProcessor.emit(
      "cherrypickReadyForStage", parentJSON, cherryPickJSON,
      "singleRequest_stagingDone"
    );
  }

  handleStagingDone(success, data) {
    let _this = this;
    // Stub for later expansion.
  }
}
module.exports = singleRequestManager;
