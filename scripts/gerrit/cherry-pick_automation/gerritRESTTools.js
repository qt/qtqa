/* eslint-disable no-unused-vars */
// Copyright (C) 2020 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "gerritRESTTools";

const axios = require("axios");
const axiosRetry = require('axios-retry');
const safeJsonStringify = require("safe-json-stringify");

const toolbox = require("./toolbox");
const config = require("./config.json");
const Logger = require("./logger");
const logger = new Logger();


axiosRetry(axios, {
  retries: 3,
  // Random delay in ms between 1 and 6 sec. Helps reduce load on gerrit.
  retryDelay: function() {Math.floor(Math.random() * 5 * 1000) + 1},
  shouldResetTimeout: true,
  retryCondition: (error) => {
    let status = error.response.status;
    let text = error.response.data;

    if (
      axiosRetry.isNetworkOrIdempotentRequestError(error)  // The default retry behavior
      || (status == 409 && text.includes("com.google.gerrit.git.LockFailureException"))
      || status == 408  // "Server Deadline Exceeded" Hit the anti-DDoS timeout threshold.
    )
      return true;
  },
});


// Set default values with the config file, but prefer environment variable.
function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

let gerritURL = envOrConfig("GERRIT_URL");
let gerritPort = envOrConfig("GERRIT_PORT");
let gerritAuth = {
  username: envOrConfig("GERRIT_USER"),
  password: envOrConfig("GERRIT_PASS")
};

// Assemble the gerrit URL, and tack on http/https if it's not already
// in the URL. Add the port if it's non-standard, and assume https
// if the port is anything other than port 80.
let gerritResolvedURL = /^https?:\/\//g.test(gerritURL)
  ? gerritURL
  : `${gerritPort == 80 ? "http" : "https"}://${gerritURL}`;
gerritResolvedURL += gerritPort != 80 && gerritPort != 443 ? ":" + gerritPort : "";
exports.gerritResolvedURL = gerritResolvedURL;

// Return an assembled url to use as a base for requests to gerrit.
function gerritBaseURL(api) {
  return `${gerritResolvedURL}/a/${api}`;
}

// Trim )]}' off of a gerrit response. This magic prefix in the response
// from gerrit helpts to prevent against XSSI attacks and will
// always be included in a genuine response from gerrit.
// See https://gerrit-review.googlesource.com/Documentation/rest-api.html
exports.trimResponse = trimResponse;
function trimResponse(response) {
  if (response.startsWith(")]}'"))
    return response.slice(4);
  else
    return response;
}

// Make a REST API call to gerrit to cherry pick the change to a requested branch.
// Splice out the "Pick-to: keyword from the old commit message, but keep the rest."
exports.generateCherryPick = generateCherryPick;
function generateCherryPick(changeJSON, parent, destinationBranch, customAuth, callback) {

  function doPick() {
    logger.log(
      `New commit message for ${destinationBranch}:\n${newCommitMessage}`,
      "verbose", changeJSON.uuid
    );
    logger.log(
      `POST request to: ${url}\nRequest Body: ${safeJsonStringify(data)}`,
      "debug", changeJSON.uuid
    );
    axios({ method: "post", url: url, data: data, auth: customAuth || gerritAuth })
      .then(function (response) {
        // Send an update with only the branch before trying to parse the raw response.
        // If the parse is bad, then at least we stored a status with the branch.
        toolbox.addToCherryPickStateUpdateQueue(
          changeJSON.uuid, { branch: destinationBranch, statusDetail: "pickCreated" },
          "validBranchReadyForPick"
        );
        let parsedResponse = JSON.parse(trimResponse(response.data));
        toolbox.addToCherryPickStateUpdateQueue(
          changeJSON.uuid,
          { branch: destinationBranch, cherrypickID: parsedResponse.id,
            statusDetail: "pickCreated" },
          "validBranchReadyForPick"
        );
        callback(true, parsedResponse);
      })
      .catch(function (error) {
        if (error.response) {
          // The server responded with a code outside of 2xx. Something's
          // actually wrong with the cherrypick request.
          logger.log(
            `An error occurred in POST to "${url}". Error ${error.response.status}: ${
              error.response.data}`,
            "error", changeJSON.uuid
          );
          callback(false, { statusDetail: error.response.data, statusCode: error.response.status });
        } else if (error.request) {
          // The server failed to respond. Try the pick later.
          callback(false, "retry");
        } else {
          // Something unexpected happened in generating the HTTP request itself.
          logger.log(
            `UNKNOWN ERROR posting cherry-pick for ${destinationBranch}: ${error}`,
            "error", changeJSON.uuid
          );
          callback(false, error.message);
        }
      }
    );
  }

  let newCommitMessage = changeJSON.change.commitMessage
    .concat(`(cherry picked from commit ${changeJSON.patchSet.revision})`);
  let url;
  if (/^(tqtc(?:%2F|\/)lts-)/.test(changeJSON.change.branch)) {
    url = `${gerritBaseURL("projects")}/${encodeURIComponent(changeJSON.change.project)}/commits/${
      changeJSON.patchSet.revision}/cherrypick`;
  } else {
    url = `${gerritBaseURL("changes")}/${changeJSON.fullChangeID}/revisions/${
      changeJSON.patchSet.revision}/cherrypick`;
  }
  let data = {
    message: newCommitMessage, destination: destinationBranch,
    notify: "NONE", base: parent, keep_reviewers: false,
    allow_conflicts: true // Add conflict markers to files in the resulting cherry-pick.
  };

  queryChangeTopic(changeJSON.uuid, changeJSON.fullChangeID, customAuth,
    function (success, topic) {
      if (success) {
        if (topic)
          data["topic"] = topic;  // Only populate topic field if the original change had one.
        doPick();
      } else if (!success && topic == "retry") {
        callback(false, "retry");
      } else {
        // Something unexpected happened when trying to get the Topic.
        logger.log(
          `UNKNOWN ERROR querying topic for change ${changeJSON.fullChangeID}: ${topic}`,
          "error", changeJSON.uuid
        );
        callback(false, topic);
      }
    });
}

