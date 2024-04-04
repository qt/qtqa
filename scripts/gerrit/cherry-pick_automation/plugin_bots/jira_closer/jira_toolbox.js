// Copyright (C) 2022 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

/* eslint-disable no-unused-vars */
const safeJsonStringify = require("safe-json-stringify");
const OAuth = require("oauth").OAuth;
const { RateLimiter } = require("limiter");

const config = require("./config.json");
const { Version } = require("./version");
const Logger = require("../../logger");
const logger = new Logger();

const JIRAoauthUrl = `${envOrConfig("JIRA_URL")}/plugins/servlet/oauth/`;
const jira_oauth_token = envOrConfig("JIRA_OAUTH_TOKEN");
const jira_oauth_token_secret = envOrConfig("JIRA_OAUTH_TOKEN_SECRET");

const limiter = new RateLimiter({ tokensPerInterval: 5, interval: "second" });


function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}


// Build OAuth provider with authentication headers
const JIRAconsumer = new OAuth(
  `${JIRAoauthUrl}request-token`,
  `${JIRAoauthUrl}access-token`,
  envOrConfig("JIRA_OAUTH_CONSUMERKEY"),
  envOrConfig("JIRA_OAUTH_CONSUMERPRIVATEKEY"),
  "1.0",
  "",
  "RSA-SHA1"
);


// monkey-patch OAuth.get since it doesn't support content-type which is required by jira's API
OAuth.prototype.get = function(
  url,
  oauth_token,
  oauth_token_secret,
  callback,
  post_content_type
) {
  return this._performSecureRequest(
    oauth_token,
    oauth_token_secret,
    "GET",
    url,
    null,
    "",
    post_content_type,
    callback
  );
};
// end monkey-patch


// Simple class to describe a JIRA Update with JSON POST body.
class IssueUpdate {
  constructor(uuid, apiPath, body, callback, args) {
    this.uuid = uuid;
    this.apiPath = apiPath;
    this.body = body;
    this.callback = callback;
    this.callbackArgs = args || [];
  }
}

// Jira statuses don't update often. No TTL needed on this cache.
// Cache them to make checking against them faster and easier.
let statusCache = {}

// Queue Jira issue Updates to avoid multiple POST requests to the same issue at once.
// Note that it is still possible to lose data if a queued update
// touches the same fields but contains different data.
// Schema:
// {
//   [issueKey]: {
//     locked: bool,
//     updateQueue: array[IssueUpdate]
//   }
// }
let issueUpdateQueue = {};

// Note: The queue actually has a small memory leak since we never clean up issueID handles,
// But unless an additional lockout is added to updating the queue itself, we could lose
// work if the handle is cleaned up when it's empty at the same time that another
// incoming work item would be pushing to the array for the issueID.
// Since this bot is designed to run in Heroku with at least daily restarts,
// This memory leak is of least concern and is safe to operate as-is.
function enqueueIssueUpdate(issueId, issueUpdate) {
  if (issueUpdateQueue[issueId])
    issueUpdateQueue[issueId].updateQueue.push(issueUpdate);
  else
    issueUpdateQueue[issueId] = {locked: false, updateQueue: [issueUpdate]};
  callNextIssueUpdate(issueId);
}


// Check the queue and execute the next action.
function callNextIssueUpdate(issueId, takeNext) {
  // Return if already locked and not explicitly being called to take the next update.
  if (issueUpdateQueue[issueId].locked && !takeNext)
    return;
  issueUpdateQueue[issueId].locked = true;
  const nextUpdate = issueUpdateQueue[issueId].updateQueue.shift();
  if (!nextUpdate) {
    issueUpdateQueue[issueId].locked = false;
    return;
  }

  return new Promise(function(resolve, reject) {
    doJIRAPutPostRequest(nextUpdate.uuid, "PUT", nextUpdate.apiPath, nextUpdate.body)
    .then(data => {
      resolve(data);
    }).catch(err => {
      reject(err);
    }).finally(() => {
      callNextIssueUpdate(issueId, true);  // Call self and force taking the next item in queue.
      // Call the update's callback. Callback structure rather than promises here allow
      // the system to be agnostic to the items in queue and maintain process flow by
      // processing a callback rather than needing to return some real value directly.
      nextUpdate.callback(...nextUpdate.callbackArgs);
    });
  })
}


