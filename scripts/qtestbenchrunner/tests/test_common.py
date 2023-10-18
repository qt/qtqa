# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import decimal
import unittest
import xml.etree.ElementTree as ET

import common


class TestXmlParser(unittest.TestCase):
    def test_decimal_attribute(self) -> None:
        """We can parse decimal attributes"""
        element = common.XmlParser(ET.fromstring("""<Circle radius="1.5"/>"""))
        value = element.decimal_attribute("radius")
        self.assertEqual(value, decimal.Decimal("1.5"))

    def test_decimal_attrubute_with_comma(self) -> None:
        """We can parse decimal attributes with commas"""
        element = common.XmlParser(ET.fromstring("""<Line length="3,4"/>"""))
        value = element.decimal_attribute("length")
        self.assertEqual(value, decimal.Decimal("3.4"))
