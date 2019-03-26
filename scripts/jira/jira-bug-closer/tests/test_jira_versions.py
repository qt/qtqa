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

from distutils.version import LooseVersion
from typing import Dict, List, Tuple
import pytest
from config import Config
from jiracloser import JiraCloser

config = Config('test')
closer = JiraCloser(config)


def test_set_jira_versions():
    issue_key = 'QTBUG-4795'
    issue = closer.jira_client.issue(issue_key)

    # clear any version that was set before
    issue.update(fields={'fixVersions': []})
    issue = closer.jira_client.issue(issue_key)
    assert not issue.fields.fixVersions

    version_id, version_field = closer._get_fix_version_field(issue, fix_version='5.11.2')
    assert version_field == {'fixVersions': [{'id': '16916'}]}
    issue.update(fields=version_field)
    issue = closer.jira_client.issue(issue_key)
    assert len(issue.fields.fixVersions) == 1
    assert issue.fields.fixVersions[0].id == '16916'
    assert issue.fields.fixVersions[0].id == version_id
    assert issue.fields.fixVersions[0].name == '5.11.2'

    # now merge to 5.12.0, we want that version added
    version_id, version_field = closer._get_fix_version_field(issue, fix_version='5.12.0')
    assert version_field == {'fixVersions': [{'id': '16916'}, {'id': '16832'}]}
    issue.update(fields=version_field)
    issue = closer.jira_client.issue(issue_key)
    assert len(issue.fields.fixVersions) == 2

    # now merge to 5.12.1, nothing should happen since we have 5.12.0 in the list
    version_id, version_field = closer._get_fix_version_field(issue, fix_version='5.12.1')
    assert version_field == {}
    issue.update(fields=version_field)
    issue = closer.jira_client.issue(issue_key)
    assert len(issue.fields.fixVersions) == 2

    # also add the change in 5.13.0, again nothing to be done, 5.12.0 is in the list
    version_id, version_field = closer._get_fix_version_field(issue, fix_version='5.13.0')
    assert version_field == {}
    issue.update(fields=version_field)
    issue = closer.jira_client.issue(issue_key)
    assert len(issue.fields.fixVersions) == 2


