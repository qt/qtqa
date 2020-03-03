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

exports.id = "gerritRESTTools";

const axios = require("axios");

const toolbox = require("./toolbox");
const config = require("./config.json");

let gerritURL = config.GERRIT_URL;
let gerritPort = config.GERRIT_PORT;
let gerritUser = config.GERRIT_USER;
let gerritPass = config.GERRIT_PASS;

if (process.env.GERRIT_URL)
  gerritURL = process.env.GERRIT_URL;

if (process.env.GERRIT_PORT)
  gerritPort = process.env.GERRIT_PORT;

if (process.env.GERRIT_USER)
  gerritUser = process.env.GERRIT_USER;

if (process.env.GERRIT_PASS)
  gerritPass = process.env.GERRIT_PASS;

// Make a REST API call to gerrit to cherry pick the change to a requested branch.
// Splice out the "Pick-to: keyword from the old commit message, but keep the rest."
exports.generateCherryPick = generateCherryPick;
function generateCherryPick(changeJSON, parent, destinationBranch, callback) {
  const changeIDPos = changeJSON.change.commitMessage.lastIndexOf("Change-Id:");
  const newCommitMessage = changeJSON.change.commitMessage
    .slice(0, changeIDPos)
    .concat(`Cherry-picked from branch: ${changeJSON.change.branch}\n\n`)
    .concat(changeJSON.change.commitMessage.slice(changeIDPos))
    .replace(/^(Pick-to:(\ +\d\.\d+)+)+/gm, "")
    .replace(/^(Reviewed-by:\ (\w.+)$)/gm, "");
  axios({
    method: "post",
    url: `https://${gerritURL}:${gerritPort}/a/changes/${changeJSON.fullChangeID}/revisions/${
      changeJSON.patchSet.revision}/cherrypick`,
    data: {
      message: newCommitMessage, destination: destinationBranch,
      notify: "NONE", base: parent, keep_reviewers: false,
      allow_conflicts: true // Add conflict markers to files in the resulting cherry-pick.
    },
    auth: { username: gerritUser, password: gerritPass }
  })
    .then(function(response) {
      // Send an update with only the branch before trying to parse the raw response.
      // If the parse is bad, then at least we stored a status with the branch.
      toolbox.addToCherryPickStateUpdateQueue(
        changeJSON.uuid, { branch: destinationBranch },
        "pickCreated"
      );
      let parsedResponse = JSON.parse(response.data.slice(4));
      toolbox.addToCherryPickStateUpdateQueue(
        changeJSON.uuid, { branch: destinationBranch, cherrypickID: parsedResponse.id },
        "pickCreated"
      );
      callback(true, parsedResponse);
    })
    .catch(function(error) {
      if (error.response) {
        // The server responded with a code outside of 2xx. Something's
        // actually wrong with the cherrypick request.
        callback(false, { statusDetail: error.response.data, statusCode: error.response.status });
      } else if (error.request) {
        // The server failed to respond. Try the pick later.
        callback(false, "retry");
      } else {
        // Something unexpected happened in generating the HTTP request itself.
        console.trace(`UNKNOWN ERROR posting cherry-pick for ${destinationBranch}:\n`, error);
        callback(false, error.message);
      }
    });
}

// Post a review to the change on the latest revision.
exports.setApproval = setApproval;
function setApproval(parentUuid, cherryPickJSON, approvalScore, message, notifyScope, callback) {
  axios({
    method: "post",
    url: `https://${gerritURL}:${gerritPort}/a/changes/${
      cherryPickJSON.id}/revisions/current/review`,
    data: {
      message: message ? message : "",
      notify: notifyScope ? notifyScope : "OWNER",
      labels: { "Code-Review": approvalScore, "Sanity-Review": 1 },
      omit_duplicate_comments: true, ready: true
    },
    auth: { username: gerritUser, password: gerritPass }
  })
    .then(function(response) {
      console.log(`Set approval to "${approvalScore}" on change ${cherryPickJSON.id}`);
      callback(true, undefined);
    })
    .catch(function(error) {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx
        console.trace(`Failed to set approval ${approvalScore} on change ${
          cherryPickJSON.id}\n\tError: ${error.response.status}: ${error.response.data}"`);
        callback(false, error.response.status);
      } else if (error.request) {
        // The request was made but no response was received
        callback(false, "retry");
      } else {
        // Something unexpected happened in generating the HTTP request itself.
        console.trace(`UNKNOWN ERROR while setting approval for ${cherryPickJSON.id}:\n`, error);
        callback(false, error.message);
      }
    });
}

