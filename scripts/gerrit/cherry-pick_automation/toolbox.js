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

const postgreSQLClient = require("./postgreSQLClient");

let dbSubStatusUpdateQueue = [];
let dbUpdateLockout = false;

// Parse the commit message and return a raw list of branches to pick to.
exports.findPickToBranches = function(message) {
  let matches = message.match(/^(Pick-to:(\ +\d\.\d+)+)+/gm);
  let branchSet = new Set();
  if (matches) {
    matches.forEach(function(match) {
      let parsedMatch = match.split(":");
      parsedMatch = parsedMatch[1].split(" ");
      parsedMatch.forEach(function(submatch) {
        if (submatch)
          branchSet.add(submatch);
      });
    });
  }
  return branchSet;
};

exports.retrieveRequestJSONFromDB = retrieveRequestJSONFromDB;
function retrieveRequestJSONFromDB(uuid, callback) {
  postgreSQLClient.query("processing_queue", "rawjson", "uuid", uuid, function(success, row) {
    // If the query is successful, the row will be returned.
    // If it fails for any reason, the error is returned in its place.
    callback(success, success ? decodeBase64toJSON(row.rawjson) : row);
  });
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
  postgreSQLClient.update(
    "processing_queue", "uuid", uuid,
    { state: newState }, callback
  );
}

// Set the count of picks remaining on the inbound request.
// This count determines when we've done all the work we need
// to do on an incoming request. When it reaches 0, move it to
// the finished_requests database.
exports.setPickCountRemaining = setPickCountRemaining;
function setPickCountRemaining(uuid, count, callback) {
  postgreSQLClient.update(
    "processing_queue", "uuid", uuid,
    { pick_count_remaining: count }, callback
  );
}

// decrement the remaining count of cherrypicks on an inbound request by 1.
exports.decrementPickCountRemaining = decrementPickCountRemaining;
function decrementPickCountRemaining(uuid, callback) {
  postgreSQLClient.decrement(
    "processing_queue", uuid, "pick_count_remaining",
    function(success, data) {
      if (callback)
        callback(success, data);
      if (data.pick_count_remaining == 0) {
        setDBState(uuid, "complete", function() {
          moveFinishedRequest("processing_queue", "uuid", uuid);
        });
      }
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
  if (parentUuid && branchData && newState)
    dbSubStatusUpdateQueue.push([parentUuid, branchData, newState, callback]);

  // setDBSubState() calls postgreSQLClient.update(). As part of that process,
  // this queue function is called again with unlock = true, with no other
  // parameters. This runs a check for remaining items in the queue and pops
  // and processes the next item until the queue is emptied. When the last
  // item has been processed and addToCherryPickStateUpdateQueue() is called
  // with unlock, the queue length will be 0 and the lockout will be removed.
  if (!dbUpdateLockout || unlock) {
    dbUpdateLockout = true;
    if (dbSubStatusUpdateQueue.length > 0) {
      let args = dbSubStatusUpdateQueue.shift();
      setDBSubState.apply(this, args);
    } else {
      dbUpdateLockout = false;
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
  return Buffer.from(JSON.stringify(json)).toString("base64");
}

// Execute an update statement for cherrypick branch statuses.
// The update action *must* be semaphored since data about cherry pick
// branches for a given change is kept in a JSON blob within a single
// cell on a given row for an origin revision.
// Use the addToCherryPickStateUpdateQueue() function to queue updates.
function setDBSubState(uuid, branchdata, state, callback) {
  postgreSQLClient.query(
    "processing_queue", "cherrypick_results_json", "uuid", uuid,
    function(success, data) {
      if (success) {
        let newdata = decodeBase64toJSON(data.cherrypick_results_json);
        if (newdata[branchdata.branch] == undefined) {
          newdata[branchdata.branch] = { state: state, targetParentRevision: branchdata.revision };
        } else {
        // Overwrite the target branch object with any new updates.
          for (let [key, value] of Object.entries(branchdata)) {
            if (key != "branch")
              newdata[branchdata.branch][key] = value;
          }
          newdata[branchdata.branch]["state"] = state; // obsolete
        }
        newdata = encodeJSONtoBase64(newdata);
        postgreSQLClient.update(
          "processing_queue", "uuid", uuid, { cherrypick_results_json: newdata }, callback,
          // Call the queue function again when the database update
          // finishes to check for further updates to process.
          addToCherryPickStateUpdateQueue
        );
      } else {
        console.trace(`ERROR: Failed to update sub-state branch ${
          branchdata.branch} on revision key ${branchdata.revision}. Raw error: ${data}`);
      }
    }
  );
}

exports.moveFinishedRequest = moveFinishedRequest;
function moveFinishedRequest(fromTable, keyName, keyValue) {
  postgreSQLClient.move(fromTable, "finished_requests", keyName, keyValue, function(success, row) {
    // TODO: Add error handling? This operation is probably fine blind, and
    // no known race conditions could call this on an invalid uuid.
  });
}
