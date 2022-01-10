/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "submodule_update_watcher";

const axios = require("axios");
const express = require("express");

const gerritTools = require("../../gerritRESTTools");
const logger = require("../../logger");
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

    this.pause_updates = this.pause_updates.bind(this);
    this.resume_updates = this.resume_updates.bind(this);
    this.reset_updates = this.reset_updates.bind(this);
    this.retry_updates = this.retry_updates.bind(this);
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

    notifier.registerCustomListener(notifier.server, "submodule_update_failed",
                                    this.handleIntegrationFailed);
    notifier.server.registerCustomEvent(
      "submodule_update_failed", "change-integration-fail",
      function (req) {
        if (req.change.commitMessage.match(
          /Update (submodule|submodules|dependencies) (refs )?on/)) {
          req["customGerritAuth"] = gerritAuth;
          req["jenkinsURL"] = jenkinsURL;
          req["jenkinsAuth"] = jenkinsAuth;
          notifier.server.emit("submodule_update_failed", req);
        }
      }
    );
    notifier.registerCustomListener(notifier.server, "submodule_update_passed",
                                    this.handleIntegrationPassed);
    notifier.server.registerCustomEvent(
      "submodule_update_passed", "change-integration-pass",
      function (req) {
        if (req.change.commitMessage.match(
          /Update (submodule|submodules|dependencies) (refs )?on/)) {
          req["customGerritAuth"] = gerritAuth;
          req["jenkinsURL"] = jenkinsURL;
          req["jenkinsAuth"] = jenkinsAuth;
          notifier.server.emit("submodule_update_passed", req);
        }
      }
    );
    this.notifier.server.server.post("/pause-submodule-updates", express.json(),
     (req, res) => {
      req = req.body;
      req["customGerritAuth"] = gerritAuth;
      req["jenkinsURL"] = jenkinsURL;
      req["jenkinsAuth"] = jenkinsAuth;
      this.pause_updates(req, res);
     })
    this.notifier.server.server.post("/resume-submodule-updates", express.json(),
     (req, res) => {
      req = req.body;
      req["customGerritAuth"] = gerritAuth;
      req["jenkinsURL"] = jenkinsURL;
      req["jenkinsAuth"] = jenkinsAuth;
      this.resume_updates(req, res);
    })
    this.notifier.server.server.post("/reset-submodule-updates", express.json(),
     (req, res) => {
      req = req.body;
      req["customGerritAuth"] = gerritAuth;
      req["jenkinsURL"] = jenkinsURL;
      req["jenkinsAuth"] = jenkinsAuth;
      this.reset_updates(req, res);
    })
    this.notifier.server.server.post("/retry-submodule-updates", express.json(),
     (req, res) => {
      req = req.body;
      req["customGerritAuth"] = gerritAuth;
      req["jenkinsURL"] = jenkinsURL;
      req["jenkinsAuth"] = jenkinsAuth;
      this.retry_updates(req, res);
    })
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
            req.uuid, req, envOrConfig("SUBMODULE_UPDATE_FAILED_ATTENTION_USER"),
            req.customGerritAuth,
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
        "Text": `Successfully updated ${req.change.project} on **${req.change.branch}** submodule`
        + ` set in [https://codereview.qt-project.org/#/q/${req.change.id},n,z]`
        + `(https://codereview.qt-project.org/#/q/${req.change.id},n,z)`
      }).catch(function (error) {
        _this.logger.log("Unable to send teams message...", "warn", "SUBMODULE");
      });
    }
    _this.sendBuildRequest(req)
  }

  handleJenkinsError(req, res, error, action) {
    let _this = this;
    _this.logger.log(`Unable to ${action} submodule update job for ${req.branch || req.change.branch}.`,
                     "warn", "SUBMODULE");
    if (error.response)
      _this.logger.log(`Jenkins Error: ${error.response.status}: ${error.response.data}`,
                       "warn", "SUBMODULE");
    if (res === undefined)
      return;  // Only button presses from Teams carry a res object to respond to.
    if (error.response) {
      res.status(500).send(`Bad response from Jenkins: ${error.response.status}`
        + ` - ${error.response.data}<br>Contact the gerrit admins at`
        + " gerrit-admin@qt.project.org");
      _this.logger.log(`Jenkins responded with: ${error.response.status}`
        + ` - ${error.response.data}`, "error", "SUBMODULE");
    } else if (error.request) {
      res.status(504).send("Timeout when attempting to contact Jenkins. Contact the gerrit"
        + " admins at gerrit-admin@qt.project.org");
      _this.logger.log(`Jenkins timed out! URL: ${req.jenkinsURL}`, "error", "SUBMODULE");
    } else {
      res.status(500).send(`Unknown error attempting to ${action} submodule update job in`
        + " Jenkins. Contact the gerrit admins at gerrit-admin@qt.project.org");
      _this.logger.log(`Unknown error attempting to ${action} submodule updates ${error}`,
        "error", "SUBMODULE");
    }
  }

  sendBuildRequest(req, res) {
    let _this = this;
    // Need to make the branch compatible with jenkins project naming rules.
    let branch = (req.branch || req.change.branch).replace("/", "-");
    if (req.jenkinsURL) {
      _this.logger.log(`Running new submodule update job on ${branch}`,
        undefined, "SUBMODULE");
      let url = `${req.jenkinsURL}/job/qt_submodule_update_${branch}/buildWithParameters`
      axios.post(url, undefined,{ auth: req.jenkinsAuth }
      ).catch(function (error) {
        _this.handleJenkinsError(req, res, error, "trigger new");
      });
    } else {
      _this.logger.log("Unable to run new submodule update job. No URL set!", "warn", "SUBMODULE");
    }
  }

  pause_updates(req, res) {
    let _this = this;
    if (req.jenkinsURL) {
      _this.logger.log(`Pausing submodule updates for ${req.branch}`, undefined, "SUBMODULE");
      axios.post(
        `${req.jenkinsURL}/job/qt_submodule_update_${req.branch}/disable`,
        undefined, { auth: req.jenkinsAuth }
      ).then(function (response) {
        res.status(200).send(`Submodule update job for ${req.branch} disabled.`);
        axios.post(envOrConfig("SUBMODULE_UPDATE_TEAMS_URL"), {
          "Text": `INFO: Paused submodule update automation on '**${req.branch}**'`
        }).catch(function (error) {
          _this.logger.log("Unable to send teams message...", "warn", "SUBMODULE");
        });
      }).catch(function (error) {
        _this.handleJenkinsError(req, res, error, "disable");
      })
    } else {
      _this.logger.log(`Unable to disable submodule update job for ${req.branch}. Jenkins`
      + " URL not set!", "warn", "SUBMODULE");
      res.status(500).send("No destination URL for Jenkins set. Contact the Gerrit Admins.");
    }
  }

  resume_updates(req, res) {
    let _this = this;
    if (req.jenkinsURL) {
      _this.logger.log(`Resuming submodule updates for ${req.branch}`, undefined, "SUBMODULE");
      axios.post(
        `${req.jenkinsURL}/job/qt_submodule_update_${req.branch}/enable`,
         undefined, { auth: req.jenkinsAuth }
      ).then(function (response) {
        res.status(200).send(`Submodule update job for ${req.branch} enabled and restarted.`);
        _this.sendBuildRequest(req, res);
        axios.post(envOrConfig("SUBMODULE_UPDATE_TEAMS_URL"), {
          "Text": `INFO: Resumed submodule update automation on '**${req.branch}**'`
        }).catch(function (error) {
          _this.logger.log("Unable to send teams message...", "warn", "SUBMODULE");
        });
      }).catch(function (error) {
        _this.handleJenkinsError(req, res, error, "resume");
      });
    } else {
      _this.logger.log(`Unable to resume submodule update job for ${req.branch}.`
      + " Jenkins URL not set!", "warn", "SUBMODULE");
      res.status(500).send("No destination URL for Jenkins set. Contact the Gerrit Admins.");
    }
  }

  reset_updates(req, res) {
    let _this = this;
    if (req.jenkinsURL) {
      // Temporary block of this button in Teams since it has been abused.
      // Will be replaced with a better button or deprecated.
      res.status(401).send("Unauthorized. Contact jani.heikkinen@qt.io to perform a reset.");
      return;
      _this.logger.log(`Resetting submodule update round on ${req.branch}`, undefined, "SUBMODULE");
      axios.post(
        `${req.jenkinsURL}/job/qt_submodule_update_${req.branch}/buildWithParameters?RESET=true`,
         undefined, { auth: req.jenkinsAuth }
      ).then(function (response) {
        res.status(200).send(`Submodule update job for ${req.branch} reset.`);
        axios.post(envOrConfig("SUBMODULE_UPDATE_TEAMS_URL"), {
          "Text": `INFO: Reset submodule update round on '**${req.branch}**'`
        }).catch(function (error) {
          _this.logger.log("Unable to send teams message...", "warn", "SUBMODULE");
        });
        // Then kick off a new round immediately
        axios.post(
          `${req.jenkinsURL}/job/qt_submodule_update_${req.branch}/buildWithParameters`,
           undefined, { auth: req.jenkinsAuth }
        ).catch(function (error) {
          _this.logger.log(`Unable to start new submodule update job for ${req.branch}.`
          + `\n${error.response ? error.response.status : error}`, "warn", "SUBMODULE");
        })
      }).catch(function (error) {
        _this.handleJenkinsError(req, res, error, "reset");
      })
    } else {
      _this.logger.log(`Unable to reset submodule update job for ${req.branch}.`
      + " Jenkins URL not set!", "warn", "SUBMODULE")
      res.status(500).send("No destination URL for Jenkins set. Contact the Gerrit Admins.");
    }
  }

  retry_updates(req, res) {
    let _this = this;
    if (req.jenkinsURL) {
      _this.logger.log(`Running RETRY submodule update job on ${req.branch}`,
       undefined, "SUBMODULE");
      axios.post(
        `${req.jenkinsURL}/job/qt_submodule_update_${req.branch}`
        + `/buildWithParameters?RETRY_FAILED_MODULES=true`, undefined,
        { auth: req.jenkinsAuth }
      ).then(function (response) {
        res.status(200).send(`Submodule update job for ${req.branch} started.`);
        axios.post(envOrConfig("SUBMODULE_UPDATE_TEAMS_URL"), {
          "Text": `INFO: Retrying failed submodules on '**${req.branch}**'`
        }).catch(function (error) {
          _this.logger.log("Unable to send teams message...", "warn", "SUBMODULE");
        });
      }).catch(function (error) {
        _this.handleJenkinsError(req, res, error, "retry");
      })
    } else {
      _this.logger.log(`Unable to start submodule update job for ${req.branch}.`
        + " Jenkins URL not set!", "warn", "SUBMODULE")
      res.status(500).send("No destination URL for Jenkins set. Contact the Gerrit Admins.")
    }
  }

}

module.exports = submodule_update_watcher;
