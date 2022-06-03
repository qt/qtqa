#!/usr/bin/env python3
# Copyright (C) 2020 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

from typing import List, Tuple

from config import Config
from jiracloser import JiraCloser, LooseVersion


""" Debugging helper to test the other code when working on these scripts. """


def print_versions(version_list: List[Tuple[LooseVersion, str, bool]]) -> None:
    print(f"    {'Version':35}{'description':35}{'released':30}")
    for version in version_list:
        print(f"    {version[0].vstring:35}{version[1]:35}{str(version[2]):30}")


if __name__ == "__main__":
    config = Config('test')
    j = JiraCloser(config)
    print("Fix versions for QTBUG:")
    issue = j.jira_client.issue('QTBUG-1')
    print_versions(j._jira_version_list(issue))

    print("Fix versions for QTCREATORBUG:")
    issue = j.jira_client.issue('QTCREATORBUG-1')
    print_versions(j._jira_version_list(issue))
