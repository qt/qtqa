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

exports.id = "emailClient";
const nodemailer = require("nodemailer");
const sesTransport = require("nodemailer-ses-transport");
const config = require("./config.json");

// Set defaults with config file.
let senderAddress = config.EMAIL_SENDER;

let SESCREDENTIALS = {
  accessKeyId: config.SES_ACCESS_KEY_ID,
  secretAccessKey: config.SES_SECRET_ACCESS_KEY
};

// Use environment variables if set.

if (process.env.EMAIL_SENDER)
  senderAddress = process.env.EMAIL_SENDER;

if (process.env.SES_ACCESS_KEY_ID)
  SESCREDENTIALS.accessKeyId = process.env.SES_ACCESS_KEY_ID;

if (process.env.SES_SECRET_ACCESS_KEY)
  SESCREDENTIALS.secretAccessKey = process.env.SES_SECRET_ACCESS_KEY;

exports.genericSendEmail = function(to, subject, htmlbody, textbody) {
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
  transporter.sendMail(mailOptions).catch(console.trace);
};