# in order to keep the test stable, use a version data dump:
jira_qt_versions = [
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11486', 'id': '11486', 'description': '3.x', 'name': '3.x', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11487', 'id': '11487', 'description': '4.0.0', 'name': '4.0.0', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11489', 'id': '11489', 'description': '4.0.1', 'name': '4.0.1', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11490', 'id': '11490', 'description': '4.1.0', 'name': '4.1.0', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11492', 'id': '11492', 'description': '4.1.1', 'name': '4.1.1', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11493', 'id': '11493', 'description': '4.1.2', 'name': '4.1.2', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11494', 'id': '11494', 'description': '4.1.3', 'name': '4.1.3', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11495', 'id': '11495', 'description': '4.1.4', 'name': '4.1.4', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11496', 'id': '11496', 'description': '4.1.5', 'name': '4.1.5', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11497', 'id': '11497', 'description': '4.2.0', 'name': '4.2.0', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11500', 'id': '11500', 'description': '4.2.1', 'name': '4.2.1', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11501', 'id': '11501', 'description': '4.2.2', 'name': '4.2.2', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11502', 'id': '11502', 'description': '4.2.3', 'name': '4.2.3', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11503', 'id': '11503', 'description': '4.3.0', 'name': '4.3.0', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11506', 'id': '11506', 'description': '4.3.1', 'name': '4.3.1', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11507', 'id': '11507', 'description': '4.3.2', 'name': '4.3.2', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11508', 'id': '11508', 'description': '4.3.3', 'name': '4.3.3', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11509', 'id': '11509', 'description': '4.3.4', 'name': '4.3.4', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11510', 'id': '11510', 'description': '4.3.5', 'name': '4.3.5', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11511', 'id': '11511', 'description': '4.4.0', 'name': '4.4.0', 'archived': False, 'released': True, 'releaseDate': '2008-05-06', 'userReleaseDate': "06 May '08", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11515', 'id': '11515', 'description': '4.4.1', 'name': '4.4.1', 'archived': False, 'released': True, 'releaseDate': '2008-06-24', 'userReleaseDate': "24 Jun '08", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11516', 'id': '11516', 'description': '4.4.2', 'name': '4.4.2', 'archived': False, 'released': True, 'releaseDate': '2008-09-18', 'userReleaseDate': "18 Sep '08", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11517', 'id': '11517', 'description': '4.4.3', 'name': '4.4.3', 'archived': False, 'released': True, 'releaseDate': '2008-09-29', 'userReleaseDate': "29 Sep '08", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11518', 'id': '11518', 'description': '4.5.0', 'name': '4.5.0', 'archived': False, 'released': True, 'releaseDate': '2009-03-03', 'userReleaseDate': "03 Mar '09", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11522', 'id': '11522', 'description': '4.5.1', 'name': '4.5.1', 'archived': False, 'released': True, 'releaseDate': '2009-04-23', 'userReleaseDate': "23 Apr '09", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11523', 'id': '11523', 'description': '4.5.2', 'name': '4.5.2', 'archived': False, 'released': True, 'releaseDate': '2009-06-23', 'userReleaseDate': "23 Jun '09", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11525', 'id': '11525', 'description': '4.5.3', 'name': '4.5.3', 'archived': False, 'released': True, 'releaseDate': '2009-10-01', 'userReleaseDate': "01 Oct '09", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11527', 'id': '11527', 'description': '4.6.0', 'name': '4.6.0', 'archived': False, 'released': True, 'releaseDate': '2009-12-01', 'userReleaseDate': "01 Dec '09", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11561', 'id': '11561', 'description': '4.6.1', 'name': '4.6.1', 'archived': False, 'released': True, 'releaseDate': '2010-01-19', 'userReleaseDate': "19 Jan '10", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11569', 'id': '11569', 'description': '4.6.2', 'name': '4.6.2', 'archived': False, 'released': True, 'releaseDate': '2010-02-15', 'userReleaseDate': "15 Feb '10", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11572', 'id': '11572', 'description': '4.6.3', 'name': '4.6.3', 'archived': False, 'released': True, 'releaseDate': '2010-06-08', 'userReleaseDate': "08 Jun '10", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11563', 'id': '11563', 'description': '4.7.0', 'name': '4.7.0', 'archived': False, 'released': True, 'releaseDate': '2010-09-21', 'userReleaseDate': "21 Sep '10", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11664', 'id': '11664', 'description': '4.7.1', 'name': '4.7.1', 'archived': False, 'released': True, 'releaseDate': '2010-11-09', 'userReleaseDate': "09 Nov '10", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11701', 'id': '11701', 'description': '4.7.2', 'name': '4.7.2', 'archived': False, 'released': True, 'releaseDate': '2011-03-01', 'userReleaseDate': "01 Mar '11", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11761', 'id': '11761', 'description': '4.7.3', 'name': '4.7.3', 'archived': False, 'released': True, 'releaseDate': '2011-05-04', 'userReleaseDate': "04 May '11", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11804', 'id': '11804', 'description': '4.7.4', 'name': '4.7.4', 'archived': False, 'released': True, 'releaseDate': '2011-09-01', 'userReleaseDate': "01 Sep '11", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11830', 'id': '11830', 'description': 'Qt3D Tech preview 1', 'name': 'Qt3D TP1', 'archived': False, 'released': True, 'releaseDate': '2011-05-20', 'userReleaseDate': "20 May '11", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11831', 'id': '11831', 'description': 'Qt3D Tech preview 2', 'name': 'Qt3D TP2', 'archived': False, 'released': True, 'releaseDate': '2011-09-23', 'userReleaseDate': "23 Sep '11", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11788', 'id': '11788', 'description': 'Qt3D Team backlog', 'name': 'Qt3D 1.0', 'archived': False, 'released': True, 'releaseDate': '2012-03-12', 'userReleaseDate': "12 Mar '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12122', 'id': '12122', 'description': 'Qt3D 2.0', 'name': 'Qt3D 2.0', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12123', 'id': '12123', 'description': 'Qt3D 2.0.1 - patch', 'name': 'Qt3D 2.0.1', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12125', 'id': '12125', 'description': 'Qt3D 2.1', 'name': 'Qt3D 2.1', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11620', 'id': '11620', 'description': '4.8.0', 'name': '4.8.0', 'archived': False, 'released': True, 'releaseDate': '2011-12-15', 'userReleaseDate': "15 Dec '11", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11905', 'id': '11905', 'description': '4.8.1', 'name': '4.8.1', 'archived': False, 'released': True, 'releaseDate': '2012-03-28', 'userReleaseDate': "28 Mar '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12120', 'id': '12120', 'description': '4.8.2', 'name': '4.8.2', 'archived': False, 'released': True, 'releaseDate': '2012-05-22', 'userReleaseDate': "22 May '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12200', 'id': '12200', 'description': '4.8.3', 'name': '4.8.3', 'archived': False, 'released': True, 'releaseDate': '2012-09-13', 'userReleaseDate': "13 Sep '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12501', 'id': '12501', 'description': '4.8.4', 'name': '4.8.4', 'archived': False, 'released': True, 'releaseDate': '2012-11-29', 'userReleaseDate': "29 Nov '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12505', 'id': '12505', 'description': '4.8.5', 'name': '4.8.5', 'archived': False, 'released': True, 'releaseDate': '2013-07-02', 'userReleaseDate': "02 Jul '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13008', 'id': '13008', 'description': '4.8.6', 'name': '4.8.6', 'archived': False, 'released': True, 'releaseDate': '2014-04-24', 'userReleaseDate': "24 Apr '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14000', 'id': '14000', 'description': '4.8.7', 'name': '4.8.7', 'archived': False, 'released': True, 'releaseDate': '2015-05-26', 'userReleaseDate': "26 May '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11621', 'id': '11621', 'description': '4.8.x', 'name': '4.8.x', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13403', 'id': '13403', 'description': '5.0.0 Alpha 1', 'name': '5.0.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2011-04-27', 'userReleaseDate': "27 Apr '11", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12126', 'id': '12126', 'description': '5.0.0 Beta 1', 'name': '5.0.0 Beta 1', 'archived': False, 'released': True, 'releaseDate': '2012-08-31', 'userReleaseDate': "31 Aug '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12500', 'id': '12500', 'description': '5.0.0 Beta 2', 'name': '5.0.0 Beta 2', 'archived': False, 'released': True, 'releaseDate': '2012-11-13', 'userReleaseDate': "13 Nov '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12300', 'id': '12300', 'description': '5.0.0 RC 1', 'name': '5.0.0 RC 1', 'archived': False, 'released': True, 'releaseDate': '2012-12-06', 'userReleaseDate': "06 Dec '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12600', 'id': '12600', 'description': '5.0.0 RC 2', 'name': '5.0.0 RC 2', 'archived': False, 'released': True, 'releaseDate': '2012-12-13', 'userReleaseDate': "13 Dec '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11529', 'id': '11529', 'description': '5.0.0', 'name': '5.0.0', 'archived': False, 'released': True, 'releaseDate': '2012-12-19', 'userReleaseDate': "19 Dec '12", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12602', 'id': '12602', 'description': '5.0.1', 'name': '5.0.1', 'archived': False, 'released': True, 'releaseDate': '2013-01-31', 'userReleaseDate': "31 Jan '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12607', 'id': '12607', 'description': '5.0.2', 'name': '5.0.2', 'archived': False, 'released': True, 'releaseDate': '2013-04-10', 'userReleaseDate': "10 Apr '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12618', 'id': '12618', 'description': '5.1.0 Beta 1', 'name': '5.1.0 Beta 1', 'archived': False, 'released': True, 'releaseDate': '2013-05-14', 'userReleaseDate': "14 May '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12700', 'id': '12700', 'description': '5.1.0 RC 1', 'name': '5.1.0 RC1', 'archived': False, 'released': True, 'releaseDate': '2013-06-18', 'userReleaseDate': "18 Jun '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13007', 'id': '13007', 'description': '5.1.0 RC 2', 'name': '5.1.0 RC2', 'archived': False, 'released': True, 'releaseDate': '2013-06-29', 'userReleaseDate': "29 Jun '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12121', 'id': '12121', 'description': '5.1.0', 'name': '5.1.0 ', 'archived': False, 'released': True, 'releaseDate': '2013-07-03', 'userReleaseDate': "03 Jul '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12900', 'id': '12900', 'description': '5.1.1', 'name': '5.1.1', 'archived': False, 'released': True, 'releaseDate': '2013-08-28', 'userReleaseDate': "28 Aug '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13202', 'id': '13202', 'description': '5.2.0 Alpha 1', 'name': '5.2.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2013-09-30', 'userReleaseDate': "30 Sep '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13203', 'id': '13203', 'description': '5.2.0 Beta 1', 'name': '5.2.0 Beta1 ', 'archived': False, 'released': True, 'releaseDate': '2013-10-23', 'userReleaseDate': "23 Oct '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13205', 'id': '13205', 'description': '5.2.0 RC 1', 'name': '5.2.0 RC1', 'archived': False, 'released': True, 'releaseDate': '2013-11-29', 'userReleaseDate': "29 Nov '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12617', 'id': '12617', 'description': '5.2.0', 'name': '5.2.0', 'archived': False, 'released': True, 'releaseDate': '2013-12-12', 'userReleaseDate': "12 Dec '13", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13400', 'id': '13400', 'description': '5.2.1', 'name': '5.2.1', 'archived': False, 'released': True, 'releaseDate': '2014-02-05', 'userReleaseDate': "05 Feb '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13602', 'id': '13602', 'description': '5.3.0 Alpha 1', 'name': '5.3.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2014-02-27', 'userReleaseDate': "27 Feb '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13603', 'id': '13603', 'description': '5.3.0 Beta 1', 'name': '5.3.0 Beta1', 'archived': False, 'released': True, 'releaseDate': '2014-03-25', 'userReleaseDate': "25 Mar '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13604', 'id': '13604', 'description': '5.3.0 RC 1', 'name': '5.3.0 RC1', 'archived': False, 'released': True, 'releaseDate': '2014-05-08', 'userReleaseDate': "08 May '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13201', 'id': '13201', 'description': '5.3.0', 'name': '5.3.0', 'archived': False, 'released': True, 'releaseDate': '2014-05-20', 'userReleaseDate': "20 May '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13900', 'id': '13900', 'description': '5.3.1', 'name': '5.3.1', 'archived': False, 'released': True, 'releaseDate': '2014-06-25', 'userReleaseDate': "25 Jun '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14005', 'id': '14005', 'description': '5.3.2', 'name': '5.3.2', 'archived': False, 'released': True, 'releaseDate': '2014-09-16', 'userReleaseDate': "16 Sep '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14300', 'id': '14300', 'description': '5.4.0 Alpha 1', 'name': '5.4.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2014-09-08', 'userReleaseDate': "08 Sep '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14301', 'id': '14301', 'description': '5.4.0 Beta 1', 'name': '5.4.0 Beta', 'archived': False, 'released': True, 'releaseDate': '2014-10-17', 'userReleaseDate': "17 Oct '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14302', 'id': '14302', 'description': '5.4.0 RC 1', 'name': '5.4.0 RC', 'archived': False, 'released': True, 'releaseDate': '2014-11-27', 'userReleaseDate': "27 Nov '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13601', 'id': '13601', 'description': '5.4.0', 'name': '5.4.0', 'archived': False, 'released': True, 'releaseDate': '2014-12-10', 'userReleaseDate': "10 Dec '14", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14400', 'id': '14400', 'description': '5.4.1', 'name': '5.4.1', 'archived': False, 'released': True, 'releaseDate': '2015-02-24', 'userReleaseDate': "24 Feb '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14600', 'id': '14600', 'description': '5.4.2', 'name': '5.4.2', 'archived': False, 'released': True, 'releaseDate': '2015-06-02', 'userReleaseDate': "02 Jun '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15102', 'id': '15102', 'description': '5.4.3', 'name': '5.4.3', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14702', 'id': '14702', 'description': '5.4.0 Alpha 1', 'name': '5.5.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2015-03-17', 'userReleaseDate': "17 Mar '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14703', 'id': '14703', 'description': '5.5.0 Beta 1', 'name': '5.5.0 Beta', 'archived': False, 'released': True, 'releaseDate': '2015-05-15', 'userReleaseDate': "15 May '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14704', 'id': '14704', 'description': '5.5.0 RC 1', 'name': '5.5.0 RC', 'archived': False, 'released': True, 'releaseDate': '2015-06-22', 'userReleaseDate': "22 Jun '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14200', 'id': '14200', 'description': '5.5.0', 'name': '5.5.0', 'archived': False, 'released': True, 'releaseDate': '2015-07-01', 'userReleaseDate': "01 Jul '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15105', 'id': '15105', 'description': '5.5.1', 'name': '5.5.1', 'archived': False, 'released': True, 'releaseDate': '2015-10-15', 'userReleaseDate': "15 Oct '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15301', 'id': '15301', 'description': '5.6.0 Alpha 1', 'name': '5.6.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2015-09-08', 'userReleaseDate': "08 Sep '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15302', 'id': '15302', 'description': '5.6.0 Beta 1', 'name': '5.6.0 Beta', 'archived': False, 'released': True, 'releaseDate': '2015-12-18', 'userReleaseDate': "18 Dec '15", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15303', 'id': '15303', 'description': '5.6.0 RC 1', 'name': '5.6.0 RC', 'archived': False, 'released': True, 'releaseDate': '2016-02-23', 'userReleaseDate': "23 Feb '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15304', 'id': '15304', 'description': '5.6.0', 'name': '5.6.0', 'archived': False, 'released': True, 'releaseDate': '2016-03-16', 'userReleaseDate': "16 Mar '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15305', 'id': '15305', 'description': '5.6.1', 'name': '5.6.1', 'archived': False, 'released': True, 'releaseDate': '2016-06-08', 'userReleaseDate': "08 Jun '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15792', 'id': '15792', 'description': '5.6.2', 'name': '5.6.2', 'archived': False, 'released': True, 'releaseDate': '2016-10-12', 'userReleaseDate': "12 Oct '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15907', 'id': '15907', 'description': '5.6.3', 'name': '5.6.3', 'archived': False, 'released': True, 'releaseDate': '2017-09-21', 'userReleaseDate': "21 Sep '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16617', 'id': '16617', 'description': '5.6.4', 'name': '5.6.4', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14901', 'id': '14901', 'description': '5.6', 'name': '5.6', 'archived': False, 'released': True, 'releaseDate': '2016-03-16', 'userReleaseDate': "16 Mar '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15602', 'id': '15602', 'description': '5.7.0 Alpha 1', 'name': '5.7.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2016-03-11', 'userReleaseDate': "11 Mar '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15603', 'id': '15603', 'description': '5.7.0 Beta 1', 'name': '5.7.0 Beta', 'archived': False, 'released': True, 'releaseDate': '2016-04-21', 'userReleaseDate': "21 Apr '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15604', 'id': '15604', 'description': '5.7.0 RC 1', 'name': '5.7.0 RC', 'archived': False, 'released': True, 'releaseDate': '2016-06-03', 'userReleaseDate': "03 Jun '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15605', 'id': '15605', 'description': '5.7.0', 'name': '5.7.0', 'archived': False, 'released': True, 'releaseDate': '2016-06-16', 'userReleaseDate': "16 Jun '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15794', 'id': '15794', 'description': '5.7.1', 'name': '5.7.1', 'archived': False, 'released': True, 'releaseDate': '2016-12-14', 'userReleaseDate': "14 Dec '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16004', 'id': '16004', 'description': '5.7.2', 'name': '5.7.2', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15205', 'id': '15205', 'description': '5.7', 'name': '5.7', 'archived': False, 'released': True, 'releaseDate': '2016-06-16', 'userReleaseDate': "16 Jun '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15701', 'id': '15701', 'description': '5.8.0 Alpha 1', 'name': '5.8.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2016-09-05', 'userReleaseDate': "05 Sep '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15702', 'id': '15702', 'description': '5.8.0 Beta 1', 'name': '5.8.0 Beta', 'archived': False, 'released': True, 'releaseDate': '2016-11-04', 'userReleaseDate': "04 Nov '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15703', 'id': '15703', 'description': '5.8.0 RC 1', 'name': '5.8.0 RC', 'archived': False, 'released': True, 'releaseDate': '2016-12-22', 'userReleaseDate': "22 Dec '16", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15704', 'id': '15704', 'description': '5.8.0', 'name': '5.8.0', 'archived': False, 'released': True, 'releaseDate': '2017-01-23', 'userReleaseDate': "23 Jan '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15700', 'id': '15700', 'description': '5.8', 'name': '5.8', 'archived': False, 'released': True, 'releaseDate': '2017-01-23', 'userReleaseDate': "23 Jan '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15915', 'id': '15915', 'description': '5.9.0 Alpha 1', 'name': '5.9.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2017-02-23', 'userReleaseDate': "23 Feb '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16003', 'id': '16003', 'description': '5.9.0 Beta 1', 'name': '5.9.0 Beta 1', 'archived': False, 'released': True, 'releaseDate': '2017-04-07', 'userReleaseDate': "07 Apr '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16328', 'id': '16328', 'description': '5.9.0 Beta 2', 'name': '5.9.0 Beta 2', 'archived': False, 'released': True, 'releaseDate': '2017-04-21', 'userReleaseDate': "21 Apr '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16329', 'id': '16329', 'description': '5.9.0 Beta 3', 'name': '5.9.0 Beta 3', 'archived': False, 'released': True, 'releaseDate': '2017-05-02', 'userReleaseDate': "02 May '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16332', 'id': '16332', 'description': '5.9.0 Beta 4', 'name': '5.9.0 Beta 4', 'archived': False, 'released': True, 'releaseDate': '2017-05-16', 'userReleaseDate': "16 May '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16311', 'id': '16311', 'description': '5.9.0 RC 1', 'name': '5.9.0 RC', 'archived': False, 'released': True, 'releaseDate': '2017-05-24', 'userReleaseDate': "24 May '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16607', 'id': '16607', 'description': '5.9.0 RC 2', 'name': '5.9.0 RC 2', 'archived': False, 'released': True, 'releaseDate': '2017-05-29', 'userReleaseDate': "29 May '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16312', 'id': '16312', 'description': '5.9.0', 'name': '5.9.0', 'archived': False, 'released': True, 'releaseDate': '2017-05-31', 'userReleaseDate': "31 May '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16334', 'id': '16334', 'description': '5.9.1', 'name': '5.9.1', 'archived': False, 'released': True, 'releaseDate': '2017-06-30', 'userReleaseDate': "30 Jun '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16611', 'id': '16611', 'description': '5.9.2', 'name': '5.9.2', 'archived': False, 'released': True, 'releaseDate': '2017-10-06', 'userReleaseDate': "06 Oct '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16612', 'id': '16612', 'description': '5.9.3', 'name': '5.9.3', 'archived': False, 'released': True, 'releaseDate': '2017-11-22', 'userReleaseDate': "22 Nov '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16781', 'id': '16781', 'description': '5.10.0 RC2', 'name': '5.10.0 RC2', 'archived': False, 'released': True, 'releaseDate': '2017-12-01', 'userReleaseDate': "01 Dec '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16784', 'id': '16784', 'description': '5.10.0 RC3', 'name': '5.10.0 RC3', 'archived': False, 'released': True, 'releaseDate': '2017-12-04', 'userReleaseDate': "04 Dec '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16613', 'id': '16613', 'description': '5.10 Alpha 1', 'name': '5.10.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2017-09-13', 'userReleaseDate': "13 Sep '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16614', 'id': '16614', 'description': '5.10.0 Beta 1', 'name': '5.10.0 Beta 1', 'archived': False, 'released': True, 'releaseDate': '2017-10-09', 'userReleaseDate': "09 Oct '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16726', 'id': '16726', 'description': '5.10.0 Beta 2', 'name': '5.10.0 Beta 2', 'archived': False, 'released': True, 'releaseDate': '2017-10-25', 'userReleaseDate': "25 Oct '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16727', 'id': '16727', 'description': '5.10.0 Beta 3', 'name': '5.10.0 Beta 3', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16752', 'id': '16752', 'description': '5.10.0 Beta 4', 'name': '5.10.0 Beta 4', 'archived': False, 'released': True, 'releaseDate': '2017-11-10', 'userReleaseDate': "10 Nov '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16615', 'id': '16615', 'description': '5.10.0 RC 1', 'name': '5.10.0 RC', 'archived': False, 'released': True, 'releaseDate': '2017-11-27', 'userReleaseDate': "27 Nov '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16616', 'id': '16616', 'description': '5.10.0', 'name': '5.10.0', 'archived': False, 'released': True, 'releaseDate': '2017-12-07', 'userReleaseDate': "07 Dec '17", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16757', 'id': '16757', 'description': '5.9.4', 'name': '5.9.4', 'archived': False, 'released': True, 'releaseDate': '2018-01-23', 'userReleaseDate': "23 Jan '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16802', 'id': '16802', 'description': '5.9.5', 'name': '5.9.5', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16836', 'id': '16836', 'description': '5.9.6', 'name': '5.9.6', 'archived': False, 'released': True, 'releaseDate': '2018-06-11', 'userReleaseDate': "11 Jun '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16917', 'id': '16917', 'description': '5.9.7', 'name': '5.9.7', 'archived': False, 'released': False, 'startDate': '2018-05-22', 'releaseDate': '2018-09-26', 'overdue': False, 'userStartDate': "22 May '18", 'userReleaseDate': "26 Sep '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16002', 'id': '16002', 'description': '5.9', 'name': '5.9', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16776', 'id': '16776', 'description': '5.10.1', 'name': '5.10.1', 'archived': False, 'released': True, 'releaseDate': '2018-02-13', 'userReleaseDate': "13 Feb '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16309', 'id': '16309', 'description': '5.10', 'name': '5.10', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16909', 'id': '16909', 'description': '5.11.0 RC2', 'name': '5.11.0 RC2', 'archived': False, 'released': True, 'startDate': '2018-05-08', 'releaseDate': '2018-05-16', 'userStartDate': "08 May '18", 'userReleaseDate': "16 May '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16791', 'id': '16791', 'description': '5.11.0 Alpha', 'name': '5.11.0 Alpha', 'archived': False, 'released': True, 'releaseDate': '2018-02-20', 'userReleaseDate': "20 Feb '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16792', 'id': '16792', 'description': '5.11.0 Beta 1', 'name': '5.11.0 Beta 1', 'archived': False, 'released': True, 'releaseDate': '2018-03-21', 'userReleaseDate': "21 Mar '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16793', 'id': '16793', 'description': '5.11.0 Beta 2', 'name': '5.11.0 Beta 2', 'archived': False, 'released': True, 'releaseDate': '2018-03-28', 'userReleaseDate': "28 Mar '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16794', 'id': '16794', 'description': '5.11.0 Beta 3', 'name': '5.11.0 Beta 3', 'archived': False, 'released': True, 'releaseDate': '2018-04-11', 'userReleaseDate': "11 Apr '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16795', 'id': '16795', 'description': '5.11.0 Beta 4', 'name': '5.11.0 Beta 4', 'archived': False, 'released': True, 'releaseDate': '2018-04-20', 'userReleaseDate': "20 Apr '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16796', 'id': '16796', 'description': '5.11.0 RC 1', 'name': '5.11.0 RC 1', 'archived': False, 'released': True, 'releaseDate': '2018-05-08', 'userReleaseDate': "08 May '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16790', 'id': '16790', 'description': '5.11.0', 'name': '5.11.0', 'archived': False, 'released': True, 'releaseDate': '2018-05-22', 'userReleaseDate': "22 May '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16852', 'id': '16852', 'description': '5.11.1', 'name': '5.11.1', 'archived': False, 'released': True, 'releaseDate': '2018-06-19', 'userReleaseDate': "19 Jun '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16916', 'id': '16916', 'description': '5.11.2', 'name': '5.11.2', 'archived': False, 'released': False, 'startDate': '2018-06-07', 'releaseDate': '2018-08-31', 'overdue': False, 'userStartDate': "07 Jun '18", 'userReleaseDate': "31 Aug '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16310', 'id': '16310', 'description': '5.11', 'name': '5.11', 'archived': False, 'released': False, 'releaseDate': '2020-05-22', 'overdue': False, 'userReleaseDate': "22 May '20", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16832', 'id': '16832', 'description': '5.12.0 Alpha 1', 'name': '5.12.0 Alpha', 'archived': False, 'released': False, 'releaseDate': '2018-08-20', 'overdue': True, 'userReleaseDate': "20 Aug '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16837', 'id': '16837', 'description': '5.12.0 Beta 1', 'name': '5.12.0 Beta 1', 'archived': False, 'released': False, 'releaseDate': '2018-09-18', 'overdue': False, 'userReleaseDate': "18 Sep '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16853', 'id': '16853', 'description': '5.12.0 RC 1', 'name': '5.12.0 RC', 'archived': False, 'released': False, 'releaseDate': '2018-11-15', 'overdue': False, 'userReleaseDate': "15 Nov '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16854', 'id': '16854', 'description': '5.12.0', 'name': '5.12.0', 'archived': False, 'released': False, 'releaseDate': '2018-11-29', 'overdue': False, 'userReleaseDate': "29 Nov '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16855', 'id': '16855', 'description': '5.12.1', 'name': '5.12.1', 'archived': False, 'released': False, 'releaseDate': '2019-01-17', 'overdue': False, 'userReleaseDate': "17 Jan '19", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16710', 'id': '16710', 'description': '5.12', 'name': '5.12', 'archived': False, 'released': False, 'releaseDate': '2018-11-30', 'overdue': False, 'userReleaseDate': "30 Nov '18", 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/17007', 'id': '17007', 'description': '5.13.0 Alpha 1', 'name': '5.13.0 Alpha 1', 'archived': False, 'released': True, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/17008', 'id': '17008', 'description': '5.13.0 Beta 1', 'name': '5.13.0 Beta 1', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/17009', 'id': '17009', 'description': '5.13.0 RC 1', 'name': '5.13.0 RC 1', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/17006', 'id': '17006', 'description': '5.13.0', 'name': '5.13.0', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/17000', 'id': '17000', 'description': '5.13', 'name': '5.13', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/17010', 'id': '17010', 'description': '6.0.0', 'name': '6.0.0', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12127', 'id': '12127', 'description': '6.0', 'name': '6.0 (Next Major Release)', 'archived': False, 'released': False, 'projectId': 10510},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11533', 'id': '11533', 'description': 'Some future release', 'name': 'Some future release', 'archived': False, 'released': False, 'projectId': 10510},
]


