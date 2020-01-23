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
        if (submatch) {
          branchSet.add(submatch);
        }
      });
    });
  }
  return branchSet;
};

// Add a status update for an inbound request's cherry-pick job to the queue.
// This needs to be under a lockout since individual cherrypicks are part of
// a larger base64 encoded blob under the parent inbound request.
exports.queueCherryPickStateUpdate = queueCherryPickStateUpdate;
function queueCherryPickStateUpdate(
  parentUuid,
  branchData,
  newState,
  callback,
  unlock = false
) {
  if (parentUuid && branchData && newState) {
    dbSubStatusUpdateQueue.push([parentUuid, branchData, newState, callback]);
  }
  if (!dbUpdateLockout || unlock) {
    dbUpdateLockout = true;
    if (dbSubStatusUpdateQueue.length > 0) {
      args = dbSubStatusUpdateQueue.shift();
      setDBSubState.apply(this, args);
    } else {
      dbUpdateLockout = false;
    }
  }
}

//Helper methods for encoding and decoding JSON objects for storage in a database.
exports.decodeBase64toJSON = decodeBase64toJSON;
function decodeBase64toJSON(base64string) {
  return JSON.parse(Buffer.from(base64string, "base64").toString("utf8"));
}

exports.encodeJSONtoBase64 = encodeJSONtoBase64;
function encodeJSONtoBase64(json) {
  return Buffer.from(JSON.stringify(json)).toString("base64");
}
