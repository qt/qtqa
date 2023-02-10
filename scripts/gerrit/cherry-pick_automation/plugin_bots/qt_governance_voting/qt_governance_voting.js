/****************************************************************************
 **
 ** Copyright (C) 2021 The Qt Company Ltd.
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

exports.id = "qt_governance_voting";

const fetch = require("node-fetch");
const Mustache = require("mustache");
const express = require("express");
const toBool = require("to-bool");
const Moniker = require("moniker");

const axios = require("axios");

const config = require("./config.json");

function envOrConfig(ID) {
  if (process.env[ID]) return process.env[ID];
  else return config[ID];
}

let gerritURL = envOrConfig("VOTING_GERRIT_URL");
let gerritPort = envOrConfig("VOTING_GERRIT_PORT");

// Assemble the gerrit URL, and tack on http/https if it's not already
// in the URL. Add the port if it's non-standard, and assume https
// if the port is anything other than port 80.
let gerritResolvedURL = /^(http)s?:\/\//g.test(gerritURL)
  ? gerritURL
  : `${gerritPort == 80 ? "http" : "https"}://${gerritURL}`;
gerritResolvedURL += gerritPort != 80 && gerritPort != 443 ? ":" + gerritPort : "";

// Return an assembled url to use as a base for requests to gerrit.
function gerritBaseURL(api) {
    return `${gerritResolvedURL}/a/${api}`;
  }

let globals = {
  currentVotes: [],
  subject: envOrConfig("VOTE_SUBJECT"),
  tally: 0,
  votes_for_count: 0,
  votes_against_count: 0,
  voting_open: toBool(envOrConfig("VOTING_OPEN")),
  voting_deadline: new Date(envOrConfig("VOTING_DEADLINE_DT")),
  vote_mappings: {},
};


const postgreSQLClient = require("../../postgreSQLClient");
postgreSQLClient.pool.query(`CREATE TABLE IF NOT EXISTS governance_voting
            (
              voter TEXT PRIMARY KEY,
              approve_measure BOOL,
              manual_voting_token TEXT
            )
          `);

let self_base_url;
if (envOrConfig("HEROKU_APP_NAME"))
  self_base_url = `https://${envOrConfig("HEROKU_APP_NAME")}.herokuapp.com`;
else self_base_url = `http://localhost:${Number(process.env.PORT) || envOrConfig("WEBHOOK_PORT")}`;

console.log(`Voting tool loaded at ${self_base_url}/voting`);

class qt_governance_voting {
  constructor(notifier) {
    // Hook into the central notifier for access to main tools.
    this.notifier = notifier;
    this.logger = notifier.logger;
    this.retryProcessor = notifier.retryProcessor;
    this.requestProcessor = notifier.requestProcessor;
    //Parse URL-encoded bodies
    this.notifier.server.app.use(express.urlencoded({ extended: true }));
    // Add new endpoints to the cental webserver
    this.notifier.server.app.use("/templates", express.static(`${__dirname}/templates/`));
    this.notifier.server.app.get("/voting", (req, res) => this.serve_voting_page(req, res));
    this.notifier.server.app.post("/voting", (req, res) => this.process_vote(req, res));

    if (globals.voting_open) {
      if (globals.voting_deadline == "Invalid Date") {
        this.logger.log(
          `Invalid voting deadline specified in "VOTING_DEADLINE_DT":` +
            ` "${globals.voting_deadline}". VOTING WILL NOT AUTO-CLOSE!`,
          "error", "VOTING"
        );
      } else {
        let now = new Date();
        if (now >= globals.voting_deadline) {
          globals.voting_open = false;
          this.logger.log(
            `The voting deadline "${globals.voting_deadline}" is passed.` + ` Closing voting.`,
            "info", "VOTING"
          );
        } else if (globals.voting_open) {
          this.logger.log(
            `Voting is open. Deadline set for "${globals.voting_deadline}".` +
              ` It is currently ${now}`,
            "info", "VOTING"
          );
          // Set the trigger to close voting on a timer
          setTimeout(() => {
            globals.voting_open = false;
            this.logger.log(
              `The voting deadline "${globals.voting_deadline}" passed.` + ` Closing voting.`,
              "info", "VOTING"
            );
          }, globals.voting_deadline - now);
        }
      }
    } else {
      this.logger.log(`Voting is closed.`, "info", "VOTING");
    }
  }

  // Serve the main voting webpage
  serve_voting_page(req, res, info = {}) {
    let _this = this;

    // The data is assembled. Apply the template and serve the response.
    function do_serve() {
      let view = {
        self_base_url: self_base_url,
        subject: globals.subject,
        tally: Number(globals.votes_for_count) + Number(globals.votes_against_count),
        votes_for: globals.voting_open ? "hidden" : globals.votes_for_count,
        votes_against: globals.voting_open ? "hidden" : globals.votes_against_count,
        vote_error: info.vote_error,
        // Maybe display a contextual message on the voting page.
        user_status_message: info.user_status_message
          ? info.user_status_message
          : !globals.voting_open && !info.vote_error
          ? "Voting is closed. The tally shown is final."
          : "",
        // Hide voting form if a status message is available (for example a vote is submitted)
        hide_voting: Boolean(info.user_status_message) || !globals.voting_open ? "hidden" : "",
        moniker_mappings: map_votes(),
      };
      // Grab the template
      fetch(`${self_base_url}/templates/voting.mustache`)
        .then((response) => response.text())
        .then((template) => {
          // Populate the template with our data
          var rendered = Mustache.render(template, view);
          // Send the finished page
          res.send(rendered);
        });
    }

    function map_votes() {
      // Map real users and their votes to the pseudonymous monikers for display.
      // Builds the html table for display.
      let voter_list =
        "<table><tr><th>Voter</th><th>Approve Measure</th></tr>" +
        (() => {
          let concatenatedString = "";
          for (let i = 0; i < globals.moniker_mappings.length; i++) {
            concatenatedString +=
              `<tr><td>${globals.moniker_mappings[i].moniker}</td>` +
              `<td>${
                globals.voting_open ? "vote hidden" : globals.moniker_mappings[i].approve_measure
              }</td></tr>`;
          }
          return concatenatedString;
        })() +
        "</table>";
      return voter_list;
    }

    // Collect the voting results status from the DB to prepare for serving the page.
    // Error handling takes place in the sql client.
    postgreSQLClient.pool.query(
      "SELECT moniker, approve_measure FROM governance_voting"
      + " WHERE approve_measure IS NOT NULL",
      (err, data) => {
        if (err) {
          // A database error likely occurred, dump the error and send a 500 response.
          this.logger.log(
            `Error in assembling the voting page: ${err}`,
            "error", "VOTING"
          );
          res.status(500).send('An internal error occurred. Please email'
          +' <a href="mailto:gerrit-admin@qt-project.org">gerrit-admin@qt-project.org</a>');
          return;
        }
        // gather the counts of approve and reject
        globals.votes_for_count = Object.values(data.rows).filter(
          (m)=>{return m.approve_measure==true}).length;
        globals.votes_against_count = Object.values(data.rows).filter(
          (m)=>{return m.approve_measure==false}).length;
        // generate the html results table
        globals.moniker_mappings = data.rows;
        // Finally, serve the page.
        do_serve();
      }
    );
  }

  do_vote(req, res) {

    function try_insert_with_moniker(user_moniker) {
      _this.logger.log(`Inserting vote for ${req.body.voter}: ${user_moniker}`, "info", "VOTING");
      postgreSQLClient.insert(
        "governance_voting", ["voter", "approve_measure", "moniker"],
        [req.body.voter, approve, user_moniker],
        function (result, data) {
          if (Number(data.code) == 23505) {
            // The chosen moniker is already taken in the database. Try again.
            let user_moniker = Moniker.choose();
            logger.log(
              `${data.detail}. Trying to assign ${user_moniker} instead.`,
              "info", "VOTING"
            );
            try_insert_with_moniker(user_moniker);
            return;
          }
          if (result)
            _this.serve_voting_page(req, res, {
              user_status_message: `Thank you for your vote! The tally above has been updated`
              + ` to include your "${req.body.button_value.replace("_", " ")}" vote as`
              + ` <b style="color:#CC0000"> ${user_moniker}</b>.`,
            });
          else
            _this.serve_voting_page(req, res, {
              vote_error:
                'There was a problem saving your vote. Please contact'
                + ' <a href="mailto:gerrit-admin@qt-project.org">gerrit-admin@qt-project.org</a>',
            });
        }
      );
    }

    let _this = this;
    let approve = req.body.button_value == "approve_measure";
    let retract = req.body.button_value == "retract_measure";
    if (retract) {
      // Set vote for the user to null, rather than deleting it.
      // This way, the user both retains the same moniker and voting token in a later vote,
      // and it can be seen that a vote was cast and later retracted in the event
      // of a complaint.
      _this.logger.log(`Retracting vote for ${req.body.voter}`, "info", "VOTING");
      postgreSQLClient.update(
        "governance_voting", "voter", req.body.voter, { approve_measure: null },
        function (result) {
          if (result)
            _this.serve_voting_page(req, res, {
              user_status_message:
                "If you previously cast a vote, it has now been removed. If you authorized"
                + " using a token, it remains valid.",
            });
          else
            _this.serve_voting_page(req, res, {
              vote_error:
                'There was a problem removing your vote. Please contact'
                + ' <a href="mailto:gerrit-admin@qt-project.org">gerrit-admin@qt-project.org</a>',
            });
        }
      );
    } else {
      // Cast a normal vote
      postgreSQLClient.query(
        "governance_voting", ["approve_measure", "moniker"], "voter", req.body.voter, "=",
        function (err, rows) {
          if (rows.length == 0) {
            // User has not previously voted, insert new row.
            let user_moniker = Moniker.choose();
            try_insert_with_moniker(user_moniker);
          } else {
            // Update the user's existing vote.
            _this.logger.log(
              `Updating for for ${req.body.voter} as ${rows[0].moniker}`,
              "info", "VOTING"
            );
            postgreSQLClient.update(
              "governance_voting", "voter", req.body.voter, { approve_measure: approve },
              function (result) {
                if (result)
                  _this.serve_voting_page(req, res, {
                    user_status_message: `Your vote as <b style="color:#CC0000">`
                    + `${rows[0].moniker}</b> has been changed or updated.`
                    + ` The tally above includes your `
                    + `"${req.body.button_value.replace("_", " ")}" vote.`,
                  });
                else
                  _this.serve_voting_page(req, res, {
                    vote_error:
                      'There was a problem updating your vote. Please contact'
                      + ' <a href="mailto:gerrit-admin@qt-project.org">'
                      + ' gerrit-admin@qt-project.org</a>',
                  });
              }
            );
          }
        }
      );
    }
  }

  // Receive a vote from the voting form and handle it
  process_vote(req, res, customAuth) {
    let _this = this;
    if (!globals.voting_open) {
      // Prevent incoming votes if voting is closed.
      _this.logger.log(
        `Voter ${req.body.voter} attempted to vote after voting was closed!`,
        "warn", "VOTING"
      );
      _this.serve_voting_page(req, res, {
        vote_error: "You cannot vote because voting is closed. The tally is final.",
      });
      return;
    }
    // Configure authorization to gerrit on behalf of the user
    let gerritAuth = {
      username: req.body.voter,
      password: req.body.password,
    };
    // Retrieve the groups that the voter is in
    axios({
      method: "get",
      url: gerritBaseURL("accounts") + `/${gerritAuth.username}/groups`,
      auth: customAuth || gerritAuth,
    })
      .then(function (response) {
        // Check to make sure the user is in one of the approved voter groups
        let authorized = false;
        let groups = JSON.parse(response.data.slice(4)); // slice '{[( from gerrit response
        for (let i in groups) {
          // Approvers and Maintainers group UUID in gerrit. These will never change.
          if (
            groups[i].id == "cc69d454b2caa4fc7ab0258ead17a6df71c4707b" ||
            groups[i].id == "a60ed457f6e3833c81023c72743ba73c7e23fb09"
          )
            authorized = true;
        }
        if (!authorized) {
          _this.logger.log(
            `Unauthorized user attempted to vote: ${req.body.voter}`,
            "warn", "VOTING"
          );
          _this.serve_voting_page(req, res, {
            vote_error: `Unable to vote. You are not a member of "Approvers" or "Maintainers"`
            + ` on codereview.qt-project.org`,
          });
          return;
        }
        // Authorized, so see what the user wanted to do.
        if (req.body.button_value == "retrieve_vote") {
          // Display the voter's currently stored vote.
          postgreSQLClient.query(
            "governance_voting", ["approve_measure", "moniker"], "voter", req.body.voter, "=",
            function (err, rows) {
              if (rows.length == 1)
                _this.serve_voting_page(req, res, {
                  user_status_message: `Your current vote as <b style="color:#CC0000">`
                  + `${rows[0].moniker}</b> is <b style="color:#CC0000">`
                  + `${rows[0].approve_measure ? "Approve Measure" : "Reject Measure"}</b>`,
                });
              else
                _this.serve_voting_page(req, res, {
                  user_status_message: `You have not voted yet. Please refresh and cast a vote.`,
                });
            }
          );
        } else {
          // User clicked Submit Vote button.
          _this.do_vote(req, res);
        }
      })
      .catch(function (error) {
        // Gerrit returned an authorization error for the user. This could be expected if the
        // user supplied a manual voting token that has been given to them by
        // a gerrit admin.
        if (error.response) {
          _this.logger.log(
            `Failed to authenticate ${req.body.voter}.`
            + ` ${error.response.status}: ${error.response.data}`,
            "warn", "VOTING"
          );
          // Query the voting database for the user's voting token.
          postgreSQLClient.query(
            "governance_voting", "manual_voting_token", "voter", req.body.voter, "=",
            function (err, rows) {
              if (rows.length == 1) {
                if (rows[0].manual_voting_token == req.body.password) {
                  // The token field was set, and it matches the password field of the voting form.
                  _this.logger.log(
                    `Authenticating ${req.body.voter} with voting token.`,
                    "info", "VOTING"
                  );
                  _this.do_vote(req, res);
                  return;
                } else if (rows[0].manual_voting_token != "null") {
                  // Gerrit password was incorrect or the voting token was wrong.
                  // Either way, we can't authenticate the voter.
                  _this.logger.log(
                    `User ${req.body.voter} failed to authenticate against voting token.`,
                    "warn", "VOTING"
                  );
                }
                _this.serve_voting_page(req, res, {
                  vote_error:
                    'Authentication error.<br>Verify your credentials or voting token are correct,'
                    + '<br>or email <a href="mailto:gerrit-admin@qt-project.org">'
                    + 'gerrit-admin@qt-project.org</a> to request a voting token instead of'
                    + ' authenticating via codereview.',
                });
              } else {
                // Unexpected database response
                _this.serve_voting_page(req, res, {
                  vote_error:
                    'Authentication error.<br>Verify your credentials or voting token are correct,'
                    + '<br>or email <a href="mailto:gerrit-admin@qt-project.org">'
                    + 'gerrit-admin@qt-project.org</a> to request a voting token instead of'
                    + ' authenticating via codereview.',
                });
              }
            }
          );
        } else {
          // Unexpected error response from Gerrit
          _this.serve_voting_page(req, res, {
            vote_error:
              'Something went wrong when trying to authenticate you. Please email'
              + ' <a href="mailto:gerrit-admin@qt-project.org">gerrit-admin@qt-project.org'
              + '</a> to investigate.',
          });
        }
      });
  }
}

module.exports = qt_governance_voting;