// Authenticated GET
async function doJIRAGetRequest(uuid, path) {
  await limiter.removeTokens(1);  // Wait for rate-limiting
  logger.log(`GET ${envOrConfig("JIRA_URL")}/rest/api/latest/${path}`, "debug", uuid);
  return new Promise(function(resolve, reject) {
    JIRAconsumer.get(
    `${envOrConfig("JIRA_URL")}/rest/api/latest/${path}`,
    jira_oauth_token,
    jira_oauth_token_secret,
    function(error, data) {
      if (error) {
        console.log(error);
        reject(error)  // error
      } else {
        try {
          data = JSON.parse(data);
          resolve(data);
        } catch (error) {
          console.log(error);
          reject(error);
        }
      }
    },
    "application/json"
    );
  });
}


// Authenticated PUT or POST
async function doJIRAPutPostRequest(uuid, method, path, body) {
  // Wait for rate-limiting
  await limiter.removeTokens(1);
  const url = `${envOrConfig("JIRA_URL")}/rest/api/latest/${path}`;
  logger.log(`${method} ${url}`, "debug", uuid);
  return new Promise(function(resolve, reject) {
    // console.log("JIRA_URL", "PutPostRequest disabled");
    // resolve();
    // return;
    JIRAconsumer[method.toLowerCase()](
    url,
    jira_oauth_token,
    jira_oauth_token_secret,
    safeJsonStringify(body),
    "application/json",
    function(error, result, response) {
      if (error) {
        logger.log(`Error in ${method} request to ${url}: ${error}`, "error", uuid);
        reject(error);
        return;
      }
      // 201 Created / 204 No Content are the expected responses for PUT and POST requests.
      if ([201, 204].includes(response.statusCode))
        resolve();
      else {
        logger.log(`Error in ${method} request to ${url}: ${result}`, "error", uuid);
        reject(result);
      }
    });
  });
}


// Query an issue in Jira to get detailed data about it.
function queryIssue(uuid, issueId) {
  return doJIRAGetRequest(uuid, `issue/${issueId}`);
}


// Query for multiple issue IDs at the same time.
function queryManyIssues(uuid, issueIds) {
  return new Promise(function(resolve, reject) {
    if (issueIds.length == 0) {
      resolve([]);  // No need to query if no issues were passed.
      return;
    }
    doJIRAGetRequest(uuid, `search/?jql=Issuekey%20in%20(${issueIds.toString()})&expand=changelog`)
    .then((res) => {
      if (res.errorMessages) {
        reject(res.errorMessages);
      } else {
        resolve(res.issues);
      }
    });
  });
}


// Collect the list of Projects in Jira with some basic info about them.
// *Part of the startup routine.
function getProjectList(uuid) {
  return new Promise(function(resolve, reject) {
    let projects = [];
    doJIRAGetRequest(uuid, "project")
    .then((data) => {
      for (const project of data)
        projects.push(project.key);
      resolve(projects);
    })
  })
}


// Try to match a qt-style version number like 6.15.3
function parseVersion(versionString) {
  "Returns an array of [FullMatch, match 1, match 2, match 3] or null"
  return /^(\d+)\.(\d+)\.(\d+)/.exec(versionString);
}


