/* eslint-disable no-unused-vars */
// Copyright (C) 2022 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

exports.id = "jira_closer";

const safeJsonStringify = require("safe-json-stringify");
const uuidv1 = require("uuidv1");
const moment = require("moment");
const net = require("net");
const express = require("express");
const toBool = require("to-bool");

const gerritTools = require("../../gerritRESTTools");
const Logger = require("../../logger");
const logger = new Logger();
const SQL = require("../../postgreSQLClient");
const { Version, filterVersions, makeVersionGenerator } = require("./version");
const { getVersionsForIssue, queryManyIssues, getProjectList, queryJQL, updateCommitField,
  updateFixVersions, updateStatusCache, closedByChangeId,
  botHasPostedMessage, closeIssue, reopenIssue, postComment } = require("./jira_toolbox");
const { promisedVerifyBranch, repoUsesCherryPicking,
  getCommitInBranches, getChangesWithFooter } = require("./gerrit_toolbox");
const config = require("./config.json");

let gerritAuth = {
  username: envOrConfig("JIRA_GERRIT_USER"),
  password: envOrConfig("JIRA_GERRIT_PASSWORD")
};

// Cache of branches from the database for each project.
// Used to determine if a branch has been encountered before.
let branchesCache = {};


function envOrConfig(ID) {
  return process.env[ID] || config[ID];
}

// Regex to parse out footers
const footerRe = new RegExp(/^(?:Fixes:|Resolves:|Task-number:|Relates:|Reopens:) (.+)$/gm);
const revertRe  = new RegExp(/^This reverts commit ([0-9a-f]{40})\./m);
// Cache a list of projects, initialized on construction of the jira_closer class.
let projectList = [];


// Try to parse a base qt version of major.feature.release, where release is optional.
// Any tqtc/lts- prefix is ignored for plain version matching.
function parseVersion(version) {
  return /^(?:tqtc\/lts-)?(\d+)\.(\d+)(?:\.(\d+))?/.exec(version);
}

// The change was committed to a version which is expected to already be a final release
// version. Search Jira versions for the best match.
function findClosestVersionMatch(uuid, branch, issueId) {
  return new Promise(function(resolve, reject) {
    getVersionsForIssue(uuid, issueId).then((data) => {
      let possibleVersions = filterVersions(data.versions, branch, false);
      if (!possibleVersions.length) {
        // No unreleased versions for this commit were found.
        // Expand the search to released versions, treating this as though it's a
        // hotfix for an already released version.
        possibleVersions = filterVersions(data.versions, branch, true);
      }
      // Take the most recent version of the released fix versions.
      resolve(possibleVersions[Object.keys(possibleVersions).shift()]);
    })
    .catch(error => {
      reject(error);
    })
  });
}

function collectIssueIdsFromChange(change, callback) {
  let issueIds = new Set();  // Collect work to do for this change here.
  const message = change.revisions[change.current_revision].commit.message;
  let footers = message.matchAll(footerRe);
  for (const footer of footers) {  // Handle multiple lines of footers
    const line = footer[1].split(); // Handle multiple targets on one line as well
    for (const key of line) {
      // All Jira tickets follow the format KEY-1234
      // Capture the KEY and make sure it's a valid project.
      let fixTargetMatch = key.match(/(.+)-/);
      if (!projectList.includes(fixTargetMatch[1])) {
        logger.log(`FIXES: Ignoring ${key} as it is not a valid project.`, "debug", "DEBUG");
      }
      if (fixTargetMatch && projectList.includes(fixTargetMatch[1])) {
        issueIds.add(key);
      }
    }
  }

  let revertMatch = revertRe.exec(message);
  if (revertMatch) {
    // Also collect any issue ids from possible reverted commit.
    let revertedSha = revertMatch[1];
    gerritTools.queryProjectCommit(change.uuid, change.project, revertedSha, gerritAuth, (success, commit) => {
      if (!success) {
        logger.log(`Failed to query for reverted commit ${revertedSha}: ${safeJsonStringify(commit)}`, "error", change.uuid);
        callback(Array.from(issueIds));
        return;
      } else {
        let footers = commit.message.matchAll(footerRe);
        for (const footer of footers) {  // Handle multiple lines of footers
          const line = footer[1].split(); // Handle multiple targets on one line as well
          for (const key of line) {
            // All Jira tickets follow the format KEY-1234
            // Capture the KEY and make sure it's a valid project.
            let fixTargetMatch = key.match(/(.+)-/);
            if (fixTargetMatch && projectList.includes(fixTargetMatch[1])) {
              issueIds.add(key);
            }
          }
        }
        callback(Array.from(issueIds));
      }
    })
  } else {
    callback(Array.from(issueIds));
  }
}