// Post a review to the change on the latest revision.
exports.setApproval = setApproval;
function setApproval(
  parentUuid, cherryPickJSON, approvalScore,
  message, notifyScope, customAuth, callback
) {
  let url = `${gerritBaseURL("changes")}/${cherryPickJSON.id}/revisions/current/review`;
  let data = {
    message: message || "", notify: notifyScope || "OWNER",
    labels: { "Code-Review": approvalScore, "Sanity-Review": 1 },
    omit_duplicate_comments: true, ready: true
  };
  logger.log(
    `POST request to: ${url}\nRequest Body: ${safeJsonStringify(data)}`,
    "debug", parentUuid
  );

  axios({ method: "post", url: url, data: data, auth: customAuth || gerritAuth })
    .then(function (response) {
      logger.log(
        `Successfully set approval to "${approvalScore}" on change ${cherryPickJSON.id}`,
        "verbose", parentUuid
      );
      callback(true, undefined);
    })
    .catch(function (error) {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx
        logger.log(
          `An error occurred in POST to "${url}". Error ${error.response.status}: ${
            error.response.data}`,
          "error", parentUuid
        );
        callback(false, error.response.status);
      } else if (error.request) {
        // The request was made but no response was received
        callback(false, "retry");
      } else {
        // Something unexpected happened in generating the HTTP request itself.
        logger.log(
          `UNKNOWN ERROR while setting approval for ${
            cherryPickJSON.id}: ${safeJsonStringify(error)}`,
          "error", parentUuid
        );
        callback(false, error.message);
      }
    });
}

// Stage a conflict-free change to Qt's CI system.
// NOTE: This requires gerrit to be extended with "gerrit-plugin-qt-workflow"
// https://codereview.qt-project.org/admin/repos/qtqa/gerrit-plugin-qt-workflow
exports.stageCherryPick = stageCherryPick;
function stageCherryPick(parentUuid, cherryPickJSON, customAuth, callback) {
  let url =`${
    gerritBaseURL("changes")}/${cherryPickJSON.id}/revisions/current/gerrit-plugin-qt-workflow~stage`;

  logger.log(`POST request to: ${url}`, "debug", parentUuid);

  setTimeout(function () {
    axios({ method: "post", url: url, data: {}, auth: customAuth || gerritAuth })
      .then(function (response) {
        logger.log(`Successfully staged "${cherryPickJSON.id}"`, "info", parentUuid);
        callback(true, undefined);
      })
      .catch(function (error) {
        if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx

          // Call this a permanent failure for staging. Ask the owner to handle it.
          logger.log(
            `An error occurred in POST to "${url}". Error ${error.response.status}: ${
              error.response.data}`,
            "error", parentUuid
          );
          callback(false, { status: error.response.status, data: error.response.data });
        } else if (error.request) {
        // The request was made but no response was received. Retry it later.
          callback(false, "retry");
        } else {
        // Something happened in setting up the request that triggered an Error
          logger.log(
            `Error in HTTP request while trying to stage. Error: ${safeJsonStringify(error)}`,
            "error", parentUuid
          );
          callback(false, error.message);
        }
      });
  }, 5000);
}

