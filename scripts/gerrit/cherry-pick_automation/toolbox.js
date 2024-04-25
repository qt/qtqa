// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "toolbox";

const safeJsonStringify = require("safe-json-stringify");
const v8 = require('v8');

const postgreSQLClient = require("./postgreSQLClient");
const { queryBranchesRe, checkBranchAndAccess, queryChange } = require("./gerritRESTTools");
const Logger = require("./logger");
const logger = new Logger();
const config = require("./config.json");

// Set default values with the config file, but prefer environment variable.
function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

let dbSubStatusUpdateQueue = [];
let dbSubStateUpdateLockout = false;
let dbListenerCacheUpdateQueue = [];
let dbListenerCacheUpdateLockout = false;

const allowedBranchRe = /^(dev|master|\d+\.\d+(\.\d+)?)$/;

// Deep copy an object. Useful for forking processing paths with different data
// than originally entered the system.
exports.deepCopy = deepCopy;
function deepCopy(obj) {
  return v8.deserialize(v8.serialize(obj));
}

// Parse the commit message and return a raw list of branches to pick to.
// Trust that the list of branches has been validated by Sanity bot.
exports.findPickToBranches = function (requestUuid, message) {
  let matches = message.match(/(?:^|\\n)Pick-to:(?:\s+(.+))/gm);
  logger.log(
    `Regex on branches matched: ${safeJsonStringify(matches)} from input:\n"${message}"`,
    "debug",
    requestUuid
  );
  let branchSet = new Set();
  if (matches) {
    matches.forEach(function (match) {
      let parsedMatch = match.split(":")[1].split(" ");
      parsedMatch.forEach(function (submatch) {
        if (submatch)
          branchSet.add(submatch);
      });
    });
  }
  return branchSet;
};

// Build a waterfall of cherry picks based on the list of branches.
// Picks to older feature and release branches must be attached to newer
// feature branch picks.
// Example: for input of ["6.5.0", "6.4", "5.15.12", "5.15.11", "5.15"],
// the output will be:
//  {
//    '6.5.0': [],
//    '6.4': ['5.15.12', '5.15.11', '5.15']
//  }
exports.waterfallCherryPicks = function (requestUuid, sourceBranch, branchList) {
  branchList = Array.from(branchList);  // Might be a set.

  if (branchList.length === 0) {
    logger.log(`No branches to waterfall.`, 'debug', requestUuid);
    return {};
  }

  // If any of the entries of branchList are not numerical/dev/master,
  // then return a waterfall object with each branch as a key.
  if (branchList.some((branch) => !allowedBranchRe.test(branch))
      || !allowedBranchRe.test(sourceBranch.replace(/^(tqtc\/)?(lts-)?/, ''))) {
    let waterfall = {};
    for (let branch of branchList) {
      waterfall[branch] = [];
    }
    return waterfall;
  }

  branchList = sortBranches(branchList);

  let waterfall = {};
  let youngestFeatureBranch = branchList.find(isFeatureBranchOrDev);
  let remainingBranches = branchList.filter((branch) => branch !== youngestFeatureBranch);
  if (!youngestFeatureBranch || remainingBranches.length === 0) {
    waterfall[youngestFeatureBranch || remainingBranches[0]] = [];
    return waterfall;
  }

  let children = remainingBranches.filter((branch) => {
    let result = (isAncestor(branch, youngestFeatureBranch)
                  || isChild(branch, youngestFeatureBranch));
    return result;
  });

  waterfall[youngestFeatureBranch] = children;

  remainingBranches = remainingBranches.filter((branch) => !children.includes(branch));

  for (let branch of remainingBranches) {
    waterfall[branch] = [];
  }

  return waterfall;
};

// Determine if a given branch is a child of another branch.
function isChild(maybeChild, maybeParent) {
  // Account for dev and master branches.
  if (maybeChild === "dev" || maybeChild === "master") {
    return false;
  }
  if (maybeParent === "dev" || maybeParent === "master") {
    return true;
  }
  let childParts = maybeChild.split('.').map(Number);
  let parentParts = maybeParent.split('.').map(Number);

  // Major version less than the parent is always a child.
  if (childParts[0] < parentParts[0]) {
    return true;
  }

  // Feature versions are children if lesser than the parent. This
  // also catches release versions of the same or newer feature versions.
  if (childParts[0] === parentParts[0] && childParts[1] <= parentParts[1]) {
    return true;
  }

  // Then the release version is newer than the parent.
  return false;
}

// Determine if a given branch is an ancestor of another branch.
function isAncestor(maybeAncestor, reference) {
  // Account for dev and master branches.
  if (maybeAncestor === "dev" || maybeAncestor === "master") {
    return true;
  }
  if (reference === "dev" || reference === "master") {
    return false;
  }
  let branchParts = maybeAncestor.split('.').map(Number);
  let ancestorParts = reference.split('.').map(Number);

  // Release branches like 5.15.0 cannot be ancestors of feature branches like 5.15.
  if (branchParts.length > ancestorParts.length) {
    return false;
  }

  // Major versions that are less than the passed ancestor are ancestors.
  if (branchParts[0] < reference[0]) {
    return true;
  }

  // Feature versions are ancestors if it is greater than the reference.
  if (branchParts[1] > reference[1]) {
    return true;
  }

  return true;
}

