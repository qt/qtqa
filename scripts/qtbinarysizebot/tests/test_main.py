#!/usr/bin/env python3
# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import unittest
import mock
import json
import main
import datetime
import time
import threading
from tl.testing.thread import ThreadAwareTestCase
from tl.testing.thread import ThreadJoiner


class TestMain(ThreadAwareTestCase):
    @mock.patch('main.gerrit_api')
    @mock.patch('main.coin_api')
    @mock.patch('main.database')
    @mock.patch('main.binarysizetest')
    @mock.patch('main.email_alert')
    def test_parallel_callbacks(self, email_alert_mock, binarysize_mock, db_mock, coin_api_mock, gerrit_api_mock):
        db_mock.Database().get_last_timestamp.return_value = datetime.datetime(2020, 1, 1, 0, 0)
        config = json.loads(
            '{ "tests_json":"tests.json", "database_info": \
                {"server_url":"url", "database_name": "dbname", "username":"john", "password":"doe"}, \
                "email_info": {"smtp_server": "smtp.localhost", "email_sender": "t@t.io", "email_cc": "cc@t.io"}, \
                "gerrit_info": {"server_url": "codereview.qt-project.org", "server_port": 29418} \
                     }')
        testable = main.CallbackHandler(config)
        db_mock.Database().get_last_timestamp.assert_called()
        binarysize_mock.BinarySizeTest().email_content.return_value = ["topic", "message"]

        # First call. No email
        coin_api_mock.get_coin_task_details.return_value = {
            'coin_update_ongoing': False,
            'last_timestamp': datetime.datetime(2020, 1, 2, 0, 0),
            'git_shas': ["sha1", "sha2"]
        }
        self.called_amount = 0
        def run_delay(coin_id, timestamp, shas):
            self.called_amount += 1
            time.sleep(0.1)
            self.called_amount -= 1
            self.assertEqual(self.called_amount, 0)
            return False
        gerrit_api_mock.GerritApi().get_coin_task_id.side_effect = ["coin_task_id1", "coin_task_id2"]
        binarysize_mock.BinarySizeTest().run.return_value = False
        binarysize_mock.BinarySizeTest().run.side_effect = run_delay
        with ThreadJoiner(1):
            threading.Thread(target=lambda: testable.callback("project", "branch", "sha1")).start()
            threading.Thread(target=lambda: testable.callback("project", "branch", "sha2")).start()
            threading.Thread(target=lambda: testable.callback("project", "branch", "sha3")).start()

        testable._workqueue.join()
        self.assertEqual(testable._processed_coin_ids, ["coin_task_id1", "coin_task_id2"])
        self.assertEqual(1, self.active_count())
        binarysize_mock.BinarySizeTest().run.assert_called()
        self.assertEqual(2, binarysize_mock.BinarySizeTest().run.call_count)
        email_alert_mock.send_email.assert_not_called()


    @mock.patch('main.gerrit_api')
    @mock.patch('main.coin_api')
    @mock.patch('main.database')
    @mock.patch('main.binarysizetest')
    @mock.patch('main.email_alert')
    def test_merged_tasks_ok_case(self, email_alert_mock, binarysize_mock, db_mock, coin_api_mock, gerrit_api_mock):
        db_mock.Database().get_last_timestamp.return_value = datetime.datetime(2020, 1, 1, 0, 0)
        config = json.loads(
            '{ "tests_json":"tests.json", "database_info": \
                {"server_url":"url", "database_name": "dbname", "username":"john", "password":"doe"}, \
                "email_info": {"smtp_server": "smtp.localhost", "email_sender": "t@t.io", "email_cc": "cc@t.io"}, \
                "gerrit_info": {"server_url": "codereview.qt-project.org", "server_port": 29418} \
                     }')
        testable = main.CallbackHandler(config)
        db_mock.Database().get_last_timestamp.assert_called()
        binarysize_mock.BinarySizeTest().email_content.return_value = ["topic", "message"]
        gerrit_api_mock.GerritApi().get_coin_task_id.return_value = "coin_task_id"

        # First call. No email
        coin_api_mock.get_coin_task_details.return_value = {
            'coin_update_ongoing': False,
            'last_timestamp': datetime.datetime(2020, 1, 2, 0, 0),
            'git_shas': ["sha1"]
        }

        binarysize_mock.BinarySizeTest().run.return_value = False
        testable._execute_test("coin_task_id", "project", "branch", "sha1")
        binarysize_mock.BinarySizeTest().run.assert_called()
        email_alert_mock.send_email.assert_not_called()

        # Second call. Send email
        coin_api_mock.get_coin_task_details.return_value = {
            'coin_update_ongoing': False,
            'last_timestamp': datetime.datetime(2020, 1, 3, 0, 0),
            'git_shas': ["sha1"]
        }

        binarysize_mock.BinarySizeTest().run.return_value = True
        email_alert_mock.get_authors.return_value = 'author@t.io'
        testable._execute_test("coin_task_id", "project", "branch", "sha1")
        binarysize_mock.BinarySizeTest().run.assert_called()
        email_alert_mock.send_email.assert_called_with(
            'smtp.localhost', 't@t.io', 'author@t.io', "cc@t.io", "topic", "message")
        self.assertEqual(2, binarysize_mock.BinarySizeTest().run.call_count)


    @mock.patch('main.gerrit_api')
    @mock.patch('main.coin_api')
    @mock.patch('main.database')
    @mock.patch('main.binarysizetest')
    @mock.patch('main.email_alert')
    def test_merged_tasks_no_coin_completion_case(self, email_alert_mock, binarysize_mock, db_mock, coin_api_mock, gerrit_api_mock):
        config = json.loads(
            '{ "tests_json":"tests.json", "database_info": \
                {"server_url":"url", "database_name": "dbname", "username":"john", "password":"doe"}, \
                "email_info": {"smtp_server": "smtp.localhost", "email_sender": "", "email_cc": ""}, \
                "gerrit_info": {"server_url": "codereview.qt-project.org", "server_port": 29418} \
                    }')
        db_mock.Database().get_last_timestamp.return_value = datetime.datetime(2020, 1, 1, 0, 0)
        testable = main.CallbackHandler(config)
        db_mock.Database().get_last_timestamp.assert_called()
        binarysize_mock.BinarySizeTest().email_content.return_value = ["topic", "message"]
        coin_api_mock.get_coin_task_details.side_effect = OSError('Expected error')

        coin_api_mock.get_coin_task_details.return_value = {
            'coin_update_ongoing': False,
            'last_timestamp': datetime.datetime(2020, 1, 2, 0, 0),
            'git_shas': ["sha1"]
        }

        testable._execute_test("coin_task_id", "project", "branch", "sha1")
        binarysize_mock.BinarySizeTest().run.assert_not_called()


    @mock.patch('main.gerrit_api')
    @mock.patch('main.coin_api')
    @mock.patch('main.database')
    @mock.patch('main.binarysizetest')
    @mock.patch('main.email_alert')
    def test_merged_tasks_exception(self, email_alert_mock, binarysize_mock, db_mock, coin_api_mock, gerrit_api_mock):
        config = json.loads(
            '{ "tests_json":"tests.json", "database_info": \
                {"server_url":"url", "database_name": "dbname", "username":"john", "password":"doe"}, \
                "email_info": {"smtp_server": "smtp.localhost", "email_sender": "sender", "email_cc": "cc"}, \
                "gerrit_info": {"server_url": "codereview.qt-project.org", "server_port": 29418} \
                    }')
        coin_api_mock.get_coin_task_details.return_value = {
            'coin_update_ongoing': False,
            'last_timestamp': datetime.datetime(2020, 1, 1, 0, 0),
            'git_shas': ["sha1"]
        }

        testable = main.CallbackHandler(config)
        db_mock.Database().get_last_timestamp.assert_called()
        binarysize_mock.BinarySizeTest().email_content.return_value = ["topic", "message"]
        binarysize_mock.BinarySizeTest().run.side_effect = OSError('Expected error')
        gerrit_api_mock.GerritApi().get_coin_task_id.return_value = "coin_task_id"

        coin_api_mock.get_coin_task_details.return_value = {
            'coin_update_ongoing': False,
            'last_timestamp': datetime.datetime(2020, 1, 2, 0, 0),
            'git_shas': ["sha1"]
        }

        testable._execute_test("coin_task_id", "project", "branch", "sha1")
        email_alert_mock.send_email.assert_called_with(
            'smtp.localhost', 'sender', ['cc'], "",
            'Error in qt-binary-size-bot', 'Reason: Expected error')