// Narrow down possible fix versions based on the branch the change was committed to.
// For repos which use use the cherry-picking model, it is correct to choose
// the next numerical branch which does not exist in gerrit, but has a fix version in Jira.
// For forward-merging repos, the latest existing but unreleased and not-started branch
// should be chosen as the fix version. If none can be found, fall back to the next
// non-existing branch as for cherry-picking repos.
async function findNextRelease(uuid, project, branch, mergeDate, usesCherryPicking, issueId) {
  logger.log(`FIXES: Searching for the next release release related to ${branch}`, "verbose", uuid);
  let prefixRe = /^(tqtc\/lts-|lts-)/;
  let match = prefixRe.exec(branch);
  let prefix = match ? match[0] : "";
  // Recurse through branches in the generator and locate the desired branch.
  // Passing negativeSearch=true searches for the next non-existent branch.
  // Otherwise, the highest existing branch is passed to callback().
  function checkNextBranch(thisBranch, generator, negativeSearch, lastFound, callback) {
    if (thisBranch.done) {  // "done" is set on on a generator when it runs out of items.
      if (negativeSearch) {
        // Negative search was requested, but all fix versions were found as branches in gerrit.
        callback(false);
      } else {
        callback(lastFound);
      }
      return;
    }
    // Allow for plain branches or Version objects equally,
    // but any value passed to thisBranch must be an object resulting from generator.next();
    let tempBranch = thisBranch.value.parsedVersion || thisBranch.value;
    let querybranch = prefixRe.test(tempBranch) ? tempBranch : `${prefix}${tempBranch}`;
    promisedVerifyBranch(uuid, project, querybranch, branchesCache)
    .then((validBranch) => {
      // Treat branches created after the merge date as non-existent. This makes the branch
      // a valid fix target since it would not have existed at the time of merging.
      if (validBranch && (moment.isMoment(validBranch) ? validBranch.isBefore(mergeDate) : true)) {
        logger.log(`FIXES: Found existing branch ${querybranch}`, "debug", uuid);
        lastFound = thisBranch.value;
        checkNextBranch(generator.next(), generator, negativeSearch, lastFound, callback);
      } else {
        logger.log(`FIXES: Couldn't find ${querybranch}, or it was created after the merge date.`,
          "debug", uuid);
        if (negativeSearch) {
          // If we couldn't find the x.x.0 release, check to make sure a feature
          // branch doesn't exist yet, either.
          // Only applies to changes on dev-like branches.
          if (tempBranch.patch == 0 && ["dev", "master"].includes(branch)) {
            let mainBranch = `${tempBranch.major}.${tempBranch.minor}`;
            promisedVerifyBranch(uuid, project, mainBranch, branchesCache)
              .then((mainBranchExists) => {
                if (mainBranchExists && (moment.isMoment(mainBranchExists) ? mainBranchExists.isBefore(mergeDate) : true)) {
                  logger.log(`FIXES: Found ${mainBranch}. Moving on...`, "debug", uuid);
                  checkNextBranch(generator.next(), generator, negativeSearch, lastFound, callback);
                } else {
                  logger.log(`FIXES: Couldn't find ${mainBranch}.`, "debug", uuid);
                  callback(thisBranch.value);  // Stop at the first not-found branch.
                }
              });
            } else {
              callback(thisBranch.value);  // Looking at a specific branch already.
            }
        } else {
          // !negativeSearch
          checkNextBranch(generator.next(), generator, negativeSearch, lastFound, callback);
        }
      }
    }).catch((error) => {
      logger.log(`Error verifying branch ${querybranch}: ${error}`, "error", uuid);
      callback(false);
    });
  }

  let highestVer = new Version();  // Track the highest version found.
  return new Promise(function(resolve, reject) {
    getVersionsForIssue(uuid, issueId).then((data) => {  // Get Jira versions
      if (data.success) {
        if (["dev", "master"].includes(branch)) {
          let majors = new Array;  // Track the Major versions i.e. 5.0, 6.0
          for (const key in data.versions) {
            if (data.versions[key].released || data.versions[key].archived)
              continue; // ignore released versions for now.
            const thisVer = data.versions[key].parsedVersion;
            if (thisVer.major > highestVer.major) {
              majors.push(`${Number(thisVer.major)}.0`);  // Assume every major has a .0 release
              highestVer = data.versions[key].parsedVersion;
            }
          }

          // Iterate through the major versions to figure out the latest Major release and
          // filter down possible fix versions to only the relevant major release.
          logger.log(`FIXES: Found major branches ${safeJsonStringify(majors)}`
            + ` for ${issueId} on ${branch}`, "verbose", uuid);
          const versionGenerator = makeVersionGenerator(majors);
          let patch = versionGenerator.next();
          checkNextBranch(patch, versionGenerator, !usesCherryPicking, undefined, (version) => {
            // Either the versionGenerator was empty, or no version was found after recursing.
            // This would be strange here since we're looking at major versions only...
            if (patch.done === true || !version) {
              reject();
              return;
            }
            // Filter down the found versions to ones that match our major version
            // which have a .0 release
            let filteredVersions = filterVersions(data.versions, `${version.split('.')[0]}.\\d+.0`);
            if (filteredVersions) {
              resolve(filteredVersions);
              return;
            }
            // If no .0 releases were found for any of the major versions,
            // try filtering down to all minor versions and resolve that.
            filteredVersions = filterVersions(data.versions, `${version.split('.')[0]}.\\d+`);
            if (filteredVersions) {
              resolve(filteredVersions);
              return;
            }
          });
        } else {  // Branch is already specific, i.e. "6.4", filter to only those fix versions.
          resolve(filterVersions(data.versions, branch));
        }
      }
    })
    .catch(error => {
      reject(error);
    });
  }).then((possibleVersions) => {
    // Now we presumably have a list of possible versions based on the originally committed branch.
    logger.log(`FIXES: possibleVersions: ${safeJsonStringify(possibleVersions)}`, "verbose", uuid);
    // Begin filtering again and testing branches' existence
    // based on the possible fix versions available for the given project in jira.
    const versionGenerator = makeVersionGenerator(possibleVersions);
    return new Promise(function(resolve, reject) {
      let patch = versionGenerator.next();
      if (patch.done) {  // No possibleVersions were passed!
        reject();
        return;
      }
      checkNextBranch(patch, versionGenerator, usesCherryPicking, undefined, (version) => {
        if (version) {
          resolve(version);  // Found a best-possible fix version! Hooray!
        } else if (!usesCherryPicking) {
          // Then maybe only minor branches exist in this forward-merging repo.
          // Test for the branch's existence from the first possible fix version.
          // If it exists, that's the fix version we want to use.
          promisedVerifyBranch(uuid, project,
            `${patch.value.parsedVersion.major}.${patch.value.parsedVersion.minor}`)
          .then((validBranch) => {
            if (validBranch)
              resolve(patch.value);
            else {
              // The previous major release is marked as "Released" in jira, but we
              // can't find a next version branch yet. Go with the next major
              // release version tag we found in jira for now.
              resolve(patch.value);
            }
          });
        } else {
          // Still Unable to determine fix version because while at least one unreleased
          // fix version exists in Jira, bugfix branches exist for all possible release
          // versions, which should not be the case.
          logger.log("FIXES: All available versions have been released prior to merge date."
          + " No unreleased versions available.", "info", uuid);
          reject();
        }
      });
    });
  }).then((version) => {
    // We have a general fix version, select the correct sub-version like Beta or RC.
    logger.log(`FIXES: Found fix version ${version.description}`, "verbose", uuid);
    return new Promise(function(resolve, reject) {
      let possibleVersions = filterVersions(version.otherVersions, version.description, false);
      resolve(possibleVersions[Object.keys(possibleVersions).shift()]);
    });
  }).catch(error => {
    logger.log(`Unable to find next release for ${issueId} on ${branch}: ${error}`, "error", uuid);
    return new Promise(function(resolve, reject) {
      reject("Unable to find next release");
    })
  })
  .catch(error => {
    logger.log(`Unable to retrieve versions from JIRA... ${error}`, "error", uuid);
    return new Promise(function(resolve, reject) {
      reject("Unable to retrieve versions from JIRA");
    })
  })
}


