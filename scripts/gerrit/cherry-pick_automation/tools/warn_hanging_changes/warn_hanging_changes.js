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

exports.id = "warn_hanging_changes";

const axios = require("axios");
const rateLimit = require("axios-rate-limit");

const http = rateLimit(axios.create(), { maxRPS: 5 })

const config = require("../../config");
const gerritRestTools = require("../../gerritRestTools");
const Logger = require("../../logger");
const logger = new Logger();

let repos = [""]

function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

function sleep(milliseconds) {
  const date = Date.now();
  let currentDate = null;
  do
    currentDate = Date.now();
  while (currentDate - date < milliseconds);
}

let commentPosterAccountId = 1007413
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

let url = `${gerritResolvedURL}/a/changes`;

repos.forEach((repo, index) => {
  http({
    method: "get",
    url: `${url}/?q=status:open+project:${encodeURIComponent(repo)}+-branch:dev&n=999`,
    auth: gerritAuth
  })
    .then(function (response) {
      let parsedResponse = JSON.parse(response.data.slice(4));
      parsedResponse.forEach(function (change, index) {
        if (!change.branch)
          change.branch = change.id.match(/(\d\.\d+(?:\.\d)?)/)[1];

        if (!change.repo)
          change.repo = change.id.match(/qt%2F(\w+(?:\-\w+)?)/)[1];

        if (!change.change_id)
          change.change_id = change.id.match(/~.+~(.+)/)[1];

        if (/\d.\d+.+/.test(change.branch)) {
          logger.log(JSON.stringify(change));
          sleep(300);
          gerritRestTools.queryChange(undefined, change.id, function (success, data) {
            if (!data.current_revision) {
              logger.log(`${JSON.stringify(data, undefined, 4)} ${change.id}`, "error");
              return;
            }
            let commitMsg = data.revisions[data.current_revision].commit.message;
            let codereview = data.labels["Code-Review"].all;
            let cherrypickbotreview = codereview.find((o) => o._account_id === commentPosterAccountId);
            if (!/\(((?:partial(?:ly)? )?(?:cherry[- ]pick|(?:back-?)?port|adapt)(?:ed)?(?: from| of)?(?: commit)?)/.test(commitMsg)) {
              gerritRestTools.queryChange(undefined, `${encodeURIComponent(change.project)}~dev~${
                change.change_id}`, (success, data) => {
                if (!success) {
                  http({
                    method: "post",
                    url: `${url}/${change.id}/revisions/current/review`,
                    auth: gerritAuth,
                    data: {
                      "message": !cherrypickbotreview ? "This repo has moved to cherry-pick mode. As such, this change will no longer be merged up to dev.\n\nIf this change still applies, please move it to dev (you can do this in the Codereview UI) and add a Pick-to: footer in the commit message with target branches where this change should be cherry-picked to.\n\n See: https://wiki.qt.io/Branch_Guidelines#How_to_cherry-pick" : "",
                      "labels": {
                        "Code-Review": -1
                      },
                      "notify": "OWNER"
                    }
                  })
                    .then(function (response) {
                      logger.log(`Success posting ${!cherrypickbotreview ? "message" : "review" } to ${change.id}: ${response.status} ${response.statusText} ${JSON.stringify(JSON.parse(response.data.slice(4)))}`);
                    })
                    .catch(function (error) {
                      logger.log(`Error posting message to ${change.id}`, "error");
                    })
                } else {
                  logger.log(`No need to post on ${change.id}. It's an existing pick.`);
                }
              });
            } else {
              if (cherrypickbotreview)
                logger.log(`Manual action to delete review needed on ${change.id}`);
              else
                logger.log(`No need to post on ${change.id}. It's an existing pick.`);
            }
          })
        }
      });
    })
    .catch(function (error) {
      logger.log(`Error getting changes for ${repo}: ${error}`, "error");
    })
});
