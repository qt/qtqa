#!/usr/bin/env python3
# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import unittest
import mock
import email_alert
from email.message import EmailMessage

class TestEmailAlert(unittest.TestCase):

    @mock.patch('email_alert.GerritRestAPI')
    def test_get_authors_ok_case(self, gerrit_rest_mock):
        gerrit_rest_mock().get().__getitem__().__getitem__.return_value = "test@email.com"
        authors = email_alert.get_authors(
            "codereview.qt-project.org",
             "qt/qtdeclarative",
             ["9a66e7981202f9b465934e3dde43bbd44c54b4f8"])

        self.assertEqual(len(authors), 1)
        self.assertEqual(authors[0], "test@email.com")


    @mock.patch('email_alert.smtplib')
    def test_send_email(self, smtp_mock):
        email_alert.send_email(
            'smtp.qt.io', "sender@qt.io", ["test@qt.io"], "cc@qt.io", "test subject", "test message")

        msg = smtp_mock.SMTP().send_message.call_args_list[0].args[0]
        self.assertEqual(msg.get_content(), "test message\n")
        self.assertEqual(msg['Subject'], "test subject")
        self.assertEqual(msg['From'], "sender@qt.io")
        self.assertEqual(msg['Cc'], "cc@qt.io")
        self.assertEqual(msg['To'], "test@qt.io")
        smtp_mock.SMTP.assert_called()
        smtp_mock.SMTP().quit.assert_called()


    @mock.patch('email_alert.smtplib')
    def test_send_email_multiple_receivers(self, smtp_mock):
        email_alert.send_email(
            'smtp.qt.io', "sender@qt.io", ["test@qt.io", "test2@qt.io"], "cc@qt.io", "test subject", "test message")

        msg = smtp_mock.SMTP().send_message.call_args_list[0].args[0]
        self.assertEqual(msg.get_content(), "test message\n")
        self.assertEqual(msg['Subject'], "test subject")
        self.assertEqual(msg['From'], "sender@qt.io")
        self.assertEqual(msg['Cc'], "cc@qt.io")
        self.assertEqual(msg['To'], "test@qt.io, test2@qt.io")
        smtp_mock.SMTP.assert_called()
        smtp_mock.SMTP().quit.assert_called()
