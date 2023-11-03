# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import json
import tempfile
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
        We can detect errors in a configuration file.
        """
        with tempfile.NamedTemporaryFile(mode="w") as f:
            json.dump(
                {
                    "coordinator_info": {"url": "https://coordinator.com/", "secret": ""},
                    "qtbase_git_remote": {"url": "ssh://codereview.qt-project.org/qt/qtbase"},
                },
                f,
            )
            f.seek(0)
            configuration = runner.Configuration.load(file=f.name, skip_upload=True)

        self.assertIsInstance(configuration, runner.Error)
        error = cast(runner.Error, configuration)
        self.assertEqual(error.message.splitlines()[0], "Configuration file contains errors:")
