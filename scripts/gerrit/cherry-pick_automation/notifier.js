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

exports.id = "notifier";
const Server = require("./server");
const server = new Server();
const RequestProcessor = require("./requestProcessor");
const requestProcessor = new RequestProcessor();
const RetryProcessor = require("./retryProcessor");
const retryProcessor = new RetryProcessor(requestProcessor);
requestProcessor.retryProcessor = retryProcessor;
const postgreSQLClient = require("./postgreSQLClient");
const onExit = require("node-cleanup");

// release resources here before node exits
onExit(function(exitCode, signal) {
  console.log("Cleaning up...");
  postgreSQLClient.end();
  console.log("Exiting");
});

// Notifier handles all event requests from worker modules.
// A worker module should avoid a function from itself or another
// module directly where possible. Instead, it should always send an
// event to Notifier, which will route the event. The exception to this
// rule is where a synchronous operation with callback is required. In
// this case, the function performing the direct call should be responsible
// for emitting a signal to Notifier when its operation is complete.

// Emitted when the HTTP Listener is up and running and we're actively listening
// for incoming POST events to /gerrit-events
server.on("serverStarted", info => {
  if (info) {
    console.log(info);
  }
});

// Emitted by server when a new incoming request is received by the listener.
server.on("newRequest", (reqBody, res) => {
  server.receiveEvent(reqBody, res);
});

// Emitted by the server when the incoming request has been written to the database.
server.on("newRequestStored", uuid => {
  requestProcessor.processMerge(uuid);
});

// Emitted when a change-merged event found pick-to branches in the commit message.
requestProcessor.on("validateBranch", (parentJSON, branch) => {
  requestProcessor.validateBranch(parentJSON, branch);
});

// Emitted when a branch has been validated against the merge's project in codereview.
requestProcessor.on(
  "validBranchReadyForPick",
  (parentJSON, branch, newParentRev) => {
    requestProcessor.doCherryPick(parentJSON, branch, newParentRev);
  }
);

// Emitted when a new cherry pick has been generated on codereview.
requestProcessor.on("newCherryPick", (parentJSON, cherryPickJSON) => {
  requestProcessor.processNewCherryPick(parentJSON, cherryPickJSON);
});

// Emitted when a cherry pick has been validated and has no merge conflicts.
requestProcessor.on("cherryPickDone", (parentJSON, cherryPickJSON) => {
  requestProcessor.autoApproveCherryPick(parentJSON, cherryPickJSON);
});

// Emitted when a cherry pick is approved and ready for automatic staging.
requestProcessor.on("cherrypickReadyForStage", (parentJSON, cherryPickJSON) => {
  requestProcessor.stageCherryPick(parentJSON, cherryPickJSON);
});

// Emitted when a comment is requested to be posted to codereview.
// requestProcessor.gerritCommentHandler handles failure cases and posts
// this event again for retry. This design is such that the gerritCommentHandler
// or this event can be fired without caring about the result.
requestProcessor.on(
  "postGerritComment",
  (fullChangeID, revision, message, notifyScope) => {
    requestProcessor.gerritCommentHandler(
      fullChangeID,
      revision,
      message,
      notifyScope
    );
  }
);

// Emitted when a job fails to complete for a non-fatal reason such as network
// disruption. The job is then stored in the database and rescheduled.
requestProcessor.on("addRetryJob", (action, args) => {
  retryProcessor.addRetryJob(action, args);
});

// Emitted when a retry job should be processed again.
retryProcessor.on("processRetry", uuid => {
  console.log(`Retrying retry job: ${uuid}`);
  retryProcessor.processRetry(uuid, function(success, data) {
    // This callback should only be called if the database threw
    // an error. This should not happen, so just log the failure.
    console.log(
      `A database error occurred when trying to process a retry for ${uuid}: ${data}`
    );
  });
});

// Start the server and begin listening for incoming webhooks.w
server.startListening();