// Examine historical versions and choose the correct one for when the change merged.
function CheckAlreadyReleased(uuid, change, usesCherryPicking, issueId) {
  const mergeDate = moment(change.submitted);
  logger.log(`FIXES: Change was merged ${mergeDate.fromNow()}. Looking at already released versions.`,
    "verbose", uuid);
  return new Promise(function(resolve, reject) {
    getVersionsForIssue(uuid, issueId).then((data) => {  // Get Jira versions
      if (data.success) {
        SQL.pool.query(`SELECT * FROM jira_branches WHERE project = '${change.project}' AND first_seen > '${mergeDate.format("YYYY-MM-DD HH:mm:ss")}' ORDER BY first_seen`, (err, result) => {
          const rows = result.rows;
          if (err) {
            logger.log(`FIXES: Error querying for branches after merge date: ${err}`, "error", uuid);
            reject();
          } else if (rows.length > 0) {
            logger.log(`FIXES: Found branches after merge date (${mergeDate.format()}): ${safeJsonStringify(rows)}`, "verbose", uuid);
            if (["dev", "master"].includes(change.branch)) {
              let found = false;
              for (const row of rows) {
                if (row.branch.split(".").length === 2) {
                  // Take the first feature version we find after the merge date.
                  logger.log(`FIXES: Found a feature branch after merge date: ${row.branch}`, "verbose", uuid);
                  let filteredVersions = filterVersions(data.versions, row.branch, true, mergeDate);
                  if (!Object.keys(filteredVersions).length) {
                    logger.log(`FIXES: No viable jira version found for ${row.branch} in ${change.project}.`, "verbose", uuid);
                    reject();
                    break;
                  }
                  filteredVersions = filterVersions(filteredVersions[Object.keys(filteredVersions).shift()].otherVersions, row.branch, true, mergeDate);
                  resolve(filteredVersions[Object.keys(filteredVersions).shift()]);
                  found = true;
                  break;
                }
              }
              if (!found) {
                logger.log(`FIXES: No branches found after merge date, using unreleased versions`, "verbose", uuid);
                findNextRelease(uuid, change.project, change.branch, mergeDate, usesCherryPicking, issueId)
                .then((version) => {
                  resolve(version);
                }
                ).catch(error => {
                  reject(error);
                });
              }
            } else {
              const changeVer = new Version(parseVersion(change.branch));
              let found = false;
              for (const row of rows) {
                const thisVer = new Version(parseVersion(row.branch));
                if (changeVer.major === thisVer.major && changeVer.minor === thisVer.minor) {
                  // Take the first release version we find after the merge date.
                  logger.log(`FIXES: Found a release branch after merge date: ${row.branch}`, "verbose", uuid);
                  let filteredVersions = filterVersions(data.versions, row.branch, true, mergeDate);
                  if (!Object.keys(filteredVersions).length) {
                    logger.log(`FIXES: No viable jira version found for ${row.branch} in ${change.project}.`, "verbose", uuid);
                    reject();
                    break;
                  }
                  filteredVersions = filterVersions(filteredVersions[Object.keys(filteredVersions).shift()].otherVersions, row.branch, true, mergeDate);
                  resolve(filteredVersions[Object.keys(filteredVersions).shift()]);
                  found = true;
                  break;
                }
              }
              if (!found) {
                logger.log(`FIXES: No branches related to ${change.branch} found after merge date,`
                  +` filtering to this branch instead`, "verbose", uuid);
                let filteredVersions = filterVersions(data.versions, change.branch, true, mergeDate);
                if (!Object.keys(filteredVersions).length) {
                  logger.log(`FIXES: No viable jira version found for ${change.branch} in ${change.project}.`, "verbose", uuid);
                  reject();
                  return;
                }
                filteredVersions = filterVersions(filteredVersions[Object.keys(filteredVersions).shift()].otherVersions, change.branch, true, mergeDate);
                resolve(filteredVersions[Object.keys(filteredVersions).shift()]);
              }
            }
          } else {
            logger.log(`FIXES: No branches found after merge date, using unreleased versions`, "verbose", uuid);
            findNextRelease(uuid, change.project, change.branch, mergeDate, usesCherryPicking, issueId)
            .then((version) => {
              resolve(version);
            }
            ).catch(error => {
              reject(error);
            });
          }
        });
      }
    })
    .catch(error => {
      reject(error);
    })
  });
}


