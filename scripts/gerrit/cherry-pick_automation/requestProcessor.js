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

  // Pull the request from the database and start processing it.
  processMerge(uuid) {
    let _this = this;

    let incoming = {};
    toolbox.retrieveRequestJSONFromDB(uuid, function(success, data) {
      if (!success) {
        console.log(`ERROR: Database access error on uuid key: ${uuid}`, data);
        return;
      }

      incoming = data;

      // Set the state to processing.
      toolbox.setDBState(incoming.uuid, "processing", function(success, data) {
        if (!success)
          console.trace(data);
      });

      // Parse the commit message and look for branches to pick to
      const branches = toolbox.findPickToBranches(incoming.change.commitMessage);
      if (branches.size == 0) {
        // The change did not have a "Pick-to: " keyword or "Pick-to:"
        // did not specify any branches.
        toolbox.setDBState(incoming.uuid, "discarded", function(success, data) {
          toolbox.moveFinishedRequest("processing_queue", "uuid", incoming.uuid);
        });
      } else {
        console.log(`Found ${branches.size} branches to pick to for ${incoming.uuid}`);
        toolbox.setPickCountRemaining(incoming.uuid, branches.size, function(success, data) {
          // The change has a Pick-to label with at least one branch.
          // Next, determine if it's part of a relation chain and handle
          // it as a member of that chain.
          _this.emit("determineProcessingPath", incoming, branches);
        });
      }
    });
  }

  // Determine if the change is part of a relation chain.
  // Hand it off to the relationChainManager if it is.
  // Otherwise, pass it off to singleRequestManager
  determineProcessingPath(incoming, branches) {
    let _this = this;
    gerritTools.queryRelated(incoming.fullChangeID, function(success, data) {
      if (success && data.length > 0) {
        // Update the request in the database with the relation chain.
        // Pass it to the relation chain manager once the database finishes.
        incoming["relatedChanges"] = data;
        toolbox.updateBaseChangeJSON(incoming.uuid, incoming, function() {
          _this.emit("processAsRelatedChange", incoming, branches);
        });
      } else if (success) {
        // Pass this down the normal pipeline and just pick the branches
        _this.emit("processAsSingleChange", incoming, branches);
      } else if (data == "retry") {
        // Failed to query for related changes, schedule a retry
        _this.retryProcessor.addRetryJob("determineProcessingPath", [incoming, branches]);
      } else {
        // A non-timeout failure occurred when querying gerrit. This should not happen.
        console.trace(`Permanently failed to query the relation chain for ${
          incoming.fullChangeID}.`);
        const message = `An unknown error occurred processing cherry picks for this change.\nPlease create cherry picks manually.`;
        const notifyScope = "OWNER";
        _this.gerritCommentHandler(incoming.fullChangeID, undefined, message, notifyScope);
        emailClient.genericSendEmail(
          config.ADMIN_EMAIL,
          `Cherry-pick bot: Error in querying for related changes [${incoming.fullChangeID}]`,
          undefined, JSON.stringify(data, undefined, 4)
        );
      }
    });
  }

  // Verify the target branch exists and call the response.
  validateBranch(incoming, branch, responseSignal) {
    let _this = this;
    gerritTools.validateBranch(incoming.change.project, branch, function(success, data) {
      if (success) {
        _this.emit(responseSignal, incoming, branch, data);
      } else if (data == "retry") {
        _this.retryProcessor.addRetryJob("validateBranch", [incoming, branch, responseSignal]);
      } else {
        console.trace(`Branch validation failed for ${branch}.`);
        const message = `Failed to cherry pick to ${branch}.\nReason: ${branch} is invalid.`;
        const notifyScope = "OWNER";
        _this.gerritCommentHandler(incoming.fullChangeID, undefined, message, notifyScope);
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid, { branch: branch }, "done_invalidBranch",
          function() {
            toolbox.decrementPickCountRemaining(incoming.uuid);
          }
        );
      }
    });
  }

  // From the current change, determine if the direct parent has a cherry-pick
  // on the target branch. If it does, call the response signal with its revision
  verifyParentPickExists(currentJSON, branch, responseSignal, errorSignal, isRetry) {
    let _this = this;

    toolbox.addToCherryPickStateUpdateQueue(
      currentJSON.uuid, { branch: branch },
      "verifyingParentExists"
    );

    function fatalError(data) {
      toolbox.addToCherryPickStateUpdateQueue(
        currentJSON.uuid,
        { branch: branch, statusCode: data.statusCode, statusDetail: data.statusDetail },
        "done_parentValidationFailed",
        function() {
          toolbox.decrementPickCountRemaining(currentJSON.uuid);
        }
      );
      _this.gerritCommentHandler(
        currentJSON.fullChangeID, undefined,
        `Failed to find this change's parent revision for cherry-picking!\nPlease verify that this change's parent is a valid commit in gerrit and process required cherry-picks manually.`
      );
    }

    function retryThis() {
      toolbox.addToCherryPickStateUpdateQueue(
        currentJSON.uuid, { branch: branch },
        "verifyParentRetryWait"
      );
      _this.retryProcessor.addRetryJob(
        "verifyParentPickExists",
        [currentJSON, branch, responseSignal, errorSignal, isRetry]
      );
    }

    gerritTools.queryChange(currentJSON.fullChangeID, function(exists, data) {
      if (exists) {
        // Success - Locate the parent revision (SHA) to the current change.
        gerritTools.queryChange(
          data.revisions[data.current_revision].commit.parents[0].commit,
          function(exists, data) {
            if (exists) {
              // Success - Found the parent (change ID) of the current change.
              if (data.status == "ABANDONED") {
                // The parent change in marked as abandoned. We cannot use it as a
                // parent for picking. Notify the owner to process the pick manually.
                toolbox.addToCherryPickStateUpdateQueue(
                  currentJSON.uuid, { branch: branch, statusDetail: "parentStateInAbandoned" },
                  "done_parentValidationFailed",
                  function() {
                    toolbox.decrementPickCountRemaining(currentJSON.uuid);
                  }
                );
                _this.gerritCommentHandler(
                  currentJSON.fullChangeID, undefined,
                  "Unable to pick this change because it's parent is abandoned.\nPlease Cherry-pick this change manually.",
                  "OWNER"
                );
                _this.emit(
                  errorSignal, currentJSON, branch,
                  { error: data.status, parentJSON: data, isRetry: isRetry }
                );
              } else if (
                ["NEW", "STAGED", "INTEGRATING"].some((element) => data.status == element)
              ) {
                // The parent has not yet been merged.
                // Fire the error signal with the parent's state.
                toolbox.addToCherryPickStateUpdateQueue(
                  currentJSON.uuid, { branch: branch },
                  "parentNotMergedWait"
                );

                _this.emit(
                  errorSignal, currentJSON, branch,
                  {
                    error: data.status,
                    unmergedChangeID:
                      `${encodeURIComponent(currentJSON.change.project)}~${
                        data.branch}~${data.change_id}`,
                    parentJSON: data, isRetry: isRetry
                  }
                );
              } else {
                // The status of the parent should be MERGED at this point.
                // Try to see if it was picked to the target branch.
                let targetPickParent =
                  `${encodeURIComponent(currentJSON.change.project)}~${branch}~${data.change_id}`;
                gerritTools.queryChange(targetPickParent, function(exists, targetData) {
                  if (exists) {
                    // Success - The target exists and can be set as the parent.
                    _this.emit(
                      responseSignal, currentJSON, branch,
                      { target: targetData.current_revision, isRetry: isRetry }
                    );
                  } else if (targetData == "retry") {
                    // Do nothing. This callback function will be called again on retry.
                    retryThis();
                  } else {
                    // The target change ID doesn't exist on the branch specified.
                    toolbox.addToCherryPickStateUpdateQueue(
                      currentJSON.uuid, { branch: branch },
                      "parentMergedNoPick",
                      function() {
                        _this.emit(
                          errorSignal, currentJSON, branch,
                          {
                            error: "notPicked",
                            parentChangeID:
                                `${encodeURIComponent(currentJSON.change.project)}~${
                                  data.branch}~${data.change_id}`,
                            parentJSON: data, targetPickParent: targetPickParent, isRetry: isRetry
                          }
                        );
                      }
                    );
                  }
                });
              }
            } else if (data == "retry") {
              // Do nothing. This callback function will be called again on retry.
              retryThis();
            } else {
              fatalError(data);
            }
          }
        );
      } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
        retryThis();
      } else {
        fatalError(data);
      }
    });
  }

  // Sanity check to make sure the cherry-pick we have can actually be staged.
  // Check to make sure its parent is merged or currently staging.
  // Send the error signal if the parent is abandoned, not yet staged,
  // or presently integrating.
  stagingReadyCheck(originalRequestJSON, cherryPickJSON, responseSignal, errorSignal) {
    let _this = this;

    function fatalError(data) {
      toolbox.addToCherryPickStateUpdateQueue(
        originalRequestJSON.uuid,
        {
          branch: cherryPickJSON.branch, statusCode: data.statusCode,
          statusDetail: data.statusDetail
        },
        "done_parentValidationFailed",
        function() {
          toolbox.decrementPickCountRemaining(originalRequestJSON.uuid);
        }
      );
      _this.gerritCommentHandler(cherryPickJSON.id, undefined, data.message, "OWNER");
    }

    function retryThis() {
      toolbox.addToCherryPickStateUpdateQueue(
        originalRequestJSON.uuid, { branch: cherryPickJSON.branch },
        "verifyParentRetryWait"
      );
      _this.retryProcessor.addRetryJob(
        "relationChain_cherrypickReadyForStage",
        [ originalRequestJSON, cherryPickJSON, responseSignal, errorSignal ]
      );
    }

    toolbox.addToCherryPickStateUpdateQueue(
      originalRequestJSON.uuid,
      { branch: cherryPickJSON.branch },
      "stageEligibilityCheckStart"
    );

    gerritTools.queryChange(cherryPickJSON.id, function(success, data) {
      if (success) {
        gerritTools.queryChange(
          data.revisions[data.current_revision].commit.parents[0].commit,
          function(success, data) {
            if (success) {
              if (data.status == "MERGED" || data.status == "STAGED") {
                toolbox.addToCherryPickStateUpdateQueue(
                  originalRequestJSON.uuid, { branch: cherryPickJSON.branch },
                  "stageEligibilityCheckPassed"
                );
                _this.emit(
                  responseSignal, originalRequestJSON, cherryPickJSON,
                  data.id, data.status
                );
              } else if (data.status == "INTEGRATING" || data.status == "NEW") {
                toolbox.addToCherryPickStateUpdateQueue(
                  originalRequestJSON.uuid, { branch: cherryPickJSON.branch },
                  "stageEligibilityCheckWaitParent"
                );
                _this.emit(errorSignal, originalRequestJSON, cherryPickJSON, data.id, data.status);
              } else {
                // Uh-oh! The parent is in some other status like ABANDONED! This
                // is bad, and shouldn't happen, since it was a cherry-pick. It's
                // possible that the owner abandoned it and created a new patch
                // to take its place. Call this a fatal error and post a comment.
                fatalError({
                  statusCode: data.statusCode, statusDetail: data.statusDetail,
                  message: `The parent to this cherry pick is in a state unsuitable for using as a parent for this cherry-pick. Please reparent it and stage it manually.`
                });
              }
            } else if (data == "retry") {
              retryThis();
            } else {
              // We somehow managed to fail querying for the cherry pick we're trying to check...
              // This should not happen, but could theoretically occur in a race condition.
              fatalError({
                statusCode: data.statusCode, statusDetail: data.statusDetail,
                message: `Cherry-pick bot permanently failed to query the status of this pick's parent. Please stage it manually.`
              });
            }
          } // End of callback
        );  // End of nested queryChange()
      } else if (data == "retry") {
        retryThis();
      } else {
        fatalError({
          statusCode: data.statusCode, statusDetail: data.statusDetail,
          message: `Cherry-pick bot permanently failed to query the status of this pick's parent. Please stage it manually.`
        });
      }
    });  // End of top-level queryChange() and its callback
  }

  // Generate a cherry pick and call the response signal.
  doCherryPick(incoming, branch, newParentRev, responseSignal) {
    let _this = this;
    console.log(`Validated branch ${branch} is at revision ${newParentRev}`);
    toolbox.addToCherryPickStateUpdateQueue(
      incoming.uuid, { branch: branch, revision: newParentRev },
      "pickStarted"
    );
    gerritTools.generateCherryPick(incoming, newParentRev, branch, function(success, data) {
      console.log(`cherry-pick result - ${success}:`, data);
      if (success) {
        _this.gerritCommentHandler(
          incoming.fullChangeID, undefined,
          `Successfully created cherry-pick to ${branch}`
        );
        // Result looks okay, let's see what to do next.
        _this.emit(responseSignal, incoming, data);
      } else if (data.statusCode) {
        // Failed to cherry pick to target branch. Post a comment on the original change
        // and stop paying attention to this pick.
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid,
          { branch: branch, statusCode: data.statusCode, statusDetail: data.statusDetail },
          "done_pickFailed",
          function() {
            toolbox.decrementPickCountRemaining(incoming.uuid);
          }
        );
        _this.gerritCommentHandler(
          incoming.fullChangeID, undefined,
          `Failed to cherry pick to ${branch}.\nReason: ${data.statusCode}: ${data.statusDetail}`
        );
      } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid, { branch: branch },
          "pickCreateRetryWait"
        );
        _this.retryProcessor.addRetryJob(
          "validBranchReadyForPick",
          [ incoming, branch, newParentRev, responseSignal ]
        );
      } else {
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid,
          {
            branch: branch, statusCode: "",
            statusDetail: "Unknown HTTP error.\nContact the Administrator."
          },
          "done_pickFailed",
          function() {
            toolbox.decrementPickCountRemaining(incoming.uuid);
          }
        );
        emailClient.genericSendEmail(
          config.ADMIN_EMAIL, "Cherry-pick bot: Error in Cherry Pick request",
          undefined, JSON.stringify(data, undefined, 4)
        );
      }
    });
  }

  // For a newly created cherry pick, check to see if there are merge
  // conflicts and set the assignee and reviewers if so.
  processNewCherryPick(parentJSON, cherryPickJSON, responseSignal) {
    let _this = this;
    if (cherryPickJSON.contains_git_conflicts) {
      gerritTools.setChangeAssignee(
        cherryPickJSON,
        parentJSON.change.owner.email
          ? parentJSON.change.owner.email
          : parentJSON.change.owner.username,
        function(success, data) {
          if (!success) {
            console.trace(`Failed to set change assignee "${
              JSON.stringify(parentJSON.change.owner)}" on ${
              cherryPickJSON.id}.\nReason: ${JSON.stringify(data)}`);
          }
        }
      );
      gerritTools.copyChangeReviewers(
        parentJSON.fullChangeID, cherryPickJSON.id,
        function(success, failedItems) {
          _this.gerritCommentHandler(
            cherryPickJSON.id, undefined,
            `INFO: This cherry-pick from your recently merged change on ${
              parentJSON.branch} has conflicts.\nPlease review.`
          );
          if (success && failedItems.length > 0) {
            _this.gerritCommentHandler(
              cherryPickJSON.id, undefined,
              `INFO: Some reviewers were not successfully added to this change. You may wish to add them manually.\n${JSON.stringify(failedItems, undefined, "\n")}`,
              "OWNER"
            );
          } else if (!success) {
            _this.gerritCommentHandler(
              cherryPickJSON.id, undefined,
              `INFO: Unable to add reviewers to this change.  Please add reviewers manually.`,
              "OWNER"
            );
          }
          // We're done with this one since it now needs human review.
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid, { branch: cherryPickJSON.branch }, "done_mergeConflicts",
            function() {
              toolbox.decrementPickCountRemaining(parentJSON.uuid);
            }
          );
        }
      );
    } else {
      _this.emit(responseSignal, parentJSON, cherryPickJSON);
    }
  }

  autoApproveCherryPick(parentJSON, cherryPickJSON, responseSignal) {
    // The resulting cherry pick passed all requirements for automatic merging.
    // Set the approval since a +2 on code-review
    // and a +1 is required on sanity-review for staging.
    let _this = this;
    const approvalmsg = `This change is being approved because it was automatically cherry-picked from dev and contains no conflicts.`;
    gerritTools.setApproval(
      parentJSON.uuid, cherryPickJSON, 2, approvalmsg, "NONE",
      function(success, data) {
        if (success) {
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid, { branch: cherryPickJSON.branch },
            "approvalSet"
          );
          _this.emit(responseSignal, parentJSON, cherryPickJSON);
        } else if (data == "retry") {
          console.log(`Failed to approve pick ${
            cherryPickJSON.id} due to a network issue. Retrying in a bit.`);
          _this.retryProcessor.addRetryJob(
            "cherryPickDone",
            [ parentJSON, cherryPickJSON, responseSignal]
          );
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid, { branch: cherryPickJSON.branch },
            "setApprovalRetryWait"
          );
        // Do nothing. This callback function will be called again on retry.
        } else {
        // This shouldn't happen. The bot should never be denied a +2.
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            { branch: cherryPickJSON.branch, statusDetail: data ? data : undefined },
            "setApprovalFailed"
          );
          gerritTools.setChangeAssignee(
            cherryPickJSON,
            parentJSON.change.owner.email
              ? parentJSON.change.owner.email
              : parentJSON.change.owner.username,
            function(success, data) {
              if (!success) {
                console.trace(`Failed to set change assignee "${
                  JSON.stringify(parentJSON.change.owner)}" on ${
                  cherryPickJSON.id}\nReason: ${JSON.stringify(data)}`);
              }
            }
          );
          _this.gerritCommentHandler(
            cherryPickJSON.id, undefined,
            `INFO: The Cherry-Pick bot was unable to automatically approve this change. Please review.\nReason:${
              data
                ? JSON.stringify(data, undefined, 4)
                : "Unknown error.\nPlease contact the gerrit admins."
            }`,
            "OWNER"
          );
        }
      }
    );
  }

  // Attempt to stage the cherry-pick to CI.
  stageCherryPick(parentJSON, cherryPickJSON, responseSignal) {
    let _this = this;
    gerritTools.stageCherryPick(parentJSON.uuid, cherryPickJSON, function(success, data) {
      if (success) {
        toolbox.addToCherryPickStateUpdateQueue(
          parentJSON.uuid, { branch: cherryPickJSON.branch },
          "staged",
          function() {
            toolbox.decrementPickCountRemaining(parentJSON.uuid);
          }
        );
        _this.emit(responseSignal, true);
      } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
        console.log(`Failed to stage cherry pick ${
          cherryPickJSON.id} due to a network issue. Retrying in a bit.`);
        _this.retryProcessor.addRetryJob(
          "cherrypickReadyForStage",
          [ parentJSON, cherryPickJSON, responseSignal ]
        );

        toolbox.addToCherryPickStateUpdateQueue(
          parentJSON.uuid, { branch: cherryPickJSON.branch },
          "stageFailedRetryWait"
        );
      } else {
        gerritTools.setChangeAssignee(
          cherryPickJSON,
          parentJSON.change.owner.email
            ? parentJSON.change.owner.email
            : parentJSON.change.owner.username,
          function(success, data) {
            if (!success) {
              console.trace(`Failed to set change assignee "${
                JSON.stringify(parentJSON.change.owner)}" on ${
                cherryPickJSON.id}\nReason: ${JSON.stringify(data)}`);
            }
          }
        );
        _this.gerritCommentHandler(
          cherryPickJSON.id, undefined,
          `INFO: The cherry-pick bot failed to automatically stage this change to CI. Please try to stage it manually.\n\nContact gerrit administration if you continue to experience issues.\n\nReason: ${
            data
              ? JSON.stringify(data, undefined, 4)
              : "Unknown error.\nPlease contact the gerrit admins."
          }`,
          "OWNER"
        );
        toolbox.addToCherryPickStateUpdateQueue(
          parentJSON.uuid,
          {
            branch: cherryPickJSON.branch,
            statusDetail: data.data ? data.data : data.message,
            statusCode: data.status ? data.status : ""
          },
          "stageFailed",
          function() {
            toolbox.decrementPickCountRemaining(parentJSON.uuid);
          }
        );
        _this.emit(responseSignal, false, data);
      }
    });
  }

  // Set up a a post-comment action and retry it until it goes through.
  // this function should never be relied upon to succeed, as posting
  // comments will be handled in an async "it's done when it's done"
  // manner.
  gerritCommentHandler(fullChangeID, revision, message, notifyScope) {
    let _this = this;
    gerritTools.postGerritComment(
      fullChangeID, revision, message, notifyScope,
      function(success, data) {
        if (!success && data == "retry") {
          _this.emit(
            "addRetryJob", "postGerritComment",
            [ fullChangeID, undefined, message, notifyScope ]
          );
        }
      }
    );
  }
}

module.exports = requestProcessor;
