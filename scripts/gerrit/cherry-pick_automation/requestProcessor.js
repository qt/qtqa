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

const EventEmitter = require("events");
const safeJsonStringify = require("safe-json-stringify");

const toolbox = require("./toolbox");
const gerritTools = require("./gerritRESTTools");
const emailClient = require("./emailClient");
const config = require("./config");

function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}
class requestProcessor extends EventEmitter {
  constructor(logger, retryProcessor) {
    super();
    this.logger = logger;
    this.retryProcessor = retryProcessor;
    this.toolbox = toolbox;
    // Set default values with the config file, but prefer environment variable.

    this.adminEmail = envOrConfig("ADMIN_EMAIL");
    this.gerritURL = envOrConfig("GERRIT_URL");
    this.gerritPort = envOrConfig("GERRIT_PORT");
    this.logger.log(
      `Initialized RequestProcessor with gerritURL=${
        this.gerritURL}, gerritPort=${this.gerritPort}`,
      "debug"
    );
  }

  // Pull the request from the database and start processing it.
  processMerge(uuid) {
    let _this = this;

    let incoming = {};
    toolbox.retrieveRequestJSONFromDB(uuid, function (success, data) {
      if (!success) {
        _this.logger.log(
          `ERROR: Database access error on uuid key: ${uuid}. Data: ${data}`,
          "error", uuid
        );
        return;
      }

      incoming = data;

      // Set the state to processing.
      toolbox.setDBState(incoming.uuid, "processing", function (success, data) {
        if (!success)
          _this.logger.log(safeJsonStringify(data), "error", uuid);
      });

      // Parse the commit message and look for branches to pick to
      const branches = toolbox.findPickToBranches(incoming.uuid, incoming.change.commitMessage);
      if (branches.size == 0) {
        _this.logger.log(`Nothing to cherry-pick. Discarding`, "verbose", incoming.uuid);
        // The change did not have a "Pick To: " keyword or "Pick To:" did not include any branches.
        toolbox.setDBState(incoming.uuid, "discarded");
      } else {
        _this.logger.log(
          `Found ${branches.size} branches to pick to for ${incoming.uuid}`,
          "info", uuid
        );
        toolbox.setPickCountRemaining(incoming.uuid, branches.size, function (success, data) {
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
    _this.logger.log(`Determining processing path...`, "debug", incoming.uuid);
    gerritTools.queryRelated(
      incoming.uuid, incoming.fullChangeID, incoming.customGerritAuth,
      function (success, data) {
        if (success && data.length > 0) {
        // Update the request in the database with the relation chain.
        // Pass it to the relation chain manager once the database finishes.
          incoming["relatedChanges"] = data;
          _this.logger.log(`Found related changes`, "debug", incoming.uuid);
          toolbox.updateBaseChangeJSON(incoming.uuid, incoming, function () {
            _this.emit("processAsRelatedChange", incoming, branches);
          });
        } else if (success) {
        // Pass this down the normal pipeline and just pick the branches
          _this.logger.log(`This is a standalone change`, "debug", incoming.uuid);
          _this.emit("processAsSingleChange", incoming, branches);
        } else if (data == "retry") {
        // Failed to query for related changes, schedule a retry
          _this.retryProcessor.addRetryJob(
            incoming.uuid, "determineProcessingPath",
            [incoming, branches]
          );
        } else {
        // A non-timeout failure occurred when querying gerrit. This should not happen.
          _this.logger.log(
            `Permanently failed to query the relation chain for ${incoming.fullChangeID}.`,
            "error", incoming.uuid
          );
          const message = `An unknown error occurred processing cherry picks for this change. Please create cherry picks manually.`;
          const notifyScope = "OWNER";
          _this.gerritCommentHandler(
            incoming.uuid, incoming.fullChangeID, undefined,
            message, notifyScope
          );
          emailClient.genericSendEmail(
            _this.adminEmail,
            `Cherry-pick bot: Error in querying for related changes [${incoming.fullChangeID}]`,
            undefined, safeJsonStringify(data, undefined, 4)
          );
        }
      }
    );
  }

  // Verify the target branch exists, and target private LTS branches if necessary,
  // then call the response.
  validateBranch(incoming, branch, responseSignal) {
    let _this = this;
    _this.logger.log(`Validating branch ${branch}`, "debug", incoming.uuid);
    toolbox.addToCherryPickStateUpdateQueue(
      incoming.uuid, { branch: branch, args: [incoming, branch, responseSignal], statusDetail: "" },
      "validateBranch"
    );

    function done(responseSignal, incoming, branch, success, data, message) {
      if (success) {
        _this.emit(responseSignal, incoming, branch, data);
      } else if (data == "retry") {
        _this.retryProcessor.addRetryJob(
          incoming.uuid, "validateBranch",
          [incoming, branch, responseSignal]
        );
      } else {
        // While the sanity bot should be warning about non-existent branches,
        // it may occur that Pick-to: footers specify a closed branch by the time
        // the change is merged. In this case, or if an lts branch fails to be created
        // for an intended target branch, this error will occur and the appropriate
        // error message will be posted to the original change, notifying the Owner.
        _this.logger.log(
          `Branch validation failed for ${branch}. Reason: ${safeJsonStringify(data)}`,
          "error", incoming.uuid
        );
        if (message) {
          const notifyScope = "OWNER";
          _this.gerritCommentHandler(
            incoming.uuid, incoming.fullChangeID, undefined,
            message, notifyScope
          );
        }
        toolbox.addToCherryPickStateUpdateQueue(
          incoming.uuid, { branch: branch, args: [], statusDetail: "" },
          "done_invalidBranch",
          function () {
            toolbox.decrementPickCountRemaining(incoming.uuid);
          }
        );
      }
    }

    incoming.originalProject = incoming.change.project;
    incoming.originalBranch = incoming.change.branch;

    gerritTools.validateBranch(
      incoming.uuid, incoming.change.project, branch, incoming.customGerritAuth,
      function (success, data) {
        if (success) {
          _this.logger.log(
            `Branch ${branch} exists. Checking if it's a private LTS.`,
            "debug", incoming.uuid
          );
          gerritTools.checkAccessRights(
            incoming.uuid, incoming.change.project, branch, envOrConfig("GERRIT_USER"), "push",
            incoming.customGerritAuth, function (canPush, error) {
              _this.logger.log(
                `Access rights check for ${incoming.change.project}:${branch} returned ${canPush}.`,
                "debug", incoming.uuid
              );
              if (canPush) {
                _this.logger.log(`Using ${/tqtc\//.test(branch) ? "private": "public"} branch ${
                  branch}.`, "verbose", incoming.uuid);
                done(responseSignal, incoming, branch, success, data);
              } else if (!/tqtc\//.test(branch) || !/tqtc-/.test(incoming.change.project)) {
                _this.logger.log(`Checking if a private LTS branch exists`, "info", incoming.uuid);
                let privateProject = incoming.change.project;
                let privateBranch = branch;
                if (!privateProject.includes("tqtc-")) {
                  let projectSplit = privateProject.split('/');
                  privateProject = projectSplit.slice(0, -1);
                  privateProject.push(`tqtc-${projectSplit.slice(-1)}`);
                  privateProject = privateProject.join('/');
                }
                if (!branch.includes("tqtc/lts-"))
                  privateBranch = `tqtc/lts-${branch}`;

                gerritTools.validateBranch(
                  incoming.uuid, privateProject, privateBranch, incoming.customGerritAuth,
                  function (success, data) {
                    if (success) {
                      gerritTools.checkAccessRights(
                        incoming.uuid, privateProject, privateBranch,  envOrConfig("GERRIT_USER"),
                        "push", incoming.customGerritAuth, function (canPushPrivate) {
                          let message;
                          if (canPushPrivate) {
                            incoming.change.project = privateProject;
                            incoming.change.branch = privateBranch;
                          } else {
                            _this.logger.log(
                              `Unable to push to private branch ${privateBranch} in ${
                                privateProject} because it is closed.`,
                              "error", incoming.uuid
                            );
                            message = `Unable to cherry-pick this change to ${branch} or`
                            + ` ${privateBranch} because the branch is closed for new changes.`
                            + `\nIf you need this change in a closed branch, please contact the`
                            + ` Releasing group to argue for inclusion: releasing@qt-project.org`;
                          }
                          done(responseSignal, incoming, incoming.change.branch, success, data, message);
                        }
                      );
                    } else { // No private lts branch exists.
                      _this.logger.log(
                        `Unable to push to public branch ${branch} in ${
                          incoming.change.project} because it is closed and no private LTS branch exists.`,
                        "error", incoming.uuid
                      );
                      let message = `Unable to cherry-pick this change to ${branch} because the`
                      + ` branch is closed for new changes.`
                      + `\nIf you need this change in a closed branch, please contact the`
                      + ` Releasing group to argue for inclusion: releasing@qt-project.org`;
                      done(responseSignal, incoming, branch, success, data, message);
                    }
                  }
                );
              } else {
                _this.logger.log(
                  `Unable to push to branch ${branch} in ${incoming.change.project} because the`
                  + ` branch is either closed or the bot user account does not have permissions`
                  + ` to create changes there.`,
                  "error", incoming.uuid
                );
                message = `Unable to cherry-pick this change to ${branch} or`
                  + ` ${privateBranch} because the branch is closed for new changes.`
                  + `\nIf you need this change in a closed branch, please contact the`
                  + ` Releasing group to argue for inclusion: releasing@qt-project.org`;
              }
              done(responseSignal, incoming, branch, success, data, message);
            }
          );
        } else {  // Invalid branch specified in Pick-to: footer or some other critical failure
          let message = `Failed to cherry pick to ${incoming.change.project}:${
            branch} due to an unknown problem with the target branch.\nPlease contact the gerrit admins.`;
          done(responseSignal, incoming, branch, success, data, message)
        }
      }
    );
  }

  // Check the prospective cherry-pick branch for LTS. If it is to be picked to
  // an lts branch, check to make sure the original change exists in the shadow repo.
  // If it doesn't, set up an action to wait for replication.
  checkLtsTarget(currentJSON, branch, branchHeadSha, responseSignal) {
    let _this = this;
    toolbox.addToCherryPickStateUpdateQueue(
      currentJSON.uuid,
      {
        branch: branch,
        args: [currentJSON, branch, branchHeadSha, responseSignal], statusDetail: ""
      }, "checkLtsTarget"
    );
    if (! /^tqtc(?:%2F|\/)lts-/.test(currentJSON.change.branch)) {
      _this.emit(responseSignal, currentJSON, branch, branchHeadSha);
    } else {
      _this.logger.log(
        `Checking to see if ${currentJSON.patchSet.revision} has been replicated to ${
          currentJSON.change.project} shadow repo yet`,
        "info", currentJSON.uuid
      );
      gerritTools.queryProjectCommit(
        currentJSON.uuid, currentJSON.change.project, currentJSON.patchSet.revision, currentJSON.customGerritAuth,
        function (success, data) {
          if (success) {
            _this.logger.log(
              `${currentJSON.patchSet.revision} is a valid ${currentJSON.change.project} target. Continuing.`,
              "info", currentJSON.uuid
            );
            _this.emit(responseSignal, currentJSON, branch, branchHeadSha);
          } else {
            _this.logger.log(
              `${currentJSON.patchSet.revision} hasn't been replicated yet. Waiting for it for 15 minutes.`,
              "info", currentJSON.uuid
            );
            // Set a 15 minute timeout to check again. This process will be iterated so long as
            // the target has not been replicated.
            setTimeout(function () {
              _this.emit("checkLtsTarget", currentJSON, branch, branchHeadSha, responseSignal)
            }, 15 * 60 * 1000);
          }
        }
      )
    }
  }

  // From the current change, determine if the direct parent has a cherry-pick
  // on the target branch. If it does, call the response signal with its revision
  verifyParentPickExists(currentJSON, branch, responseSignal, errorSignal, isRetry) {
    let _this = this;
    _this.logger.log(`Verifying parent pick exists on ${branch}...`, "debug", currentJSON.uuid);
    toolbox.addToCherryPickStateUpdateQueue(
      currentJSON.uuid,
      {
        branch: branch, args: [currentJSON, branch, responseSignal, errorSignal, isRetry],
        statusDetail: ""
      },
      "verifyParentPickExists"
    );

    function fatalError(data) {
      _this.logger.log(`Failed to locate a parent pick on ${branch}`, "error", currentJSON.uuid);
      toolbox.addToCherryPickStateUpdateQueue(
        currentJSON.uuid,
        { branch: branch, statusCode: data.statusCode, statusDetail: data.statusDetail, args: [] },
        "done_parentValidationFailed",
        function () {
          toolbox.decrementPickCountRemaining(currentJSON.uuid);
        }
      );
      _this.gerritCommentHandler(
        currentJSON.uuid, currentJSON.fullChangeID, undefined,
        `Failed to find this change's parent revision for cherry-picking!\nPlease verify that this change's parent is a valid commit in gerrit and process required cherry-picks manually.`
      );
    }

    function retryThis() {
      _this.retryProcessor.addRetryJob(
        currentJSON.uuid, "verifyParentPickExists",
        [currentJSON, branch, responseSignal, errorSignal, isRetry]
      );
    }

    // Query for the current change to get a list of its parents.
    gerritTools.queryChange(
      currentJSON.uuid, currentJSON.fullChangeID, undefined, currentJSON.customGerritAuth,
      function (exists, data) {
        if (exists) {
        // Success - Locate the parent revision (SHA) to the current change.
          let immediateParent = data.revisions[data.current_revision].commit.parents[0].commit;
          gerritTools.queryChange(
            currentJSON.uuid, immediateParent, undefined, currentJSON.customGerritAuth,
            function (exists, data) {
              if (exists) {
                let targetPickParent = `${encodeURIComponent(currentJSON.change.project)}~${
                  encodeURIComponent(branch)}~${data.change_id}`;
                _this.logger.log(
                  `Set target pick parent for ${branch} to ${targetPickParent}`,
                  "debug", currentJSON.uuid
                );
                // Success - Found the parent (change ID) of the current change.
                if (data.status == "ABANDONED") {
                  // The parent is an abandoned state. Send the error signal.
                  _this.logger.log(
                    `Immediate parent (${immediateParent}) for ${
                      currentJSON.fullChangeID} is in state: ${data.status}`,
                    "warn", currentJSON.uuid
                  );
                  _this.emit(
                    errorSignal, currentJSON, branch,
                    { error: data.status, parentJSON: data, isRetry: isRetry }
                  );
                } else if (["NEW", "STAGED", "INTEGRATING"].some((element) => data.status == element)) {
                  // The parent has not yet been merged.
                  // Fire the error signal with the parent's state.
                  _this.logger.log(
                    `Immediate parent (${immediateParent}) for ${
                      currentJSON.fullChangeID} is in state: ${data.status}`,
                    "verbose", currentJSON.uuid
                  );
                  _this.emit(errorSignal, currentJSON, branch, {
                    error: data.status,
                    unmergedChangeID: `${
                      encodeURIComponent(currentJSON.change.project)}~${
                      encodeURIComponent(data.branch)}~${data.change_id}`,
                    targetPickParent: targetPickParent, parentJSON: data, isRetry: isRetry
                  });
                } else {
                  // The status of the parent should be MERGED at this point.
                  // Try to see if it was picked to the target branch.
                  _this.logger.log(
                    `Immediate parent (${immediateParent}) for ${
                      currentJSON.fullChangeID} is in state: ${data.status}`,
                    "debug", currentJSON.uuid
                  );
                  gerritTools.queryChange(
                    currentJSON.uuid, targetPickParent, undefined, currentJSON.customGerritAuth,
                    function (exists, targetData) {
                      if (exists) {
                        _this.logger.log(
                          `Target pick parent ${
                            targetPickParent} exists and will be used as the the parent for ${branch}`,
                          "debug", currentJSON.uuid
                        );
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
                        _this.logger.log(
                          `Target pick parent ${targetPickParent} does not exist on ${branch}`,
                          "debug", currentJSON.uuid
                        );
                        toolbox.addToCherryPickStateUpdateQueue(
                          currentJSON.uuid,
                          { branch: branch, statusDetail: "parentMergedNoPick" },
                          "verifyParentPickExists",
                          function () {
                            _this.emit(
                              errorSignal, currentJSON, branch,
                              {
                                error: "notPicked",
                                parentChangeID: data.id,
                                parentJSON: data, targetPickParent: targetPickParent, isRetry: isRetry
                              }
                            );
                          }
                        );
                      }
                    }
                  );
                } // End of target pick parent queryChange call
              } else if (data == "retry") {
                // Do nothing. This callback function will be called again on retry.
                retryThis();
              } else {
                fatalError(data);
              }
            }
          ); // End of parent change queryChange call
        } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
          retryThis();
        } else {
          fatalError(data);
        }
      }
    ); // End of current change queryChange call
  }

  // From the current change, try to locate the nearest parent in the
  // chain that is picked to the same branch as this pick is intended for.
  // Use the nearmost change on the target branch as the parent for this pick
  // Use branch HEAD if no parents to this change are picked to the same
  // branch.
  locateNearestParent(currentJSON, next, branch, responseSignal) {
    let _this = this;

    function retryThis() {
      toolbox.addToCherryPickStateUpdateQueue(
        currentJSON.uuid, { branch: branch, statusDetail: "locateNearestParentRetryWait" },
        "locateNearestParent"
      );
      _this.retryProcessor.addRetryJob(
        currentJSON.uuid, "locateNearestParent",
        [currentJSON, next, branch, responseSignal]
      );
    }

    toolbox.addToCherryPickStateUpdateQueue(
      currentJSON.uuid,
      {
        branch: branch, statusDetail: "locateNearestParent",
        args: [currentJSON, next, branch, responseSignal]
      },
      "locateNearestParent"
    );

    let positionInChain = currentJSON.relatedChanges.findIndex((i) =>
      i.change_id === (next || currentJSON.change.id));

    if (next === -1) {
      // We've reached the top of the chain and found no suitable parent.
      // Send the response signal with the target branch head.
      _this.logger.log(
        `Using ${branch} head as the target pick parent in ${currentJSON.change.project}`,
        "verbose", currentJSON.uuid
      );
      gerritTools.validateBranch(
        currentJSON.uuid, currentJSON.change.project, branch, currentJSON.customGerritAuth,
        (success, branchHead) => {
          // This should never hard-fail since the branch is already
          // validated!
          _this.emit(responseSignal, currentJSON, branch, { target: branchHead });
        }
      );
    } else {
      let targetPickParent = `${encodeURIComponent(currentJSON.change.project)}~${
        encodeURIComponent(branch)}~${currentJSON.relatedChanges[positionInChain].change_id
      }`;
      _this.logger.log(
        `Locating nearest parent in relation chain to ${currentJSON.fullChangeID}. Now trying: ${
          targetPickParent}\nCurrent position in parent chain=${positionInChain}`,
        "debug", currentJSON.uuid
      );

      // See if a pick exists on the target branch for this candidate.
      gerritTools.queryChange(
        currentJSON.uuid, targetPickParent, undefined, currentJSON.customGerritAuth,
        (success, data) => {
          if (success) {
            _this.logger.log(
              `Found a parent to use: ${data.current_revision} for ${branch}`,
              "verbose", currentJSON.uuid
            );
            // The target parent exists on the target branch. Use it.
            _this.emit(responseSignal, currentJSON, branch, { target: data.current_revision });
          } else if (data == "retry") {
          // Do nothing. This callback function will be called again on retry.
            retryThis();
          } else if (positionInChain < currentJSON.relatedChanges.length - 1) {
          // Still more items to check. Check the next parent.
            _this.emit(
              "locateNearestParent", currentJSON,
              currentJSON.relatedChanges[positionInChain + 1].change_id, branch,
              "relationChain_validBranchReadyForPick"
            );
          } else {
          // No more items to check. Pass -1 in "next" param to send the
          // sha of the target branch head.
            _this.logger.log(
              `Reached the end of the relation chain for finding a parent`,
              "debug", currentJSON.uuid
            );
            _this.emit(
              "locateNearestParent", currentJSON, -1, branch,
              "relationChain_validBranchReadyForPick"
            );
          }
        }
      );
    }
  }

  // Sanity check to make sure the cherry-pick we have can actually be staged.
  // Check to make sure its parent is merged or currently staging.
  // Send the error signal if the parent is abandoned, not yet staged,
  // or presently integrating.
  stagingReadyCheck(originalRequestJSON, cherryPickJSON, responseSignal, errorSignal) {
    let _this = this;

    function fatalError(data) {
      _this.logger.log(
        `Failed to validate staging readiness for ${cherryPickJSON.id}`,
        "debug", originalRequestJSON.uuid
      );
      toolbox.addToCherryPickStateUpdateQueue(
        originalRequestJSON.uuid,
        {
          branch: cherryPickJSON.branch,
          statusCode: data.statusCode, statusDetail: data.statusDetail
        },
        "done_parentValidationFailed",
        function () {
          toolbox.decrementPickCountRemaining(originalRequestJSON.uuid);
        }
      );
      _this.gerritCommentHandler(
        originalRequestJSON.uuid, cherryPickJSON.id, undefined, data.message,
        "OWNER"
      );
    }

    function retryThis() {
      toolbox.addToCherryPickStateUpdateQueue(
        originalRequestJSON.uuid,
        { branch: cherryPickJSON.branch, statusDetail: "verifyParentRetryWait" },
        "stageEligibilityCheck"
      );
      _this.retryProcessor.addRetryJob(
        originalRequestJSON.uuid,
        "relationChain_cherrypickReadyForStage",
        [originalRequestJSON, cherryPickJSON, responseSignal, errorSignal]
      );
    }

    _this.logger.log(
      `Checking for staging readiness on ${cherryPickJSON.id}`,
      "verbose", originalRequestJSON.uuid
    );

    toolbox.addToCherryPickStateUpdateQueue(
      originalRequestJSON.uuid,
      {
        branch: cherryPickJSON.branch,
        args: [originalRequestJSON, cherryPickJSON, responseSignal, errorSignal]
      },
      "stageEligibilityCheck"
    );

    gerritTools.queryChange(
      originalRequestJSON.uuid, cherryPickJSON.id, undefined,  originalRequestJSON.customGerritAuth,
      function (success, data) {
        if (success) {
          gerritTools.queryChange(
            originalRequestJSON.uuid,
            data.revisions[data.current_revision].commit.parents[0].commit, undefined,
            originalRequestJSON.customGerritAuth,
            function (success, data) {
              if (success) {
                _this.logger.log(
                  `Parent ${data.id} for ${cherryPickJSON.id} is in state ${data.status}`,
                  "debug", originalRequestJSON.uuid
                );
                if (data.status == "MERGED" || data.status == "STAGED") {
                  toolbox.addToCherryPickStateUpdateQueue(
                    originalRequestJSON.uuid,
                    { branch: cherryPickJSON.branch, statusDetail: "stageEligibilityCheckPassed" },
                    "stageEligibilityCheck"
                  );
                  _this.emit(
                    responseSignal, originalRequestJSON, cherryPickJSON,
                    data.id, data.status
                  );
                } else if (data.status == "INTEGRATING" || data.status == "NEW") {
                  toolbox.addToCherryPickStateUpdateQueue(
                    originalRequestJSON.uuid,
                    {
                      branch: cherryPickJSON.branch,
                      statusDetail: "stageEligibilityCheckWaitParent"
                    }, "stageEligibilityCheck"
                  );
                  // Stop processing this request and consider it done.
                  // If further processing is needed, the caller should
                  // handle the error signal as needed.
                  _this.emit(errorSignal, originalRequestJSON, cherryPickJSON, data.id, data.status);
                  toolbox.addToCherryPickStateUpdateQueue(
                    originalRequestJSON.uuid,
                    {
                      branch: cherryPickJSON.branch,
                      statusDetail: data.status
                    },
                    "done_waitParent",
                    function () {
                      toolbox.decrementPickCountRemaining(originalRequestJSON.uuid);
                    }
                  );
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
      }
    );  // End of top-level queryChange() and its callback
  }

  // Generate a cherry pick and call the response signal.
  doCherryPick(incoming, branch, newParentRev, responseSignal) {
    let _this = this;
    _this.logger.log(
      `Performing cherry-pick to ${branch} from ${incoming.fullChangeID}`,
      "info", incoming.uuid
    );
    toolbox.addToCherryPickStateUpdateQueue(
      incoming.uuid,
      {
        branch: branch, revision: newParentRev, statusDetail: "pickStarted",
        args: [incoming, branch, newParentRev, responseSignal]
      }, "validBranchReadyForPick"
    );
    gerritTools.generateCherryPick(
      incoming, newParentRev, branch, incoming.customGerritAuth,
      function (success, data) {
        _this.logger.log(
          `Cherry-pick result on ${incoming.change.branch}: ${success}:\n${safeJsonStringify(data)}`,
          "info", incoming.uuid
        );
        if (success) {
          let message = `Successfully created cherry-pick to ${branch}`;
          // Some nasty assembly of the gerrit URL of the change.
          // Formatted as https://codereview.qt-project.org/c/qt%2Fqtqa/+/294338
          let gerritResolvedURL = /^(http)s?:\/\//g.test(_this.gerritURL)
            ? _this.gerritURL
            : `${_this.gerritPort == 80 ? "http" : "https"}://${_this.gerritURL}`;
          gerritResolvedURL +=
          _this.gerritPort != 80 && _this.gerritPort != 443 ? ":" + _this.gerritPort : "";
          message += `\nView it here: ${gerritResolvedURL}/c/${encodeURIComponent(data.project)}/+/${
            data._number
          }`;
          _this.gerritCommentHandler(incoming.uuid, incoming.fullChangeID, undefined, message);
          // Result looks okay, let's see what to do next.
          _this.emit(responseSignal, incoming, data);
        } else if (data.statusCode) {
        // Failed to cherry pick to target branch. Post a comment on the original change
        // and stop paying attention to this pick.
          toolbox.addToCherryPickStateUpdateQueue(
            incoming.uuid,
            {
              branch: branch, statusCode: data.statusCode, statusDetail: data.statusDetail, args: []
            },
            "done_pickFailed",
            function () {
              toolbox.decrementPickCountRemaining(incoming.uuid);
            }
          );
          _this.gerritCommentHandler(
            incoming.uuid, incoming.fullChangeID, undefined,
            `Failed to cherry pick to ${branch}.\nReason: ${data.statusCode}: ${data.statusDetail}`
          );
        } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
          toolbox.addToCherryPickStateUpdateQueue(
            incoming.uuid, { branch: branch, statusDetail: "pickCreateRetryWait" },
            "validBranchReadyForPick"
          );
          _this.retryProcessor.addRetryJob(
            incoming.uuid, "validBranchReadyForPick",
            [incoming, branch, newParentRev, responseSignal]
          );
        } else {
          toolbox.addToCherryPickStateUpdateQueue(
            incoming.uuid,
            {
              branch: branch, statusCode: "",
              statusDetail: "Unknown HTTP error. Contact the gerrit admins at gerrit-admin@qt-project.org", args: []
            },
            "done_pickFailed",
            function () {
              toolbox.decrementPickCountRemaining(incoming.uuid);
            }
          );
          emailClient.genericSendEmail(
            _this.adminEmail, "Cherry-pick bot: Error in Cherry Pick request",
            undefined, safeJsonStringify(data, undefined, 4)
          );
        }
      }
    );
  }

  // For a newly created cherry pick, check to see if there are merge
  // conflicts and set the assignee and reviewers if so.
  processNewCherryPick(parentJSON, cherryPickJSON, responseSignal) {
    let _this = this;

    _this.logger.log(
      `Checking cherry-pick ${cherryPickJSON.id} for conflicts`,
      "verbose", parentJSON.uuid
    );
    toolbox.addToCherryPickStateUpdateQueue(
      parentJSON.uuid,
      {
        branch: cherryPickJSON.branch, args: [parentJSON, cherryPickJSON, responseSignal],
        statusDetail: "processNewCherryPick"
      },
      "newCherryPick"
    );

    if (cherryPickJSON.contains_git_conflicts) {
      _this.logger.log(
        `Conflicts found for ${cherryPickJSON.id}`,
        "verbose", parentJSON.uuid
      );
      // Internal emitter in case anything needs to know about conflicts on this change.
      _this.emit(`mergeConflict_${cherryPickJSON.id}`);
      gerritTools.setChangeAssignee(
        parentJSON.uuid, cherryPickJSON,
        parentJSON.change.owner.email || parentJSON.change.owner.username,
        parentJSON.customGerritAuth,
        function (success, data) {
          if (!success) {
            _this.logger.log(
              `Failed to set change assignee "${safeJsonStringify(parentJSON.change.owner)}" on ${
                cherryPickJSON.id}.\nReason: ${safeJsonStringify(data)}`,
              "warn", parentJSON.uuid
            );
            _this.gerritCommentHandler(
              parentJSON.uuid, cherryPickJSON.id, undefined,
              `Unable to add ${parentJSON.change.owner.email || parentJSON.change.owner.username
              } as the assignee to this issue.\nReason: ${data}`,
              "NONE"
            );
          }
        }
      );
      gerritTools.copyChangeReviewers(
        parentJSON.uuid, parentJSON.fullChangeID, cherryPickJSON.id, parentJSON.customGerritAuth,
        function (success, failedItems) {
          _this.gerritCommentHandler(
            parentJSON.uuid, cherryPickJSON.id, undefined,
            `INFO: This cherry-pick from your recently merged change on ${
              parentJSON.originalBranch} has conflicts.\nPlease review.`
          );
          if (success && failedItems.length > 0) {
            _this.gerritCommentHandler(
              parentJSON.uuid, cherryPickJSON.id, undefined,
              `INFO: Some reviewers were not successfully added to this change. You may wish to add them manually.\n ${
                safeJsonStringify(failedItems, undefined, "\n")}`,
              "OWNER"
            );
          } else if (!success) {
            _this.gerritCommentHandler(
              parentJSON.uuid, cherryPickJSON.id, undefined,
              `INFO: Reviewers were unable to be automatically added to this change. Please add reviewers manually.`,
              "OWNER"
            );
          }
          // We're done with this one since it now needs human review.
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid, { branch: cherryPickJSON.branch, args: [] },
            "done_mergeConflicts",
            function () {
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

    _this.logger.log(`Auto-approving ${cherryPickJSON.id} for staging`, "verbose", parentJSON.uuid);
    toolbox.addToCherryPickStateUpdateQueue(
      parentJSON.uuid,
      {
        branch: cherryPickJSON.branch, statusDetail: "startedApproval",
        args: [parentJSON, cherryPickJSON, responseSignal]
      },
      "cherryPickDone"
    );

    const approvalmsg = `This change is being approved because it was automatically cherry-picked from dev and contains no conflicts.`;
    gerritTools.setApproval(
      parentJSON.uuid, cherryPickJSON, 2, approvalmsg, "NONE", parentJSON.customGerritAuth,
      function (success, data) {
        if (success) {
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            { branch: cherryPickJSON.branch, statusDetail: "approvalSet" },
            "cherryPickDone"
          );
          _this.emit(responseSignal, parentJSON, cherryPickJSON);
        } else if (data == "retry") {
          _this.logger.log(
            `Failed to approve pick ${
              cherryPickJSON.id} due to a network issue. Retrying in a bit.`,
            "warn", parentJSON.uuid
          );
          _this.retryProcessor.addRetryJob(
            parentJSON.uuid, "cherryPickDone",
            [parentJSON, cherryPickJSON, responseSignal]
          );
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            { branch: cherryPickJSON.branch, statusDetail: "setApprovalRetryWait" },
            "cherryPickDone"
          );
        // Do nothing. This callback function will be called again on retry.
        } else {
        // This shouldn't happen. The bot should never be denied a +2.
          _this.logger.log(
            `Failed to set approvals on ${cherryPickJSON.id}.\nReason: ${safeJsonStringify(data)}`,
            "error", parentJSON.uuid
          );
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            {
              branch: cherryPickJSON.branch, statusDetail: data || undefined, args: []
            },
            "done_setApprovalFailed",
            function () {
              toolbox.decrementPickCountRemaining(parentJSON.uuid);
            }
          );
          gerritTools.setChangeAssignee(
            parentJSON.uuid, cherryPickJSON,
            parentJSON.change.owner.email || parentJSON.change.owner.username,
            parentJSON.customGerritAuth,
            function (success, data) {
              if (!success) {
                _this.logger.log(
                  `Failed to set change assignee "${
                    safeJsonStringify(parentJSON.change.owner)}" on ${cherryPickJSON.id}\nReason: ${
                    safeJsonStringify(data)}`,
                  "error", parentJSON.uuid
                );
              }
            }
          );
          _this.gerritCommentHandler(
            parentJSON.uuid, cherryPickJSON.id, undefined,
            `INFO: The Cherry-Pick bot was unable to automatically approve this change. Please review.\nReason:${
              data
                ? safeJsonStringify(data, undefined, 4)
                : "Unknown error. Please contact the gerrit admins at gerrit-admin@qt-project.org"
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
    _this.logger.log(`Starting staging for ${cherryPickJSON.id}`, "verbose", parentJSON.uuid);
    toolbox.addToCherryPickStateUpdateQueue(
      parentJSON.uuid,
      {
        branch: cherryPickJSON.branch, statusDetail: "stagingStarted",
        args: [parentJSON, cherryPickJSON, responseSignal]
      },
      "cherrypickReadyForStage"
    );
    gerritTools.stageCherryPick(
      parentJSON.uuid, cherryPickJSON, parentJSON.customGerritAuth,
      function (success, data) {
        if (success) {
          _this.logger.log(`Staged ${cherryPickJSON.id}`, "info", parentJSON.uuid);
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid, { branch: cherryPickJSON.branch, statusDetail: "staged", args: [] },
            "done_staged",
            function () {
              toolbox.decrementPickCountRemaining(parentJSON.uuid);
            }
          );
          _this.emit(responseSignal, true, parentJSON, cherryPickJSON);
        } else if (data == "retry") {
        // Do nothing. This callback function will be called again on retry.
          _this.logger.log(`Failed to stage cherry pick ${
            cherryPickJSON.id} due to a network issue. Retrying in a bit.`);
          _this.retryProcessor.addRetryJob(
            parentJSON.uuid, "cherrypickReadyForStage",
            [parentJSON, cherryPickJSON, responseSignal]
          );

          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            { branch: cherryPickJSON.branch, statusDetail: "stageFailedRetryWait" },
            "cherrypickReadyForStage"
          );
        } else {
          _this.logger.log(
            `Failed to stage ${cherryPickJSON.id}. Reason: ${safeJsonStringify(data)}`,
            "error", parentJSON.uuid
          );
          gerritTools.setChangeAssignee(
            parentJSON.uuid, cherryPickJSON,
            parentJSON.change.owner.email || parentJSON.change.owner.username,
            parentJSON.customGerritAuth,
            function (success, data) {
              if (!success) {
                _this.logger.log(
                  `Failed to set change assignee "${safeJsonStringify(parentJSON.change.owner)}" on ${
                    cherryPickJSON.id}\nReason: ${safeJsonStringify(data)}`,
                  "error", parentJSON.uuid
                );
              }
            }
          );
          _this.gerritCommentHandler(
            parentJSON.uuid, cherryPickJSON.id,
            undefined,
            `INFO: The cherry-pick bot failed to automatically stage this change to CI. Please try to stage it manually.\n\nContact gerrit administration if you continue to experience issues.\n\nReason: ${
              data
                ? safeJsonStringify(data, undefined, 4)
                : "Unknown error. Please contact the gerrit admins at gerrit-admin@qt-project.org"
            }`,
            "OWNER"
          );
          toolbox.addToCherryPickStateUpdateQueue(
            parentJSON.uuid,
            {
              branch: cherryPickJSON.branch, statusDetail: data.data || data.message,
              statusCode: data.status || "", args: []
            },
            "stageFailed",
            function () {
              toolbox.decrementPickCountRemaining(parentJSON.uuid);
            }
          );
          _this.emit(responseSignal, false, parentJSON, cherryPickJSON);
        }
      }
    );
  }

  // Set up a a post-comment action and retry it until it goes through.
  // this function should never be relied upon to succeed, as posting
  // comments will be handled in an async "it's done when it's done"
  // manner.
  gerritCommentHandler(parentUuid, fullChangeID, revision, message, notifyScope, customGerritAuth) {
    let _this = this;
    gerritTools.postGerritComment(
      parentUuid, fullChangeID, revision, message, notifyScope, customGerritAuth,
      function (success, data) {
        if (!success && data == "retry") {
          _this.emit(
            "addRetryJob", "postGerritComment",
            [parentUuid, fullChangeID, undefined, message, notifyScope, customGerritAuth]
          );
        }
      }
    );
  }
}

module.exports = requestProcessor;
