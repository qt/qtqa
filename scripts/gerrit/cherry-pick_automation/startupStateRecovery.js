// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

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
