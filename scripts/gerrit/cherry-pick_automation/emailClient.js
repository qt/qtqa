// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "emailClient";
const nodemailer = require("nodemailer");
const sesTransport = require("nodemailer-ses-transport");

const config = require("./config.json");
const Logger = require("./logger");
const logger = new Logger();

// Set default values with the config file, but prefer environment variable.
function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

let senderAddress = envOrConfig("EMAIL_SENDER");

let SESCREDENTIALS = {
  accessKeyId: envOrConfig("SES_ACCESS_KEY_ID"),
  secretAccessKey: envOrConfig("SES_SECRET_ACCESS_KEY")
};

exports.genericSendEmail = function (to, subject, htmlbody, textbody) {
  // create reusable transporter
  let transporter = nodemailer.createTransport(sesTransport({
    accessKeyId: SESCREDENTIALS.accessKeyId,
    secretAccessKey: SESCREDENTIALS.secretAccessKey,
    rateLimit: 5
  }));

  // setup email data with unicode symbols
  let mailOptions = {
    from: senderAddress, // sender address
    to: to, // list of receivers
    subject: subject, // Subject line
    text: textbody, // plain text body
    html: htmlbody // html body
  };

  // send mail with defined transport object
  transporter.sendMail(mailOptions).catch((err) => {
    logger.log(`Error sending email: ${err}`, "error", "MAILER");
  });
};
