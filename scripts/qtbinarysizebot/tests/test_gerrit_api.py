# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import unittest
import gerrit_api
import mock
import json
import pytest

class TestGerritApi(unittest.TestCase):

    @mock.patch('gerrit_api.GerritRestAPI')
    def test_gerrit_ok_case(self, gerrit_mock):
        gerrit_mock().get.return_value = json.loads(
            '['
            '{"message" : "Test message"},'
            '{"message" : "\\nContinuous Integration: Passed\\n\\nPatch looks good. Thanks.\\n\\nDetails: https://testresults.qt.io/coin/integration/qt/qtdeclarative/tasks/1714471416\\n\\nTested changes (refs/builds/qtci/dev/1714471407):\\n  https://codereview.qt-project.org/c/qt/qtdeclarative/+/557208/5 Fix test compilation issues with QtLite configuration\\n"}'
            ']'
        )
        testable = gerrit_api.GerritApi("codereview.qt-project.org")
        self.assertEqual(testable.get_coin_task_id('4949768067cfc8a16c0cef958928e94147842bb8'), "1714471416")

        gerrit_mock().get.assert_called()


    @mock.patch('gerrit_api.GerritRestAPI')
    def test_gerrit_nok_case(self, gerrit_mock):
        gerrit_mock().get.return_value = json.loads(
            '['
            '{"message" : "Test message"}'
            ']'
        )
        testable = gerrit_api.GerritApi("codereview.qt-project.org")
        with pytest.raises(gerrit_api.GerritApiException) as exc_info:
            testable.get_coin_task_id('4949768067cfc8a16c0cef958928e94147842bb8')

        self.assertEqual(exc_info.value.args[0], "Gerrit comment from COIN not found from [{'message': 'Test message'}]")
        self.assertEqual(str(exc_info.value), "Gerrit comment from COIN not found from [{'message': 'Test message'}]")
