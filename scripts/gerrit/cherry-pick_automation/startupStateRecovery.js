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

const EventEmitter = require("events");
const safeJsonStringify = require("safe-json-stringify");

const toolbox = require("./toolbox");

class startupStateRecovery extends EventEmitter {
  constructor(logger, requestProcessor) {
    super();
    this.logger = logger;
    this.requestProcessor = requestProcessor;
  }

  // Recover all currently processing items and re-emit the last signal
  // This will restore the process to the same step it was last on when
  // the server shutdown.
  restoreProcessingItems() {
    let _this = this;

    _this.logger.log("Restoring in-process items from the database.");
    toolbox.getAllProcessingRequests((success, data) => {
      if (success) {
        let itemsRemaining = data.length;
        _this.logger.log(`found ${itemsRemaining} in-process items to restore...`);
        if (itemsRemaining == 0)
          _this.emit("restoreProcessingDone");

        data.forEach((element) => {
          _this.logger.log(`restoring uuid ${element.uuid}`, "info", element.uuid);
          let cherrypicks = toolbox.decodeBase64toJSON(element.cherrypick_results_json);
          if (Object.keys(cherrypicks).length > 0) {
            let cherrypickCount = 0;
            for (var branch in cherrypicks) {
              if (Object.prototype.hasOwnProperty.call(cherrypicks, branch)) {
                // Emitting the event returns 1 if anything's listening
                // otherwise, 0.
                _this.logger.log(
                  `Emitting in-processing item recovery: ${cherrypicks[branch].state} with args: ${
                    safeJsonStringify(cherrypicks[branch].args)}`,
                  "debug", element.uuid
                );
                cherrypickCount += _this.requestProcessor.emit(
                  cherrypicks[branch].state,
                  ...cherrypicks[branch].args || []
                );
              }
            }
            // If none of the signals we sent were listened to, make sure
            // the item is marked as "complete" so it doesn't stay stuck.
            if (cherrypickCount == 0) {
              _this.logger.log(
                `This in-process item had nothing to restore! Moving it to 'complete' state.`,
                "verbose", element.uuid
              );
              toolbox.decrementPickCountRemaining(element.uuid);
            }
          } else {
            _this.logger.log(
              "This in-process item is being recovered as though it's a new item.",
              "verbose", element.uuid
            );
            _this.emit("recoverFromStart", element.uuid);
          }
          --itemsRemaining;
          if (itemsRemaining == 0)
            _this.emit("restoreProcessingDone");

        });
      } else {
        _this.logger.log(
          `failed to restore processing items from the database! Database error: ${data}`,
          "error"
        );
        _this.emit("restoreProcessingDone");
      }
    });
  }

  restoreActionListeners() {
    let _this = this;
    toolbox.getCachedListeners((success, data) => {
      if (success) {
        let itemsRemaining = data.length;
        _this.logger.log(`found ${itemsRemaining} items with listeners to restore...`);
        if (itemsRemaining == 0)
          _this.emit("RestoreListenersDone");

        data.forEach((element) => {
          let jsonData = toolbox.decodeBase64toJSON(element.listener_cache);
          if (Object.keys(jsonData).length > 0) {
            for (var listenerData in jsonData) {
              _this.logger.log(
                `restoring listener ${listenerData}`,
                "info", jsonData[listenerData][11]
              );
              _this.logger.log(
                `Listener being restored with args: ${safeJsonStringify(jsonData[listenerData])}`,
                "debug", jsonData[listenerData][11]
              );
              // requestProcessor is the only type that should be setting up,
              // listeners, but this 'if' below allows for expansion.
              if (jsonData[listenerData][0] == "requestProcessor")
                jsonData[listenerData][0] = _this.requestProcessor;
              // set up the listener with a flag that denotes that it was restored.
              // This suppresses the initial gerrit comments.
              jsonData[listenerData].push(true);
              toolbox.setupListener.apply(this, jsonData[listenerData]);
            }
          }
          --itemsRemaining;
          if (itemsRemaining == 0)
            _this.emit("RestoreListenersDone");

        });
      } else {
        _this.logger.log(
          `failed to restore listeners from the database! Database error: ${data}`,
          "error"
        );
        _this.emit("RestoreListenersDone");
      }
    });
  }
}

module.exports = startupStateRecovery;
