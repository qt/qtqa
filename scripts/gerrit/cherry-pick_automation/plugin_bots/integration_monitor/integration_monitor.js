/* eslint-disable no-unused-vars */
/****************************************************************************
 **
 ** Copyright (C) 2022 The Qt Company Ltd.
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
              logger.log(`Failed to query gerrit for ${req.fullChangeID}`, "error", req.uuid);
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

  doAddToAttentionSet(req, user, comment) {
    let _this = this;
    gerritTools.addToAttentionSet(
      req.uuid, req.change, user, undefined,
      function (success, msg) {
        // No need to do anything after adding.
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
    _this.doAddToAttentionSet(req, author);
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
    // Query the cherry-pick's original branch change to identify the original
    // author.
    let ReviewRegex = /^Reviewed-by: .+<(.+)>$/m;
    let commitMessage = req.change.commitMessage;
    let originalApprover = undefined;
    try {
      originalApprover = commitMessage.match(ReviewRegex)[1];
    } catch {
      // Should really never fail, since cherry-picks should always be created
      // with the original Review footers intact.
      _this.logger.log(`Failed to locate a reviewer from commit message:\n${commitMessage}`,
      "error", req.uuid);
    }
    if (originalApprover && originalApprover != uploader) {
      // The approver from the original change should be able to help.
      gerritTools.setChangeReviewers(req.uuid, req.change.fullChangeID, [originalApprover], undefined,
        function(){})
      _this.doAddToAttentionSet(req, originalApprover,
         `Attention set updated: Added original patch Approver: ${originalApprover}`);
      return;
    }
    // This insane regex is the same as used in the commit message sanitizer,
    // So it should always find the right footer which references the
    // picked-from sha.
    let cherryPickRegex = /^\((?:partial(?:ly)? )?(?:cherry[- ]pick|(?:back-?)?port|adapt)(?:ed)?(?: from| of)?(?: commit)? (\w+\/)?([0-9a-fA-F]{7,40})/m;
    let originSha = undefined;
    try{
      originSha = commitMessage.match(cherryPickRegex)[0];
    } catch {
      _this.logger.log(`Failed to match a cherry-pick footer for ${req.change.fullChangeID}`,
       "error", req.uuid);
      return // No point in continuing. Log the error and move on.
    }
    gerritTools.queryChange(req.uuid, originSha, undefined, undefined,
      function(success, changeData) {
        if (success) {
          let originalAuthor = changeData.revisions[changeData.current_revision].commit.author.email;
          if (uploader != originalAuthor) {
            // Add the author of the original change's final patchset to the
            // attention set of the cherry-pick.
            gerritTools.setChangeReviewers(req.uuid, req.change.fullChangeID, [originalAuthor],
              undefined, function(){})
            _this.doAddToAttentionSet(req, originalAuthor,
              `Attention set updated: Added original patch author: ${originalAuthor}`);
          } else {
            // Now we have a problem. The uploader is the original author, but
            // they also appear to have self-approved the original patch.
            // Try to copy all the reviewers from the original change (hopefully there are some).
            // Adding them as a reviewer will also add them to the attention set.
            gerritTools.copyChangeReviewers(req.uuid, changeData.id, req.change.fullChangeID);
          }
        } else {
          _this.logger.log(`Failed to query gerrit for ${originSha}`, "error", req.uuid);
        }
      }
    );
  }
}

module.exports = integration_monitor;