// Query Jira for the possible versions of an issue. This is based on the IssueType
// such as QTBUG, QTCREATORBUG, etc.
function getVersionsForIssue(uuid, issueId) {
  return new Promise((resolve, reject) => queryIssue(uuid, issueId)
  .then((data) => {
    doJIRAGetRequest(uuid, `issue/createmeta/${data.fields.project.id}/issuetypes/${data.fields.issuetype.id}?expand=projects.issuetypes.fields`)
    .then((metadata) => {
      let versions = {};
      let jiraVersions;
      // The version list can exist in two places, depending on the project.
      const fixVersions = metadata.values.find(element => element.fieldId == "fixVersions");
      if (versions)
        jiraVersions = fixVersions.allowedValues;
      else {
        const versions = metadata.values.find(element => element.fieldId == "versions");
        if (versions)
          jiraVersions = fixVersions.allowedValues;
      }
      if (!jiraVersions) {
        reject(`No versions for Issue Type "${data.fields.issuetype.name}"`);
        return;
      }
      let lastVersion = null;
      let otherLikeVersions = [];
      for (let i in jiraVersions) {
        const thisVer = jiraVersions[i];
        const parsedVersion = parseVersion(thisVer.description) || parseVersion(thisVer.name);
        if (!parsedVersion)  // Only include versions which begin with a numeric branch name.
          continue;
        // Description is preferred for legacy reasons. Nomenclature and bot usage of
        // the description field states that it *must* start with the bare numerical branch
        // name. Fall back to using Name if someone forgot to set description.
        let version = {
          id: thisVer.id,
          description: thisVer.description || thisVer.name,
          parsedVersion: new Version(parsedVersion),
          archived: thisVer.archived,
          released: thisVer.released,
          startDate: thisVer.startDate,
          releaseDate: thisVer.releaseDate,
        };

        // The last version to be iterated will always be the plain version number,
        // i.e. 6.2.0, rather than 6.2.0 Beta 1. Attach all versions to it
        // as "otherVersions" so that we can choose the most appropriate version
        // later once we have the target narrowed down.
        if (lastVersion && lastVersion != parsedVersion[0]) {
          versions[lastVersion].otherVersions = otherLikeVersions.map(item => ({...item}));
          otherLikeVersions = [];  // Zero the array since we're on a new version now.
        }
        if (i == jiraVersions.length - 1) {
          // This version is the last in the array. Attach the otherVersions array directly,
          // and add self to the otherVersions since it's the last iteration.
          otherLikeVersions.push(version);
          version.otherVersions = otherLikeVersions.map(item => ({...item}));
        }

        otherLikeVersions.push(version);
        versions[parsedVersion[0]] = version;
        lastVersion = parsedVersion[0];
      }
      resolve({ success: true, versions: versions });
    }).catch(err => {logger.log(safeJsonStringify(err), "error", uuid); reject(err);});
  }).catch(err => {logger.log(safeJsonStringify(err), "error", uuid); reject(err);})
  );
}

function queryJQL(uuid, jql) {
  return new Promise(function(resolve, reject) {
    doJIRAGetRequest(uuid, `search?jql=${jql}`)
    .then((data) => {
      resolve(data);
    })
    .catch((err) => {
      reject(err);
    });
  });
}


// Try to update the list of Fix Versions in jira.
function updateFixVersions(uuid, issueId, fixVersion, callback) {
  // Pull the issue data first to get the current fix versions.
  queryIssue(uuid, issueId).then((issueData) => {
    let fixVersions = issueData.fields.fixVersions;
    const thisFixVersion = fixVersion.toString();
    if (fixVersions.find(f => f.id === thisFixVersion)) {
      logger.log(`FIXES: Issue ${issueId} already has fixVersion ${thisFixVersion}`, "debug", uuid);
      callback(false);
      return;
    }
    // Add the new fix version to the list of fix versions returned by jira for this issue.
    fixVersions.push({
      id: fixVersion.toString()
    });
    const newData = {
      fields: {
        fixVersions: fixVersions
      }
    }
    logger.log(`FIXES: Requesting Update of FixVersions on ${issueId}:`
     + ` ${safeJsonStringify(fixVersions)}`, "verbose", uuid);
    enqueueIssueUpdate(issueId,
      new IssueUpdate(uuid, `issue/${issueId}`, newData, callback, [true]));
  })
  .catch(err => logger.log(safeJsonStringify(err).length > 2 ? safeJsonStringify(err) : err,
                  "error", uuid));
}


function updateCommitField(uuid, issueId, commit, branch, callback) {
  queryIssue(uuid, issueId).then((issueData) => {
    const originalCommits = issueData.fields.customfield_10142;
    let newCommits = [];
    if (originalCommits && originalCommits.length >= 7)  // Single min-length sha
      newCommits = originalCommits.split(', ');
    if (newCommits.find(c => c.includes(commit.slice(0,7)))) {
      logger.log(`COMMIT: Issue ${issueId} already has commit ${commit}`, "debug", uuid);
      callback(false);
      return;
    }
    // Add the new commit in the format "abc1234 (dev)"
    newCommits.push(`${commit.slice(0,9)} (${branch})`);
    if (newCommits.join(', ').length > 255) {
      // Still longer than 255, there's simply too many shas to list.
      // Holy smokes that's a big bug, but there's nothing we can do
      // other than start dropping commits from the list.
      while (newCommits.join(', ').length > 255)
        newCommits.pop();
    }
    newCommits = newCommits.join(', ');
    const newData = {
      fields: {
        customfield_10142: newCommits
      }
    }
    logger.log(`COMMIT: Requesting Update of Commits on ${issueId}: ${newCommits.toString()}`,
      "verbose", uuid);
    enqueueIssueUpdate(issueId,
      new IssueUpdate(uuid, `issue/${issueId}`, newData, callback, [true]));

  })
  .catch(err => {
    logger.log(safeJsonStringify(err).length > 2 ? safeJsonStringify(err) : err, "error", uuid);
    callback();
  });
}


