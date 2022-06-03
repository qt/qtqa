# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

from config import Config
from jiracloser import JiraCloser
from logger import get_logger
from git import FixedByTag
import pytest

log = get_logger('test')


@pytest.mark.parametrize("issue_key, issue_type", [
                         ('QTBUG-4795', 'Bug'),
                         ('QTBUG-85641', 'Epic'),
                         ('QTBUG-85642', 'User Story'),
                         ('QTBUG-85643', 'Task')]
                         )
def test_close_issue(issue_key, issue_type):
    config = Config('test')
    j = JiraCloser(config)
    log.info(f'Testing Close issue on {issue_key} - {issue_type}')
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
