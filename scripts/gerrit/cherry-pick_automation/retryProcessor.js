/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

const EventEmitter = require("events");
const uuidv1 = require("uuidv1");

const postgreSQLClient = require("./postgreSQLClient");
const toolbox = require("./toolbox");

class retryProcessor extends EventEmitter {
  constructor(logger, requestProcessor) {
    super();
    this.logger = logger;
    this.requestProcessor = requestProcessor;
  }

  addRetryJob(originalUuid, retryAction, args) {
    let _this = this;
    const retryUuid = uuidv1();
    _this.logger.log(`Setting up ${retryAction}`, "warn", originalUuid);
    postgreSQLClient.insert(
      "retry_queue", ["uuid", "retryaction", "args"],
      [retryUuid, retryAction, toolbox.encodeJSONtoBase64(args)],
      function () {
        _this.logger.log(
          `Retry ${retryAction} registered for ${retryUuid}`,
          "verbose", originalUuid
        );
        // Call retry in 30 seconds.
        setTimeout(function () {
          _this.emit("processRetry", retryUuid);
        }, 30000);
      }
    );
  }

  // Process a retry item and call its original callback, which should resume
  // the process where it left off.
  processRetry(uuid, callback) {
    let _this = this;
    _this.logger.log(`Processing retry event with uuid ${uuid}`);
    function deleteRetryRecord() {
      postgreSQLClient.deleteDBEntry("retry_queue", "uuid", uuid, function (success, data) {});
    }

    postgreSQLClient.query("retry_queue", undefined, "uuid", uuid, "=", function (success, rows) {
      if (success) {
        deleteRetryRecord();
        let args = toolbox.decodeBase64toJSON(rows[0].args);
        _this.logger.log(
          `Processing retryRequest "${rows[0].retryAction}" for ${uuid} with args: ${args}`,
          "debug"
        );
        _this.requestProcessor.emit(rows[0].retryaction, ...args);
      } else if (callback) {
        _this.logger.log(
          `Error retrieving retryRequest ${uuid} from the database, ${rows}`,
          "error"
        );
        callback(false, rows);
      } else {
        // This is a silent failure and may leave orphaned jobs.
        // All calls to processRetry should pass a callback for safety.
      }
    });
  }
}

module.exports = retryProcessor;