// Post a comment to the change on the latest revision.
exports.postGerritComment = postGerritComment;
function postGerritComment(
  parentUuid, fullChangeID, revision, message,
  notifyScope, customAuth, callback
) {
  let url = `${gerritBaseURL("changes")}/${fullChangeID}/revisions/${
    revision || "current"}/review`;
  let data = { message: message, notify: notifyScope || "OWNER_REVIEWERS" };

  logger.log(
    `POST request to: ${url}\nRequest Body: ${safeJsonStringify(data)}`,
    "debug", parentUuid
  );

  axios({ method: "post", url: url, data: data, auth: customAuth || gerritAuth })
    .then(function (response) {
      logger.log(`Posted comment "${message}" to change "${fullChangeID}"`, "info", parentUuid);
      callback(true, undefined);
    })
    .catch(function (error) {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx
        logger.log(
          `An error occurred in POST (gerrit comment) to "${url}". Error ${
            error.response.status}: ${error.response.data}`,
          "error", parentUuid
        );
        callback(false, error.response);
      } else if (error.request) {
        // The request was made but no response was received
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `Error in HTTP request while posting comment. Error: ${safeJsonStringify(error)}`,
          "error", parentUuid
        );
        callback(false, error.message);
      }
    });
}

// Query gerrit project to make sure a target cherry-pick branch exists.
exports.validateBranch = validateBranch;
function validateBranch (parentUuid, project, branch, customAuth, callback) {
  let url = `${gerritBaseURL("projects")}/${encodeURIComponent(project)}/branches/${
    encodeURIComponent(branch)}`;
  logger.log(`GET request to: ${url}`, "debug", parentUuid);
  axios.get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      // Execute callback with the target branch head SHA1 of that branch.
      callback(true, JSON.parse(trimResponse(response.data)).revision);
    })
    .catch(function (error) {
      if (error.response) {
        if (error.response.status == 404) {
          // Not a valid branch according to gerrit.
          callback(
            false,
            { "status": error.response.status, "statusText": error.response.statusText }
          );
        } else {
          logger.log(
            `An error occurred in GET "${url}". Error ${error.response.status}: ${
              error.response.data}`,
            "error", parentUuid
          );
        }
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `Error in HTTP request while requesting branch validation for ${
            branch}. Error: ${safeJsonStringify(error)}`,
          "warn", parentUuid
        );
        callback(false, error.message);
      }
    });
}

exports.queryBranchesRe = queryBranchesRe;
function queryBranchesRe(uuid, project, bypassTqtc, searchRegex, customAuth, callback) {
  // Prefix the project with tqtc- if it's not already prefixed,
  // but respect the bypassTqtc flag. This is so that we can get the
  // latest branches prefixed with tqtc/lts- for comparison.
  let tqtcProject = project;
  if (!bypassTqtc) {
    tqtcProject = project.includes("qt/tqtc-") ? project : project.replace("qt/", "qt/tqtc-");
  }
  let url = `${gerritBaseURL("projects")}/${encodeURIComponent(tqtcProject)}`
    + `/branches?r=${searchRegex}`;
  logger.log(`GET request to: ${url}`, "debug", uuid);
  axios.get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      // Execute callback and return the list of changes
      logger.log(`Raw Response:\n${response.data}`, "debug", uuid);
      let branches = [];
      const parsed = JSON.parse(trimResponse(response.data));
      for (let i=0; i < parsed.length; i++) {
        branches.push(parsed[i].ref.slice(11,).replace("tqtc/lts-", "")); // trim "refs/heads/"
      }
      callback(true, branches);
    })
    .catch(function (error) {
      if (error.response) {
        if (error.response.status == 404 && !project.includes("qt/tqtc") && !bypassTqtc) {
          // The tqtc- project doesn't exist, try again with the original prefix.
          logger.log(`Project ${tqtcProject} doesn't exist, trying ${project}`, "debug", uuid);
          queryBranchesRe(uuid, project, true, searchRegex, customAuth, callback);
          return;
        }
        // An error here would be unexpected. A query with no results should
        // still return an empty list.
        callback(false, error.response);
        logger.log(
          `An error occurred in GET "${url}". Error ${error.response.status}: ${
            error.response.data}`,
          "error", uuid
        );
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `Error in HTTP request while trying to query branches in ${project} with regex `
          + `${searchRegex}. Error: ${safeJsonStringify(error)}`,
          "error", uuid
        );
        callback(false, error.message);
      }
    });
}

