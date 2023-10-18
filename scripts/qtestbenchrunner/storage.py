# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import logging
from typing import Any, List, Optional

import common
import coordinator
import host
import qt


class Error(common.Error):
    pass


class Mode:
    """
    Decides how the runner should store results.
    """

    def create_environment(self) -> "Environment":
        raise NotImplementedError()  # Should be overridden by subclasses.


class Environment:
    """
    Stores results.
    """

    async def __aenter__(self) -> "Environment":
        raise NotImplementedError()  # Should be overridden by subclasses.

    async def __aexit__(
        self, exception_type: Any, exception_value: Any, exception_traceback: Any
    ) -> bool:
        raise NotImplementedError()  # Should be overridden by subclasses.

    async def store(
        self,
        results: List[qt.TestFileResult],
        issues: List[qt.TestFileIssue],
        work_item: coordinator.WorkItem,
        host_info: host.Info,
        logger: logging.Logger,
    ) -> Optional[Error]:
        raise NotImplementedError()  # Should be overridden by subclasses.


class DropMode(Mode):
    """
    A storage mode in which the runner drops results.
    """

    def create_environment(self) -> "DropEnvironment":
        return DropEnvironment()


class DropEnvironment(Environment):
    """
    Drops results.
    """

    async def __aenter__(self) -> "DropEnvironment":
        return self

    async def __aexit__(self, exception_type: Any, exception_value: Any, traceback: Any) -> bool:
        return False

    async def store(
        self,
        results: List[qt.TestFileResult],
        issues: List[qt.TestFileIssue],
        work_item: coordinator.WorkItem,
        host_info: host.Info,
        logger: logging.Logger,
    ) -> Optional[Error]:
        logger.warning("Dropping results")
        return None
