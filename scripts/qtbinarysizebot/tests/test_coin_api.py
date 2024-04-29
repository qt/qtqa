#!/usr/bin/env python3
# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import unittest
import coin_api
import datetime
import requests_mock


class TestCoinApi(unittest.TestCase):
    @requests_mock.Mocker()
    def test_task_details_ok_case(self, m):
        m.get('https://coin.ci.qt.io/coin/api/taskDetail',
              text='{"tasks":                                     \
                [{"state":"Passed",                               \
                  "completed_on":"2024-03-28 11:40:49 +0000 UTC", \
                  "id":"test_id",                                 \
                  "sha":"sha1",                          \
                  "tested_changes": [ { \
                     "sha": "sha2", \
                     "project": "project" \
                  },{ \
                     "sha": "sha3", \
                     "project": "project" \
                  }] \
                        }]}')

        dictionary = coin_api.get_coin_task_details("test_id")
        self.assertEqual(dictionary['coin_update_ongoing'],  False)
        self.assertEqual(dictionary['last_timestamp'], datetime.datetime.fromisoformat("2024-03-28 11:40:49").replace(tzinfo=datetime.timezone.utc))
        self.assertEqual(dictionary['git_shas'], ["sha2", "sha3"])

    @requests_mock.Mocker()
    def test_artifacts_url_ok_case(self, m):
        m.get('https://coin.ci.qt.io/coin/api/taskWorkItems',
              text='{"tasks_with_workitems":                   \
                [{"workitems":[{                               \
                  "project":"project",                         \
                  "branch":"branch",                           \
                  "identifier":"task_identifier",              \
                  "storage_paths": {"log_raw":"/log.txt.gz"},  \
                  "state":"Done"                               \
                        }]}]}')

        self.assertEqual(coin_api.get_artifacts_url("test_id", "project", "branch", "task_identifier"), "https://coin.intra.qt.io/artifacts.tar.gz")