// Stage a conflict-free change to Qt's CI system.
// NOTE: This requires gerrit to be extended with "gerrit-plugin-qt-workflow"
// https://codereview.qt-project.org/admin/repos/qtqa/gerrit-plugin-qt-workflow
exports.stageCherryPick = stageCherryPick;
function stageCherryPick(parentUuid, cherryPickJSON, callback) {
  axios({
    method: "post",
    url: `https://${gerritURL}:${gerritPort}/a/changes/${
      cherryPickJSON.id}/revisions/current/gerrit-plugin-qt-workflow~stage`,
    data: {},
    auth: { username: gerritUser, password: gerritPass }
  })
    .then(function(response) {
      console.log(`Successfully staged "${cherryPickJSON.id}"`);
      callback(true, undefined);
    })
    .catch(function(error) {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx

        // Call this a permenant failure for staging. Ask the owner to handle it.
        callback(false, { status: error.response.status, data: error.response.data });
      } else if (error.request) {
        // The request was made but no response was received. Retry it later.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        console.trace("Error in HTTP request while trying to stage.", error.message);
        callback(false, error.message);
      }
    });
}

// Post a comment to the change on the latest revision.
exports.postGerritComment = postGerritComment;
function postGerritComment(fullChangeID, revision, message, notifyScope, callback) {
  axios({
    method: "post",
    url: `https://${gerritURL}:${gerritPort}/a/changes/${fullChangeID}/revisions/${
      revision ? revision : "current"}/review`,
    data: { message: message, notify: notifyScope ? notifyScope : "OWNER_REVIEWERS" },
    auth: { username: gerritUser, password: gerritPass }
  })
    .then(function(response) {
      console.log(`Posted comment "${message}" to change "${fullChangeID}"`);
      callback(true, undefined);
    })
    .catch(function(error) {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx
        console.trace(`Failed when posting comment "${message}" to change "${
          fullChangeID}! Error: ${error.response.status}: ${error.response.data}"`);
        callback(false, error.response);
      } else if (error.request) {
        // The request was made but no response was received
        console.trace(`Failed when posting comment "${message}" to change "${
          fullChangeID}! Error: No response from server`);
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        console.trace("Error in HTTP request while posting comment.", error.message);
        callback(false, error.message);
      }
    });
}

// Query gerrit project to make sure a target cherry-pick branch exists.
exports.validateBranch = function(project, branch, callback) {
  axios
    .get(
      `https://${gerritURL}:${gerritPort}/a/projects/${
        encodeURIComponent(project)}/branches/${branch}`,
      { auth: { username: gerritUser, password: gerritPass } }
    )
    .then(function(response) {
      // Execute callback with the target branch head SHA1 of that branch
      callback(true, JSON.parse(response.data.slice(4)).revision);
    })
    .catch(function(error) {
      if (error.response) {
        if (error.response.status == 404) {
          // Not a valid branch according to gerrit.
          callback(false, error.response);
          console.log(error.response);
        }
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        console.trace(
          `Error in HTTP request while requesting branch validation for ${branch}.`,
          error.message
        );
        callback(false, error.message);
      }
    });
};

// Query gerrit commit for it's relation chain. Returns a list of changes.
exports.queryRelated = function(fullChangeID, callback) {
  axios
    .get(
      `https://${gerritURL}:${gerritPort}/a/changes/${fullChangeID}/revisions/current/related`,
      { auth: { username: gerritUser, password: gerritPass } }
    )
    .then(function(response) {
      // Execute callback and return the list of changes
      callback(true, JSON.parse(response.data.slice(4)).changes);
    })
    .catch(function(error) {
      if (error.response) {
        // An error here would be unexpected. Changes without related changes
        // should still return valid JSON with an empty "changes" field
        callback(false, error.response);
        console.log(error.response);
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        console.trace(
          `Error in HTTP request while trying to query for related changes on ${fullChangeID}.`,
          error.message
        );
        callback(false, error.message);
      }
    });
};

