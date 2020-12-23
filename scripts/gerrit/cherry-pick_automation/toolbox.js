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

exports.id = "toolbox";

const safeJsonStringify = require("safe-json-stringify");
const v8 = require('v8');

const postgreSQLClient = require("./postgreSQLClient");
const Logger = require("./logger");
const logger = new Logger();

let dbSubStatusUpdateQueue = [];
let dbSubStateUpdateLockout = false;
let dbListenerCacheUpdateQueue = [];
let dbListenerCacheUpdateLockout = false;

// Deep copy an object. Useful for forking processing paths with different data
// than originally entered the system.
exports.deepCopy = function (obj) {
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
  emitterArgs, originalChangeUuid, persistListener,
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
      emitterArgs, originalChangeUuid, persistListener, callback
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
  emitterArgs, originalChangeUuid, persistListener, isRestoredListener
) {
  // Check to make sure we don't register the same listener twice.
  // Event listeners should be unique and never called from different
  // places in the application, so there's no need to worry about
  // updating the listener with new data.
  if (source.eventNames().includes(listenerEvent)) {
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
        undefined, originalChangeUuid, false
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
      source.removeAllListeners(listenerEvent);
      source.removeAllListeners(messageTriggerEvent);
      source.removeAllListeners(messageCancelTriggerEvent);
      // Post a message to gerrit on timeout if set.
      if (messageOnTimeout && !messageTriggerEvent) {
        source.emit(
          "postGerritComment", originalChangeUuid, messageChangeId, undefined, messageOnTimeout,
          "OWNER"
        );
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
      source.once(messageTriggerEvent, function () {
        logger.log(`Event trigger ${messageTriggerEvent} received.`, "debug", originalChangeUuid);
        if (persistListener) {
          addToListenerCacheUpdateQueue(
            // Pass the class name, not the class object
            "add", source.constructor.name, listenerEvent, "", messageCancelTriggerEvent,
            timeout, timestamp, messageChangeId,
            messageOnSetup, messageOnTimeout,
            emitterEvent,
            emitterArgs, originalChangeUuid, persistListener
          );
        }
        source.removeAllListeners(messageCancelTriggerEvent);
        source.emit(
          "postGerritComment", originalChangeUuid, messageChangeId, undefined, messageOnSetup,
          "OWNER"
        );
      });
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
      source.once(messageCancelTriggerEvent, () => {
        logger.log(
          `Event trigger ${messageCancelTriggerEvent} received.`,
          "debug", originalChangeUuid
        );
        clearTimeout(timeoutHandle);
        source.removeAllListeners(listenerEvent);
        source.removeAllListeners(messageTriggerEvent);
        addToListenerCacheUpdateQueue(
          "delete", undefined, listenerEvent, undefined, undefined,
          undefined, undefined, undefined,
          undefined, undefined,
          undefined,
          undefined, originalChangeUuid, false
        );
      });
    }
  }

  // Listen for event only once. The listener is consumed if triggered, and
  // should also be deleted from the database.
  if (listenerEvent) {
    source.once(
      listenerEvent,
      function () {
        clearTimeout(timeoutHandle);
        source.removeAllListeners(messageTriggerEvent);
        source.removeAllListeners(messageCancelTriggerEvent);
        logger.log(`Received event for listener ${listenerEvent}`);
        setTimeout(function () {
          source.emit(emitterEvent, ...emitterArgs);
          addToListenerCacheUpdateQueue(
            "delete", undefined, listenerEvent, undefined, undefined,
            undefined, undefined, undefined,
            undefined, undefined,
            undefined,
            undefined, originalChangeUuid, false
          );
        }, 1000);
      },
      1000
    );
    logger.log(
      `Set up listener for ${listenerEvent} with remaining timeout ${newTimeout}`,
      "info", originalChangeUuid
    );
  }

  // Add this listener to the database.
  if (persistListener) {
    addToListenerCacheUpdateQueue(
      // Pass the class name, not the class object
      "add", source.constructor.name, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
      timeout, timestamp, messageChangeId,
      messageOnSetup, messageOnTimeout,
      emitterEvent,
      emitterArgs, originalChangeUuid, persistListener
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
  emitterArgs, originalChangeUuid, persistListener, callback
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
      undefined, undefined, undefined, undefined, true
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
          dataJSON[listenerEvent] =
            [
              source, listenerEvent, messageTriggerEvent, messageCancelTriggerEvent,
              timeout, timestamp, messageChangeId,
              messageOnSetup, messageOnTimeout,
              emitterEvent,
              emitterArgs, originalChangeUuid, persistListener
            ];
          break;
        case "delete":
          delete dataJSON[listenerEvent];
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
