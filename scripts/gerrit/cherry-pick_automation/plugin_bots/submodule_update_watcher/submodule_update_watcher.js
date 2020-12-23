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
        if (!data.assignee && envOrConfig("SUBMODULE_UPDATE_FAILED_ASSIGNEE")) {
          gerritTools.setChangeAssignee(
            req.uuid, req, envOrConfig("SUBMODULE_UPDATE_FAILED_ASSIGNEE"), req.customGerritAuth,
            function () {
              _this.notifier.requestProcessor.emit(
                "postGerritComment", req.uuid, req.fullChangeID,
                undefined, `${req.change.project} dependency update integration failed.`,
                undefined, req.customGerritAuth
              );
            }
          );
        } else {
          _this.logger.log("Ignoring. Assignee already set or no new assignee configured.", undefined, req.uuid);
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