function isFeatureBranchOrDev(branch) {
  return branch === "dev" || branch === "master" || branch.split('.').length === 2;
}

// given a list of pick-to branches, determine if any gaps exist in the list.
// Return a completed list of pick-to targets with a diff.
exports.findMissingTargets = function (uuid, changeId, project, targets, callback) {

  const isTqtc = /tqtc-/.test(project);  // Is the cherry-pick request coming from a tqtc repo?
  const isLTS = /^(tqtc\/)?lts-/.test(decodeURIComponent(changeId).split('~')[1]); // Is the change on an LTS branch?
  const prefix = isTqtc && isLTS
    ? "tqtc/lts-"
    : isTqtc
      ? "tqtc/"
      : isLTS
        ? "lts-" : "";
  const bareBranch = decodeURIComponent(changeId).split('~')[1].replace(/^(tqtc\/)?(lts-)?/, '');


  let highestTarget = "";

  if (Array.from(targets).length === 0) {
    logger.log(`No targets to check.`, 'debug', uuid);
    callback(false, undefined, []);
    return;
  }

  // If any of the entries of branchList are not numerical/dev/master,
  // It is not possible to identify missing targets. Abort.
  if (Array.from(targets).some((branch) => !allowedBranchRe.test(branch))
      || !allowedBranchRe.test(bareBranch)) {
    callback(false, undefined, []);
    return;
  }

  // targets will always be bare versions, like "5.15".
  let featureBranches = new Set();
  let devMaster = [];
  for (let target of targets) {
    // account for dev and master branches.
    if (target === "dev" || target === "master") {
      devMaster = target;
      continue;
    }
    let parts = target.split('.');
    featureBranches.add(parts[0] + '.' + parts[1]);
  }
  highestTarget = Array.from(featureBranches).concat(devMaster).sort(sortBranches)[0];
  if (isChild(highestTarget, bareBranch)) {
    // If the highest target is a child of the bare branch, then the highest target
    // should be considered self.
    highestTarget = bareBranch;
  }



  let releaseBranches = {};
  for (let key of featureBranches) {
    releaseBranches[key] = [];
  }
  for (let target of targets) {
    // account for dev and master branches.
    if (target === "dev" || target === "master") {
      continue;
    }
    let parts = target.split('.');
    if (parts.length === 3) {
      releaseBranches[parts[0] + '.' + parts[1]].push(target);
    }
  }

  // Sort by release version
  for (let key of featureBranches) {
    releaseBranches[key].sort((a, b) => {
      let aParts = a.split('.').map(Number);
      let bParts = b.split('.').map(Number);
      return aParts[2] - bParts[2];
    });
  }

  // Filter result branches if the originating change had a tqtc and/or an LTS prefix.
  const searchRe = `(${prefix}(?:${Array.from(featureBranches).join('|')}|[0-9].[0-9]{1,}|${prefix}dev|${prefix}master)).*`
  queryBranchesRe(uuid, project, false, searchRe, undefined, (success, remoteBranches) => {
    if (!success) {
      return;
    }

    function makeNextFeature(branch) {
      return branch.split('.').slice(0, 1).join('.')
        + '.' + (Number(branch.split('.')[1]) + 1);  // f.e. 5.15 -> 5.16
    }

    // Use sanitized branches to determine if any gaps exist.
    const bareRemoteBranches = remoteBranches.map((branch) => branch.replace(/^(tqtc\/)?(lts-)?/, ''));

    function _finishUp(error, change) {
      // Always include all gaps in release branches.
      for (let branch of featureBranches) {
        for (let release of releaseBranches[branch]) {
          const nextRelease = release.split('.').slice(0, 2).join('.')
          + '.' + (Number(release.split('.')[2]) + 1);  // f.e. 5.15.12 -> 5.15.13
          if (releaseBranches[branch].includes(nextRelease)) {
            continue;
          }
          if (bareRemoteBranches.includes(nextRelease)) {
            missing.push(nextRelease);
          }
        }
      }

      if (missing.length) {
        logger.log(`Missing branches: ${missing.join(', ')}`, 'info', uuid);
      }
      callback(Boolean(error), change, missing);
    }

    let missing = [];
    function _findMissingFeatures(branch, start = false) {
      if (start) {
        if (bareRemoteBranches.includes(branch)) {
          if (branch === bareBranch) {
            // Do not test the branch we're picking from. It must exist.
            _findMissingFeatures(branch);  // recurse normally
          } else if (!targets.has(branch)) {
            // Check to see if the next feature branch is still open for new changes.
            checkBranchAndAccess(uuid, project, prefix + branch, "cherrypickbot", "push", undefined,
              (success, hasAccess) => {
                if (success && hasAccess) {
                  const missingChangeId = `${encodeURIComponent(project)}~`
                    + `${encodeURIComponent(prefix + branch)}~${changeId.split('~').pop()}`
                  queryChange(uuid, missingChangeId, undefined, undefined, (success) => {
                    if (!success)
                      missing.push(branch);
                    else
                      logger.log(`Skipping ${branch}. Change already exists.`, "debug", uuid);
                    _findMissingFeatures(branch);  // recurse normally
                  });
                } else {
                  logger.log(`Skipping ${branch} because it is closed.`, "debug", uuid);
                  _findMissingFeatures(branch);  // recurse normally
                }
            });
          } else {
            logger.log(`Skipping ${branch} because it is already in the list.`, "debug", uuid);
            _findMissingFeatures(branch);  // recurse normally
          }
        } else {
          logger.log(`Skipping ${branch} because it does not exist.`, "debug", uuid);
          _findMissingFeatures(branch);  // recurse normally
        }
        return;
      }

      const nextFeature = makeNextFeature(branch);
      if (bareRemoteBranches.includes(nextFeature)) {
        if (nextFeature === bareBranch || featureBranches.has(nextFeature)) {
          _findMissingFeatures(nextFeature);   // Recurse to the next feature branch.
        } else if (isChild(nextFeature, highestTarget)) {
          // Only test branches which are older than/children to the current branch.
          // This forces the waterfall to only work downwards from the highest
          // specified branch.
          // Check to see if the next feature branch is still open for new changes.
          checkBranchAndAccess(uuid, project, prefix + nextFeature, "cherrypickbot", "push", undefined,
            (success, hasAccess) => {
              if (success && hasAccess) {
                const missingChangeId = `${encodeURIComponent(project)}~`
                  + `${encodeURIComponent(prefix + nextFeature)}~${changeId.split('~').pop()}`
                  queryChange(uuid, missingChangeId, undefined, undefined, (success, data) => {
                    if (!success)
                      missing.push(prefix + nextFeature);
                    else {
                      if (data.status == "MERGED") {
                        logger.log(`Skipping ${prefix + nextFeature}. Merged change already exists.`, "debug", uuid);
                      } else {
                        const _next = makeNextFeature(nextFeature);
                        if (!bareRemoteBranches.includes(_next)) {
                          // This was the last and highest feature branch, which means it would
                          // be our first pick target (excepting dev). Since the change is open,
                          // we should not touch it.
                          // Call _finishUp() and pick to only any immediate release targets.
                          logger.log(`Missing immediate target ${prefix + nextFeature} has a change in ${data.status}.`, "error", uuid);
                          _finishUp(true, data);
                          return;
                        }
                      }
                    }
                    _findMissingFeatures(nextFeature);
                  });
              } else {
                logger.log(`Skipping ${prefix + nextFeature} because it is closed.`, "debug", uuid);
                _findMissingFeatures(nextFeature);
              }
          });
        } else {
          // NextFeature exists remotely, but is out of scope based on pick targets and source branch.
          _finishUp();
        }
      } else {
        // We've reached the end of the feature branches which are older than the highest branch.
        _finishUp();
      }
    }

    // Use the oldest feature version to find any gaps since then.
    if (Array.from(featureBranches).length === 0) {
      _finishUp();
      return;
    }
    try {
      _findMissingFeatures(Array.from(featureBranches).sort(sortBranches)[0], true);
    } catch (e) {
      logger.log(`Error finding missing targets: ${e}`, 'error', uuid);
    }
  });
}

