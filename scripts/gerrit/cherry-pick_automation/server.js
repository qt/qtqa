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

const express = require("express");
const EventEmitter = require("events");
const net = require("net");
const uuidv1 = require("uuidv1");
const portfinder = require("portfinder");

const postgreSQLClient = require("./postgreSQLClient");
const emailClient = require("./emailClient");
const toolbox = require("./toolbox");
const config = require("./config.json");

// Receive and route incoming requests
// Only pay attention to change-merged events.
// Each gerrit repo that needs use of the bot must be configured with a
// webhook that will send change-merged notifications to this bot.

// Set default values with the config file, but prefer environment variable.
function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

let webhookPort = envOrConfig("WEBHOOK_PORT");
let gerritIPv4 = envOrConfig("GERRIT_IPV4");
let gerritIPv6 = envOrConfig("GERRIT_IPV6");
let adminEmail = envOrConfig("ADMIN_EMAIL");

// Override webhookPort with the PORT environment variable if it's set
// This is required by Heroku instances, as the app MUST bind to the
// port set in the PORT environment variable.
if (process.env.PORT)
  webhookPort = Number(process.env.PORT);

class webhookListener extends EventEmitter {
  constructor(logger, requestProcessor) {
    super();
    this.logger = logger;
    this.requestProcessor = requestProcessor;

    /* Holds objects describing events which should be emitted by
    receiveEvent.
    Schema:
    "<gerrit-event-type>": {
        "<unique-name>": someFunction(),
      }
    */
    this.customEvents = {};
  }

  registerCustomEvent(name, eventType, action) {
    let _this = this;
    if (!_this.customEvents[eventType])
      _this.customEvents[eventType] = {};
    _this.customEvents[eventType][name] = action;
  }

  receiveEvent(req) {
    let _this = this;

    // Set a unique ID and the full change ID for all inbound requests.
    req["uuid"] = uuidv1(); // used for tracking and database access.
    if (req.change) {
      req["fullChangeID"] =
        `${encodeURIComponent(req.change.project)}~${encodeURIComponent(req.change.branch)}~${
          req.change.id}`;
      _this.logger.log(`Event ${req.type} received on ${req.fullChangeID}`, "verbose");
    }

    if (req.type == "change-merged") {
      // Insert the new request into the database for survivability.
      const columns = [
        "uuid", "changeid", "state", "revision", "rawjson", "cherrypick_results_json"
      ];
      const rowdata = [
        req.uuid, req.change.id, "new", req.patchSet.revision,
        toolbox.encodeJSONtoBase64(req), toolbox.encodeJSONtoBase64({})
      ];
      postgreSQLClient.insert("processing_queue", columns, rowdata, function (changes) {
        // Emit a signal for this merge in case anything is waiting on it.
        _this.requestProcessor.emit(`merge_${req.fullChangeID}`);
        // Ready to begin processing the merged change.
        _this.emit("newRequestStored", req.uuid);
      });
    } else if (req.type == "change-abandoned") {
      // Emit a signal that the change was abandoned in case anything is
      // waiting on it. We don't need to do any direct processing on
      // abandoned changes.
      _this.requestProcessor.emit(`abandon_${req.fullChangeID}`);
    } else if (req.type == "patchset-created") {
      // Treat all new changes as "cherryPickCreated"
      // since gerrit doesn't send a separate notification for actual
      // cherry-picks. This should be harmless since we will only
      // ever be listening for this signal on change ID's that should
      // be the direct result of a cherry-pick.
      if (req.patchSet.number == 1)
        _this.requestProcessor.emit(`cherryPickCreated_${req.fullChangeID}`);
    } else if (req.type == "change-staged") {
      // Emit a signal that the change was staged in case anything is
      // waiting on it.
      _this.requestProcessor.emit(`staged_${req.fullChangeID}`);
    } else if (req.type == "change-unstaged") {
      // Emit a signal that the change was staged in case anything is
      // waiting on it.
      _this.requestProcessor.emit(`unstaged_${req.fullChangeID}`);
    } else if (req.type == "change-integration-pass") {
      _this.requestProcessor.emit(`integrationPass_${req.fullChangeID}`);
    } else if (req.type == "change-integration-fail") {
      _this.requestProcessor.emit(`integrationFail_${req.fullChangeID}`);
    }
    if (_this.customEvents[req.type]) {
      Object.keys(_this.customEvents[req.type]).forEach((name) => {
        _this.customEvents[req.type][name](req);
      });
    }
  }

  send_status(req, res) {
    let self_base_url;
    if (envOrConfig("HEROKU_APP_NAME"))
        self_base_url = `https://${envOrConfig("HEROKU_APP_NAME")}.herokuapp.com`;
    else
        // Fall back to localhost, as HEROKU_APP_NAME is only set in a production heroku instance.
        self_base_url = `http://localhost:${Number(process.env.PORT) || envOrConfig("WEBHOOK_PORT")}`;

    let status = {
      url: self_base_url,
      time: Date.now(),
      status: "OK"
    }

    res.send(status);
  }

  // Set up a server and start listening on a given port.
  startListening() {
    let _this = this;
    let server = express();
    server.use(express.json()); // Set Express to use JSON parsing by default.
    server.enable("trust proxy", true);

    // Create a custom error handler for Express.
    server.use(function (err, req, res, next) {
      if (err instanceof SyntaxError) {
        // Send the bad request to gerrit admins so it can either be manually processed
        // or fixed if there's a bug.
        _this.logger.log("Syntax error in input. The incoming request may be broken!", "error");
        emailClient.genericSendEmail(
          adminEmail, "Cherry-pick bot: Error in received webhook",
          undefined, // Don't bother assembling an HTML body for this debug message.
          err.message + "\n\n" + err.body
        );
        res.sendStatus(400);
      } else {
        // This shouldn't happen as long as we're only receiving JSON formatted webhooks from gerrit
        res.sendStatus(500);
        _this.logger.log(err, "error");
      }
    });

    function validateOrigin(req, res) {
      if (process.env.IGNORE_IP_VALIDATE) {
        res.sendStatus(200);
        return true;
      }
      // Filter requests to only receive from an expected gerrit instance.
      let clientIp = req.headers["x-forwarded-for"] || req.connection.remoteAddress;
      let validOrigin = false;
      if (net.isIPv4(clientIp) && clientIp != gerritIPv4) {
        res.sendStatus(401);
      } else if (net.isIPv6(clientIp) && clientIp != gerritIPv6) {
        res.sendStatus(401);
      } else if (!net.isIP(clientIp)) {
        // ERROR, but don't exit.
        _this.logger.log(
          `FATAL: Incoming request appears to have an invalid origin IP: ${clientIp}`,
          "warn"
        );
        res.sendStatus(500); // Try to send a status anyway.
      } else {
        res.sendStatus(200);
        validOrigin = true;
      }
      return validOrigin;
    }

    // Set up the listening endpoint
    _this.logger.log("Starting server.");
    server.post("/gerrit-events", (req, res) => {
      if (validateOrigin(req, res))
        _this.emit("newRequest", req.body);
    });
    server.get("/status", (req, res) => _this.send_status(req, res));
    server.get("/", (req, res) => res.send("Nothing to see here."));
    portfinder
      .getPortPromise()
      .then((port) => {
        // `port` is guaranteed to be a free port in this scope.
        server.listen(webhookPort);
        _this.emit("serverStarted", `Server started listening on port ${webhookPort}`);
      })
      .catch((err) => {
        // Could not get a free port, `err` contains the reason.
        _this.logger.log(err, "error");
        process.exit();
      });
  }
}

module.exports = webhookListener;
