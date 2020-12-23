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

const path = require('path');
const onExit = require("node-cleanup");
let autoload = require("auto-load")
let fs = require('fs');

const Logger = require("./logger");
const logger = new Logger();
exports.logger = logger;
logger.log("Logger started...");
const Server = require("./server");
const server = new Server(logger);
exports.server = server;
const RequestProcessor = require("./requestProcessor");
const requestProcessor = new RequestProcessor(logger);
exports.requestProcessor = requestProcessor;
server.requestProcessor = requestProcessor;
const RetryProcessor = require("./retryProcessor");
const retryProcessor = new RetryProcessor(logger, requestProcessor);
exports.retryProcessor = retryProcessor;
requestProcessor.retryProcessor = retryProcessor;
const SingleRequestManager = require("./singleRequestManager");
const singleRequestManager = new SingleRequestManager(logger, retryProcessor, requestProcessor);
const RelationChainManager = require("./relationChainManager");
const relationChainManager = new RelationChainManager(logger, retryProcessor, requestProcessor);
const StartupStateRecovery = require("./startupStateRecovery");
const startupStateRecovery = new StartupStateRecovery(logger, requestProcessor);
const postgreSQLClient = require("./postgreSQLClient");

exports.registerCustomListener = registerCustomListener;

function envOrConfig(ID, configFile) {
  if (process.env[ID]) {
    return process.env[ID];
  } else if (configFile) {
    const config = require(configFile);
    return config[ID];
  }
}

// release resources here before node exits
onExit(function (exitCode, signal) {
  if (signal) {
    logger.log("Cleaning up...");
    postgreSQLClient.end(() => {
      logger.log("Exiting");
      process.exit(0);
    });
    onExit.uninstall(); // don't call cleanup handler again
    return false;
  }
});

// Create user bots which can tie into the rest of the system.
// Bots should accept this instance of Notifier as the only
// constructor parameter.
// Bot configuration should set an environment variable of the same
// name as the bot, upper cased and suffixed with _ENABLED.
// If this variable is set in neither the environment or in the
// config file, the plugin will not be loaded.
if (!fs.existsSync('plugin_bots'))
  fs.mkdirSync('plugin_bots');
let plugin_bots = autoload('plugin_bots');
let initialized_bots = {};
Object.keys(plugin_bots).forEach((bot) => {
  if (
    envOrConfig(`${bot.toUpperCase()}_ENABLED`, path.resolve("plugin_bots", bot, "config.json"))
  ) {
    initialized_bots[bot] = new plugin_bots[bot][bot](this);
    logger.log(`plugin "${bot}" loaded`);
  } else {
    logger.log(`${bot} is disabled in config. Skipping...`);
  }
});

// Plugin bots can use this function to register a custom listener to
// route events from one module to itself. For example, to set up
// a listener for server to emit an event "integrationFail"
function registerCustomListener(source, event, destination) {
  source.on(event, function () {
    destination(...arguments)
  });
}

// Notifier handles all event requests from worker modules.
// A worker module should avoid calling a function from itself or another
// module directly where possible. Instead, it should always send an
// event to Notifier, which will route the event. The exception to this
// rule is where a synchronous operation with callback is required. In
// this case, the function performing the direct call should be responsible
// for emitting a signal to Notifier when its operation is complete.

// Emitted when the HTTP Listener is up and running and we're actively listening
// for incoming POST events to /gerrit-events
server.on("serverStarted", (info) => {
  if (info)
    console.log(info);
});

// Emitted by server when a new incoming request is received by the listener.
server.on("newRequest", (reqBody) => {
  server.receiveEvent(reqBody);
});

// Emitted by the server when the incoming request has been written to the database.
server.on("newRequestStored", (uuid) => {
  requestProcessor.processMerge(uuid);
});

// Emitted by startupStateRecovery if an in-process item stored had no
// cherry-picks created yet.
startupStateRecovery.on("recoverFromStart", (uuid) => {
  requestProcessor.processMerge(uuid);
});

// Emitted when an incoming change has been found to have a pick-to header with
// at least one branch. Before continuing, determine if the change is part of
// a relation chain and process it accordingly.
requestProcessor.on("determineProcessingPath", (parentJSON, branches) => {
  requestProcessor.determineProcessingPath(parentJSON, branches);
});

// Emitted when a merged change is part of a relation chain.
requestProcessor.on("processAsSingleChange", (parentJSON, branches) => {
  singleRequestManager.start(parentJSON, branches);
});

