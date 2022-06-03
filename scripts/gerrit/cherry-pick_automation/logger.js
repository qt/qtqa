// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

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
