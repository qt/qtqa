/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

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
    this.eventCache = {};
  }

  // Cache an event with an expiry duration in ms
  // This allows listeners to check for missed events
  cacheEvent(event, ttl) {
    let _this = this;
    // Try to clear any existing timeout to prevent it from firing.
    // This does not delete the event from the cache, so it can still be
    // read while we set up the new timeout below.
    clearTimeout(_this.eventCache[event]);
    // NOTE: There is an extremely small race condition here where the
    // event may be deleted from the cache and then requested by a listener
    // before it can be re-added.
    _this.eventCache[event] = setTimeout(function() { delete _this.eventCache[event]; }, ttl);
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
      let allBranches = toolbox.findPickToBranches(incoming.uuid, incoming.change.commitMessage);
      toolbox.findMissingTargets(incoming.uuid, incoming.fullChangeID, incoming.project.name || incoming.project,
        allBranches, (error, _change, missing) => {
          if (missing.length > 0) {
            missing.forEach(allBranches.add, allBranches);
          }
          const suggestedPicks = Array.from(allBranches);
          const morePicks = suggestedPicks.length > 0;
          if (error) {
            allBranches.delete(_change.branch);
            const message = ` ${_change.branch} was identified as a missing target based on this change's commit message.\n`
              + `WARN: Cherry-pick bot cannot pick this change to ${_change.branch} because`
              + ` a change already exists on ${_change.branch} which is in status: ${_change.status}.\n`
              + `Cherry-pick bot will only proceed automatically for any release branch targets of this branch. (${incoming.change.branch})\n`
              + (morePicks ? `It is recommended to update the existing change with further pick-to targets.\n\n` : "\n\n")
              + `    Change ID: ${_change.change_id}\n`
              + `    Subject: ${_change.subject}\n`
              + (morePicks
                ? `    Suggested Pick-to: ${suggestedPicks.join(" ")}\n\n`
                : "\n\n")
              + `Link: ${gerritTools.gerritResolvedURL}/c/${_change.project}/+/${_change._number}`;
            gerritTools.locateDefaultAttentionUser(incoming.uuid, incoming,
              incoming.change.owner.email, (user) => {
                gerritTools.addToAttentionSet(incoming.uuid, incoming, user, undefined, undefined, () => {
                  const notifyScope = "ALL";
                  _this.gerritCommentHandler(
                    incoming.uuid, incoming.fullChangeID, undefined,
                    message, notifyScope
                  );
                });
              }
            );
            _this.logger.log(`Aborting non-release cherry picking due to unpickable primary target`
              + ` on ${_change.branch}`, "error", uuid);
            let thisStableBranch = incoming.change.branch.split(".")
            if (thisStableBranch.length >= 2) {
              thisStableBranch.pop();
              thisStableBranch = thisStableBranch.join("\\.");
              const restring = new RegExp(`^${thisStableBranch}\\.\\d+$`);
              // Filter out all branches except releases of the current branch.
              //Does not apply to dev.
              allBranches = new Set(Array.from(allBranches).filter(
                (branch) => branch.match(restring)));
            } else {
              // Non numeric branches cannot have release branches. Delete all targets.
              allBranches.clear();
            }
          }
          const picks = toolbox.waterfallCherryPicks(incoming.uuid, allBranches);
          const pickCount = Object.keys(picks).length;
          if (pickCount == 0) {
            _this.logger.log(`Nothing to cherry-pick. Discarding`, "verbose", incoming.uuid);
            // The change did not have a "Pick To: " keyword or "Pick To:"
            // did not include any branches.
            toolbox.setDBState(incoming.uuid, "discarded");
          } else {
            _this.logger.log(
              `Found ${pickCount} branches to pick to for ${incoming.uuid}`,
              "info", uuid
            );
            toolbox.setPickCountRemaining(incoming.uuid, pickCount, function (success, data) {
              // The change has a Pick-to label with at least one branch.
              // Next, determine if it's part of a relation chain and handle
              // it as a member of that chain.
              _this.emit("determineProcessingPath", incoming, picks);
            });
          }
      });
    });
  }

  // Determine if the change is part of a relation chain.
  // Hand it off to the relationChainManager if it is.
  // Otherwise, pass it off to singleRequestManager
  determineProcessingPath(incoming, branches) {
    let _this = this;
    _this.logger.log(`Determining processing path...`, "debug", incoming.uuid);
    gerritTools.queryRelated(
      incoming.uuid, incoming.fullChangeID, incoming.patchSet.number, incoming.customGerritAuth,
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

    let gerrit_user = envOrConfig("GERRIT_USER")
    _this.logger.log(`Validating branch ${branch}`, "debug", incoming.uuid);
    toolbox.addToCherryPickStateUpdateQueue(
      incoming.uuid, { branch: branch, args: [incoming, branch, responseSignal], statusDetail: "" },
      "validateBranch"
    );

    function done(responseSignal, incoming, branch, success, data, message) {
      if (success) {
        // Check to see if a change already exists on the target branch.
        // If it does, abort the cherry-pick and notify the owner.
        gerritTools.queryChange(incoming.uuid,
          encodeURIComponent(`${incoming.change.project}~${branch}~${incoming.change.id}`),
          undefined, undefined, function (exists, changeData) {
          if (exists && changeData.status != "MERGED") {
            _this.logger.log(
              `A change already exists on ${branch} for ${incoming.change.id}`
              + ` and is ${changeData.status}`, "verbose", incoming.uuid);
            let targets = toolbox.findPickToBranches(incoming.uuid, incoming.change.commitMessage);
            targets.delete(branch);
            const suggestedPicks = Array.from(targets);
            const morePicks = suggestedPicks.length > 0;
            let message = `WARN: Cherry-pick bot cannot pick this change to ${branch} because`
              + ` a change already exists on ${branch} which is in status: ${changeData.status}.\n`
              + `Cherry-pick bot will not proceed automatically.\n`
              + (morePicks ? `It is recommended to update the existing change with further pick-to targets.\n\n` : "\n\n")
              + `    Change ID: ${incoming.change.id}\n`
              + `    Subject: ${incoming.change.subject}\n`
              + (morePicks
                  ? `    Suggested Pick-to: ${suggestedPicks.join(" ")}\n\n`
                  : "\n\n")
              + `Link: ${gerritTools.gerritResolvedURL}/c/${changeData.project}/+/${changeData._number}`;
            gerritTools.locateDefaultAttentionUser(incoming.uuid, incoming,
              incoming.change.owner.email, (user) => {
                gerritTools.addToAttentionSet(incoming.uuid, incoming, user, undefined, undefined, () => {
                  _this.gerritCommentHandler(
                    incoming.uuid, incoming.fullChangeID, undefined,
                    message, "OWNER"
                  );
                });
              });
            toolbox.addToCherryPickStateUpdateQueue(
              incoming.uuid,
              { branch: branch, statusDetail: `OpenOrAbandonedExistsOnTarget`, args: [] },
              "done_targetExistsIsOpen",
              function () {
                toolbox.decrementPickCountRemaining(incoming.uuid);
              }
            );
          } else if (data == "retry") {
            _this.retryProcessor.addRetryJob(
              incoming.uuid, "validateBranch",
              [incoming, branch, responseSignal]
            );
          } else {
            // Success (Change on target branch may not exist or is already merged)
            _this.emit(responseSignal, incoming, branch, data);
          }
        });
        // _this.emit(responseSignal, incoming, branch, data);
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

    function tryLTS() {
      // The target branch existed in the project, but was closed for new changes.
      // So if either the branch or the project is not currently tqtc private, search for
      // a public lts branch first in the passed repo, then search the possible
      // tqtc- repo for a matching tqtc/ branch.
      _this.logger.log("Checking if a public LTS branch exists", "info", incoming.uuid);
      let publicLtsBranch = `lts-${branch}`;
      gerritTools.checkBranchAndAccess(incoming.uuid, incoming.change.project,
        publicLtsBranch, gerrit_user, "push", incoming.customGerritAuth,
        function(validPublicLts, canPushPublicLts, data) {
          if (validPublicLts && canPushPublicLts) {
            // A non-tqtc marked lts- branch was found.
            _this.logger.log(`Using public branch ${publicLtsBranch}.`, "verbose",
                              incoming.uuid);
            done(responseSignal, incoming, publicLtsBranch, true, data);
          } else {
            // It doesn't matter if the bot user is blocked on the branch
            // or it simply doesn't exist, fall back to searching for a
            // tqtc repo and search for the LTS branch there.
            let privateProject = incoming.change.project;
            let privateBranch = branch;
            if (!privateProject.includes("tqtc-")) {
              let projectSplit = privateProject.split('/');
              privateProject = projectSplit.slice(0, -1);
              privateProject.push(`tqtc-${projectSplit.slice(-1)}`);
              privateProject = privateProject.join('/');
            }
            if (!branch.includes("tqtc/lts-"))
              privateBranch = `tqtc/${publicLtsBranch}`;
            gerritTools.checkBranchAndAccess(incoming.uuid, privateProject, privateBranch,
              gerrit_user, "push", incoming.customGerritAuth,
              function(validPrivateLTS, canPushPrivateLTS, data) {
                let message;
                if (validPrivateLTS && canPushPrivateLTS) {
                  // Modify the original object so the bot treats it like it's always been
                  // on tqtc/* with an LTS branch target.
                  incoming.change.project = privateProject;
                  incoming.change.branch = privateBranch;
                } else if (validPrivateLTS) {
                  // Valid private branch, but closed for changes.
                  let errMsg = `Unable to cherry-pick this change to ${branch} or`
                  + ` ${privateBranch} because the branch is closed for new changes.`
                  _this.logger.log(errMsg, "error", incoming.uuid);
                  message =  errMsg + "\n" + closedBranchMsg;
                } else {
                    // No private lts branch exists.
                    let errMsg = `Unable to cherry-pick this change to ${branch}`
                    + ` because the branch is closed for new changes and`
                    + validPublicLts ? ` ${publicLtsBranch} is also closed for new changes.`
                                      : " no private LTS branch exists."
                  _this.logger.log(errMsg, "error", incoming.uuid);
                  message = errMsg + "\n" + closedBranchMsg;
                }
                done(responseSignal, incoming, incoming.change.branch,
                      validPrivateLTS && canPushPrivateLTS, data, message);
              }
            )
          }
        }
      )
    }

    incoming.originalProject = incoming.change.project;
    incoming.originalBranch = incoming.change.branch;
    let closedBranchMsg = "If you need this change in a closed branch, please contact the"
      + " Releasing group to argue for inclusion: releasing@qt-project.org";

    gerritTools.checkBranchAndAccess(
      incoming.uuid, incoming.change.project, branch, gerrit_user,
      "push", incoming.customGerritAuth,
      function(validBranch, canPush, data) {
        let tqtcBranch = /tqtc\//.test(branch);
        if (!validBranch && !tqtcBranch) {
          if (incoming.change.project.includes("/tqtc-")) {
            tryLTS();
          } else {
            // Invalid branch specified in Pick-to: footer or some other critical failure
            let message = `Failed to cherry pick to ${incoming.change.project}:${branch} due`
            + ` to an unknown problem with the target branch.`
            + `\nPlease contact the gerrit admins.`;
            done(responseSignal, incoming, branch, false, data, message);
            return;
          }
        }
        if (canPush) {
          // The incoming branch and project targets are available for pushing new changes.
          _this.logger.log(`Using ${tqtcBranch ? "private" : "public"} branch ${branch}.`,
                           "verbose", incoming.uuid);
          done(responseSignal, incoming, branch, true, data);
        } else if (tqtcBranch && /tqtc-/.test(incoming.change.project)) {
          // The target tqtc branch in the tqtc repo was valid, but required push
          // permissions are denied. Cannot fall back any further.
          _this.logger.log(
            `Unable to push to branch ${branch} in ${incoming.change.project} because either the`
            + " branch is closed or the bot user account does not have permissions"
            + " to create changes there.",
            "error", incoming.uuid
          );
          let message = `Unable to cherry-pick this change to ${branch}`
            + ` because the branch is closed for new changes.\n${closedBranchMsg}`;
          done(responseSignal, incoming, branch, false, data, message);
        } else {
          tryLTS();
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

    function _doPickAlreadyExists(data, message) {
      toolbox.addToCherryPickStateUpdateQueue(
        incoming.uuid,
        {
          branch: branch, statusCode: data.statusCode, statusDetail: data.statusDetail, args: []
        },
        "done_pickAlreadyExists",
        function () {
          toolbox.decrementPickCountRemaining(incoming.uuid);
          gerritTools.locateDefaultAttentionUser(incoming.uuid, incoming,
            incoming.change.owner.email, (user) => {
              gerritTools.addToAttentionSet(incoming.uuid, incoming, user, undefined, undefined, () => {
                const notifyScope = "ALL";
                _this.gerritCommentHandler(
                  incoming.uuid, incoming.fullChangeID, undefined,
                  message, notifyScope
                );
              });
            }
          );
        });
    }

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
          if (data.statusCode == 400 && data.statusDetail.includes("could not update the existing change")) {
            // The cherry-pick failed because the change already exists. This can happen if
            // the pick-targets are user-specified and the user has already cherry-picked
            // to the target branch.
            // Pretend that the target branch has just merged and emit a change-merged signal.


            let remainingPicks = toolbox.findPickToBranches(incoming.uuid, incoming.change.commitMessage);
            remainingPicks.delete(branch);  // Delete this branch from the list of remaining picks.
            // Parse the status from the statusDetail. It exists as the last word in the string,
            // wrapped in ().
            let changeStatus = data.statusDetail.match(/\(([^)]+)\)(?:\\n)?/)[1];
            // Parse the change number for the existing change. It is surrounded by "change" and "in destination"
            // in the statusDetail.
            let existingChangeNumber = data.statusDetail.match(/change (\d+) in destination/)[1];
            let existingChangeURL = `${gerritTools.gerritResolvedURL}/c/${incoming.project.name || incoming.project}/+/${existingChangeNumber}`;
            _this.logger.log(
              `Cherry-pick to ${branch} already exists in state ${changeStatus}.`,
              "info", incoming.uuid
            );
            if (changeStatus == "MERGED") {
              if (remainingPicks.size == 0) {
                // No more picks to do. Just post a comment.
                _doPickAlreadyExists(data,
                  `A closed change already exists on ${branch} with the same change ID.\n`
                  + `No further picks are necessary. Please verify that the existing change`
                  + ` is correct.\n\n`
                  + `Link: ${existingChangeURL}`
                  );
              } else {
              // Mock up a change-merged signal and re-emit it as though the target
              // branch just merged.
              _this.logger.log(`Mocking Merge on ${branch}.`, "info", incoming.uuid);
                toolbox.mockChangeMergedFromOther(incoming.uuid, incoming, branch, remainingPicks, (mockObject) => {
                  if (mockObject) {
                    _this.emit("mock-change-merged", mockObject);
                  }
                  _doPickAlreadyExists(data,
                    `A closed change already exists on ${branch} with this change ID.\n`
                    + `Picks to ${Array.from(remainingPicks).join(", ")} will be performed using`
                    + ` that change as a base.\n`
                    + `Please verify that the existing change and resulting picks are correct.\n\n`
                    + `    Change ID: ${mockObject.change.change_id}\n`
                    + `    Subject: ${mockObject.change.subject}\n\n`
                    + `Link: ${mockObject.change.url}`
                  );
                });
              }
            } else if (changeStatus == "ABANDONED" || changeStatus == "DEFERRED") {
              _doPickAlreadyExists(data,
                `An abandoned change already exists on ${branch} with this change ID .\n`
                + `WARN: Cherry-pick bot cannot continue.\n`
                + `Picks to ${Array.from(remainingPicks).join(", ")} will not be performed automatically.\n\n`
                + `Link: ${existingChangeURL}`
              );
            } else if (changeStatus == "INTEGRATING" || changeStatus == "STAGED") {
              _doPickAlreadyExists(data,
                `A change in in state ${changeStatus} already exists on ${branch} with this change ID .\n`
                + `WARN: Cherry-pick bot cannot continue.\n`
                + `Picks to ${Array.from(remainingPicks).join(", ")} will not be performed automatically from this change.\n`
                + `Picks from the ${changeStatus} change on ${branch} will execute normally upon merge.`
                + ` Please review that change's Pick-to: for correctness.`
                + `Link: ${existingChangeURL}`
              );
            } else {
              _doPickAlreadyExists(data,
                `A change in in state ${changeStatus} already exists on ${branch} with this change ID .\n`
                + `WARN: Cherry-pick bot cannot continue. Please report this issue to gerrit admins.\n`
                + `Cherry-pick bot does not know how to handle changes in ${changeStatus} state.`
              );
            }
          } else {
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
          }
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
  // conflicts and update the attention set to add reviewers if so.
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
      let owner = parentJSON.change.owner.email || parentJSON.change.owner.username;
      gerritTools.checkAccessRights(parentJSON.uuid, parentJSON.change.project,
        cherryPickJSON.branch, owner, "read", undefined,
        (canRead) => {
          if (canRead) {
            gerritTools.setChangeReviewers(parentJSON.uuid, cherryPickJSON.id, [owner], undefined,
              () =>{
                gerritTools.addToAttentionSet(
                  parentJSON.uuid, cherryPickJSON, owner, "Original change owner",
                  parentJSON.customGerritAuth,
                  function (success, data) {
                    if (!success) {
                      _this.logger.log(
                        `Failed to add "${safeJsonStringify(parentJSON.change.owner)}" to the attention`
                        + ` set on ${cherryPickJSON.id}.\nReason: ${safeJsonStringify(data)}`,
                        "warn", parentJSON.uuid
                      );
                      _this.gerritCommentHandler(
                        parentJSON.uuid, cherryPickJSON.id, undefined,
                        `Unable to add ${owner} to the attention set of this issue.\n`
                        + `Reason: ${safeJsonStringify(data)}`,
                        "NONE"
                      );
                    }
                  }
              );
            });
          } else {
            gerritTools.locateDefaultAttentionUser(parentJSON.uuid, cherryPickJSON,
              parentJSON.patchSet.uploader.email,
              (user) => {
                if (user == "copyReviewers")
                  return;  // Copying users is done later regardless of attention set users.
                else {
                  gerritTools.setChangeReviewers(parentJSON.uuid, cherryPickJSON.id,
                    [user], undefined, function(){
                      gerritTools.addToAttentionSet(
                        parentJSON.uuid, cherryPickJSON, owner, "Original Reviewer",
                        undefined, function(){});
                    });
                }
            } )
          }
        });
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
          gerritTools.addToAttentionSet(
            parentJSON.uuid, cherryPickJSON,
            parentJSON.change.owner.email || parentJSON.change.owner.username, "Original Owner",
            parentJSON.customGerritAuth,
            function (success, data) {
              if (!success) {
                _this.logger.log(
                  `Failed to add "${safeJsonStringify(parentJSON.change.owner)}" to the`
                  + ` attention set of ${cherryPickJSON.id}\nReason: ${safeJsonStringify(data)}`,
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
          gerritTools.locateDefaultAttentionUser(parentJSON.uuid, cherryPickJSON,
            parentJSON.patchSet.uploader.email, function(user) {
              if (user && user == "copyReviewers") {
                gerritTools.copyChangeReviewers(parentJSON.uuid, parentJSON.fullChangeID,
                  cherryPickJSON.id);
              } else {
                gerritTools.setChangeReviewers(parentJSON.uuid, cherryPickJSON.id,
                  [user], undefined, function() {
                    gerritTools.addToAttentionSet(
                      parentJSON.uuid, cherryPickJSON, user, "Relevant user",
                      parentJSON.customGerritAuth,
                      function (success, data) {
                        if (!success) {
                          _this.logger.log(
                            `Failed to add "${safeJsonStringify(parentJSON.change.owner)}" to the`
                            + ` attention set of ${cherryPickJSON.id}\n`
                            + `Reason: ${safeJsonStringify(data)}`,
                            "error", parentJSON.uuid
                          );
                        }
                      }
                    );
                  });
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
