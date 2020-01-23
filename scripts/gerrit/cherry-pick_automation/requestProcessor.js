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

const EventEmitter = require("events");
const toolbox = require("./toolbox");
const gerritTools = require("./gerritRESTTools");
const emailClient = require("./emailClient");
const config = require("./config");

class requestProcessor extends EventEmitter {
  constructor(retryProcessor) {
    super();
    this.retryProcessor = retryProcessor;
  }

  processMerge(uuid) {
    let _this = this;

    let incoming = {};
    toolbox.retrieveRequestJSONFromDB(uuid, function(success, data) {
      if (!success) {
        console.log(`ERROR: Database access error on uuid key: ${uuid}`, data);
        return;
      } else {
        incoming = data;

        // Set the state to processing.
        toolbox.setDBState(incoming.uuid, "processing", function(
          success,
          data
        ) {
          if (!success) {
            console.trace(data);
          }
        });

        // Parse the commit message and look for branches to pick to
        const branches = toolbox.findPickToBranches(
          incoming.change.commitMessage
        );
        if (branches.size == 0) {
          // The change did not have a "Pick To: " keyword or "Pick To:" did not include any branches.
          toolbox.setDBState(incoming.uuid, "discarded", function(
            success,
            data
          ) {
            toolbox.moveFinishedRequest(
              "processing_queue",
              "uuid",
              incoming.uuid
            );
          });
        } else {
          console.log(
            `Found ${branches.size} branches to pick to for ${incoming.uuid}`
          );
          toolbox.setPickCountRemaining(incoming.uuid, branches.size, function(
            success,
            data
          ) {});
        }

        branches.forEach(function(branch) {
          _this.emit("validateBranch", incoming, branch);
        });
      }
    });
  }

