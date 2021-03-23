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
