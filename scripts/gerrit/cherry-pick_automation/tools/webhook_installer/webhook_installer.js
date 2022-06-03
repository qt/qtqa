// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "webhookinstaller";
// This script configures webhooks for the Qt Cherry-pick bot in
// gerrit repos. Note that additional manual configuration is
// required to enable Sanity-bot in repos where cherry-picking
// should be enabled.

const axios = require("axios");
const proc = require("child_process");
const config = require("../../config");
const Logger = require("../../logger");
const logger = new Logger();

let repos = [""]

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

repos.forEach((repo, index) => {
  let baseUrl = `${gerritResolvedURL}/a/changes/`;
  axios({
    method: "post", url: baseUrl,
    data: {
      "project" : `${repo}`, "subject" : `Configure webhooks for Qt Cherry-pick bot`,
      "branch" : "refs/meta/config", "status" : "NEW"
    },
    auth: gerritAuth
  })
    .then(function (response) {
      let parsedResponse = JSON.parse(response.data.slice(4));
      let changeID = parsedResponse.change_id;
      logger.log(`success creating change on ${repo} with change ID ${changeID}`);

      proc.exec(
        `curl --location --request PUT "${baseUrl}${
          changeID}/edit/webhooks.config" --header "Authorization: Basic ${
          Buffer.from(gerritAuth.username + ":" + gerritAuth.password).toString('base64')
        }" --header "Content-Type: application/octet-stream" --data-binary "@./webhooks.config"`,
        (error, stdout, stderr) => {
          logger.log(`${stderr} - ${stdout}`)
          axios({ method: "post", url: `${baseUrl}${changeID}/edit:publish`, auth: gerritAuth })
            .then(function (response) {
              logger.log(`Success posting edit to ${repo}`);
              axios({
                method: "post", url: `${baseUrl}${changeID}/revisions/current/review`, auth: gerritAuth,
                data: {
                  "message": "Auto-approving",
                  "labels": { "Code-Review": 2, "Sanity-Review": 1 }
                }
              })
                .then(function (response) {
                  logger.log(`Success setting review on ${repo}`);
                  if (! process.argv.some((e) => e == "nosubmit")) {
                    axios({ method: "post", url: `${baseUrl}${changeID}/submit`, auth: gerritAuth })
                      .then(function (response) {
                        logger.log(`Success submitting on ${repo}`);
                      })
                      .catch(function (error) {
                        logger.log(`Failed to submit on ${repo} ${changeID}\n ${error.message}`, "error");
                      });
                  }
                })
                .catch(function (error) {
                  logger.log(`Failed to set review on ${repo} ${changeID}\n ${error.message}`, "error");
                });
            })
            .catch(function (error) {
              logger.log(`Failed to publish edit on ${repo} ${changeID}\n ${error.message}`, "error");
            });
        }
      )
    })
    .catch(function (error) {
      logger.log(`Failed to create webhook config change on ${repo}\n${baseUrl}\n${error.message}`, "error");
    })
})