exports.sortBranches = sortBranches;
function sortBranches(branches) {
  return Array.from(branches).sort((a, b) => {
    // Account for dev and master branches.
    if (a === "dev" || a === "master") {
      return -1;
    }
    if (b === "dev" || b === "master") {
      return 1;
    }
    let aParts = a.split('.').map(Number);
    let bParts = b.split('.').map(Number);

    for (let i = 0; i < Math.min(aParts.length, bParts.length); i++) {
      if (aParts[i] !== bParts[i]) {
        return bParts[i] - aParts[i];
      }
    }

    return aParts.length - bParts.length;
  });
}

exports.repoUsesStaging = repoUsesStaging;
function repoUsesStaging(uuid, cherryPickJSON) {
  let submitModeRepos = envOrConfig("SUBMIT_MODE_REPOS");
  // Convert the comma-separated list of repos to an array if it is not already.
  if (submitModeRepos && typeof submitModeRepos === "string") {
    submitModeRepos = submitModeRepos.split(",");
  }
  if (submitModeRepos && submitModeRepos.includes(cherryPickJSON.project)) {
    logger.log(
      `Repo ${cherryPickJSON.project} is in SUBMIT_MODE.`, "verbose", uuid);
    return false;
  }
  return true;
}

// Take a gerrit Change object and mock a change-merged event.
// Use the original merge event as the template for the mocked event.
exports.mockChangeMergedFromOther = mockChangeMergedFromOther;
function mockChangeMergedFromOther(uuid, originalMerge, targetBranch, remainingPicks, callback) {
  if (remainingPicks.size == 0) {
    logger.log(`No remaining picks for existing target on ${targetBranch}. Nothing to do.`,
      "debug", uuid);
    callback(null);
    return;
  }
  let mockMerge = deepCopy(originalMerge);
  // Assemble the fullChangeID from the project and branch.
  let targetChangeId = encodeURIComponent(mockMerge.change.project) + "~"
    + encodeURIComponent(targetBranch) + "~" + mockMerge.change.id;
  // Query the target change from gerrit.
  queryChange(uuid, targetChangeId, undefined, undefined, function (success, targetChange) {
    if (!success) {
      logger.log(`Error mocking change-merged event: ${targetChangeId}, ${targetChange}`, "error", uuid);
      callback(null);
      return;
    }
    // Replace the following properties of mockMerge with the targetChange:
    //   newRev
    //   patchSet
    //   change
    //   refName
    //   changeKey
    //   fullChangeID
    //   eventCreatedOn
    delete mockMerge.uuid;
    mockMerge.newRev = targetChange.current_revision;
    mockMerge.patchSet = {
      number: targetChange.revisions[targetChange.current_revision]._number,
      revision: targetChange.current_revision,
      parents: targetChange.revisions[targetChange.current_revision].commit.parents,
      ref: `refs/changes/${targetChange._number}/${targetChange.current_revision}`,
      uploader: targetChange.owner,
      author: targetChange.revisions[targetChange.current_revision].commit.author,
      createdOn: targetChange.created
    };
    targetChange.id = targetChange.change_id;
    targetChange.number = targetChange._number;
    // build the url from the project and change number.
    targetChange.url = `https://codereview.qt-project.org/c/${targetChange.project}/+/`
      + `${targetChange._number}`;
    // Replace Pick-to: footer with the remaining picks.
    // If targetChange did not have a Pick-to footer, add one at the beginning
    // of the footers. Footers are separated from the commit message body by the last\n\n.
    const origCommitMessage = targetChange.revisions[targetChange.current_revision].commit.message;
    let footerIndex = origCommitMessage.lastIndexOf("\n\n");
    if (footerIndex === -1) {
      footerIndex = origCommitMessage.length;
    } else {
      footerIndex += 2;  // Start after the last \n\n.
    }
    let footer = origCommitMessage.slice(footerIndex);
    let pickToFooter = "Pick-to: " + Array.from(remainingPicks).join(" ");
    if (footer.match(/Pick-to:.*$/m)) {
      footer = footer.replace(/Pick-to:.*$/m, pickToFooter);
    } else {
      footer = pickToFooter + "\n\n" + footer;
    }
    targetChange.commitMessage = origCommitMessage.slice(0, footerIndex) + footer;
    mockMerge.change = targetChange;
    mockMerge.refName = `refs/heads/${targetChange.branch}`;
    mockMerge.changeKey = { key: targetChange.change_id };
    mockMerge.fullChangeID = encodeURIComponent(targetChange.project) + "~"
      + encodeURIComponent(targetChange.branch) + "~" + targetChange.change_id;
    mockMerge.eventCreatedOn = Date.now();

    callback(mockMerge);
  });
}

