// Copyright (C) 2022 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

const moment = require("moment");

class Version {
  constructor(parsedVersion) {
    if (!parsedVersion)
      parsedVersion = [0, 0, 0, 0];  // Initialize with zeroes so we can compare against something.
    this.major = Number(parsedVersion[1]);
    this.minor = Number(parsedVersion[2]);
    this.patch = Number(parsedVersion[3]);
  }
}


Version.prototype.toString = function() {
  return `${this.major}.${this.minor}.${this.patch}`;
}

// Filter down an Object of versions by branch.
// Set allowReleased=true to include released versions.
function filterVersions(versions, branch, allowReleased, date) {
  branch = branch.replace(/(?:tqtc\/)?(?:lts-)?/, "");  // Strip tqtc prefix from branch for this step.
  const branchre = new RegExp(`^${branch}`);  // Force left-anchored branch matching for safety.
  let fromArray = {};
  if (Array.isArray(versions)) {
    fromArray = versions.reduce((acc, cur) => {
      acc[cur.description] = cur;
      return acc;
    }, {});
  }
  const filtered = Object.entries(Object.keys(fromArray).length ? fromArray : versions).filter(([key, value]) => {
    if (branchre.test(key)) {
      if ((value.released || value.archived) && !allowReleased)
        return false;
      if (allowReleased && date &&
        (value.released && moment(value.releaseDate).isBefore(date)
        || (value.startDate && moment(value.startDate).isAfter(date)
            // Sub versions always include a space (e.g. "6.2.0 Beta 1").
            // Avoid excluding main versions that were started after the merge date
            // since they represent the final release; Sub-versions like Beta and RC
            // are included in the otherVerions property of the main version
            // and are expected to be passed to filterVersions() separately.
            && /\s/.test(key))
        ))
        return false;  // Exclude versions that were started after, or released before the date.
      return true;
    }
    return false;
  })
  return Object.fromEntries(filtered) || {};
}

// TODO: May need to sort this to be super sure it's in ascending order, but it always seems to be...
// Controllable generator to be used when iterating Objects or arrays of Versions()
function* makeVersionGenerator(versions) {
  let iterationCount = 0;
  for (const version of Object.keys(versions)) {
    iterationCount++;
    yield versions[version];
  }
  return iterationCount;
}


module.exports = { Version, filterVersions, makeVersionGenerator };