// Choose the appropriate method for determining fix version and execute it.
async function determineFixVersion(uuid, change, issueId) {
  const usesCherryPicking = await repoUsesCherryPicking(uuid, change.project);
  logger.log(`FIXES: ${change.project} ${usesCherryPicking ? "uses" : "does not use"}`
    + " cherry-picking", "verbose", uuid);
  if (/^(tqtc\/lts-)?\d+\.\d+\.\d+$/.test(change.branch)) {
    // Committing directly to an x.x.x bugfix release. It should be the fix version.
    logger.log(`FIXES: Closest Version Match Mode with ${change.branch}`, "debug", uuid);
    return new Promise(function(resolve, reject) {
      findClosestVersionMatch(uuid, change.branch, issueId)
      .then((closestVersion) => {
        if (!closestVersion) {
          logger.log(`FIXES: No viable jira version found for ${change.branch} in ${change.project} for ${change.current_revision}`, "warn", uuid);
          reject();
          return;
        }
        let filteredVersions = filterVersions(closestVersion.otherVersions, change.branch, true, moment(change.submitted));
        if (!Object.keys(filteredVersions).length) {
          logger.log(`FIXES: No viable jira version found for ${change.branch} in ${change.project} for ${change.current_revision}.`, "warn", uuid);
          reject();
          return;
        }
        resolve(filteredVersions[Object.keys(filteredVersions).shift()]);
      }).catch((error) => {
        reject(error);
      });
    });
  } else if (change.submitted && moment(change.submitted).isBefore(moment(0, "HH"))) {
    // Change was submitted earlier than "today". See if it should be fixed in a
    // past release.
    return CheckAlreadyReleased(uuid, change, usesCherryPicking, issueId);
  } else {
    return findNextRelease(uuid, change.project, change.branch, moment(change.submitted), usesCherryPicking, issueId);
  }
}