// Get all database items in the processing_queue with state "processing"
exports.getAllProcessingRequests = getAllProcessingRequests;
function getAllProcessingRequests(callback) {
  postgreSQLClient.query(
    "processing_queue", "*", "state", "processing", "=",
    function (success, rows) {
      // If the query is successful, the rows will be returned.
      // If it fails for any reason, the error is returned in its place.
      if (success)
        callback(true, rows);
      else
        callback(false, rows);
    }
  );
}

// Query the database for any listeners that need to be set up.
// These are listeners that were tied to in-process items, and should
// be set up again, even if the item is marked as "finished" in the database.
exports.getCachedListeners = getCachedListeners;
function getCachedListeners(callback) {
  postgreSQLClient.query(
    "processing_queue", "listener_cache", "listener_cache", "", "IS NOT NULL",
    function (success, rows) {
      // If the query is successful, the rows will be returned.
      // If it fails for any reason, the error is returned in its place.
      callback(success, rows);
    }
  );
}

exports.retrieveRequestJSONFromDB = retrieveRequestJSONFromDB;
function retrieveRequestJSONFromDB(uuid, callback) {
  postgreSQLClient.query(
    "processing_queue", "rawjson", "uuid", uuid, "=",
    function (success, rows) {
      // If the query is successful, the row will be returned.
      // If it fails for any reason, the error is returned in its place.
      callback(success, success ? decodeBase64toJSON(rows[0].rawjson) : rows);
    }
  );
}

