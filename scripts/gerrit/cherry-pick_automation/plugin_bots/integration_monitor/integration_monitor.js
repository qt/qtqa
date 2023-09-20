/* eslint-disable no-unused-vars */
// Copyright (C) 2022 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "integration_monitor";

const gerritTools = require("../../gerritRESTTools");

// This plugin requires no additional config, and relies
// on the base cherry-pick-bot credentials.

// This plugin listens for failed integrations owned by the cherry-pick
// bot (The owner of a change is the uploader of the first patch set and cannot
// be changed). When such a change fails to integrate, this plugin adds
// the author of the most recent patch set to the attention set and posts
// a basic message.
class integration_monitor {
  constructor(notifier) {
    this.notifier = notifier;
    this.logger = notifier.logger;
    this.retryProcessor = notifier.retryProcessor;
    this.requestProcessor = notifier.requestProcessor;

    this.handleIntegrationFailed = this.handleIntegrationFailed.bind(this);
    this.handlePatchsetCreated = this.handlePatchsetCreated.bind(this);

    function pickbotIsOwner(userEmail) {
      return userEmail == "cherrypick_bot@qt-project.org";
    }

    notifier.registerCustomListener(notifier.server, "integration_monitor_failed",
                                    this.handleIntegrationFailed);
    notifier.server.registerCustomEvent("integration_monitor_failed", "change-integration-fail",
      function (req) {
        // The change-integration-fail event doesn't have the patchset author,
        // so query gerrit for the full change details.
        gerritTools.queryChange(req.uuid, req.fullChangeID, undefined, undefined,
          function(success, changeData) {
            if (success) {
              let author = changeData.revisions[changeData.current_revision].commit.author.email;
              let pickbotIsAuthor = author == "cherrypick_bot@qt-project.org";
              if (pickbotIsOwner(req.change.owner.email) && !pickbotIsAuthor) {
                // A real user is the author and should be added to the attention set.
                notifier.server.emit("integration_monitor_failed", req, author);
              }
            } else {
              this.logger.log(`Failed to query gerrit for ${req.fullChangeID}`, "error", req.uuid);
            }
          }
        );
      }
    );

    notifier.registerCustomListener(notifier.server, "integration_monitor_patchset-created",
                                    this.handlePatchsetCreated);
    notifier.server.registerCustomEvent("integration_monitor_patchset-created", "patchset-created",
      function(req) {
        if (req.change.status == "MERGED")
          return;  // The CI created a new patchset upon change merge.
        let uploader = req.uploader.email;
        let pickbotIsUploader = uploader == "cherrypick_bot@qt-project.org";
        if (pickbotIsOwner(req.change.owner.email) && !pickbotIsUploader) {
          // A real user is the uploader and should be added to the attention set.
          notifier.server.emit("integration_monitor_patchset-created", req, uploader);
        }
      }
    );
  }

  doAddToAttentionSet(req, user, reason, callback) {
    let _this = this;
    gerritTools.addToAttentionSet(
      req.uuid, req.change, user, reason, undefined,
      function (success, msg) {
        if (callback)
          callback(success);
      }
    );
  }

  handleIntegrationFailed(req, author) {
    let _this = this;
    _this.logger.log(
      `Received integration failure notification for cherry-picked change ${req.fullChangeID}`,
      "info", req.uuid
    );
    req.change.fullChangeID = req.fullChangeID // Tack on the full change ID so it gets used
    _this.doAddToAttentionSet(req, author, "Change author", (success) => {
      if (!success) {
        gerritTools.locateDefaultAttentionUser(req.uuid, req.change, req.change.owner.email,
          (user, fallbackId) => {
          if (user == "copyReviewers")
            gerritTools.copyChangeReviewers(req.uuid, fallbackId, req.change.fullChangeID);
          else {
            gerritTools.setChangeReviewers(req.uuid, req.change.fullChangeID, [user], undefined,
              function(){})
            _this.doAddToAttentionSet(req, user, "Original reviewer");
          }
        });
      }
    });
  }

  handlePatchsetCreated(req, uploader) {
    let _this = this;
    _this.logger.log(
      `Received patchset-created by ${uploader} for cherry-picked change ${req.change.project}`,
      "info", req.uuid
    );
    // Patchset-created does not include a full change ID. Assemble one.
    req.fullChangeID = encodeURIComponent(`${req.change.project}~${req.change.branch}~${req.change.id}`);
    req.change.fullChangeID = req.fullChangeID;
    gerritTools.locateDefaultAttentionUser(req.uuid, req.change, uploader, (user, fallbackId) => {
      if (user == "copyReviewers")
        gerritTools.copyChangeReviewers(req.uuid, fallbackId, req.change.fullChangeID);
      else {
        gerritTools.setChangeReviewers(req.uuid, req.change.fullChangeID, [user], undefined,
          function(){})
        _this.doAddToAttentionSet(req, user, "Original reviewer");
      }
    });
  }
}

module.exports = integration_monitor;