async function handle_fix_version_api(req, res) {
  // Req has URL parameters for gerrit Change Number or ID.
  // Query gerrit for the change and then process it.
  // This is a public endpoint, so we need to validate the request.
  if (!req.query || !req.query.change) {
    res.status(400).send("Bad Request: Missing 'change' parameter.");
    return;
  }
  let changeID = req.query.change;
  // Sanitize the changeID to only contain 6 digits".
  if (!/^\d{6}$/.test(Number(changeID))) {
    res.status(400).send("Bad Request: Invalid 'change' parameter. Accepts 6 digits only.");
    return;
  }

  req["uuid"] = uuidv1();
  logger.log(`Processing FixVersion API request for ${changeID}`, "info", req.uuid);
  let issueCount = 0;
  let collectedResults = {fixVersions: new Set(), errors: []};
  let getRetObj = () => {
    return {
      fixVersions: Array.from(collectedResults.fixVersions),
      errors: collectedResults.errors
    }
  }

  function checkDone(version, change, isFallback) {
    if (version)
      collectedResults.fixVersions.add(version);
    if (--issueCount === 0) {
      // Send the response if we have a fix version or we've tried a fallback.
      if (collectedResults.fixVersions.size || isFallback)
          res.status(200).send(getRetObj());
      else if (change.project.includes("qt/")) {
        logger.log(`Issue query returned no fix version for ${change.id}.`
          + `Defaulting to latest QTBUG issue.`, "info", req.uuid);
        queryJQL(req.uuid, `project = QTBUG AND type = Bug AND status = Open ORDER BY created DESC &maxResults=1`)
        .then((issues) => {
          issueCount = issues.issues.length;
          if (issueCount) {
            let issueId = issues.issues[0].key;
            logger.log(`Substituting default QTBUG issue ${issueId} for ${change.id}.`,
              "info", req.uuid);
            _doCheckFixVersion(change, [issueId], true);
          } else {
            logger.log(`Failed to query for QTBUG issue.`, "error", req.uuid);
            res.status(500).send("Internal Server Error");
          }
        }).catch(err => {
          logger.log(`Critical error querying jira: ${safeJsonStringify(err)}`, "error", req.uuid);
          res.status(500).send("Internal Server Error");
        });
      } else {
        logger.log(`No Fix version available for ${change.id}, and cannot use default bug.`,
          "warn", req.uuid);
        res.status(200).send(getRetObj());
      }
    }
  }

  function _doCheckFixVersion(change, issueIds, isFallback) {
    issueIds.forEach((issueId) => {
      determineFixVersion(req.uuid, change, issueId)
      .then((fixVersion) => {
        logger.log(`FIXES: Fix Version for ${issueId} in ${change.project}`
          + ` on ${change.branch}: ${safeJsonStringify(fixVersion)}`, "info", req.uuid);
        checkDone(fixVersion, change, isFallback);
      }).catch(err => {
        const msg = `${issueId}: ${typeof(err) == String ? err : safeJsonStringify(err)}`;
        logger.log(msg, "warn", req.uuid);
        collectedResults.errors.push(msg);
        checkDone(undefined, change, isFallback);
      });
    });
  }

  // uuid and fullChangeID are expected fields by most tools in the core bot framework.
  // Query for the full issue. Change-merged events aren't full enough.
  gerritTools.queryChange(req.uuid, changeID, undefined, gerritAuth,
    function(success, change) {  // Should never hard-fail since the change exists.
      // change is an HTTP Response object if !success
      if (!success && change && change.statusCode == 404) {
        logger.log(`Got 404 Not Found for ${changeID}. Jirabot probably doesn't have
        permissions to see it in gerrit.`, "error", req.uuid);
        res.status(404).send("Not Found");
        return;
      } else if (!success) {
        logger.log(`Failed to query for ${changeID}: ${safeJsonStringify(change)}`,
        "error", req.uuid);
        res.status(500).send("Internal Server Error");
        return;
      }
      req["fullChangeID"] = change.id;
      collectIssueIdsFromChange(change, (issueIds) => {
        issueCount = issueIds.length;
        if (issueCount) {
          _doCheckFixVersion(change, issueIds, false);
        } else {
          if (change.project.includes("qt/")) {
            logger.log(`No footers found on qt/ ${change.id}. Using latest QTBUG issue.`,
              "info", req.uuid);
            queryJQL(req.uuid, `project = QTBUG AND type = Bug AND status = Open ORDER BY created DESC &maxResults=1`)
            .then((issues) => {
              issueCount = issues.issues.length;
              if (issueCount) {
                let issueId = issues.issues[0].key;
                logger.log(`Substituting default QTBUG issue ${issueId} for ${change.id}.`,
                  "info", req.uuid);
                _doCheckFixVersion(change, [issueId], true);
              } else {
                logger.log(`Failed to query for QTBUG issue.`, "error", req.uuid);
                checkDone(undefined, change, true);
              }
            }).catch(err => {
              logger.log(`Critical err querying jira: ${safeJsonStringify(err)}`, "error", req.uuid);
              checkDone(undefined, change, true);
              return;
            });
          } else {
            logger.log(`No footers found on ${change.id}. Cannot provide fix version.`,"info", req.uuid);
            res.status(200).send(getRetObj());
            return;
          }
        }
    });  // End of collectIssueIdsFromChange
    }
  );
}