  validateBranch(incoming, branch) {
    // For each branch found, validate it and kick off the next process.
    let _this = this;
    gerritTools.validateBranch(incoming.change.project, branch, function(
      success,
      data
    ) {
      if (success) {
        _this.emit("validBranchReadyForPick", incoming, branch, data);
      } else if (data == "retry") {
        _this.retryProcessor.addRetryJob("validateBranch", [incoming, branch]);
      } else {
        console.trace(`Branch validation failed for ${branch}.`);
        const message = `Failed to cherry pick to ${branch}.\nReason: ${branch} is invalid.`;
        const notifyScope = "OWNER";
        _this.gerritCommentHandler(
          incoming.fullChangeID,
          undefined,
          message,
          notifyScope
        );
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid,
          { branch: branch },
          "done_invalidBranch",
          toolbox.decrementPickCountRemaining(incoming.uuid)
        );
      }
    });
  }

  // Generate a cherry pick and take some action based on the result
  doCherryPick(incoming, branch, newParentRev) {
    let _this = this;
    console.log(`Validated branch ${branch} is at revision ${newParentRev}`);
    toolbox.addToCherryPickStateUpdateQueue(
      incoming.uuid,
      { branch: branch, revision: newParentRev },
      "pickStarted"
    );
    gerritTools.generateCherryPick(incoming, newParentRev, branch, function(
      success,
      data
    ) {
      console.log(`cherry-pick result - ${success}:`, data);
      if (success) {
        _this.gerritCommentHandler(
          incoming.fullChangeID,
          undefined,
          `Successfully created cherry-pick to ${branch}`
        );
        // Result looks okay, let's see what to do next.
        _this.emit("newCherryPick", incoming, data);
      } else if (data.statusCode) {
        // Failed to cherry pick to target branch. Post a comment on the original change
        // and stop paying attention to this pick.
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid,
          {
            branch: branch,
            statusCode: data.statusCode,
            statusDetail: data.statusDetail
          },
          "done_pickFailed",
          toolbox.decrementPickCountRemaining(incoming.uuid)
        );
        _this.gerritCommentHandler(
          incoming.fullChangeID,
          undefined,
          `Failed to cherry pick to ${branch}.\nReason: ${data.statusCode}: ${data.statusDetail}`
        );
      } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid,
          { branch: branch },
          "pickCreateRetryWait"
        );
        _this.retryProcessor.addRetryJob("validBranchReadyForPick", [
          incoming,
          branch,
          newParentRev
        ]);
      } else {
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid,
          {
            branch: branch,
            statusCode: "",
            statusDetail: "Unknown HTTP error. Contact the Administrator."
          },
          "done_pickFailed",
          toolbox.decrementPickCountRemaining(incoming.uuid)
        );
        emailClient.genericSendEmail(
          config.ADMIN_EMAIL,
          "Cherry-pick bot: Error in Cherry Pick request",
          undefined,
          JSON.stringify(data, undefined, 4)
        );
      }
    });
  }

  // For a newly created cherry pick, give codereview +2 and stage if there are no conflicts.
  // Notify the owner and re-add reviewers if there are conflicts.
  processNewCherryPick(parentJSON, cherrypickJSON) {
    let _this = this;
    if (cherrypickJSON.contains_git_conflicts) {
      gerritTools.copyChangeReviewers(
        parentJSON.fullChangeID,
        cherrypickJSON.id,
        function() {
          _this.gerritCommentHandler(
            cherrypickJSON.id,
            undefined,
            `INFO: This cherry-pick from your recently merged change on ${parentJSON.branch} has merge conflicts.\nPlease review.`
          );
          // We're done with this one since it now needs human review.
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            { branch: cherrypickJSON.branch },
            "done_mergeConflicts",
            toolbox.decrementPickCountRemaining(parentJSON.uuid)
          );
        }
      );
    } else {
      _this.emit("cherryPickDone", parentJSON, cherrypickJSON);
    }
  }

  autoApproveCherryPick(parentJSON, cherrypickJSON) {
    // The resulting cherry pick passed all requirements for automatic merging.
    // Need to +2 the change before staging!!!
    let _this = this;
    const approvalmsg = `This change is being approved because it was automatically cherry-picked from dev and contains no merge conflicts.`;
    gerritTools.setApproval(
      parentJSON.uuid,
      cherrypickJSON,
      2,
      approvalmsg,
      "NONE",
      function(success, data) {
        if (success) {
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            {
              branch: cherrypickJSON.branch
            },
            "approvalSet"
          );
          _this.emit("cherrypickReadyForStage", parentJSON, cherrypickJSON);
        } else if (data == "retry") {
          console.log(
            `Failed to approve pick ${cherrypickJSON.id} due to a network issue. Retrying in a bit.`
          );
          _this.retryProcessor.addRetryJob("cherryPickDone", [
            parentJSON,
            cherrypickJSON
          ]);
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            {
              branch: cherrypickJSON.branch
            },
            "setApprovalRetryWait"
          );
          // Do nothing. This callback function will be called again on retry.
        } else {
          // This shouldn't happen. The bot should never be denied a +2.
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            {
              branch: cherrypickJSON.branch,
              statusDetail: data ? data : undefined
            },
            "setApprovalFailed"
          );
          _this.gerritCommentHandler(
            cherrypickJSON.id,
            undefined,
            `INFO: The Cherry-Pick bot was unable to automatically approve this change. Please review.\nReason:${
              data
                ? JSON.stringify(data, undefined, 4)
                : "Unknown error. Please contact the gerrit admins."
            }`,
            "OWNER"
          );
        }
      }
    );
  }

  stageCherryPick(parentJSON, cherrypickJSON) {
    let _this = this;
    gerritTools.stageCherryPick(parentJSON.uuid, cherrypickJSON, function(
      success,
      data
    ) {
      if (success) {
        toolbox.addToCherryPickStateUpdateQueue(
          parentJSON.uuid,
          { branch: cherrypickJSON.branch },
          "staged",
          toolbox.decrementPickCountRemaining(parentJSON.uuid)
        );
      } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
        console.log(
          `Failed to stage cherry pick ${cherrypickJSON.id} due to a network issue. Retrying in a bit.`
        );
        _this.retryProcessor.addRetryJob("cherrypickReadyForStage", [
          parentJSON,
          cherrypickJSON
        ]);

        toolbox.addToCherryPickStateUpdateQueue(
          parentJSON.uuid,
          {
            branch: cherrypickJSON.branch
          },
          "stageFailedRetryWait"
        );
      } else {
        _this.gerritCommentHandler(
          cherrypickJSON.id,
          undefined,
          `INFO: The cherry-pick bot failed to automatically stage this change to CI. Please try to stage it manually.\n\nContact gerrit administration if you continue to experience issues.\n\nReason: ${
            data
              ? JSON.stringify(data, undefined, 4)
              : "Unknown error. Please contact the gerrit admins."
          }`,
          "OWNER"
        );
        toolbox.addToCherryPickStateUpdateQueue(
          parentUuid,
          {
            branch: cherrypickJSON.branch,
            statusDetail: data.response ? data.response.data : error.message,
            statusCode: error.response ? error.response.status : ""
          },
          "stageFailed",
          toolbox.decrementPickCountRemaining(parentJSON.uuid)
        );
      }
    });
  }

  gerritCommentHandler(fullChangeID, revision, message, notifyScope) {
    gerritTools.postGerritComment(
      fullChangeID,
      revision,
      message,
      notifyScope,
      function(success, data) {
        if (!success && data == "retry") {
          _this.emit("addRetryJob", "postGerritComment", [
            incoming.fullChangeID,
            undefined,
            message,
            notifyScope
          ]);
        }
      }
    );
  }
}

module.exports = requestProcessor;
