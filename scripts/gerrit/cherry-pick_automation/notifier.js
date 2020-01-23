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
const onExit = require("node-cleanup");

// release resources here before node exits
onExit(function(exitCode, signal) {
  console.log("Cleaning up...");
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
});
// Start the server and begin listening for incoming webhooks.w
server.startListening();
