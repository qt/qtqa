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

exports.id = "check_bot_config";

const axios = require("axios");
const rateLimit = require("axios-rate-limit");

const http = rateLimit(axios.create(), { maxRPS: 5 })

const config = require("../../config");
const Logger = require("../../logger");
const logger = new Logger();

function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

let gerritURL = envOrConfig("GERRIT_URL");
let gerritPort = envOrConfig("GERRIT_PORT");
let gerritAuth = {
  username: envOrConfig("GERRIT_USER"),
  password: envOrConfig("GERRIT_PASS")
};

let gerritResolvedURL = /^(http)s?:\/\//g.test(gerritURL)
  ? gerritURL
  : `${gerritPort == 80 ? "http" : "https"}://${gerritURL}`;
gerritResolvedURL += gerritPort != 80 && gerritPort != 443 ? ":" + gerritPort : "";

let searchPattern = "qt-extensions/"

http({
  method: "get",
  url: `${gerritResolvedURL}/a/projects/?m=${searchPattern}&n=999`,
  auth: gerritAuth
})
  .then(function (response) {
    let parsedResponse = JSON.parse(response.data.slice(4));
    Object.keys(parsedResponse).forEach(function (repo) {
      logger.log(repo);
      http({
        method: "get",
        url: `${gerritResolvedURL}/a/projects/${encodeURIComponent(repo)}/branches/`,
        auth: gerritAuth
      })
        .then(function (response) {
          let parsedResponse = JSON.parse(response.data.slice(4));
          logger.log(`Checking branches on ${repo}`);
          let foundDev;
          parsedResponse.forEach(function (branch) {
            if (branch.ref.includes("/dev") || branch.ref.includes("/master"))
              foundDev = branch.ref;
          });
          if (!foundDev)
            logger.log(`${repo} does not contain a masterlike branch.`, "warn");
          else
            logger.log(`found masterlike branch on ${repo}: ${foundDev}`);
        })
        .catch(function (error) {
          logger.log(error);
        })

    })
  })
  .catch(function (error) {
    logger.log(error);
  })
