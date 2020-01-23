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
const requestIp = require("request-ip");
const net = require("net");
const uuidv1 = require("uuid/v1");
const postgreSQLClient = require("./postgreSQLClient");
const toolbox = require("./toolbox");
const config = require("./config.json");

// Receive and route incoming requests
// Only pay attention to change-merged events.
// Each gerrit repo that needs use of the bot must be configured with a
// webhook that will send change-merged notifications to this bot.

// Set default values with the config file.
let webhookPort = config.WEBHOOK_PORT;
let gerritIPv4 = config.GERRIT_IPV4;
let gerritIPv6 = config.GERRIT_IPV6;
let adminEmail = config.ADMIN_EMAIL;

// Prefer environment variable if set.
if (process.env.WEBHOOK_PORT) {
  webhookPort = Number(process.env.WEBHOOK_PORT);
}
if (process.env.GERRIT_IPV4) {
  gerritIPv4 = process.env.GERRIT_IPV4;
}

if (process.env.GERRIT_IPV6) {
  gerritIPv6 = process.env.GERRIT_IPV6;
}

if (process.env.ADMIN_EMAIL) {
  adminEmail = process.env.ADMIN_EMAIL;
}

class webhookListener extends EventEmitter {
  constructor() {
    super();
  }

  receiveEvent(req, res) {
    let _this = this;
    // Filter requests to only receive from an expected gerrit instance.
    const clientIp = requestIp.getClientIp(res);
    if (net.isIPv4(clientIp) && clientIp != gerritIPv4) {
      res.sendStatus(401);
      return;
    } else if (net.isIPv6(clientIp) && clientIp != gerritIPv6) {
      res.sendStatus(401);
      return;
    } else if (!net.isIP(clientIp)) {
      console.trace(
        `FATAL: Incoming request appears to have an invalid origin IP.`
      ); // ERROR, but don't exit.
      res.sendStatus(500); // Try to send a status anyway.
      return;
    }

    res.sendStatus(200);

    if (req.type != "change-merged") {
      return;
    }

    req["uuid"] = uuidv1(); // Set a unique ID for this inbound request to make it easier to track.
    req["fullChangeID"] = `${encodeURIComponent(req.change.project)}~${
      req.change.branch
    }~${req.change.id}`;

    //Insert the new request into the database for survivability.
    const columns = [
      "uuid",
      "changeid",
      "state",
      "revision",
      "rawjson",
      "cherrypick_results_json"
    ];
    const rowdata = [
      `'${req.uuid}'`,
      `'${req.change.id}'`,
      `'new'`,
      `'${req.patchSet.revision}'`,
      `'${toolbox.encodeJSONtoBase64(req)}'`,
      `'${toolbox.encodeJSONtoBase64({})}'`
    ];
    postgreSQLClient.insert("processing_queue", columns, rowdata, function(
      changes
    ) {
      // Ready to begin processing the merged change.
      _this.emit("newRequestStored", req.uuid);
    });
  }

  // Set up a server and start listening on a given port.
  startListening() {
    let _this = this;
    let server = express();
    server.use(express.json()); // Set Express to use JSON parsing by default.

    // Create a custom error handler for Express.
    server.use(function(err, req, res, next) {
      if (err instanceof SyntaxError) {
        // Send the bad request to gerrit admins so it can either be manually processed
        // or fixed if there's a bug.
        console.log(
          "Syntax error in input. The incoming request may be broken!"
        );
        emailClient.genericSendEmail(
          adminEmail,
          "Cherry-pick bot: Error in received webhook",
          undefined, // Don't bother assembling an HTML body for this debug message.
          err.message + "\n\n" + err.body
        );
        res.sendStatus(400);
      } else {
        // This shouldn't happen as long as we're only receiving JSON formatted webhooks from gerrit.
        res.sendStatus(500);
        console.trace(err);
      }
    });

    // Set up the listening endpoint
    console.log("Starting server.");
    server.post("/gerrit-events", (req, res) =>
      _this.emit("newRequest", req.body, res)
    );
    server.listen(webhookPort);
    _this.emit(
      "serverStarted",
      `Server started listening on port ${webhookPort}`
    );
  }
}

module.exports = webhookListener;
