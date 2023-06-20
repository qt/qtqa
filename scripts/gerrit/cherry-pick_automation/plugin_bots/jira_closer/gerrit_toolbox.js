// Copyright (C) 2022 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

const Axios = require("axios");
const axiosRateLimit = require("axios-rate-limit")
const { setupCache, buildMemoryStorage,
  defaultKeyGenerator, defaultHeaderInterpreter } = require('axios-cache-interceptor');
const moment = require("moment");
const ConfigIniParser = require("config-ini-parser").ConfigIniParser;

const gerritTools = require("../../gerritRESTTools");
const Logger = require("../../logger");
const logger = new Logger();
const config = require("./config.json");
const res = require("express/lib/response");


function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

let gerritURL = envOrConfig("JIRA_GERRIT_URL");
let gerritPort = envOrConfig("GERRIT_PORT") || 443;
let gerritResolvedURL = /^https?:\/\//g.test(gerritURL)
  ? gerritURL
  : `${gerritPort == 80 ? "http" : "https"}://${gerritURL}`;
gerritResolvedURL += gerritPort != 80 && gerritPort != 443 ? ":" + gerritPort : "";
let gerritAuth = {
  username: envOrConfig("JIRA_GERRIT_USER"),
  password: envOrConfig("JIRA_GERRIT_PASSWORD")
};

// Boilerplate from https://axios-cache-interceptor.js.org/#/pages/configuration
const axios = setupCache(
  // axios instance
  axiosRateLimit(Axios.create(), { maxRPS: 20 }),

  // All options with their default values
  {
    // The storage to save the cache data. There are more available by default.
    //
    // https://axios-cache-interceptor.js.org/#/pages/storages
    storage: buildMemoryStorage(),

    // The mechanism to generate a unique key for each request.
    //
    // https://axios-cache-interceptor.js.org/#/pages/request-id
    generateKey: defaultKeyGenerator,

    // The mechanism to interpret headers (when cache.interpretHeader is true).
    //
    // https://axios-cache-interceptor.js.org/#/pages/global-configuration?id=headerinterpreter
    headerInterpreter: defaultHeaderInterpreter,

    // The function that will receive debug information.
    // NOTE: For this to work, you need to enable development mode.
    //
    // https://axios-cache-interceptor.js.org/#/pages/development-mode
    // https://axios-cache-interceptor.js.org/#/pages/global-configuration?id=debug
    debug: undefined
  }
);

// Return a promise for validateBranch, which normally requires a callback.
const promisedVerifyBranch = async function (uuid, project, branch, branchesCache) { //, expandSearch) {
  return new Promise((resolve) => {
    // 5.0 branch predates gerrit, and some projects did not start with 6.0
    // However, it is expected that all projects with 5.x or 6.x branches should
    // be based on a X.0 release.
    if (branch == "5.0" || branch == "6.0") {
      resolve(true);
      return;
    }
    try {
      // Cached branches will resolve with a Moment of the branch creation.
      const branchDate = branchesCache[project][branch];
      if (branchDate) {
        resolve(branchDate);
        return;
      }
    }
    catch (e) {}  // Expected if we don't have the branch cached.
    // If we don't have the branch cached, we need to fetch it.
    gerritTools.validateBranch(uuid, project, branch, gerritAuth,
      function(success, data) {
        if (success) {
          resolve(data);
        } else {
          resolve(false);
        }
      }
    );
  });
}

// Get the inheritance of a repo
async function getAccessInheritanceRepo(uuid, repo) {
  let data;
  const url = `${gerritResolvedURL}/a/projects/${encodeURIComponent(repo)}/access`;
  try {
    logger.log(url, "verbose", uuid);
    const resp = await axios.get(url, { auth: gerritAuth })
    data = JSON.parse(gerritTools.trimResponse(resp.data));
  } catch(e) {
    logger.log(e, "error", uuid);
    return false;  // safely catch if we requested an invalid repo
  }
  if (data.inherits_from && data.inherits_from.id) {
    return data.inherits_from.id;
  } else {
    // No further inheritance exists, this is a top-level repo.
    return false;
  }
}


async function repoUsesCherryPicking(uuid, repo) {
  let data;
  const url = `${gerritResolvedURL}/a/projects/${encodeURIComponent(repo)}`
    + `/branches/refs%2Fmeta%2Fconfig/files/webhooks.config/content`;
  logger.log(url, "debug", uuid);
  const resp = await axios.get(url, { auth: gerritAuth })
  .catch(error => {
    if (error.response && error.response.status == 404)
      return error;  // expected, but we have to catch the error safely.
    else
      throw(error);  // Something else failed and should fall through.
  });
  if (resp.status == 200) {
    // Can only call parse once on the object, so create it here instead of globally.
    const iniParser = new ConfigIniParser();
    data = iniParser.parse(Buffer.from(resp.data, 'base64').toString('ascii'));
    if (data.isHaveSection('remote "qt-cherry-pick-bot"'))
      return true;
  }
  // Not cherry-picking at this repo level. Check parent repo.
  const parentRepo = await getAccessInheritanceRepo(uuid, repo);
  if (parentRepo)
    return repoUsesCherryPicking(uuid, parentRepo)
  else
    return false;  // Could not find any parent repo with webhooks.yaml
}

// Check to see what branch a commit appears in.
// Useful when a change in included in a branching event such as 6.4 -> 6.4.2
async function getCommitInBranches(uuid, repo, commit) {
  let data;
  const url = `${gerritResolvedURL}/a/projects/${encodeURIComponent(repo)}/commits/${commit}/in`;
  try {
    logger.log(url, "verbose", uuid);
    const resp = await axios.get(url, { auth: gerritAuth });
    data = JSON.parse(gerritTools.trimResponse(resp.data));
    return data.branches;
  } catch(e) {
    logger.log(e, "error", uuid);
    return [];  // Default to thinking this is a Qt/ based change?
  }
}


// Query $JIRA_BACKLOG_DAYS worth of merged issues.
async function getChangesWithFooter(uuid, queryOverride) {
  const days = Number(process.env.JIRA_BACKLOG_DAYS);
  if ((!days || days < 1) && !queryOverride)
    return [];
  const age = moment().subtract(days, 'days').format('YYYY-MM-DD');
  const querystring = queryOverride || `(message:"\nFixes: .+$" OR message:"\nTask-Number: .+$")`
    + `+AND+status:merged+AND+mergedafter:${age}&o=CURRENT_REVISION&o=CURRENT_COMMIT&no-limit`;
    // + `+AND+status:merged+AND+mergedafter:2023-07-06+mergedbefore:2023-07-08&o=CURRENT_REVISION&o=CURRENT_COMMIT`;
    // + `+AND+commit:7d426b6226aa052f1dbbdc08a0b67dae8ba115e0&o=CURRENT_REVISION&o=CURRENT_COMMIT`
  const url = `${gerritResolvedURL}/a/changes/?q=${querystring}`;
  try {
    logger.log(url, 'debug', uuid);
    const resp = await axios.get(url, { auth: gerritAuth });
    let data = JSON.parse(gerritTools.trimResponse(resp.data));
    return data;
  } catch(e) {
    console.log(e);
    return [];
  }
}

module.exports = { promisedVerifyBranch, repoUsesCherryPicking, getCommitInBranches,
  getChangesWithFooter };