// Update a inbound change's JSON inbound request.
exports.updateBaseChangeJSON = updateBaseChangeJSON;
function updateBaseChangeJSON(uuid, rawjson, callback) {
  postgreSQLClient.update(
    "processing_queue", "uuid", uuid,
    { rawjson: encodeJSONtoBase64(rawjson) }, callback
  );
}

// Set the current state of an inbound request.
exports.setDBState = setDBState;
function setDBState(uuid, newState, callback) {
  postgreSQLClient.update("processing_queue", "uuid", uuid, { state: newState }, callback);
}

// Set the count of picks remaining on the inbound request.
// This count determines when we've done all the work we need
// to do on an incoming request.
exports.setPickCountRemaining = setPickCountRemaining;
function setPickCountRemaining(uuid, count, callback) {
  logger.log(`Set pick count to ${count}`, "debug", uuid);
  postgreSQLClient.update(
    "processing_queue", "uuid", uuid,
    { pick_count_remaining: count }, callback
  );
}

// decrement the remaining count of cherrypicks on an inbound request by 1.
exports.decrementPickCountRemaining = decrementPickCountRemaining;
function decrementPickCountRemaining(uuid, callback) {
  logger.log(`Decrementing pick count.`, "debug", uuid);
  postgreSQLClient.decrement(
    "processing_queue", uuid, "pick_count_remaining",
    function (success, data) {
      logger.log(`New pick count: ${data[0].pick_count_remaining}`, "debug", uuid);
      if (data[0].pick_count_remaining == 0)
        setDBState(uuid, "complete");
      if (callback)
        callback(success, data);
    }
  );
}

// Add a status update for an inbound request's cherry-pick job to the queue.
// Process it immediately if the queue is unlocked (no other update is currently
// being processed).
// This needs to be under a lockout since individual cherrypicks are part of
// a larger base64 encoded blob under the parent inbound request.
exports.addToCherryPickStateUpdateQueue = addToCherryPickStateUpdateQueue;
function addToCherryPickStateUpdateQueue(
  parentUuid, branchData, newState,
  callback, unlock = false
) {
  if (unlock) {
    logger.log(`State update received with unlock=true`, "silly");
  } else {
    logger.log(
      `New state update request: State: ${newState}, Data: ${safeJsonStringify(branchData)}`,
      "debug", parentUuid
    );
  }
  if (parentUuid && branchData && newState)
    dbSubStatusUpdateQueue.push([parentUuid, branchData, newState, callback]);

  // setDBSubState() calls postgreSQLClient.update(). As part of that process,
  // this queue function is called again with unlock = true, with no other
  // parameters. This runs a check for remaining items in the queue and pops
  // and processes the next item until the queue is emptied. When the last
  // item has been processed and addToCherryPickStateUpdateQueue() is called
  // with unlock, the queue length will be 0 and the lockout will be removed.
  if (!dbSubStateUpdateLockout || unlock) {
    dbSubStateUpdateLockout = true;
    if (dbSubStatusUpdateQueue.length > 0) {
      let args = dbSubStatusUpdateQueue.shift();
      setDBSubState.apply(this, args);
    } else {
      dbSubStateUpdateLockout = false;
    }
  }
}

// Like addToCherryPickStateUpdateQueue above, listeners are stored in the
// database as a JSON blob and must be added, removed, and updated
// synchronously.
exports.addToListenerCacheUpdateQueue = addToListenerCacheUpdateQueue;
function addToListenerCacheUpdateQueue(
  action, source, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
  timeout, timestamp, messageChangeId,
  messageOnSetup, messageOnTimeout,
  emitterEvent,
  emitterArgs, eventActionOnTimeout, eventActionOnTimeoutArgs, originalChangeUuid,
  persistListener, contextId,
  callback, unlock = false
) {
  if (unlock) {
    logger.log(`Listener cache update received with unlock=true`, "silly");
  } else {
    logger.log(
      `New listener cache request: ${safeJsonStringify(arguments)}`,
      "silly", originalChangeUuid
    );
    dbListenerCacheUpdateQueue.push([
      action, source, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
      timeout, timestamp, messageChangeId,
      messageOnSetup, messageOnTimeout,
      emitterEvent,
      emitterArgs, eventActionOnTimeout, eventActionOnTimeoutArgs, originalChangeUuid,
      persistListener, contextId, callback
    ]);
  }

  // updateDBListenerCache() calls this queue function is called again with
  // unlock = true, with no other parameters.
  // This runs a check for remaining items in the queue and pops
  // and processes the next item until the queue is emptied. When the last
  // item has been processed and addToListenerCacheUpdateQueue() is called
  // with unlock, the queue length will be 0 and the lockout will be removed.
  if (!dbListenerCacheUpdateLockout || unlock) {
    dbListenerCacheUpdateLockout = true;
    if (dbListenerCacheUpdateQueue.length > 0) {
      let args = dbListenerCacheUpdateQueue.shift();
      updateDBListenerCache.apply(this, args);
    } else {
      dbListenerCacheUpdateLockout = false;
    }
  }
}