// Query gerrit commit for it's relation chain. Returns a list of changes.
exports.queryRelated = function (parentUuid, fullChangeID, latestPatchNum, customAuth, callback) {
  // Work around broken relation chains of merged changes by examining current-1.
  const patchNo = latestPatchNum == 1 ? 1 : latestPatchNum - 1;
  let url = `${gerritBaseURL("changes")}/${fullChangeID}/revisions/${patchNo}/related`;
  logger.log(`GET request to: ${url}`, "debug", parentUuid);
  axios.get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      // Execute callback and return the list of changes
      logger.log(`Raw Response:\n${response.data}`, "debug", parentUuid);
      callback(true, JSON.parse(trimResponse(response.data)).changes);
    })
    .catch(function (error) {
      if (error.response) {
        // An error here would be unexpected. Changes without related changes
        // should still return valid JSON with an empty "changes" field
        callback(false, error.response);
        logger.log(
          `An error occurred in GET "${url}". Error ${error.response.status}: ${
            error.response.data}`,
          "error", parentUuid
        );
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `Error in HTTP request while trying to query for related changes on ${
            fullChangeID}. Error: ${safeJsonStringify(error)}`,
          "error", parentUuid
        );
        callback(false, error.message);
      }
    });
};

// Query gerrit for a change and return it along with the current revision if it exists.

exports.queryChange = queryChange;
function queryChange(parentUuid, fullChangeID, fields, customAuth, callback) {
  let url = `${gerritBaseURL("changes")}/${fullChangeID}/?o=CURRENT_COMMIT&o=CURRENT_REVISION`;
  // Tack on any additional fields requested
  if (fields)
    fields.forEach((field) => url = `${url}&o=${field}`);
  logger.log(`Querying gerrit for ${url}`, "debug", parentUuid);
  axios.get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      // Execute callback and return the list of changes
      logger.log(`Raw response: ${response.data}`, "debug", parentUuid);
      callback(true, JSON.parse(trimResponse(response.data)));
    })
    .catch(function (error) {
      if (error.response) {
        if (error.response.status == 404) {
          // Change does not exist. Depending on usage, this may not
          // be considered an error, so only write an error trace if
          // a status other than 404 is returned.
          callback(false, { statusCode: 404 });
        } else {
          // Some other error was returned
          logger.log(
            `An error occurred in GET "${url}". Error ${error.response.status}: ${
              error.response.data}`,
            "error", parentUuid
          );
          callback(false, { statusCode: error.response.status, statusDetail: error.response.data });
        }
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `Error in HTTP request while trying to query ${fullChangeID}. ${error}`,
          "error", parentUuid
        );
        callback(false, error.message);
      }
    });
}

// Query gerrit for a change's topic
exports.queryChangeTopic = queryChangeTopic
function queryChangeTopic(parentUuid, fullChangeID, customAuth, callback) {
  let url = `${gerritBaseURL("changes")}/${fullChangeID}/topic`;
  logger.log(`Querying gerrit for ${url}`, "debug", parentUuid);
  axios.get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      logger.log(`Raw response: ${response.data}`, "debug", parentUuid);
       // Topic responses are always double-quoted, and a double-quote is
       // otherwise not permitted in topics, so a blind replacement is safe.
      let topic = trimResponse(response.data).replace(/"/g, '');
      callback(true, topic);
    })
    .catch(function (error) {
      if (error.response) {
        // Some other error was returned
        logger.log(
          `An error occurred in GET "${url}". Error ${error.response.status}: ${
            error.response.data}`,
          "error", parentUuid
        );
        callback(false, { statusCode: error.response.status, statusDetail: error.response.data });
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `Error in HTTP request while trying to query ${fullChangeID}. ${error}`,
          "error", parentUuid
        );
        callback(false, error.message);
      }
    });
}

