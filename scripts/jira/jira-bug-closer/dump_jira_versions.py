#!/usr/bin/env python3
#############################################################################
##
## Copyright (C) 2020 The Qt Company Ltd.
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
