# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import os
import unittest
from typing import cast

import runner


class TestArguments(unittest.TestCase):
    def test_parse(self) -> None:
        """
        We can parse the required arguments.
        """
        arguments = runner.Arguments.parse(["--configuration", "file", "--output", "directory"])
        self.assertEqual(arguments.configuration_file, "file")
        self.assertEqual(arguments.output_directory, "directory")


class TestConfiguration(unittest.TestCase):
    def test_load(self) -> None:
        """
        We can detect errors in the default configuration file.
        """
        directory = os.path.dirname(os.path.dirname(__file__))
        file = os.path.join(directory, "config.json")
        configuration = runner.Configuration.load(file=file, skip_upload=False)
        self.assertIsInstance(configuration, runner.Error)
        error = cast(runner.Error, configuration)
        self.assertEqual(error.message.splitlines()[0], "Configuration file contains errors:")