// Helper methods for encoding and decoding JSON objects for storage in a database.
exports.decodeBase64toJSON = decodeBase64toJSON;
function decodeBase64toJSON(base64string) {
  return JSON.parse(Buffer.from(base64string, "base64").toString("utf8"));
}

exports.encodeJSONtoBase64 = encodeJSONtoBase64;
function encodeJSONtoBase64(json) {
  return Buffer.from(safeJsonStringify(json)).toString("base64");
}

let listeners = {};
// Set up an event listener on ${source}, which can also be accompanied by
// a gerrit comment on setup and/or timeout. Listeners are stored in the
// database until consumed, tied to the original change-merged event
// that created them. When a listener is triggered or times out, it is
// removed from the database listener_cache.
exports.setupListener = setupListener;
function setupListener(
  source, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
  timeout, timestamp, messageChangeId,
  messageOnSetup, messageOnTimeout,
  emitterEvent,
  emitterArgs, eventActionOnTimeout, eventActionOnTimeoutArgs, originalChangeUuid,
  persistListener, contextId, isRestoredListener
) {
  const listenerId = `${listenerEvent}~${contextId}`;
  const messageTriggerId = `${listenerEvent}~${messageTriggerEvent}~${contextId}`;
  const messageCancelTriggerId = `${listenerEvent}~${messageCancelTriggerEvent}~${contextId}`;

  // Check to make sure we don't register the same listener twice.
  // Event listeners should be unique and the same source should never call
  // setupListener() twice for the same event.
  // The same listenerEvent may be subscribed to from multiple sources, however.
  // This is why the listenerId is a combination of the listenerEvent and the
  // contextId.
  if (listeners[listenerId]) {
    logger.log(
      `Ignoring listener setup request: ${
        source.constructor.name} already has a listener for ${listenerEvent}`,
      "info", originalChangeUuid
    );
    return;
  }

  if (!isRestoredListener || logger.levels[logger.level] >= logger.levels["debug"])
    logger.log(`Requested listener setup of ${listenerEvent}`, "info", originalChangeUuid);

  // Calculate the timeout value based on the original timestamp passed.
  // This is required for listeners restored from the database so that
  // If a server is restarted daily for example, it will not extend a
  // listener beyond the original intended length.
  let elapsed = 0;
  let newTimeout = timeout;
  if (!timestamp)
    timestamp = Date.now();

  if (isRestoredListener) {
    elapsed = Date.now() - timestamp;
    newTimeout -= elapsed;
    // If the listener has 5000 ms or less remaining, delete it.
    if (newTimeout < 5000) {
      // Post a comment if the nearly expired listener should, as long as it's not expired yet.
      if (newTimeout > 0 && messageOnTimeout && !messageTriggerEvent) {
        source.emit(
          "postGerritComment", originalChangeUuid, messageChangeId, undefined, messageOnTimeout,
          "OWNER"
        );
        // Emit the eventActionOnTimeout event if set.
        if (eventActionOnTimeout) {
          source.emit(eventActionOnTimeout, ...eventActionOnTimeoutArgs);
        }
      }
      logger.log(
        `Recovered listener is stale: ${
          listenerEvent}. Not restoring it, and deleting it from the database.`,
        "warn", originalChangeUuid
      );
      addToListenerCacheUpdateQueue(
        "delete", undefined, listenerEvent, undefined, undefined,
        undefined, undefined, undefined,
        undefined, undefined,
        undefined,
        undefined, undefined, undefined, originalChangeUuid,
        false, contextId
      );
      // Do not execute the rest of the listener setup.
      return;
    }
  }

  // Cancel the event listener after ${newTimeout} if timeout is set, since
  // leaving listeners is a memory leak and a manually processed cherry
  // pick MAY not retain the same changeID
  let timeoutHandle;
  if (listenerEvent && newTimeout) {
    timeoutHandle = setTimeout(() => {
      if (listeners[listenerId])
        source.removeListener(listenerEvent, listeners[listenerId]);
      if (listeners[messageTriggerId])
        source.removeListener(messageTriggerEvent, listeners[messageTriggerId]);
      if (listeners[messageCancelTriggerId])
        source.removeListener(messageCancelTriggerEvent, listeners[messageCancelTriggerId]);
      delete listeners[listenerId];
      delete listeners[messageTriggerId];
      delete listeners[messageCancelTriggerId];
      // Post a message to gerrit on timeout if set.
      if (messageOnTimeout && !messageTriggerEvent) {
        source.emit(
          "postGerritComment", originalChangeUuid, messageChangeId, undefined, messageOnTimeout,
          "OWNER"
        );
      }
      // Emit the eventActionOnTimeout event if set.
      if (eventActionOnTimeout) {
        source.emit(eventActionOnTimeout, ...eventActionOnTimeoutArgs);
      }
    }, newTimeout);
  }

  if (messageChangeId && messageOnSetup) {
    if (messageTriggerEvent) {
      if (!isRestoredListener || logger.levels[logger.level] >= logger.levels["debug"]) {
        logger.log(
          `Requested message trigger listener setup of ${messageTriggerEvent}`,
          "info", originalChangeUuid
        );
      }
      listeners[messageTriggerId] = function () {
        logger.log(`Event trigger ${messageTriggerEvent} received.`, "debug", originalChangeUuid);
        if (persistListener) {
          addToListenerCacheUpdateQueue(
            // Pass the class name, not the class object
            "add", source.constructor.name, listenerEvent, "", messageCancelTriggerEvent,
            timeout, timestamp, messageChangeId,
            messageOnSetup, messageOnTimeout,
            emitterEvent,
            emitterArgs, eventActionOnTimeout, eventActionOnTimeoutArgs, originalChangeUuid,
            persistListener, contextId
          );
        }
        if (listeners[messageCancelTriggerId])
          source.removeListener(messageCancelTriggerEvent, listeners[messageCancelTriggerId]);
        source.emit(
          "postGerritComment", originalChangeUuid, messageChangeId, undefined, messageOnSetup,
          "OWNER"
        );
      };
      source.once(messageTriggerEvent, listeners[messageTriggerId]);
    } else if (!isRestoredListener) {
      source.emit(
        "postGerritComment", originalChangeUuid, messageChangeId, undefined, messageOnSetup,
        "OWNER"
      );
    }

    if (messageCancelTriggerEvent) {
      logger.log(
        `Requested message cancel trigger listener setup of ${messageCancelTriggerEvent}`,
        "info", originalChangeUuid
      );
      listeners[messageCancelTriggerId] = function () {
        logger.log(
          `Event trigger ${messageCancelTriggerEvent} received.`,
          "debug", originalChangeUuid
        );
        clearTimeout(timeoutHandle);
        if (listeners[listenerId])
          source.removeListener(listenerEvent, listeners[listenerId]);
        if (listeners[messageTriggerId])
          source.removeListener(messageTriggerEvent, listeners[messageTriggerId]);
        delete listeners[listenerId];
        delete listeners[messageTriggerId];
        delete listeners[messageCancelTriggerId];
        addToListenerCacheUpdateQueue(
          "delete", undefined, listenerEvent, undefined, undefined,
          undefined, undefined, undefined,
          undefined, undefined,
          undefined,
          undefined, undefined, undefined, originalChangeUuid,
          false, contextId
        );
      };
      source.once(messageCancelTriggerEvent, listeners[messageCancelTriggerId]);
    }
  }

  // Listen for event only once. The listener is consumed if triggered, and
  // should also be deleted from the database.
  if (listenerEvent) {
    listeners[listenerId] = function () {
      clearTimeout(timeoutHandle);
      if (listeners[messageTriggerId])
        source.removeListener(messageTriggerEvent, listeners[messageTriggerId]);
      if (listeners[messageCancelTriggerId])
        source.removeListener(messageCancelTriggerEvent, listeners[messageCancelTriggerId]);
      logger.log(`Received event for listener ${listenerEvent}`);
      setTimeout(function () {
        source.emit(emitterEvent, ...emitterArgs);
        delete listeners[listenerId];
        delete listeners[messageTriggerId];
        delete listeners[messageCancelTriggerId];
        addToListenerCacheUpdateQueue(
          "delete", undefined, listenerEvent, undefined, undefined,
          undefined, undefined, undefined,
          undefined, undefined,
          undefined,
          undefined, undefined, undefined, originalChangeUuid, false, contextId
        );
      }, 1000);
    };
    source.once(listenerEvent, listeners[listenerId]);
    logger.log(
      `Set up listener for ${listenerEvent} with remaining timeout ${newTimeout}`,
      "info", originalChangeUuid
    );
    // Broadcast the event again if it was cached while we were still setting up the listener.
    // Source must have a cache for this to work. Most commonly used with RequestProcessor.
    if (source.eventCache && source.eventCache[listenerEvent]) {
      source.emit(listenerEvent);
      logger.log(`Found event ${listenerEvent} in the cache of ${source.constructor.name}.`,
                 "debug", originalChangeUuid)
    }
  }

  // Add this listener to the database.
  if (persistListener) {
    addToListenerCacheUpdateQueue(
      // Pass the class name, not the class object
      "add", source.constructor.name, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
      timeout, timestamp, messageChangeId,
      messageOnSetup, messageOnTimeout,
      emitterEvent,
      emitterArgs, eventActionOnTimeout, eventActionOnTimeoutArgs, originalChangeUuid,
      persistListener, contextId
    );
  }
}