// Query gerrit for a change and return it along with the current revision if it exists.
exports.queryChange = function(fullChangeID, callback) {
  axios
    .get(
      `https://${gerritURL}:${gerritPort}/a/changes/${
        fullChangeID}/?o=CURRENT_COMMIT&o=CURRENT_REVISION`,
      { auth: { username: gerritUser, password: gerritPass } }
    )
    .then(function(response) {
      // Execute callback and return the list of changes
      callback(true, JSON.parse(response.data.slice(4)));
    })
    .catch(function(error) {
      if (error.response) {
        if (error.response.status == 404) {
          // Change does not exist.
          callback(false, { statusCode: 404 });
        } else {
          // Some other error was returned
          callback(false, { statusCode: error.response.status, statusDetail: error.response.data });
        }
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        console.trace(
          `Error in HTTP request while trying to query if change ID ${fullChangeID} exists.`,
          error.message
        );
        callback(false, error.message);
      }
    });
};

// Set the assignee of a change
exports.setChangeAssignee = setChangeAssignee;
function setChangeAssignee(changeJSON, newAssignee, callback) {
  axios({
    method: "PUT",
    url: `https://${gerritURL}:${gerritPort}/a/changes/${changeJSON.id}/assignee`,
    data: { assignee: newAssignee },
    auth: { username: gerritUser, password: gerritPass }
  })
    .then(function(response) {
      console.log(`Set new assignee "${newAssignee}" on "${changeJSON.id}"`);
      callback(true, undefined);
    })
    .catch(function(error) {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx

        // Call this a permenant failure for staging. Ask the owner to handle it.
        callback(false, { status: error.response.status, data: error.response.data });
      } else if (error.request) {
        // The request was made but no response was received. Retry it later.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        console.trace("Error in HTTP request while trying to set assignee.", error.message);
        callback(false, error.message);
      }
    });
}

// Query gerrit for the existing reviewers on a change.
exports.getChangeReviewers = getChangeReviewers;
function getChangeReviewers(fullChangeID, callback) {
  axios
    .get(
      `https://${gerritURL}:${gerritPort}/a/changes/${fullChangeID}/reviewers/`,
      { auth: { username: gerritUser, password: gerritPass } }
    )
    .then(function(response) {
      // Execute callback with the target branch head SHA1 of that branch
      let reviewerlist = [];
      JSON.parse(response.data.slice(4)).forEach(function(item) {
        // Email as user ID is preferred. If unavailable, use the bare username.
        if (item.email)
          reviewerlist.push(item.email);
        else if (item.username)
          reviewerlist.push(item.username);
      });
      callback(true, reviewerlist);
    })
    .catch(function(error) {
      console.trace(error);
      // Some kind of error occurred. Have the caller take some action to
      // alert the owner that they need to add reviewers manually.
      callback(false, "manual");
    });
}

// Add new reviewers to a change.
exports.setChangeReviewers = setChangeReviewers;
function setChangeReviewers(fullChangeID, reviewers, callback) {
  let failedItems = [];

  function postReviewer(reviewer) {
    axios({
      method: "post",
      url: `https://${gerritURL}:${gerritPort}/a/changes/${fullChangeID}/reviewers`,
      data: { reviewer: reviewer },
      auth: { username: gerritUser, password: gerritPass }
    })
      .then(function(response) {
        console.log(`Success adding ${reviewer} to ${fullChangeID}`, response.data);
      })
      .catch(function(error) {
        console.trace(`Error adding a reviewer (${reviewer}) to ${fullChangeID}:`, error);
        failedItems.push(reviewer);
      });
  }

  // Not possible to batch reviewer adding into a single request. Iterate through
  // the list instead.
  reviewers.forEach(postReviewer);

  callback(failedItems);
}

exports.copyChangeReviewers = copyChangeReviewers;
function copyChangeReviewers(fromChangeID, toChangeID, callback) {
  getChangeReviewers(fromChangeID, function(success, reviewerlist) {
    if (success) {
      setChangeReviewers(toChangeID, reviewerlist, function(failedItems) {
        if (callback)
          callback(true, failedItems);
      });
    } else {
      if (callback)
        callback(false, []);
    }
  });
}
