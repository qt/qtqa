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

from config import Config
from jiracloser import JiraCloser
from logger import get_logger
from git import FixedByTag

log = get_logger('test')


def test_close_issue():
    config = Config('test')
    j = JiraCloser(config)
    issue_key = 'QTBUG-4795'

    issue = j.jira_client.issue(issue_key)

    if issue.fields.status.name != 'Open':
        log.info('Re-opening issue from "%s"', issue.fields.status)
        if issue.fields.status.name == 'In Progress':
            j.jira_client.transition_issue(issue.key, transition='Stop Work')
        else:
            j.jira_client.transition_issue(issue_key, transition='Re-open')
    # clear fix versions and commits
    issue.update(fields={'fixVersions': [], 'customfield_10142': ''})

    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Open'
    fix = FixedByTag(repository='foo/bar', branch='dev', version='5.13.0',
                     sha1='bd0279c4173eb627d432d9a05411bbc725240d4e', task_numbers=[], fixes=['CON-5'],
                     author='Some One', subject='Close a test issue')
    j._update_issue_with_retry(fix, issue_key, fixes=True)

    # This issue was re-opened, by default we will only post a comment but not re-open it again
    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Open'

    j._update_issue_with_retry(fix, issue_key, fixes=True, ignore_reopened=True)

    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Closed'
    assert issue.fields.resolution.name == 'Done'
    assert len(issue.fields.fixVersions) == 1
    assert issue.fields.fixVersions[0].name.startswith('5.13.0')
    assert issue.fields.customfield_10142 == 'bd0279c4173eb627d432d9a05411bbc725240d4e (foo/bar/dev)'

    j.jira_client.transition_issue(issue_key, transition='Re-open')
    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Open'
    assert not issue.fields.resolution

    # Assign to bot and start work
    assert j.jira_client.assign_issue(issue.key, assignee='qtgerritbot')
    j.jira_client.transition_issue(issue_key, transition='Start Work')
    j._update_issue_with_retry(fix, issue_key, True, ignore_reopened=True)
    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Closed'
    assert issue.fields.resolution.name == 'Done'

    # Close it a second time (and that should just do nothing, not raise an exception)
    j._update_issue_with_retry(fix, issue_key, True)
    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Closed'
    assert issue.fields.resolution.name == 'Done'

    # Sometimes we have less sensical fix versions set already, such as "Some future release".
    # Make sure that doesn't bother the bot.
    j.jira_client.transition_issue(issue_key, transition='Re-open')
    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Open'
    assert not issue.fields.resolution
    version_some_future_release = '11533'
    issue.update(fields={'fixVersions': [{'id': version_some_future_release}]})
    issue = j.jira_client.issue(issue_key)
    assert len(issue.fields.fixVersions) == 1

    j._update_issue_with_retry(fix, issue_key, True, ignore_reopened=True)
    issue = j.jira_client.issue(issue_key)
    assert issue.fields.status.name == 'Closed'
    assert issue.fields.resolution.name == 'Done'
    # Verify that the new fix version was added and the "some future release" is still there.
    assert len(issue.fields.fixVersions) == 2