@pytest.mark.parametrize("branch,expected", [
    ('', None),
    ('something', None),
    ('5.9', None),
    ('5.9.5', '16802'),
    ('5.9.6', '16836'),
    ('5.9.7', '16917'),
    ('5.12', None),
    ('5.12.0', '16832'),
    ('5.12.1', '16855'),
    ('5.12.2', None),
    ('5.13.0', '17008'),  # should give Beta 1, the data above is manipulated to test this case
    ('dev', None),
    ('master', None),
    ('6.0.0', '17010'),
])
def test_jira_versions(branch: str, expected: str):
    version_id = closer._guess_fix_version(branch, JiraCloser._clean_jira_versions(jira_qt_versions))
    assert version_id == expected


# Qt Creator
creator_versions = [
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11470', 'id': '11470', 'name': 'Qt Creator 1.0', 'archived': False, 'released': True, 'releaseDate': '2009-03-12', 'userReleaseDate': "12 Mar '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11471', 'id': '11471', 'name': 'Qt Creator 1.1', 'archived': False, 'released': True, 'releaseDate': '2009-04-23', 'userReleaseDate': "23 Apr '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11550', 'id': '11550', 'name': 'Qt Creator 1.1.1', 'archived': False, 'released': True, 'releaseDate': '2009-05-27', 'userReleaseDate': "27 May '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11472', 'id': '11472', 'name': 'Qt Creator 1.2', 'archived': False, 'released': True, 'releaseDate': '2009-06-25', 'userReleaseDate': "25 Jun '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11473', 'id': '11473', 'name': 'Qt Creator 1.2.1', 'archived': False, 'released': True, 'releaseDate': '2009-07-14', 'userReleaseDate': "14 Jul '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11551', 'id': '11551', 'name': 'Qt Creator 1.2.90', 'archived': False, 'released': True, 'releaseDate': '2009-09-10', 'userReleaseDate': "10 Sep '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11475', 'id': '11475', 'name': 'Qt Creator 1.3.0 rc1', 'archived': False, 'released': True, 'releaseDate': '2009-11-17', 'userReleaseDate': "17 Nov '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11568', 'id': '11568', 'name': 'Qt Creator 1.3.0', 'archived': False, 'released': True, 'releaseDate': '2009-12-01', 'userReleaseDate': "01 Dec '09", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11474', 'id': '11474', 'name': 'Qt Creator 1.3.1', 'archived': False, 'released': True, 'releaseDate': '2010-01-19', 'userReleaseDate': "19 Jan '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11590', 'id': '11590', 'name': 'Qt Creator 1.3.81 (2.0.0-alpha)', 'archived': False, 'released': True, 'releaseDate': '2010-03-11', 'userReleaseDate': "11 Mar '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11565', 'id': '11565', 'name': 'Qt Creator 1.3.83 (2.0.0-beta)', 'archived': False, 'released': True, 'releaseDate': '2010-05-06', 'userReleaseDate': "06 May '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11610', 'id': '11610', 'name': 'Qt Creator 1.3.85 (2.0.0-rc1)', 'archived': False, 'released': True, 'releaseDate': '2010-06-09', 'userReleaseDate': "09 Jun '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11652', 'id': '11652', 'name': 'Qt Creator 2.0.0', 'archived': False, 'released': True, 'releaseDate': '2010-06-23', 'userReleaseDate': "23 Jun '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11675', 'id': '11675', 'name': 'Qt Creator 2.0.1', 'archived': False, 'released': True, 'releaseDate': '2010-08-25', 'userReleaseDate': "25 Aug '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11719', 'id': '11719', 'name': 'Qt Creator 2.1.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2010-10-07', 'userReleaseDate': "07 Oct '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11732', 'id': '11732', 'name': 'Qt Creator 2.1.0-beta2', 'archived': False, 'released': True, 'releaseDate': '2010-11-09', 'userReleaseDate': "09 Nov '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11720', 'id': '11720', 'name': 'Qt Creator 2.1.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2010-11-25', 'userReleaseDate': "25 Nov '10", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11704', 'id': '11704', 'name': 'Qt Creator 2.1.0', 'archived': False, 'released': True, 'releaseDate': '2011-03-01', 'userReleaseDate': "01 Mar '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11832', 'id': '11832', 'name': 'Qt Creator 2.2.0-beta', 'archived': False, 'released': True, 'releaseDate': '2011-03-24', 'userReleaseDate': "24 Mar '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11841', 'id': '11841', 'name': 'Qt Creator 2.2.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2011-04-19', 'userReleaseDate': "19 Apr '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11705', 'id': '11705', 'name': 'Qt Creator 2.2.0', 'archived': False, 'released': True, 'releaseDate': '2011-05-06', 'userReleaseDate': "06 May '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11860', 'id': '11860', 'name': 'Qt Creator 2.2.1', 'archived': False, 'released': True, 'releaseDate': '2011-06-21', 'userReleaseDate': "21 Jun '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11877', 'id': '11877', 'name': 'Qt Creator 2.3.0-beta', 'archived': False, 'released': True, 'releaseDate': '2011-07-13', 'userReleaseDate': "13 Jul '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11880', 'id': '11880', 'name': 'Qt Creator 2.3.0-rc', 'archived': False, 'released': True, 'releaseDate': '2011-08-11', 'userReleaseDate': "11 Aug '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11802', 'id': '11802', 'name': 'Qt Creator 2.3.0', 'archived': False, 'released': True, 'releaseDate': '2011-09-01', 'userReleaseDate': "01 Sep '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11885', 'id': '11885', 'name': 'Qt Creator 2.3.1', 'archived': False, 'released': True, 'releaseDate': '2011-09-29', 'userReleaseDate': "29 Sep '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11897', 'id': '11897', 'name': 'Qt Creator 2.4.0-beta', 'archived': False, 'released': True, 'releaseDate': '2011-10-20', 'userReleaseDate': "20 Oct '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11904', 'id': '11904', 'name': 'Qt Creator 2.4.0-rc', 'archived': False, 'released': True, 'releaseDate': '2011-11-16', 'userReleaseDate': "16 Nov '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11835', 'id': '11835', 'name': 'Qt Creator 2.4.0', 'archived': False, 'released': True, 'releaseDate': '2011-12-13', 'userReleaseDate': "13 Dec '11", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11903', 'id': '11903', 'name': 'Qt Creator 2.4.1', 'archived': False, 'released': True, 'releaseDate': '2012-02-01', 'userReleaseDate': "01 Feb '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11876', 'id': '11876', 'name': 'Qt Creator 2.5.0-beta', 'archived': False, 'released': True, 'releaseDate': '2012-03-15', 'userReleaseDate': "15 Mar '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12119', 'id': '12119', 'name': 'Qt Creator 2.5.0-rc', 'archived': False, 'released': True, 'releaseDate': '2012-04-23', 'userReleaseDate': "23 Apr '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12131', 'id': '12131', 'name': 'Qt Creator 2.5.0', 'archived': False, 'released': True, 'releaseDate': '2012-05-09', 'userReleaseDate': "09 May '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12133', 'id': '12133', 'name': 'Qt Creator 2.5.1', 'archived': False, 'released': True, 'releaseDate': '2012-07-25', 'userReleaseDate': "25 Jul '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12401', 'id': '12401', 'name': 'Qt Creator 2.5.2', 'archived': False, 'released': True, 'releaseDate': '2012-08-09', 'userReleaseDate': "09 Aug '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12405', 'id': '12405', 'name': 'Qt Creator 2.6.0-beta', 'archived': False, 'released': True, 'releaseDate': '2012-09-11', 'userReleaseDate': "11 Sep '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/11894', 'id': '11894', 'name': 'Qt Creator 2.6.0-rc', 'archived': False, 'released': True, 'releaseDate': '2012-10-17', 'userReleaseDate': "17 Oct '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12503', 'id': '12503', 'name': 'Qt Creator 2.6.0', 'archived': False, 'released': True, 'releaseDate': '2012-11-08', 'userReleaseDate': "08 Nov '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12504', 'id': '12504', 'name': 'Qt Creator 2.6.1', 'archived': False, 'released': True, 'releaseDate': '2012-12-19', 'userReleaseDate': "19 Dec '12", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12603', 'id': '12603', 'name': 'Qt Creator 2.6.2', 'archived': False, 'released': True, 'releaseDate': '2013-01-31', 'userReleaseDate': "31 Jan '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12611', 'id': '12611', 'name': 'Qt Creator 2.7.0-beta', 'archived': False, 'released': True, 'releaseDate': '2013-02-07', 'userReleaseDate': "07 Feb '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12615', 'id': '12615', 'name': 'Qt Creator 2.7.0-rc', 'archived': False, 'released': True, 'releaseDate': '2013-03-07', 'userReleaseDate': "07 Mar '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12117', 'id': '12117', 'name': 'Qt Creator 2.7.0', 'archived': False, 'released': True, 'releaseDate': '2013-03-21', 'userReleaseDate': "21 Mar '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12614', 'id': '12614', 'name': 'Qt Creator 2.7.1', 'archived': False, 'released': True, 'releaseDate': '2013-05-14', 'userReleaseDate': "14 May '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12701', 'id': '12701', 'name': 'Qt Creator 2.7.2', 'archived': False, 'released': True, 'releaseDate': '2013-07-03', 'userReleaseDate': "03 Jul '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12608', 'id': '12608', 'name': 'Qt Creator 2.8.0-beta', 'archived': False, 'released': True, 'releaseDate': '2013-05-30', 'userReleaseDate': "30 May '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12800', 'id': '12800', 'name': 'Qt Creator 2.8.0-rc', 'archived': False, 'released': True, 'releaseDate': '2013-06-28', 'userReleaseDate': "28 Jun '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13005', 'id': '13005', 'name': 'Qt Creator 2.8.0', 'archived': False, 'released': True, 'releaseDate': '2013-07-11', 'userReleaseDate': "11 Jul '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13000', 'id': '13000', 'name': 'Qt Creator 2.8.1', 'archived': False, 'released': True, 'releaseDate': '2013-08-28', 'userReleaseDate': "28 Aug '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13206', 'id': '13206', 'name': 'Qt Creator 3.0.0-beta', 'archived': False, 'released': True, 'releaseDate': '2013-10-23', 'userReleaseDate': "23 Oct '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/12702', 'id': '12702', 'name': 'Qt Creator 3.0.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2013-11-29', 'userReleaseDate': "29 Nov '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13401', 'id': '13401', 'name': 'Qt Creator 3.0.0', 'archived': False, 'released': True, 'releaseDate': '2013-12-12', 'userReleaseDate': "12 Dec '13", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13402', 'id': '13402', 'name': 'Qt Creator 3.0.1', 'archived': False, 'released': True, 'releaseDate': '2014-02-05', 'userReleaseDate': "05 Feb '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13204', 'id': '13204', 'name': 'Qt Creator 3.1.0-beta', 'archived': False, 'released': True, 'releaseDate': '2014-03-04', 'userReleaseDate': "04 Mar '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13700', 'id': '13700', 'name': 'Qt Creator 3.1.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2014-04-03', 'userReleaseDate': "03 Apr '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13800', 'id': '13800', 'name': 'Qt Creator 3.1.0', 'archived': False, 'released': True, 'releaseDate': '2014-04-15', 'userReleaseDate': "15 Apr '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13902', 'id': '13902', 'name': 'Qt Creator 3.1.1', 'archived': False, 'released': True, 'releaseDate': '2014-05-20', 'userReleaseDate': "20 May '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14002', 'id': '14002', 'name': 'Qt Creator 3.1.2', 'archived': False, 'released': True, 'releaseDate': '2014-06-25', 'userReleaseDate': "25 Jun '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/13600', 'id': '13600', 'name': 'Qt Creator 3.2.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2014-07-08', 'userReleaseDate': "08 Jul '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14011', 'id': '14011', 'name': 'Qt Creator 3.2.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2014-08-05', 'userReleaseDate': "05 Aug '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14101', 'id': '14101', 'name': 'Qt Creator 3.2.0', 'archived': False, 'released': True, 'releaseDate': '2014-08-19', 'userReleaseDate': "19 Aug '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14102', 'id': '14102', 'name': 'Qt Creator 3.2.1', 'archived': False, 'released': True, 'releaseDate': '2014-09-16', 'userReleaseDate': "16 Sep '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14304', 'id': '14304', 'name': 'Qt Creator 3.2.2', 'archived': False, 'released': True, 'releaseDate': '2014-10-14', 'userReleaseDate': "14 Oct '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14006', 'id': '14006', 'name': 'Qt Creator 3.3.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2014-10-30', 'userReleaseDate': "30 Oct '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14309', 'id': '14309', 'name': 'Qt Creator 3.3.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2014-11-27', 'userReleaseDate': "27 Nov '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14401', 'id': '14401', 'name': 'Qt Creator 3.3.0', 'archived': False, 'released': True, 'releaseDate': '2014-12-10', 'userReleaseDate': "10 Dec '14", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14402', 'id': '14402', 'name': 'Qt Creator 3.3.1', 'archived': False, 'released': True, 'releaseDate': '2015-02-24', 'userReleaseDate': "24 Feb '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14800', 'id': '14800', 'name': 'Qt Creator 3.3.2', 'archived': False, 'released': True, 'releaseDate': '2015-03-05', 'userReleaseDate': "05 Mar '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14308', 'id': '14308', 'name': 'Qt Creator 3.4.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2015-03-05', 'userReleaseDate': "05 Mar '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14902', 'id': '14902', 'name': 'Qt Creator 3.4.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2015-04-01', 'userReleaseDate': "01 Apr '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14904', 'id': '14904', 'name': 'Qt Creator 3.4.0', 'archived': False, 'released': True, 'releaseDate': '2015-04-23', 'userReleaseDate': "23 Apr '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15000', 'id': '15000', 'name': 'Qt Creator 3.4.1', 'archived': False, 'released': True, 'releaseDate': '2015-06-02', 'userReleaseDate': "02 Jun '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15104', 'id': '15104', 'name': 'Qt Creator 3.4.2', 'archived': False, 'released': True, 'releaseDate': '2015-07-01', 'userReleaseDate': "01 Jul '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/14701', 'id': '14701', 'name': 'Qt Creator 3.5.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2015-07-08', 'userReleaseDate': "08 Jul '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15202', 'id': '15202', 'name': 'Qt Creator 3.5.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2015-08-06', 'userReleaseDate': "06 Aug '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15204', 'id': '15204', 'name': 'Qt Creator 3.5.0', 'archived': False, 'released': True, 'releaseDate': '2015-08-20', 'userReleaseDate': "20 Aug '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15300', 'id': '15300', 'name': 'Qt Creator 3.5.1', 'archived': False, 'released': True, 'releaseDate': '2015-10-15', 'userReleaseDate': "15 Oct '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15200', 'id': '15200', 'name': 'Qt Creator 3.6.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2015-10-27', 'userReleaseDate': "27 Oct '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15405', 'id': '15405', 'name': 'Qt Creator 3.6.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2015-11-26', 'userReleaseDate': "26 Nov '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15408', 'id': '15408', 'name': 'Qt Creator 3.6.0', 'archived': False, 'released': True, 'releaseDate': '2015-12-15', 'userReleaseDate': "15 Dec '15", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15413', 'id': '15413', 'name': 'Qt Creator 3.6.1', 'archived': False, 'released': True, 'releaseDate': '2016-03-16', 'userReleaseDate': "16 Mar '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15404', 'id': '15404', 'name': 'Qt Creator 4.0.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2016-03-23', 'userReleaseDate': "23 Mar '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15766', 'id': '15766', 'name': 'Qt Creator 4.0.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2016-04-20', 'userReleaseDate': "20 Apr '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15787', 'id': '15787', 'name': 'Qt Creator 4.0.0', 'archived': False, 'released': True, 'releaseDate': '2016-05-11', 'userReleaseDate': "11 May '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15789', 'id': '15789', 'name': 'Qt Creator 4.0.1', 'archived': False, 'released': True, 'releaseDate': '2016-06-08', 'userReleaseDate': "08 Jun '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15800', 'id': '15800', 'name': 'Qt Creator 4.0.2', 'archived': False, 'released': True, 'releaseDate': '2016-06-16', 'userReleaseDate': "16 Jun '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15804', 'id': '15804', 'name': 'Qt Creator 4.0.3', 'archived': False, 'released': True, 'releaseDate': '2016-07-07', 'userReleaseDate': "07 Jul '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15706', 'id': '15706', 'name': 'Qt Creator 4.1.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2016-07-06', 'userReleaseDate': "06 Jul '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15903', 'id': '15903', 'name': 'Qt Creator 4.1.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2016-08-08', 'userReleaseDate': "08 Aug '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15910', 'id': '15910', 'name': 'Qt Creator 4.1.0', 'archived': False, 'released': True, 'releaseDate': '2016-08-25', 'userReleaseDate': "25 Aug '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/15807', 'id': '15807', 'name': 'Qt Creator 4.2.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2016-10-27', 'userReleaseDate': "27 Oct '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16101', 'id': '16101', 'name': 'Qt Creator 4.2.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2016-11-30', 'userReleaseDate': "30 Nov '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16207', 'id': '16207', 'name': 'Qt Creator 4.2.0', 'archived': False, 'released': True, 'releaseDate': '2016-12-14', 'userReleaseDate': "14 Dec '16", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16210', 'id': '16210', 'name': 'Qt Creator 4.2.1', 'archived': False, 'released': True, 'releaseDate': '2017-01-23', 'userReleaseDate': "23 Jan '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16301', 'id': '16301', 'name': 'Qt Creator 4.2.2', 'archived': False, 'released': True, 'releaseDate': '2017-04-21', 'userReleaseDate': "21 Apr '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16001', 'id': '16001', 'name': 'Qt Creator 4.3.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2017-03-30', 'userReleaseDate': "30 Mar '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16323', 'id': '16323', 'name': 'Qt Creator 4.3.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2017-05-09', 'userReleaseDate': "09 May '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16335', 'id': '16335', 'name': 'Qt Creator 4.3.0', 'archived': False, 'released': True, 'releaseDate': '2017-05-24', 'userReleaseDate': "24 May '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16600', 'id': '16600', 'name': 'Qt Creator 4.3.1', 'archived': False, 'released': True, 'releaseDate': '2017-06-30', 'userReleaseDate': "30 Jun '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16306', 'id': '16306', 'name': 'Qt Creator 4.4.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2017-07-20', 'userReleaseDate': "20 Jul '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16701', 'id': '16701', 'name': 'Qt Creator 4.4.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2017-08-17', 'userReleaseDate': "17 Aug '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16716', 'id': '16716', 'name': 'Qt Creator 4.4.0', 'archived': False, 'released': True, 'releaseDate': '2017-09-05', 'userReleaseDate': "05 Sep '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16721', 'id': '16721', 'name': 'Qt Creator 4.4.1', 'archived': False, 'released': True, 'releaseDate': '2017-10-06', 'userReleaseDate': "06 Oct '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16308', 'id': '16308', 'name': 'Qt Creator 4.5.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2017-10-12', 'userReleaseDate': "12 Oct '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16744', 'id': '16744', 'name': 'Qt Creator 4.5.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2017-11-22', 'userReleaseDate': "22 Nov '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16779', 'id': '16779', 'description': '4.5.0', 'name': 'Qt Creator 4.5.0', 'archived': False, 'released': True, 'releaseDate': '2017-12-07', 'userReleaseDate': "07 Dec '17", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16787', 'id': '16787', 'description': '4.5.1', 'name': 'Qt Creator 4.5.1', 'archived': False, 'released': True, 'releaseDate': '2018-02-13', 'userReleaseDate': "13 Feb '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16830', 'id': '16830', 'description': '4.5.2', 'name': 'Qt Creator 4.5.2', 'archived': False, 'released': True, 'releaseDate': '2018-03-13', 'userReleaseDate': "13 Mar '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16737', 'id': '16737', 'description': '4.6.0 Beta 1', 'name': 'Qt Creator 4.6.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2018-02-07', 'userReleaseDate': "07 Feb '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16812', 'id': '16812', 'description': '4.6.0 RC 1', 'name': 'Qt Creator 4.6.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2018-03-15', 'userReleaseDate': "15 Mar '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16838', 'id': '16838', 'description': '4.6.0', 'name': 'Qt Creator 4.6.0 ', 'archived': False, 'released': True, 'releaseDate': '2018-03-28', 'userReleaseDate': "28 Mar '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16840', 'id': '16840', 'description': '4.6.1', 'name': 'Qt Creator 4.6.1', 'archived': False, 'released': True, 'releaseDate': '2018-05-03', 'userReleaseDate': "03 May '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16900', 'id': '16900', 'description': '4.6.2', 'name': 'Qt Creator 4.6.2', 'archived': False, 'released': True, 'releaseDate': '2018-06-11', 'userReleaseDate': "11 Jun '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16758', 'id': '16758', 'description': '4.7.0 Beta 1', 'name': 'Qt Creator 4.7.0-beta1', 'archived': False, 'released': True, 'releaseDate': '2018-06-05', 'userReleaseDate': "05 Jun '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16921', 'id': '16921', 'description': '4.7.0 Beta 2', 'name': 'Qt Creator 4.7.0-beta2', 'archived': False, 'released': True, 'releaseDate': '2018-06-21', 'userReleaseDate': "21 Jun '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16932', 'id': '16932', 'description': '4.7.0 RC 1', 'name': 'Qt Creator 4.7.0-rc1', 'archived': False, 'released': True, 'releaseDate': '2018-07-05', 'userReleaseDate': "05 Jul '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16935', 'id': '16935', 'description': '4.7.0', 'name': 'Qt Creator 4.7.0', 'archived': False, 'released': True, 'releaseDate': '2018-07-18', 'userReleaseDate': "18 Jul '18", 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16937', 'id': '16937', 'description': '4.7.1', 'name': 'Qt Creator 4.7.1 (4.7 branch)', 'archived': False, 'released': False, 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16759', 'id': '16759', 'description': '4.8.0 Beta 1', 'name': 'Qt Creator 4.8.0 (master branch)', 'archived': False, 'released': False, 'projectId': 10512},
    {'self': 'https://bugreports-test.qt.io/rest/api/2/version/16819', 'id': '16819', 'description': '4.9.0 Beta 1', 'name': 'Qt Creator 4.9.0', 'archived': False, 'released': False, 'projectId': 10512},
]