// Query gerrit for a change and return it along with the current revision if it exists.
exports.queryProjectCommit = function (parentUuid, project, commit, customAuth, callback) {
  let url = `${gerritBaseURL("projects")}/${encodeURIComponent(project)}/commits/${commit}`;
  logger.log(`Querying gerrit for ${url}`, "debug", parentUuid);
  axios.get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      // Execute callback and return the list of changes
      logger.log(`Raw response: ${response.data}`, "debug", parentUuid);
      callback(true, JSON.parse(trimResponse(response.data)));
    })
    .catch(function (error) {
      if (error.response) {
        // Depending on usage, a 404 may not
        // be considered an error, so only write an error trace if
        // a status other than 404 is returned.
        if (error.response.status != 404) {
          // Some other error was returned
          logger.log(
            `An error occurred in GET "${url}". Error ${error.response.status}: ${
              error.response.data}`,
            "error", parentUuid
          );
        }
        callback(false, { statusCode: error.response.status, statusDetail: error.response.data });
      } else if (error.request) {
        // Gerrit failed to respond, try again later and resume the process.
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `Error in HTTP request while trying to query ${project}:${commit}. ${error}`,
          "error", parentUuid
        );
        callback(false, error.message);
      }
    });
};

// Add a user to the attention set of a change
exports.addToAttentionSet = addToAttentionSet;
function addToAttentionSet(parentUuid, changeJSON, user, reason, customAuth, callback) {
  let project = changeJSON.project.name ? changeJSON.project.name : changeJSON.project;
  checkAccessRights(
    parentUuid, project, changeJSON.branch || changeJSON.change.branch,
    user, "push", customAuth || gerritAuth,
    function (success, data) {
      if (!success) {
        let msg = `User "${user}" cannot push to ${project}:${changeJSON.branch}.`
        logger.log(msg, "warn", parentUuid);
        callback(false, msg);
        let botAssignee = envOrConfig("GERRIT_USER");
        if (botAssignee && user != botAssignee) {
          logger.log(`Falling back to GERRIT_USER (${botAssignee}) as assignee...`);
          addToAttentionSet(
            parentUuid, changeJSON, botAssignee, "fallback to bot", customAuth,
            function () {}
          );
        }
      } else {
        let url = `${gerritBaseURL("changes")}/${changeJSON.fullChangeID || changeJSON.id}/attention`;
        let data = { user: user, "reason": reason || "Update Attention Set" };
        logger.log(
          `POST request to: ${url}\nRequest Body: ${safeJsonStringify(data)}`,
          "debug", parentUuid
        );
        axios({ method: "POST", url: url, data: data, auth: customAuth || gerritAuth })
          .then(function (response) {
            logger.log(
              `Added Attention Set user: "${user}" on "${changeJSON.fullChangeID || changeJSON.id}"`,
              "info", parentUuid
            );
            callback(true, undefined);
          })
          .catch(function (error) {
            if (error.response) {
              // The request was made and the server responded with a status code
              // that falls out of the range of 2xx
              logger.log(
                `An error occurred in POST to "${url}". Error: ${error.response.status}: ${
                  error.response.data}`,
                "error", parentUuid
              );
              callback(false, { status: error.response.status, data: error.response.data });
            } else if (error.request) {
              // The request was made but no response was received. Retry it later.
              callback(false, "retry");
            } else {
              // Something happened in setting up the request that triggered an Error
              logger.log(
                `Error in HTTP request while trying to add to attention set. Error: ${error}`,
                "error", parentUuid
              );
              callback(false, error.message);
            }
          });
      }
    }
  )
}