class jira_closer {
  constructor(notifier) {
    this.notifier = notifier;
    this.Server = this.notifier.server;
    this.logger = notifier.logger;
    this.handleChangeMerged = this.handleChange.bind(this);
    this.recover = this.recover.bind(this);

    // Queue work to avoid race conditions.
    this.issueUpdateQueue = {};
    // Schema:
    // {
    //   [issueKey]: {
    //     locked: bool,
    //     updateQueue: array[array[function, array[args]]]
    //   }
    // }

    // Add our endpoint to the central Express server.
    this.Server.app.use("/jiracloser", express.json());
    this.Server.app.post("/jiracloser", (req, res) => this.handleChange(req, res));
    this.Server.app.get("/jiracloser/fixversion", (req, res) => handle_fix_version_api(req, res));

    // Synchronous startup tasks.
    getProjectList("JIRA").then((projects) => {
      this.logger.log(`Initialized Jira Closer plugin: ${envOrConfig("JIRA_URL")}`)
      projectList = projects;
      return updateStatusCache();
    }).then(() => {
      this.recover(); // Don't begin recovery until the project list and status cache are loaded.
    }).catch(error => {
      this.logger.log(`Critical error initializing Jira Closer plugin: ${safeJsonStringify(error)}`, "error");
      throw error;
    });
  }

  // Incoming change merged notices from gerrit, begin processing.
  handleChange(req, res) {
    // IP validate the request so that only gerrit can send us messages.
    let gerritIPv4 = envOrConfig("GERRIT_IPV4");
    let gerritIPv6 = envOrConfig("GERRIT_IPV6");
    if (!toBool(process.env.IGNORE_IP_VALIDATE)) {
      // Filter requests to only receive from an expected gerrit instance.
      let clientIp = req.headers["x-forwarded-for"] || req.connection.remoteAddress;
      if (net.isIPv4(clientIp) && clientIp != gerritIPv4) {
        res.sendStatus(401);
        return false;
      } else if (net.isIPv6(clientIp) && clientIp != gerritIPv6) {
        res.sendStatus(401);
        return false;
      } else if (!net.isIP(clientIp)) {
        // ERROR, but don't exit.
        this.logger.log(
          `FATAL: Incoming request appears to have an invalid origin IP: ${clientIp}`,
          "warn"
        );
        res.sendStatus(500); // Try to send a status anyway.
        return false;
      }
    }
    res.sendStatus(200);
    req = req.body; // discard the HTTP request data and just use the incoming body.
    // uuid and fullChangeID are expected fields by most tools in the core bot framework.
    req["uuid"] = uuidv1();
    req["fullChangeID"] =
      `${encodeURIComponent(req.change.project)}~${encodeURIComponent(req.change.branch)}~`
      + req.change.id;
    this.logger.log(`Processing ${req.fullChangeID}`, "info", req.uuid);
    // Query for the full issue. Change-merged/patchset-created events aren't full enough.
    let _this = this;
    gerritTools.queryChange(req.uuid, req.fullChangeID, undefined, gerritAuth,
      function(success, change) {  // Should never hard-fail since the change exists.
        // change is an HTTP Response object if !success
        if (!success && change && change.statusCode == 404) {
          _this.logger.log(`Got 404 Not Found for ${req.fullChangeID}. Jirabot probably doesn't have
          permissions to see it in gerrit!`, "error", req.uuid);
          return;
        } else if (!success) {
          _this.logger.log(`Failed to query for ${req.fullChangeID}: ${safeJsonStringify(change)}`,
          "error", req.uuid);
          return
        }
        change.type = req.type;
        _this.getWorkForChange(change);
      }
    );
  }

  // On startup, pull recent merged changes and run the closer for each issue.
  async recover() {
    this.logger.log("Catching up work for JIRA Closer...", "info", "JIRA");
    const changes = await getChangesWithFooter("JIRA");
    if (changes.length)
      for (let change of changes) {
        change.type = "change-merged"
        this.getWorkForChange(change);  // Get and execute work
      }
    else
      this.logger.log("No recently closed issues to catch up.", "info", "JIRA");
  }

  // The queue actually has a small memory leak since we never clean up issueID handles,
  // But unless an additional lockout is added to updating the queue itself, we could lose
  // work if the handle is cleaned up when it's empty at the same time that another
  // incoming work item would be pushing to the array for the issueID.
  // Since this bot is designed to run in Heroku with at least daily restarts,
  // This memory leak is of least concern and is safe to operate as-is.
  enqueueIssueUpdate(issueId, func, args) {
    if (this.issueUpdateQueue[issueId])
      this.issueUpdateQueue[issueId].updateQueue.push([func, args]);
    else
      this.issueUpdateQueue[issueId] = {locked: false, updateQueue: [[func, args]]};
    this.callNextIssueUpdate(issueId);
  }