// Execute an update statement for cherrypick branch statuses.
// The update action *must* be semaphored since data about cherry pick
// branches for a given change is kept in a JSON blob within a single
// cell on a given row for an origin revision.
// Use the addToCherryPickStateUpdateQueue() function to queue updates.
// NOTE: branches are sanitized by this operation:
// "tqtc/lts-5.15" is written as simply "5.15" for better state tracking.
function setDBSubState(uuid, branchdata, state, callback) {
  let branch = /(?:tqtc\/lts-)?(.+)/.exec(branchdata.branch).pop()
  postgreSQLClient.query(
    "processing_queue", "cherrypick_results_json", "uuid", uuid, "=",
    function (success, rows) {
      if (success) {
        let newdata = decodeBase64toJSON(rows[0].cherrypick_results_json);
        if (newdata[branch] == undefined) {
          newdata[branch] = { state: state, targetParentRevision: branchdata.revision };
        } else {
          // Overwrite the target branch object with any new updates.
          for (let [key, value] of Object.entries(branchdata)) {
            if (key != "branch")
              newdata[branch][key] = value;
          }
          newdata[branch]["state"] = state;
        }
        newdata = encodeJSONtoBase64(newdata);
        postgreSQLClient.update(
          "processing_queue", "uuid", uuid, { cherrypick_results_json: newdata }, callback,
          // Call the queue function again when the database update
          // finishes to check for further updates to process.
          addToCherryPickStateUpdateQueue
        );
      } else {
        logger.log(
          `ERROR: Failed to update sub-state branch ${branch} on revision key ${
            branchdata.revision}. Raw error: ${rows}`,
          "error", uuid
        );
      }
    }
  );
}