// Query gerrit for the existing reviewers on a change.
exports.getChangeReviewers = getChangeReviewers;
function getChangeReviewers(parentUuid, fullChangeID, customAuth, callback) {
  let url = `${gerritBaseURL("changes")}/${fullChangeID}/reviewers/`;
  logger.log(`GET request for ${url}`, "debug", parentUuid);
  axios
    .get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      logger.log(`Raw Response: ${response.data}`, "debug", parentUuid);
      // Execute callback with the target branch head SHA1 of that branch
      let reviewerlist = [];
      JSON.parse(trimResponse(response.data)).forEach(function (item) {
        // Email as user ID is preferred. If unavailable, use the bare username.
        if (item.email)
          reviewerlist.push(item.email);
        else if (item.username)
          reviewerlist.push(item.username);
      });
      callback(true, reviewerlist);
    })
    .catch(function (error) {
      if (error.response) {
        // The request was made and the server responded with a status code
        // that falls out of the range of 2xx
        logger.log(
          `An error occurred in GET to "${url}". Error ${error.response.status}: ${
            error.response.data}`,
          "error", parentUuid
        );
      } else {
        logger.log(
          `Failed to get change reviewers on ${fullChangeID}: ${safeJsonStringify(error)}`,
          "error", parentUuid
        );
      }
      // Some kind of error occurred. Have the caller take some action to
      // alert the owner that they need to add reviewers manually.
      callback(false, "manual");
    });
}

// Add new reviewers to a change.
exports.setChangeReviewers = setChangeReviewers;
function setChangeReviewers(parentUuid, fullChangeID, reviewers, customAuth, callback) {
  let failedItems = [];
  if (reviewers.length == 0)  // This function is a no-op if there are no reviewers.
    callback(failedItems);
  let project = /^((?:\w+-?)+(?:%2F|\/)(?:-?\w)+)/.exec(fullChangeID).pop();
  let branch = /~(.+)~/.exec(fullChangeID).pop();
  let doneCount = 0;
  function postReviewer(reviewer) {
    checkAccessRights(
      parentUuid, project, branch, reviewer, "read", customAuth,
      function (success, data) {
        if (!success) {
          doneCount++;
          logger.log(`Dropping reviewer ${reviewer} from cherry-pick to ${
            branch} because they can't view it.`, "info", parentUuid);
          logger.log(`Reason: ${data}`, "debug", parentUuid);
          failedItems.push(reviewer);
        } else {
          let url = `${gerritBaseURL("changes")}/${fullChangeID}/reviewers`;
          let data = { reviewer: reviewer };
          logger.log(
            `POST request to ${url}\nRequest Body: ${safeJsonStringify(data)}`,
            "debug", parentUuid
          );
          axios({ method: "post", url: url, data: data, auth: customAuth || gerritAuth })
            .then(function (response) {
              logger.log(
                `Success adding ${reviewer} to ${fullChangeID}\n${response.data}`,
                "info", parentUuid
              );
              doneCount++;
              if (doneCount == reviewers.length)
                callback(failedItems);
            })
            .catch(function (error) {
              doneCount++;
              if (doneCount == reviewers.length)
                callback(failedItems);
              if (error.response) {
                // The request was made and the server responded with a status code
                // that falls out of the range of 2xx
                logger.log(
                  `Error in POST to ${url} to add reviewer ${reviewer}: ${
                    error.response.status}: ${error.response.data}`,
                  "error", parentUuid
                );
              } else {
                logger.log(
                  `Error adding a reviewer (${reviewer}) to ${fullChangeID}: ${safeJsonStringify(error)}`,
                  "warn", parentUuid
                );
              }
              failedItems.push(reviewer);
            });
        }
      }
    );
  }

  // Not possible to batch reviewer adding into a single request. Iterate through
  // the list instead.
  setReadyForReview(parentUuid, fullChangeID, customAuth, function () {
    // Even if setting Ready fails, still attempt to post the reviewers.
    reviewers.forEach(postReviewer);
  });
}

exports.setReadyForReview = setReadyForReview;
function setReadyForReview(parentUuid, fullChangeID, customAuth, callback) {
  let url = `${gerritBaseURL("changes")}/${fullChangeID}/ready`;
  axios({ method: "post", url: url, data: {}, auth: customAuth || gerritAuth })
    .then(function (response) {
      logger.log(`Successfully set ready for review on change ${fullChangeID}`, "verbose", parentUuid);
      callback(true, undefined);
    })
    .catch(function (error) {
      if (error.response) {
        // 409 is expected if the change is not WIP.
        if (error.response.status == 409) {
          logger.log(`Change ${fullChangeID} is not WIP.`, "debug", parentUuid);
          callback(true, undefined);
        } else {
          // The request was made and the server responded with a status code
          // that falls out of the range of 2xx
          logger.log(
            `An error occurred in POST to "${url}". Error ${error.response.status}: ${
              error.response.data}`,
            "error", parentUuid
          );
          callback(false, error.response.status);
        }
      } else if (error.request) {
        // The request was made but no response was received
        callback(false, "retry");
      } else {
        // Something happened in setting up the request that triggered an Error
        logger.log(
          `UNKNOWN ERROR while setting ready for review on ${
            fullChangeID}: ${safeJsonStringify(error)}`,
          "error", parentUuid
        );
        callback(false, error.message);
      }
    });
}