// Emitted when a merged change is part of a relation chain.
requestProcessor.on("processAsRelatedChange", (parentJSON, branches) => {
  relationChainManager.start(parentJSON, branches);
});

// Emitted when a change-merged event found pick-to branches in the commit message.
requestProcessor.on("validateBranch", (parentJSON, branch, responseSignal) => {
  requestProcessor.validateBranch(parentJSON, branch, responseSignal);
});

// Emitted when a branch needs to be checked against private lts branches.
requestProcessor.on("checkLtsTarget", (currentJSON, branch, newParentRev, responseSignal) => {
  requestProcessor.checkLtsTarget(currentJSON, branch, newParentRev, responseSignal);
});

// Emitted when a cherry pick is dependent on another cherry pick.
requestProcessor.on("verifyParentPickExists", (parentJSON, branch, responseSignal, errorSignal, isRetry) => {
  requestProcessor.verifyParentPickExists(parentJSON, branch, responseSignal, errorSignal, isRetry);
});

// Emitted when a cherry-pick's parent is not a suitable target on the pick-to branch.
requestProcessor.on("locateNearestParent", (currentJSON, next, branch, responseSignal) =>
  requestProcessor.locateNearestParent(currentJSON, next, branch, responseSignal));

// Emitted when a branch has been validated against the merge's project in codereview.
requestProcessor.on(
  "validBranchReadyForPick",
  (parentJSON, branch, newParentRev, responseSignal) => {
    requestProcessor.doCherryPick(parentJSON, branch, newParentRev, responseSignal);
  }
);

// Emitted when a new cherry pick has been generated on codereview.
requestProcessor.on("newCherryPick", (parentJSON, cherryPickJSON, responseSignal) => {
  requestProcessor.processNewCherryPick(parentJSON, cherryPickJSON, responseSignal);
});

// Emitted when a cherry pick has been validated and has no conflicts.
requestProcessor.on("cherryPickDone", (parentJSON, cherryPickJSON, responseSignal) => {
  requestProcessor.autoApproveCherryPick(parentJSON, cherryPickJSON, responseSignal);
});

// Emitted when a cherry pick needs to stage against a specific parent change.
requestProcessor.on(
  "stageEligibilityCheck",
  (originalRequestJSON, cherryPickJSON, responseSignal, errorSignal) => {
    requestProcessor.stagingReadyCheck(
      originalRequestJSON, cherryPickJSON,
      responseSignal, errorSignal
    );
  }
);

// Emitted when a cherry pick is approved and ready for automatic staging.
requestProcessor.on("cherrypickReadyForStage", (parentJSON, cherryPickJSON, responseSignal) => {
  requestProcessor.stageCherryPick(parentJSON, cherryPickJSON, responseSignal);
});

// Emitted when a comment is requested to be posted to codereview.
// requestProcessor.gerritCommentHandler handles failure cases and posts
// this event again for retry. This design is such that the gerritCommentHandler
// or this event can be fired without caring about the result.
requestProcessor.on(
  "postGerritComment",
  (parentUuid, fullChangeID, revision, message, notifyScope, customGerritAuth) => {
    requestProcessor.gerritCommentHandler(
      parentUuid, fullChangeID, revision,
      message, notifyScope, customGerritAuth
    );
  }
);

// Emitted when a job fails to complete for a non-fatal reason such as network
// disruption. The job is then stored in the database and rescheduled.
requestProcessor.on("addRetryJob", (originalUuid, action, args) => {
  retryProcessor.addRetryJob(originalUuid, action, args);
});

// Emitted when a retry job should be processed again.
retryProcessor.on("processRetry", (uuid) => {
  logger.log(`Retrying retry job: ${uuid}`, "warn");
  retryProcessor.processRetry(uuid, function (success, data) {
    // This callback should only be called if the database threw
    // an error. This should not happen, so just log the failure.
    logger.log(
      `A database error occurred when trying to process a retry for ${uuid}: ${data}`,
      "warn"
    );
  });
});

// Restore any open event listeners, followed by any items that
// weren't complete before the last app shutdown.
startupStateRecovery.restoreActionListeners();
startupStateRecovery.on("RestoreListenersDone", () => {
  logger.log("Finished restoring listeners from the database.");
  startupStateRecovery.restoreProcessingItems();
});

startupStateRecovery.on("restoreProcessingDone", () => {
  logger.log("Finished restoring in-process items from the database.");
});

// Start the server and begin listening for incoming webhooks.w
server.startListening();
