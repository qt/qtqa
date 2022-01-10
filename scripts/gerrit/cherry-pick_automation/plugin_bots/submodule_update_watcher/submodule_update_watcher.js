/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "submodule_update_watcher";

const axios = require("axios");

const gerritTools = require("../../gerritRESTTools");
const config = require("./config.json");

function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

class submodule_update_watcher {
  constructor(notifier) {
    this.notifier = notifier;
    this.logger = notifier.logger;
    this.retryProcessor = notifier.retryProcessor;
    this.requestProcessor = notifier.requestProcessor;

    this.handleIntegrationFailed = this.handleIntegrationFailed.bind(this);
    this.handleIntegrationPassed = this.handleIntegrationPassed.bind(this);

    const gerritAuth = {
      username: envOrConfig("SUBMODULE_UPDATE_GERRIT_USER"),
      password: envOrConfig("SUBMODULE_UPDATE_GERRIT_PASS")
    };
    const jenkinsAuth = {
      username: envOrConfig("SUBMODULE_UPDATE_JENKINS_USER"),
      password: envOrConfig("SUBMODULE_UPDATE_JENKINS_TOKEN")
    };
    const jenkinsURL = envOrConfig("SUBMODULE_UPDATE_JENKINS_URL");

    notifier.registerCustomListener(notifier.server, "submodule_update_failed", this.handleIntegrationFailed);
    notifier.server.registerCustomEvent(
      "submodule_update_failed", "change-integration-fail",
      function (req) {
        if (req.change.commitMessage.match(/Update (submodule|submodules|dependencies) (refs )?on/)) {
          req["customGerritAuth"] = gerritAuth;
          req["jenkinsURL"] = jenkinsURL;
          req["jenkinsAuth"] = jenkinsAuth;
          notifier.server.emit("submodule_update_failed", req);
        }
      }
    );
    notifier.registerCustomListener(notifier.server, "submodule_update_passed", this.handleIntegrationPassed);
    notifier.server.registerCustomEvent(
      "submodule_update_passed", "change-integration-pass",
      function (req) {
        if (req.change.commitMessage.match(/Update (submodule|submodules|dependencies) (refs )?on/)) {
          req["customGerritAuth"] = gerritAuth;
          req["jenkinsURL"] = jenkinsURL;
          req["jenkinsAuth"] = jenkinsAuth;
          notifier.server.emit("submodule_update_passed", req);
        }
      }
    );
  }

  handleIntegrationFailed(req) {
    let _this = this;
    _this.logger.log(
      `Received dependency update failure notification for ${req.change.project}`,
      "info", req.uuid
    );
    gerritTools.queryChange(
      req.uuid, req.fullChangeID, undefined, req.customGerritAuth,
      function (success, data) {
        if (envOrConfig("SUBMODULE_UPDATE_FAILED_ATTENTION_USER")) {
          gerritTools.addToAttentionSet(
            req.uuid, req, envOrConfig("SUBMODULE_UPDATE_FAILED_ATTENTION_USER"), req.customGerritAuth,
            function () {
              _this.notifier.requestProcessor.emit(
                "postGerritComment", req.uuid, req.fullChangeID,
                undefined, `${req.change.project} dependency update integration failed.`,
                undefined, req.customGerritAuth
              );
            }
          );
        } else {
          _this.logger.log("No default user configured to add to the attention set"
                           + " for submodule updates.", undefined, req.uuid);
        }

        // Run the bot again, which will either stage it or give up.
        _this.sendBuildRequest(req);
      }
    );
  }

  handleIntegrationPassed(req) {
    let _this = this;
    if (envOrConfig("SUBMODULE_UPDATE_TEAMS_URL")
        && req.change.commitMessage.match(/Update (submodule refs|submodules) on/)
    ) {
      axios.post(envOrConfig("SUBMODULE_UPDATE_TEAMS_URL"), {
        "Text": `Successfully updated ${req.change.project} on **${req.change.branch}** submodules set in [https://codereview.qt-project.org/#/q/${req.change.id},n,z](https://codereview.qt-project.org/#/q/${req.change.id},n,z)`
      });
    }
    _this.sendBuildRequest(req)
  }

  sendBuildRequest(req) {
    let _this = this;
    if (req.jenkinsURL) {
      _this.logger.log("Running new submodule update job", undefined, req.uuid);
      // Need to make the branch compatible with jenkins project naming rules.
      axios.post(
        `${req.jenkinsURL}/job/qt_submodule_update_${req.change.branch.replace("/", "-")}/buildWithParameters`, undefined,
        { auth: req.jenkinsAuth }
      );
    } else {
      _this.logger.log("Unable to run new submodule update job. No URL set!", "warn", req.uuid)
    }
  }

}

module.exports = submodule_update_watcher;