// Internal function used at startup to read status data from Jira. This should
// very, very rarely change, so it's safe to cache until next bot restart.
function updateStatusCache() {
  return new Promise((resolve, reject) => doJIRAGetRequest("JIRA", "status")
  .then(statuses => {
    statusCache = statuses;
    resolve()
  }))
  .catch(err => logger.log(safeJsonStringify(err).length > 2 ? safeJsonStringify(err) : err,
                  "error", "JIRA"));
}


// Determine if an issue has been closed by jirabot before.
function wasClosedByJiraBot(issue) {
  // Filter comments by qtgerritbot. Then filter again by if the bot made a status change.
  // The bot only ever closes issues, so it is safe to not be specific here.
  return issue.changelog.histories.filter(h =>
    h.author.key === "qtgerritbot"
    && h.items.filter(i => i.field === "status" && isStatusDoneCategory(i.to)).length > 0
  ).length > 0;
}


// Determine if the bot has posted a given message on the ticket already.
function botHasPostedMessage(uuid, issue, message) {
  return new Promise((resolve, reject) => {
    doJIRAGetRequest(uuid, `issue/${issue.key}/comment`)
    .then(issueData => {
      resolve(issueData.comments.filter(m =>
        m.author.key === "qtgerritbot"
        && m.body.includes(message)).length > 0
      );
      }
    );
  });
}


function isStatusDoneCategory(statusNumber) {
  // statusCategory of "3" is the "Done" category. This will never change.
  return statusCache.find(s => s.id == statusNumber && s.statusCategory.id === 3);
}


// Pull the transition list from jira for a particular issue.
// Not every transition is available in every project or current issue status,
// so the list needs to be pulled for each unique issue at time of need.
function getTransitions(uuid, issueId) {
  return doJIRAGetRequest(uuid, `issue/${issueId}/transitions`);
}


// Perform a Close transition on a jira issue.
function closeIssue(uuid, issue, change, callback) {
  getTransitions(uuid, issue.key).then((possibleTransitions) => {
    // Filter transitions to only those which end in a Done category status.
    possibleTransitions = possibleTransitions.transitions.filter(t =>
                                                                 isStatusDoneCategory(t.to.id));
    // Select the suitable Done type transition.
    const transition = possibleTransitions.find(t => ["Fixed", "Done", "Close"].includes(t.name));
    if (!transition) {  // No suitable Done type transitions were present.
      const msg = `CLOSER: ${issue.key} already closed.`
      logger.log(msg, "verbose", uuid);
      callback(msg);
      return;
    }
    logger.log(`CLOSER: Closing issue ${issue.key} with transition ${transition.name}`,
      "info", uuid);
    let body = {
      "transition": {
        "id": transition.id
      },
      "cause": {  // These fields are required, but the values are arbitrary.
        "id": "ChangeMerged",
        "type": "ChangeMerged-event"
    }
    }
    doJIRAPutPostRequest(uuid, "POST", `issue/${issue.key}/transitions`, body)
    .then(() => {
      const msg = `CLOSER: Successfully closed ${issue.key}.`;
      logger.log(msg, "info", uuid);
      callback(msg);
    })
    .catch(err => {
      let error = safeJsonStringify(err).length > 2 ? safeJsonStringify(err) : err;
      logger.log(error, "error", "JIRA");
      callback(error);
    });
  })
}

// Post a simple comment to a jira issue
function postComment(uuid, issueId, comment) {
  const body = {
    "body": comment
  }
  doJIRAPutPostRequest(uuid, "POST", `issue/${issueId}/comment`, body);
}


module.exports = { queryManyIssues, getVersionsForIssue, getProjectList, queryJQL, updateFixVersions,
   updateCommitField, updateStatusCache, wasClosedByJiraBot, botHasPostedMessage, closeIssue, postComment };