// Copy reviewers from one change ID to another
exports.copyChangeReviewers = copyChangeReviewers;
function copyChangeReviewers(parentUuid, fromChangeID, toChangeID, customAuth, callback) {
  logger.log(`Copy change reviewers from ${fromChangeID} to ${toChangeID}`, "info", parentUuid);
  getChangeReviewers(parentUuid, fromChangeID, customAuth, function (success, reviewerlist) {
    if (success) {
      setChangeReviewers(parentUuid, toChangeID, reviewerlist, customAuth, function (failedItems) {
        if (callback)
          callback(true, failedItems);
      });
    } else {
      if (callback)
        callback(false, []);
    }
  });
}

// Locate an appropriate user to try adding as reviewer and to the attention set.
exports.locateDefaultAttentionUser = locateDefaultAttentionUser;
function locateDefaultAttentionUser(uuid, cherryPickChange, uploader, callback) {
  // Query the cherry-pick's original branch change to identify the original
  // author.
  let ReviewRegex = /^Reviewed-by: .+<(.+)>$/m;
  let commitMessage = "";
  let originalApprover = undefined;
  try {
    commitMessage = cherryPickChange.commitMessage || cherryPickChange.change.commitMessage;
    doMain();
  } catch {
    queryChange(uuid, cherryPickChange.fullChangeID || cherryPickChange.id, undefined, undefined,
       (success, data) => {
        commitMessage = data.revisions[data.current_revision].commit.message;
        doMain();
        }
    );
  }

  function doMain() {
    try {
      originalApprover = commitMessage.match(ReviewRegex)[1];
    } catch {
      logger.log(`Failed to locate a reviewer from commit message:\n${commitMessage}`,
      "warn", uuid);
    }
    if (originalApprover && originalApprover != uploader) {
      // The approver from the original change should be able to help.
      let project = typeof cherryPickChange.project === "string"
        ? cherryPickChange.project
        : cherryPickChange.change.project;
      let branch = cherryPickChange.branch
        ? cherryPickChange.branch
        : cherryPickChange.change.branch;
      checkAccessRights(uuid, project, branch, originalApprover,
        "read", undefined,
        (canRead) => {
          if (canRead)
            callback(originalApprover);
          else
            tryFallback(project, branch);
        }
      );
    } else {
      callback(uploader);
    }
  }

  function tryFallback(project, branch) {
    // This insane regex is the same as used in the commit message sanitizer,
    // So it should always find the right footer which references the
    // picked-from sha.
    let cherryPickRegex = /^\((?:partial(?:ly)? )?(?:cherry[- ]pick|(?:back-?)?port|adapt)(?:ed)?(?: from| of)?(?: commit)? (\w+\/)?([0-9a-fA-F]{7,40})/m;
    let originSha = undefined;
    try{
      originSha = commitMessage.match(cherryPickRegex)[2];
    } catch {
      // Seems this isn't a cherry-pick. Perhaps this is being called for a standalone change.
      logger.log(`Failed to match a cherry-pick footer for ${cherryPickChange.fullChangeID}`,
      "warn", uuid);
      originSha = cherryPickChange.change.current_revision || cherryPickChange.newRev;
    }
    queryChange(uuid, originSha, undefined, undefined,
      function(success, changeData) {
        if (success) {
          let originalAuthor = changeData.revisions[changeData.current_revision]
            .commit.author.email;
          if (uploader != originalAuthor) {
            // Add the author of the original change's final patchset to the
            // attention set of the cherry-pick.
            checkAccessRights(uuid, project, branch,
              originalAuthor, "read", undefined,
              (canRead) => {
                if (canRead)
                  callback(originalAuthor);
                else {
                  if (changeData.owner._account_id == 1007413 // Cherry-pick bot
                    && /^(tqtc(?:%2F|\/)lts-)/.test(changeData.branch)) {
                    // LTS release manager
                    callback(envOrConfig("TQTC_LTS_NOTIFY_FALLBACK_USER"));
                  } else {
                    // Now we have a problem. The uploader is the original author, but
                    // they also appear to have self-approved the original patch.
                    // Try to copy all the reviewers from the original change
                    // (hopefully there are some).
                    // Adding them as a reviewer will also add them to the attention set.
                    callback("copyReviewers", changeData.id);
                  }
                }
              });
            }
        } else {
          logger.log(`Failed to query gerrit for ${originSha}`, "error", uuid);
        }
      }
    );
  }
}

// Check permissions for a branch. Returns Bool.
exports.checkAccessRights = checkAccessRights;
function checkAccessRights(uuid, repo, branch, user, permission, customAuth, callback) {
  // Decode and re-encode to be sure we don't double-encode something that was already
  // passed to us in URI encoded format.
  repo = encodeURIComponent(decodeURIComponent(repo));
  branch = encodeURIComponent(decodeURIComponent(branch));
  let url = `${gerritBaseURL("projects")}/${repo}/check.access?account=${
    user}&ref=${encodeURIComponent('refs/for/refs/heads/')}${branch}&perm=${permission}`;
  logger.log(`GET request for ${url}`, "debug", uuid);
  axios
    .get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      // A successful response's JSON object has a status field (independent
      // of the HTTP response's status), that tells us whether this user
      // does (200) or doesn't (403) have the requested permissions.
      logger.log(`Raw Response: ${response.data}`, "debug", uuid);
      callback(JSON.parse(trimResponse(response.data)).status == 200, undefined)
    })
    .catch(function (error) {
      let data = ""
      if (error.response) {
        if (error.response.status != 403) {
          // The request was made and the server responded with a status code
          // that falls out of the range of 2xx and response code is unexpected.
          // However, a 403 response code means that the bot does not have permissions
          // to check permissions of other users, a much bigger problem.
          data = "retry";
        }
        logger.log(
          `An error occurred in GET to "${url}". Error ${error.response.status}: ${
            error.response.data}`,
          "error", uuid
        );
      } else {
        data = `${error.status}:${error.message}`;
        logger.log(
          `Failed to get ${permission} access rights on ${repo}:${branch}\n${
            safeJsonStringify(error)}`,
          "error", uuid
        );
      }
      callback(false, data);
    });
}

