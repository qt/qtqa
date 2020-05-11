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

exports.id = "logger";

const winston = require("winston");
const { format } = winston;
const { combine } = format;

// New prototype method for string to prepend and postfix color
// escape control sequences for writing colors to the console.
String.prototype.color = function (color) {
  return `${color}${this}\x1b[0m`;
};

class logger {
  constructor() {
    this.level = process.env.LOG_LEVEL || "info";
    this.levels = {
      error: 0,
      warn: 1,
      info: 2,
      http: 3,
      verbose: 4,
      debug: 5,
      silly: 6
    };

    this.logger = winston.createLogger({
      levels: this.levels,
      level: this.level,
      format: combine(format.colorize(), format.align(), format.simple()),
      defaultMeta: { service: "user-service" },
      exitOnError: false,
      transports: [new winston.transports.Console()]
    });

    this.logger.log("info", `Log verbosity set to ${this.level.color("\x1b[38;2;241;241;0m")}`);
  }

  // Generate a unique color based on the uuid.
  getUuidColor(uuid) {
    let uuidInt = parseInt(uuid, 16);
    if (isNaN(uuidInt))
      return `\x1b[38;5;202m`;
    else
      return `\x1b[38;5;${Math.max(uuidInt % 231, 8)}m`;

  }

  // Log a message to the console. UUID, if passed, will be assigned a unique color.
  // level defaults to "info" if not set. Level may be set to numeric or string
  // RFC5424 standards:
  //   error: 0,
  //   warn: 1,
  //   info: 2,
  //   http: 3,
  //   verbose: 4,
  //   debug: 5,
  //   silly: 6
  log(message, level, uuid) {
    if (!uuid)
      uuid = "SYSTEM";
    if (!level)
      level = "info";
    let color = this.getUuidColor(uuid);
    this.logger.log(level, `${uuid.slice(0, 8).color(color)} ${message}`);
  }
}
module.exports = logger;