  callNextIssueUpdate(issueId, takeNext) {
    // Return if already locked and not explicitly being called to take the next update.
    if (this.issueUpdateQueue[issueId].locked && !takeNext)
      return;
    this.issueUpdateQueue[issueId].locked = true;
    const nextUpdate = this.issueUpdateQueue[issueId].updateQueue.shift();
    if (!nextUpdate) {
      this.issueUpdateQueue[issueId].locked = false;
      return;
    }

    nextUpdate[0](...nextUpdate[1])  // Call the queued function with args
    .then(data => {
      // resolve(data);  // No-op
    }).catch(err => {
      // reject(err);  // No-op
    }).finally(() => {
      this.callNextIssueUpdate(issueId, true);  // Always call for the next update for this issueId.
    });
  }

  getWorkForChange(change) {
    collectIssueIdsFromChange(change, (issueIds) => {
      if (!issueIds.length) {
        this.logger.log(`No footers found on ${change.id}. Discarding.`, "info", change.uuid || "JIRA");
        return;
      }
      // Get data for each of the issues
      queryManyIssues(change.uuid || "JIRA", issueIds)
      .then((issues) => {
        logger.log(`FIXES: Found ${issues.length} issues for ${change.id}`, "info", change.uuid || "JIRA")
        issues.forEach((issue) =>
          // Perform doUpdatesForGerritChange sequentially per-issue to avoid overwriting data
          // on an issue or double-closing an issue since more than one footer may
          // target the same issue.
          this.enqueueIssueUpdate(issue.id, this.doUpdatesForGerritChange, [issue, change]));
      })
      .catch(err => this.logger.log(safeJsonStringify(err).length > 2 ? safeJsonStringify(err) : err,
              "error", change.uuid || "JIRA"));
    });
  }

