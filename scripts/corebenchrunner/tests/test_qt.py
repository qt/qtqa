# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import decimal
import unittest
import xml.etree.ElementTree as ET
from typing import cast

import common
import qt


class TestResultFileParser(unittest.TestCase):
    def test_parse_test_case_result(self) -> None:
        """We can parse test case results"""
        element = ET.fromstring(
            """
            <TestCase name="editor">
                <TestFunction name="open"/>
                <TestFunction name="close"/>
                <Duration msecs="123.4"/>
            </TestCase>
            """
        )
        result = qt.ResultFileParser.parse_test_case_result(common.XmlParser(element))
        self.assertIsInstance(result, qt.TestCaseResult)
        result = cast(qt.TestCaseResult, result)
        self.assertEqual(result.name, "editor")
        self.assertEqual(result.duration, decimal.Decimal("123.4"))
        self.assertEqual(len(result.test_function_results), 2)
        self.assertIsInstance(result.test_function_results[0], qt.TestFunctionResult)
        self.assertIsInstance(result.test_function_results[1], qt.TestFunctionResult)

    def test_parse_test_function_result(self) -> None:
        """We can parse test function results"""
        element = ET.fromstring(
            """
            <TestFunction name="sort">
              <BenchmarkResult metric="Seconds" tag="" value="20.4" iterations="512"/>
              <Incident type="pass"/>
              <Message type="warning"><Description>nothing to sort</Description></Message>
            </TestFunction>
            """
        )
        result = qt.ResultFileParser.parse_test_function_result(common.XmlParser(element))
        self.assertIsInstance(result, qt.TestFunctionResult)
        result = cast(qt.TestFunctionResult, result)
        self.assertEqual(result.name, "sort")
        self.assertEqual(len(result.benchmark_results), 1)
        self.assertIsInstance(result.benchmark_results[0], qt.BenchmarkResult)
        self.assertEqual(len(result.incidents), 1)
        self.assertIsInstance(result.incidents[0], qt.Incident)
        self.assertEqual(len(result.messages), 1)
        self.assertIsInstance(result.messages[0], qt.Message)

    def test_parse_benchmark_result(self) -> None:
        """We can parse benchmark results"""
        element = ET.fromstring(
            """<BenchmarkResult metric="seconds" tag="" value="1.23" iterations="128"/>"""
        )
        result = qt.ResultFileParser.parse_benchmark_result(common.XmlParser(element))
        self.assertIsInstance(result, qt.BenchmarkResult)
        result = cast(qt.BenchmarkResult, result)
        self.assertEqual(result.metric, "seconds")
        self.assertEqual(result.data_tag, None)
        self.assertEqual(result.value, decimal.Decimal("1.23"))
        self.assertEqual(result.iterations, 128)

    def test_parse_benchmark_result_with_data_tag(self) -> None:
        """We can parse benchmark results with data tags"""
        element = ET.fromstring(
            """<BenchmarkResult metric="seconds" tag="long list" value="4.56" iterations="256"/>"""
        )
        result = qt.ResultFileParser.parse_benchmark_result(common.XmlParser(element))
        self.assertIsInstance(result, qt.BenchmarkResult)
        result = cast(qt.BenchmarkResult, result)
        self.assertEqual(result.metric, "seconds")
        self.assertEqual(result.data_tag, "long list")
        self.assertEqual(result.value, decimal.Decimal("4.56"))
        self.assertEqual(result.iterations, 256)

    def test_parse_incident(self) -> None:
        """We can parse incidents"""
        element = ET.fromstring("""<Incident type="pass"/>""")
        incident = qt.ResultFileParser.parse_incident(common.XmlParser(element))
        self.assertIsInstance(incident, qt.Incident)
        incident = cast(qt.Incident, incident)
        self.assertEqual(incident.incident_type, "pass")
        self.assertEqual(incident.data_tag, None)

    def test_parse_incident_with_data_tag(self) -> None:
        """We can parse incidents with data tags"""
        element = ET.fromstring(
            """
            <Incident type="fail">
                <DataTag><![CDATA[guilty tag]]></DataTag>
            </Incident>
            """
        )
        incident = qt.ResultFileParser.parse_incident(common.XmlParser(element))
        self.assertIsInstance(incident, qt.Incident)
        incident = cast(qt.Incident, incident)
        self.assertEqual(incident.incident_type, "fail")
        self.assertEqual(incident.data_tag, "guilty tag")

    def test_parse_message(self) -> None:
        """We can parse messages"""
        element = ET.fromstring(
            """
            <Message type="qwarn">
                <Description>something happened</Description>
            </Message>
            """
        )
        message = qt.ResultFileParser.parse_message(common.XmlParser(element))
        self.assertIsInstance(message, qt.Message)
        message = cast(qt.Message, message)
        self.assertEqual(message.message_type, "qwarn")
        self.assertEqual(message.description, "something happened")
        self.assertEqual(message.data_tag, None)

    def test_parse_message_with_data_tag(self) -> None:
        """We can parse messages with data tags"""
        element = ET.fromstring(
            """
            <Message type="qfatal">
                <Description>something failed</Description>
                <DataTag><![CDATA[guilty tag]]></DataTag>
            </Message>
            """
        )
        message = qt.ResultFileParser.parse_message(common.XmlParser(element))
        self.assertIsInstance(message, qt.Message)
        message = cast(qt.Message, message)
        self.assertEqual(message.message_type, "qfatal")
        self.assertEqual(message.description, "something failed")
        self.assertEqual(message.data_tag, "guilty tag")