// Validate branch and check access in one action.
// Callback called with params (branchExists: bool,  PermissionAllowed: bool, data: str|undefined)
exports.checkBranchAndAccess = checkBranchAndAccess;
function checkBranchAndAccess(uuid, repo, branch, user, permission, customAuth, callback) {
 validateBranch(uuid, repo, branch, customAuth, function(success, data) {
    if (success && data != "retry") {
      logger.log(`${repo}:${branch} exists. Checking permissions...`, "info", uuid);
      checkAccessRights(uuid, repo, branch, user, permission, customAuth, function(hasRights, err) {
          callback(true, hasRights, hasRights ? data : err); // data from validateBranch contains a SHA.
      });
    } else {
      callback(false, false, data);
    }
  });
}

exports.findIntegrationIDFromChange = findIntegrationIDFromChange;
function findIntegrationIDFromChange(uuid, fullChangeID, customAuth, callback) {
  let url = `${gerritBaseURL("changes")}/${fullChangeID}/messages`;
  logger.log(`GET request for ${url}`, "debug", uuid);
  axios
    .get(url, { auth: customAuth || gerritAuth })
    .then(function (response) {
      // logger.log(`Raw Response: ${response.data}`, "silly", uuid);
      const messages = JSON.parse(trimResponse(response.data));
      messages.reverse();
      for (let i=0; i < messages.length; i++) {  // CI passed messages are usually near the end.
        if (messages[i].message.includes("Continuous Integration: Passed")) {
          // Capture the integration ID or return false.
          // Though a change with the above line should never *not*
          // have an IntegrationID
          try {
            callback(messages[i].message.match(/^Details:.+\/tasks\/(.+)$/m)[1], new Date(messages[i].date));
          } catch {
            callback(false);
          }
          break;
        }
      }
    })
    .catch((error) => {
      logger.log(`Failed to get IntegrationId for ${fullChangeID}\n${error}`, "error", uuid);
      callback(false);
    })
}