  // This function should be called per-issue listed by footers in a change.
  // Functionally, this means that many calls to this function can be made for the same
  // gerrit change. Logic within focuses on the behavior applied to a single jira issue.
  doUpdatesForGerritChange(issue, originalChange) {
    if (!branchesCache[originalChange.project]) {
      branchesCache[originalChange.project] = {};
    }
    if (!branchesCache[originalChange.project][originalChange.branch]
      && originalChange.branch.match(/^(?:tqtc\/lts-|lts-)?\d+\..+$/)) {
      // Cache the first time we see a branch for a project.
      // Only numeric Qt branches are tracked, since only they have proper release versions.
      // Then save it to the database.
      SQL.pool.query(`SELECT * FROM jira_branches WHERE project = '${originalChange.project}' AND branch = '${originalChange.branch}'`, (err, result) => {
        if (err) {
          logger.log(`FIXES: Error querying for branch ${originalChange.project}`
            + ` ${originalChange.branch}: ${err}`, "error", originalChange.uuid);
        } else if (result.rows.length > 0) {
          branchesCache[originalChange.project][originalChange.branch] = moment(result.rows[0].first_seen);
        } else {
          let firstSeen = moment(originalChange.submitted).format("YYYY-MM-DD HH:mm:ss");
          branchesCache[originalChange.project][originalChange.branch] = firstSeen;
          SQL.pool.query(
            `INSERT INTO jira_branches (project, branch, first_seen) `
            + `VALUES ('${originalChange.project}', '${originalChange.branch}', '${firstSeen}') `
            + `ON CONFLICT (project, branch) `
            + `DO NOTHING`,
            (err, result) => {
              if (err) {
                logger.log(`FIXES: Error inserting branch ${originalChange.project}`
                + ` ${originalChange.branch} into database: ${err}`, "error", originalChange.uuid);
              }
          });
        }
      });
    }
    return new Promise(function(resolve, reject) {
      let uuid;
      // Possible to not have a uuid if the item was discovered through querying gerrit.
      if (!originalChange.uuid)
        uuid = uuidv1();
      else
        uuid = originalChange.uuid;
      logger.log(`Updating ${issue.key} for ${originalChange.id}`, "info", uuid);
      let waitingActions = 0;
      const reopensRe = new RegExp(`^Reopens: ${issue.key}$`, "m");
      const fixesRe = new RegExp(`^Fixes: ${issue.key}$`, "m");
      const commitMsg = originalChange.revisions[originalChange.current_revision].commit.message;

      // If waitingActions decrements to 0, we're done with the work.
      // reject is never called in this function. Even performing no work is a success.
      function decrementAndCheckDone() {
        setTimeout(() => {
          if (--waitingActions === 0)
            resolve();
        }, 2000);
      }

      // Functionality to reopen on pushing a patch disabled due to public discussion.
      // if (originalChange.type == "patchset-created") {
      //   waitingActions++;
      //   const fixesAnyRe = new RegExp(`^Fixes: .+$`, 'm')
      //   if (originalChange.revisions[originalChange.current_revision]._number == 1
      //   && reopensRe.test(commitMsg)
      //   && fixesAnyRe.test(commitMsg) ) {
      //     // The issue should be reopened, but only if a fixes tag targeting anything exists.
      //     if (issue.fields.resolution) {
      //       reopenIssue(uuid, issue, originalChange, decrementAndCheckDone);
      //     } else {
      //       logger.log(`CLOSER: ${issue.key} is already open, cannot reopen.`, "verbose", uuid);
      //       decrementAndCheckDone();
      //     }
      //   } else
      //     decrementAndCheckDone();
      // }
      logger.log(`CLOSER: ${originalChange.type} issue ${issue.key} is currently in state: ${issue.fields.status.name}.`,
        "debug", uuid);
      if (originalChange.type == "change-merged") {
        if (originalChange.current_revision) {  // There's a commit sha available
          waitingActions++;
          updateCommitField(uuid, issue.key, originalChange.current_revision, originalChange.branch,
            (actionTaken) => {
              if (actionTaken) {  // Only post a comment if the commit wasn't already on the issue
                let comment = `A change related to this issue`
                  + ` (sha1 '${originalChange.current_revision}')  was integrated in`
                  + ` '${originalChange.project}' in the '${originalChange.branch}' branch.`;
                botHasPostedMessage(uuid, issue, comment)
                .then(hasPosted => {
                  if (hasPosted) {  // Don't duplicate comments.
                    decrementAndCheckDone();
                    return;
                  }
                  postComment(uuid, issue.key, comment);
                  decrementAndCheckDone();
                }).catch(() => {
                  // If we can't determine if the bot has posted a message, just post the comment.
                  postComment(uuid, issue.key, comment);
                  decrementAndCheckDone();
                });
              } else {
                decrementAndCheckDone();
              }
            }
          );
        }

        // Resolution is null if the issue isn't in a closed state.
        // Close issues with "Fixes: " in the footers.
        if (fixesRe.test(commitMsg)) {
          waitingActions++; // Add a waiting action immediately for the fix version check below.

          if (!issue.fields.resolution) {  // Issue isn't closed yet.
            waitingActions++;
            logger.log(`CLOSER: ${issue.key} is currently in state: ${issue.fields.status.name}.`,
              "verbose", uuid);
            closedByChangeId(uuid, issue, originalChange.change.id)
            .then((closedByBot) => {
                if (!closedByBot) {
                logger.log(`CLOSER: ${issue.key} is ready to be closed.`, "debug", uuid);
                // Only close if issue has not previously been closed by jirabot for this change ID
                // This ensures that cherry-picks don't close the same issue multiple times if
                // it has been reopened.
                // Just pass the decrement function as the callback since no other work is needed.
                closeIssue(uuid, issue, originalChange, decrementAndCheckDone);
              } else {
                logger.log(`CLOSER: ${issue.key} has been previously closed by`
                  + ` ${originalChange.change.id}. Not closing it again,`, "debug", uuid);
                  decrementAndCheckDone();
              }
            }).catch(err => {
              logger.log(`CLOSER: Error closing issue ${issue.key}: ${err}`, "error", uuid);
              decrementAndCheckDone();
            });
          }

          determineFixVersion(uuid, originalChange, issue.key)
          .then((fixVersion) => {
            logger.log(`FIXES: Fix Version for ${issue.key} in ${originalChange.project}`
              + ` on ${originalChange.branch}: ${safeJsonStringify(fixVersion)}`, "info", uuid);
            updateFixVersions(uuid, issue.key, fixVersion.id, decrementAndCheckDone);
          }).catch(err => {
            const msg = err
              || `FIXES: No version for ${issue.key} in ${originalChange.project} on ${originalChange.branch}`;
            logger.log(msg, "warn", uuid);
            decrementAndCheckDone();
          });
        } else if (reopensRe.test(commitMsg)) {
          // On change-merge, if Reopens exists, but a Fixes footer for the same
          // issueID is not present, the issue specified by Reopens should be reopened.
          // Often seen in a revert of a previous commit.
          if (issue.fields.resolution) {
            waitingActions++;
            logger.log(`CLOSER: ${issue.key} is currently in state: ${issue.fields.status.name}.`,
              "verbose", uuid);
            logger.log(`CLOSER: ${issue.key} is ready to be reopened.`, "debug", uuid);
            reopenIssue(uuid, issue, originalChange, decrementAndCheckDone);
          } else {
            logger.log(`CLOSER: Reopens issue ${issue.key} is already open.`, "verbose", uuid);
          }
        }
      }
    });
  }
}

module.exports = jira_closer;