@pytest.mark.parametrize("branch,expected", [
    ('', None),
    ('something', None),
    ('4.5.0', '16779'),
    ('4.6.0', '16838'),
    ('4.6.1', '16840'),
    ('4.6.2', '16900'),
    ('4.6.3', None),
    ('4.7.0', '16935'),
    ('4.7.1', '16937'),
    # resolved before, should never get there, so rather make sure we return just None
    ('master', None),
    ('dev', None),
])
def test_jira_versions_creator(branch: str, expected: str):
    version_id = closer._guess_fix_version(branch, JiraCloser._clean_jira_versions(creator_versions))
    assert version_id == expected


@pytest.mark.parametrize("jira_version_list,expected", [
    (creator_versions, [(LooseVersion('4.5.0'), '16779', True), (LooseVersion('4.5.1'), '16787', True), (LooseVersion('4.5.2'), '16830', True), (LooseVersion('4.6.0 Beta 1'), '16737', True), (LooseVersion('4.6.0 RC 1'), '16812', True), (LooseVersion('4.6.0'), '16838', True), (LooseVersion('4.6.1'), '16840', True), (LooseVersion('4.6.2'), '16900', True), (LooseVersion('4.7.0 Beta 1'), '16758', True), (LooseVersion('4.7.0 Beta 2'), '16921', True), (LooseVersion('4.7.0 RC 1'), '16932', True), (LooseVersion('4.7.0'), '16935', True), (LooseVersion('4.7.1'), '16937', False), (LooseVersion('4.8.0 Beta 1'), '16759', False), (LooseVersion('4.9.0 Beta 1'), '16819', False)]),
])
def test_jira_versions_to_dict(jira_version_list: List[Dict[str, str]], expected: List[Tuple[LooseVersion, str, bool]]):
    versions = JiraCloser._clean_jira_versions(jira_version_list)
    assert versions == expected
