# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

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