// Retrieve the state of an ongoing cherry-pick target.
// Useful to avoid race-conditions and collisions when listening
// for an event which may result in parallel processes acting on the
// same cherry-pick target.
exports.getDBSubState = getDBSubState;
function getDBSubState(uuid, branch, callback) {
  postgreSQLClient.query(
    "processing_queue", "cherrypick_results_json", "uuid", uuid, "=",
    (success, rows) => {
      if (success) {
        let picksJSON = decodeBase64toJSON(rows[0].cherrypick_results_json);
        if (picksJSON[branch])
          callback(true, picksJSON[branch].state);
        else
          callback(false);
      } else {
        callback(false);
      }
    }
  );
}

// Update the database with the passed listener data.
// This should only ever be called by addToListenerCacheUpdateQueue()
// since database operations on listener_cache should never be done
// in parallel due to potential data loss.
function updateDBListenerCache(
  action, source, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
  timeout, timestamp, messageChangeId,
  messageOnSetup, messageOnTimeout,
  emitterEvent,
  emitterArgs, eventActionOnTimeout, eventActionOnTimeoutArgs, originalChangeUuid,
  persistListener, contextId, callback
) {
  function doNext() {
    // call the queue manager again with only unlock. This will pop
    // the next update in queue if available.
    logger.log("calling next listener cache update.", "verbose");
    addToListenerCacheUpdateQueue(
      undefined, undefined, undefined, undefined, undefined,
      undefined, undefined, undefined,
      undefined, undefined,
      undefined,
      undefined, undefined, undefined, undefined,
      undefined, undefined,
      undefined, true
    );
  }

  postgreSQLClient.query(
    "processing_queue", "listener_cache", "uuid", originalChangeUuid, "=",
    (success, data) => {
      if (success) {
        let dataJSON;
        let newData;
        let rawWrite;
        // decode the base64 encoded {} object. Create a new one if it
        // doesn't exist.
        if (data[0].listener_cache)
          dataJSON = decodeBase64toJSON(data[0].listener_cache);
        else
          dataJSON = {};
        switch (action) {
        case "add":
          dataJSON[listenerEvent + '~' + contextId] =
            [
              source, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
              timeout, timestamp, messageChangeId,
              messageOnSetup, messageOnTimeout,
              emitterEvent,
              emitterArgs, eventActionOnTimeout, eventActionOnTimeoutArgs, originalChangeUuid,
              persistListener, contextId
            ];
          break;
        case "delete":
          delete dataJSON[listenerEvent + '~' + contextId];
          if (Object.keys(dataJSON).length === 0 && dataJSON.constructor === Object) {
            // Deleting the listener caused the list to be empty.
            // Write a [null] to the database instead of {}.
            // This keeps things clean and stops the startup procedure
            // from pulling rows that have empty objects of no listeners.
            newData = null;
            rawWrite = true;
          }
          break;
        default:
          // Just return. The action to perform is bad.
          // This should never happen.
          logger.log(
            `bad Listener action "${action}". Args:\n${
              safeJsonStringify(arguments, undefined, 2)}`,
            "error", originalChangeUuid
          );
          if (callback)
            callback(success, data);
          doNext();
          return;
        }
        if (!rawWrite)
          newData = encodeJSONtoBase64(dataJSON);
        postgreSQLClient.update(
          "processing_queue", "uuid", originalChangeUuid, { listener_cache: newData },
          doNext
        );
      }
      if (callback)
        callback(success, data);
    }
  );
}
