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

import os
from config import Config


def test_have_secrets():
    dir_name = os.path.join(os.path.dirname(os.path.abspath(__file__)))
    assert os.path.exists(os.path.join(dir_name, "../jira_gerrit_bot_id_rsa"))

    config = Config('production')
    oauth = config.get_oauth_data()
    assert oauth["access_token"] != "get_this_by_running_oauth_dance.py"
    assert oauth["access_token_secret"] != "get_this_by_running_oauth_dance.py"
    assert oauth["key_cert"]
