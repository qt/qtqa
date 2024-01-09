/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "new_contributor_welcome";

const gerritTools = require("../../gerritRESTTools");
const config = require("./config.json");

function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

class new_contributor_welcome {
  constructor(notifier) {
    this.notifier = notifier;
    this.logger = notifier.logger;
    this.retryProcessor = notifier.retryProcessor;
    this.requestProcessor = notifier.requestProcessor;

    this.gerritAuth = {
      username: envOrConfig("CONTRIBUTOR_GERRIT_USER"),
      password: envOrConfig("CONTRIBUTOR_GERRIT_PASS")
    };


    notifier.registerCustomListener(notifier.requestProcessor, "check_new_contributor_reviewers",
      this.check_new_contributor_reviewers.bind(this));
    notifier.server.registerCustomEvent(
      "welcome_new_contributor", "patchset-created",
      (req) => {
        // Run a few checks.

        // Is the patchset a new change on patchset 1?
        if (req.patchSet.number != 1) {
          return;
        }

        // Has the user already contributed?
        gerritTools.getContributorChangeCount(req.uuid, req.change.owner.username, this.gerritAuth,
          (success, count) => {
            if (!success) {
              this.logger.log("Failed to get contributor info for " + req.change.owner.username
                + " on " + req.change.number, "error", req.uuid);
              return;
            }
            if (count > 1) {
              // Already contributed, no need to welcome.
              return;
            }

            // This is the first change the user has submitted.
            // Wait two minutes to see if they add reviewers.
            this.retryProcessor.addRetryJob("WELCOME", "check_new_contributor_reviewers",
              [req], 120000);
          })
      }
    );
    this.logger.log("Initialized New contributor welcome bot", "info", "SYSTEM");
  }

  check_new_contributor_reviewers(req) {
    // Get the current reviewers of the change.
    gerritTools.getChangeReviewers(req.uuid, req.change.number, this.gerritAuth,
      (success, reviewers) => {
        if (!success) {
          this.logger.log("Failed to get change info for " + req.change.number,
            "error", req.uuid);
          return;
        }
        // Check if the change has reviewers. Sanity bot will always be added as a reviewer.
        reviewers = reviewers.filter(reviewer => reviewer != "qt_sanitybot@qt-project.org");
        this.logger.log("Existing reviewers: [" + reviewers + "]", "verbose", req.uuid);
        if (reviewers.length > 0) {
          // The change has reviewers, no need to welcome.
          return;
        }

        // The change has no reviewers, send a welcome message.
        this.send_welcome_message(req, req.change.project);
      })
  }

  send_welcome_message(req) {
    const user = req.change.owner.name || req.change.owner.username;
    const message = `Welcome to The Qt Project, ${user}! `
      + "Thank you for your contribution!\n\n"
      + "In order to get your change merged, it needs to be reviewed and approved first.\n"
      + "Since you are new to the project, we've added a few reviewers for you that can help"
      + " you with your first contribution and find a reviewer who knows this code well."
      + " If you have any questions about getting set up with Qt, or anything else in our review"
      + " process, feel free to ask them.\n\n"
      + "In case you haven't read it yet, please take a look at our "
      + "[Contribution guide](https://wiki.qt.io/Qt_Contribution_Guidelines),"
      + " [Coding style](https://wiki.qt.io/Qt_Coding_Style), and"
      + " [Contributions homepage](https://wiki.qt.io/Contribute).\n\n"
      + "Note that this change has been set to \"Ready for review\" automatically so that the added"
      + " reviewers can see it. If you are not ready for review yet, please set the change back to"
      + " \"Work in progress\" using the menu in the top-right of the page.\n\n"
      + "And again, welcome to The Qt Project! Your contribution is greatly appreciated!";

    // Add the reviewers.
    gerritTools.postGerritComment(req.uuid, req.change.number, undefined, message,
      undefined, undefined, this.gerritAuth,
      (success, data) => {
        if (!success) {
          this.logger.log("Failed to post welcome message for " + req.change.number,
            "error", req.uuid);
          return;
        }
        // Get group members
        // Gerrit group for review buddies: eb1d5ff38b9cfe20c4cfada58b5bf8ba246ad6ab
        // AKA: "New Contributors Welcome Buddies"
        gerritTools.getGroupMembers(req.uuid, "New Contributors Welcome Buddies", this.gerritAuth,
          (success, members) => {
            if (!success) {
              this.logger.log("Failed to get group members for " + req.change.number,
                "error", req.uuid);
              return;
            }
            members = members.map(member => member.username);
            // Randomly select 4 reviewers.
            members = members.sort(() => Math.random() - Math.random()).slice(0, 4);
            // Add the reviewers.
            this.logger.log("Adding reviewers [" + members + "] for " + req.change.number,
              "verbose", req.uuid);
            gerritTools.setChangeReviewers(req.uuid, req.change.number,
              members, this.gerritAuth,
              (failedItems) => {
                if (failedItems.length > 0) {
                  this.logger.log("Failed to add reviewers for " + req.change.number,
                    "error", req.uuid);
                  return;
                }
                this.logger.log("Added reviewers for " + req.change.number,
                  "verbose", req.uuid);
              }
            );
          }
        );
        this.logger.log("Posted welcome message for " + req.change.number,
          "verbose", req.uuid);
      }
    );

    // Also set a hashtag marking the change as from a new contributor.
    // This makes all changes from new contributors easy to find.
    // https://codereview.qt-project.org/q/hashtag:new_contributor
    gerritTools.setHashtags(req.uuid, req.change.number, ["new_contributor"],
      this.gerritAuth, (success) => {
        if (!success) {
          this.logger.log("Failed to set hashtags for " + req.change.number,
            "error", req.uuid);
          return;
        }
        this.logger.log("Set hashtags for " + req.change.number,
          "verbose", req.uuid);
      }
    );
  }
}

module.exports = new_contributor_welcome;
