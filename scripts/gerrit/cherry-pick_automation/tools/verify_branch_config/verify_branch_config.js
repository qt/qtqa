// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

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
