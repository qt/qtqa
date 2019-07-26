#!/usr/bin/env python3
#############################################################################
##
## Copyright (C) 2019 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:GPL-EXCEPT$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3 as published by the Free Software
## Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################

from string import Template
from time import sleep
from distutils.version import LooseVersion
from typing import Any, Dict, List, Optional, Tuple
import jira  # type: ignore
from config import Config
from git import FixedByTag
from logger import logger

log = logger.get_logger('jira')

comment_template = Template(
    """A change related to this issue (sha1 '$sha1') was integrated in '$repository' in the '$branch' branch.
This change will be in version: $fix_version - (JIRA: $version_id).
Subject: {{$subject}}"
""")


class JiraCloser:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.jira_url = self.config.jira_url
        self.jira_client = jira.JIRA(self.jira_url, oauth=self.config.get_oauth_data())

    @staticmethod
    def _clean_jira_versions(jira_version_list: List[Dict[str, str]]) -> List[Tuple[LooseVersion, str, bool]]:
        versions: List[Tuple[LooseVersion, str, bool]] = []
        for version_data in jira_version_list:
            # Skip empty descriptions, they are only missing for old versions and irrelevant
            version_description = version_data.get('description')
            if not version_description:
                continue
            looseVersion = LooseVersion(version_description)
            # Skip versions that are for example only two digits, e.g. "6.0"
            if len(looseVersion.version) < 3:
                continue
            id = version_data['id']
            released = bool(version_data['released'])
            versions.append((looseVersion, id, released))
        return versions

    def _jira_version_list(self, issue: jira.Issue) -> List[Tuple[LooseVersion, str, bool]]:
        try:
            project_key = issue.key.split('-')[0]
            meta = self.jira_client.createmeta(
                projectKeys=project_key,
                issuetypeIds=[issue.fields.issuetype.id], expand='projects.issuetypes.fields')
            projects = meta['projects'][0]
            fields = projects['issuetypes'][0]['fields']
            versions = fields.get('versions')
            # tasks have fixVersions instead
            if not versions:
                versions = fields.get('fixVersions')
            if not versions:
                log.error("Could not get versions or fixVersions for issue '%s'", issue.key)
                return []

            allowed_versions: List[Dict[str, str]] = versions['allowedValues']
            return JiraCloser._clean_jira_versions(allowed_versions)
        except Exception as e:
            log.error("Could not determine allowed versions.")
            log.warning(str(e))
            return []

    def _guess_fix_version(self, version: str, known_versions: List[Tuple[LooseVersion, str, bool]]) -> Optional[str]:
        if not version.count('.') == 2:
            log.error("Invalid version: '%s' (must be 'x.y.z')", version)
            return None

        def is_same_version(left: LooseVersion, right: LooseVersion) -> bool:
            assert len(left.version) > 2
            assert len(right.version) > 2
            return left.version[0] == right.version[0] and left.version[1] == right.version[1] and left.version[2] == right.version[2]

        needle = LooseVersion(version)
        candidates = [v for v in known_versions if is_same_version(needle, v[0])]
        if not candidates:
            return None

        # take everything where major, minor, patch are right
        if len(candidates) == 1:
            return candidates[0][1]

        # Sort, except for one silly thing in LooseVersion: no alphanumeric component is smallest, so 5.13.0 < 5.13.0 Alpha 1
        candidates.sort()
        if len(candidates[0][0].version) == 3:
            candidates.append(candidates.pop(0))

        # if there are released and unreleased versions, narrow it down to unreleased
        unreleased = [v for v in candidates if not v[2]]
        if unreleased:
            candidates = unreleased
            return candidates[0][1]

        # we seem to have no unreleased versions, that means the last one is correct
        return candidates[-1][1]

    def _get_fix_version_field(self, issue: jira.Issue, fix_version: Optional[str]) -> Tuple[str, Dict[str, Any]]:
        """ Returns the version_id and the needed fields to update the fix version in JIRA. """
        if not fix_version:
            return 'unknown version', {}

        jira_versions = self._jira_version_list(issue)
        version_id = self._guess_fix_version(fix_version, jira_versions)
        if not version_id:
            log.warning("Could not guess fix version for issue '%s': %s - versions: %s", issue.key, fix_version, jira_versions)
            return 'unknown version', {}

        # check if this version should be added at all
        # only operate on major/minor/patch and ignore alpha/beta/...
        new_version_major, new_version_minor, new_version_patch = LooseVersion(fix_version).version[0:3]
        assert isinstance(new_version_major, int)
        assert isinstance(new_version_minor, int)
        assert isinstance(new_version_patch, int)

        set_versions = [LooseVersion(version.description) for version in issue.fields.fixVersions]
        for old_version in set_versions:
            if len(old_version.version) < 3:
                continue

            old_version_major, old_version_minor, old_version_patch = old_version.version[0:3]
            # skip existing random fix versions that do not have major/minor/patch set
            if not (isinstance(old_version_major, int) and isinstance(old_version_minor, int) and isinstance(old_version_patch, int)):
                continue

            # if 5.12.2 is there, don't add 5.12.3
            if (new_version_major, new_version_minor) == (old_version_major, old_version_minor) and int(new_version_patch) >= int(old_version_patch):
                log.info("Skipping adding version '%s' because of '%s' for '%s'", fix_version, old_version, issue.key)
                return '', {}  # ### FIXME is there any point in returning the version id here?

            # if 5.12.0 is there, don't add 5.13.x
            # if 5.x.0 is there, don't add 6.y.z
            if (new_version_major, new_version_minor) > (old_version_major, old_version_minor) and old_version_patch == 0:
                log.info("Skipping adding version '%s' because of '%s' for '%s'", fix_version, old_version, issue.key)
                return '', {}  # ### FIXME is there any point in returning the version id here?

        version_ids = [version.id for version in issue.fields.fixVersions]
        version_ids.append(version_id)
        versions: List[Dict[str, str]] = []
        for v in version_ids:
            versions.append({'id': v})
        log.info("Added version '%s' (%s) to '%s'", fix_version, version_id, issue.key)
        return version_id, {'fixVersions': versions}

    def _get_change_sha1_field(self, issue: jira.Issue, fix: FixedByTag) -> Dict[str, Any]:
        change_field = issue.fields.customfield_10142 or ''
        changes = change_field.split()
        if fix.sha1 in changes:
            return {}
        changes.append('%s (%s/%s)' % (fix.sha1, fix.repository, fix.branch))
        return {'customfield_10142': ' '.join(changes)}

    @staticmethod
    def _is_reopened(issue: jira.Issue) -> bool:
        for change in issue.changelog.histories:
            for item in change.items:
                if item.toString == 'Open' and item.fromString == 'Closed':
                    return True
        return False

    def _close_issue(self, issue: jira.Issue, fields: Dict[str, Any], ignore_reopened: bool) -> None:
        if issue.fields.status.name == 'Closed':
            issue.update(fields=fields)
            return
        if not ignore_reopened and JiraCloser._is_reopened(issue):
            self.jira_client.add_comment(issue, 'A change related to this issue was integrated. This issue was re-opened before, the bot will not close this issue, please close it manually when applicable.')
            return
        if issue.fields.status.name == 'In Progress':
            fields.update({'resolution': {'name': 'Done'}})
            self.jira_client.transition_issue(issue.key, transition='Fixed', fields=fields)
            return
        fields.update({'resolution': {'name': 'Done'}})
        self.jira_client.transition_issue(issue.key, transition='Close', fields=fields)

    def _update_issue(self, fix: FixedByTag, issue_key: str, fixes: bool, ignore_reopened: bool = False) -> None:
        try:
            issue = self.jira_client.issue(issue_key, expand='changelog')
            version_id = None
            if fixes:
                # get the fix version to update
                version_id, extra_fields = self._get_fix_version_field(issue, fix.version)
                # get changes in the form of sha1 and repo + branch
                extra_fields.update(self._get_change_sha1_field(issue, fix))
                # close the issue
                self._close_issue(issue, extra_fields, ignore_reopened=ignore_reopened)

            if self.config.add_comment_to_issues:
                comment = comment_template.substitute(sha1=fix.sha1, repository=fix.repository, branch=fix.branch, fix_version=fix.version or 'unknown version', version_id=version_id or 'unknown version', subject=fix.subject)
                self.jira_client.add_comment(issue, comment)
                log.info('Added comment to %s', self.config.jira_url + '/browse/' + issue_key)

            log.info("Finished updating %s successfully", fix)

        except jira.exceptions.JIRAError as e:
            if e.status_code == 404:
                log.warning("Issue could not be found: %s", issue_key)
            else:
                raise e

    def _update_issue_with_retry(self, fix: FixedByTag, issue_key: str, fixes: bool, ignore_reopened: bool = False) -> None:
        for attempt in range(5):
            sleep(attempt)  # wait for up to 4 seconds, try 5 times
            try:
                self._update_issue(fix, issue_key, fixes, ignore_reopened)
                break
            except jira.exceptions.JIRAError as e:
                if e.status_code == 500:
                    log.warning("Got internal server error from jira for: %s", e.url)
                    log.info(str(e))
                else:
                    raise e

    def run(self, fix: FixedByTag) -> None:
        log.info("Processing %s", fix)
        for issue_key in fix.task_numbers:
            self._update_issue_with_retry(fix, issue_key, fixes=False)
        for issue_key in fix.fixes:
            self._update_issue_with_retry(fix, issue_key, fixes=True)
