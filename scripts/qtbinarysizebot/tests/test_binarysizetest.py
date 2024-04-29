#!/usr/bin/env python3
# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import unittest
import binarysizetest
import datetime
import requests_mock
import mock
import pytest

class db:
    def __init__(self):
        self.last_value = 0

    def get_last_timestamp(self) -> datetime.datetime:
        return self.last_timestamp

    def push(self, series: str, commit_url: str, coin_task_datetime : datetime.datetime, binary: str, value: int):
        self.last_value = value
        self.last_timestamp = coin_task_datetime

    def pull(self, entry) -> float:
        return self.last_value

class TestBinarySizeTest(unittest.TestCase):
    @classmethod
    def setUpClass(self):
        self.db_stub =  db()

    @classmethod
    def tearDownClass(self):
        self.db_stub = None

    @mock.patch("builtins.open", new_callable=mock.mock_open, read_data='{ \
        "branch": "test_dev",     \
        "integration": "test_project", \
        "series": "test_series", \
        "coin_id": "test_coin_id", \
        "builds_to_check" : [ { \
            "name": "qt/qtdeclarative", \
            "size_comparision": [ \
            { "file": "bin/qml", "threshold": 0.05 } \
        ] } ] }')
    def init_test(self, open_mock):
        testable = binarysizetest.BinarySizeTest("qtlite_tests.json", self.db_stub)

        return testable

    def test_email_content(self):
        entry_datetime = datetime.datetime(2019, 5, 18, 15, 17, tzinfo=datetime.timezone.utc)
        [topic, message] = self.init_test().email_content(
            "1001", entry_datetime, entry_datetime, ["sha1", "sha2"])
        self.maxDiff = 2000
        self.assertEqual(topic, "Binary size increased over threshold")
        self.assertEqual(message, ("Hi, "
            "This alert comes from qt-binary-size-bot.\n"
            "\n"
            "The bot is monitoring test_coin_id for test_project integration in test_dev branch "
            "with the following configuration:\n"
            "[{\'name\': \'qt/qtdeclarative\', \'size_comparision\': [{\'file\': \'bin/qml\', \'threshold\': 0.05}]}]\n"
            "You can find the histogram at: http://testresults.qt.io/grafana/goto/JDaMrUaSR?orgId=1\n"
            "The failed build used artifacts from COIN job id: "
            "https://coin.intra.qt.io/coin/integration/test_project/tasks/1001\n"
            "It's possible that the issue was introduced between 2019-05-18 15:17:00+00:00 and 2019-05-18 15:17:00+00:00 UTC.\n"
            "Related commits: [\'sha1\', \'sha2\']\n"
            "\n"
            "For now, this alert is just an informal notification.\n"
            "If you could add functionality behind existing or new Qt feature flags, please check your commit.\n"
            "For more information, feel free to ask the person who is CC'd."))


    @requests_mock.Mocker()
    @mock.patch('binarysizetest.urllib')
    @mock.patch('binarysizetest.tarfile')
    @mock.patch('binarysizetest.os.stat')
    @mock.patch('binarysizetest.tempfile')
    @mock.patch('binarysizetest.os.path.exists', return_value=True)
    def test_run_ok_case(self, m, os_path_exists_mock, tempfile_mock, os_stat_mock, tarfile_mock, urllib_mock):
        m.get('https://coin.ci.qt.io/coin/api/taskWorkItems?id=last_task-id',
              text='{"tasks_with_workitems":                        \
                [{"workitems":                                      \
                [{  "identifier":"test_coin_id", \
                    "project":"qt/qtdeclarative",                   \
                    "branch":"test_dev",                            \
                    "state":"Done",                                 \
                    "storage_paths": {"log_raw": "/log.txt.gz"}     \
                        }]}]}')

        def get_mock_context(filename):
            mock_context = mock.MagicMock()
            mock_context.__enter__.return_value = mock_context
            mock_context.__exit__.return_value = False
            return mock_context
        tarfile_mock.open.side_effect = get_mock_context
        os_stat_mock().st_size = 10000
        tempfile_mock.TemporaryDirectory().__enter__.return_value = "test_temp_dir/"
        urllib_mock.request.urlretrieve.return_value = "artifacts.tar.gz", 200
        entry_datetime = datetime.datetime.now()
        testable = self.init_test()

        # Push initial value
        send_email = testable.run("last_task-id", entry_datetime, ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_called_with(
            "https://coin.intra.qt.io/artifacts.tar.gz", "test_temp_dir/artifacts.tar.gz")
        tarfile_mock.open.assert_called_with("test_temp_dir/artifacts.tar.gz")
        os_stat_mock.assert_called_with("test_temp_dir/install/bin/qml")

        self.assertEqual(self.db_stub.last_value, os_stat_mock().st_size)
        self.assertEqual(self.db_stub.last_timestamp, entry_datetime)
        self.assertEqual(send_email, False)

        # Push second value (same)
        send_email = testable.run("last_task-id", entry_datetime, ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_called_with(
            "https://coin.intra.qt.io/artifacts.tar.gz", "test_temp_dir/artifacts.tar.gz")
        tarfile_mock.open.assert_called_with("test_temp_dir/artifacts.tar.gz")
        os_stat_mock.assert_called_with("test_temp_dir/install/bin/qml")

        self.assertEqual(self.db_stub.last_value, os_stat_mock().st_size)
        self.assertEqual(self.db_stub.last_timestamp, entry_datetime)
        self.assertEqual(send_email, False)

        # Push third value (bigger)
        os_stat_mock().st_size = 11000
        send_email = testable.run("last_task-id", entry_datetime, ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_called_with(
            "https://coin.intra.qt.io/artifacts.tar.gz", "test_temp_dir/artifacts.tar.gz")
        tarfile_mock.open.assert_called_with("test_temp_dir/artifacts.tar.gz")
        os_stat_mock.assert_called_with("test_temp_dir/install/bin/qml")

        self.assertEqual(self.db_stub.last_value, os_stat_mock().st_size)
        self.assertEqual(self.db_stub.last_timestamp, entry_datetime)
        self.assertEqual(send_email, True)

        # Push fourth value (smaller)
        os_stat_mock().st_size = 10000
        send_email = testable.run("last_task-id", entry_datetime, ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_called_with(
            "https://coin.intra.qt.io/artifacts.tar.gz", "test_temp_dir/artifacts.tar.gz")
        tarfile_mock.open.assert_called_with("test_temp_dir/artifacts.tar.gz")
        os_stat_mock.assert_called_with("test_temp_dir/install/bin/qml")

        self.assertEqual(self.db_stub.last_value, os_stat_mock().st_size)
        self.assertEqual(self.db_stub.last_timestamp, entry_datetime)
        self.assertEqual(send_email, False)


    @requests_mock.Mocker()
    @mock.patch('binarysizetest.urllib')
    @mock.patch('binarysizetest.tarfile')
    @mock.patch('binarysizetest.os.stat')
    @mock.patch('binarysizetest.os.path.exists', return_value=True)
    def test_run_fail_wrong_state_case(self, m, os_path_exists_mock, os_stat_mock, tarfile_mock, urllib_mock):
        m.get('https://coin.ci.qt.io/coin/api/taskWorkItems?id=last_task-id',
              text='{"tasks_with_workitems":                        \
                [{"workitems":                                      \
                [{  "identifier":"test_coin_id",                    \
                    "project":"qt/qtdeclarative",                   \
                    "branch":"test_dev",                            \
                    "state":"Insignificant",                        \
                    "storage_paths": {"log_raw": "/log.txt.gz"}     \
                        }]}]}')

        with pytest.raises(Exception, match="Wrong state: Insignificant"):
            self.init_test().run("last_task-id", datetime.datetime.now(), ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_not_called()
        tarfile_mock.open.assert_not_called()
        os_stat_mock.assert_not_called()

    @requests_mock.Mocker()
    @mock.patch('binarysizetest.urllib')
    @mock.patch('binarysizetest.tarfile')
    @mock.patch('binarysizetest.os.stat')
    @mock.patch('binarysizetest.os.path.exists', return_value=True)
    def test_run_fail_wrong_identifier_case(self, m, os_path_exists_mock, os_stat_mock, tarfile_mock, urllib_mock):
        m.get('https://coin.ci.qt.io/coin/api/taskWorkItems?id=last_task-id',
              text='{"tasks_with_workitems":                        \
                [{"workitems":                                      \
                [{  "identifier":"wrong_test_coin_id",                    \
                    "project":"qt/qtdeclarative",                   \
                    "branch":"test_dev",                            \
                    "state":"Insignificant",                        \
                    "storage_paths": {"log_raw": "/log.txt.gz"}     \
                        }]}]}')
        with pytest.raises(Exception, match="No artifact url found for last_task-id.*"):
            self.init_test().run("last_task-id", datetime.datetime.now(), ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_not_called()
        tarfile_mock.open.assert_not_called()
        os_stat_mock.assert_not_called()

    @requests_mock.Mocker()
    @mock.patch('binarysizetest.urllib')
    @mock.patch('binarysizetest.tarfile')
    @mock.patch('binarysizetest.os.stat')
    @mock.patch('binarysizetest.os.path.exists', return_value=True)
    def test_run_fail_wrong_branch_case(self, m, os_path_exists_mock, os_stat_mock, tarfile_mock, urllib_mock):
        m.get('https://coin.ci.qt.io/coin/api/taskWorkItems?id=last_task-id',
              text='{"tasks_with_workitems":                        \
                [{"workitems":                                      \
                [{  "identifier":"test_coin_id",                    \
                    "project":"qt/qtdeclarative",                   \
                    "branch":"wrong_branch",                        \
                    "state":"Insignificant",                        \
                    "storage_paths": {"log_raw": "/log.txt.gz"}     \
                        }]}]}')
        with pytest.raises(Exception, match="Wrong branch: wrong_branch"):
            self.init_test().run("last_task-id", datetime.datetime.now(), ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_not_called()
        tarfile_mock.open.assert_not_called()
        os_stat_mock.assert_not_called()


    @requests_mock.Mocker()
    @mock.patch('binarysizetest.urllib')
    @mock.patch('binarysizetest.tarfile')
    @mock.patch('binarysizetest.os.stat')
    @mock.patch('binarysizetest.os.path.exists', return_value=True)
    def test_run_fail_no_results_case(self, m, os_path_exists_mock, os_stat_mock, tarfile_mock, urllib_mock):
        m.get('https://coin.ci.qt.io/coin/api/taskWorkItems?id=last_task-id',
              text='{"tasks_with_workitems":                        \
                [{"workitems": []                                   \
                        }]}')
        with pytest.raises(Exception, match="No artifact url found for last_task-id.*"):
            self.init_test().run("last_task-id", datetime.datetime.now(), ["sha1", "sha2"])
        urllib_mock.request.urlretrieve.assert_not_called()
        tarfile_mock.open.assert_not_called()
        os_stat_mock.assert_not_called()


