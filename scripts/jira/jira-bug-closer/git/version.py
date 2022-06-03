#!/usr/bin/env python3
# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

from distutils.version import StrictVersion
from typing import Any, List, Optional


class Version(StrictVersion):
    """Class representing a version number."""
    def __init__(self, version_string: str) -> None:
        super().__init__(version_string)
        self.original_version_string = version_string

    def __lt__(self, other: Any) -> Any:
        """ Compare versions taking the original_version_string into account.

            There are some cases where the default comparison is not good enough: we want 5.12.0 > 5.12,
            otherwise changes going into 5.12 while 5.12.0 exists will end up in 5.12.0 instead of 5.12.1. """
        if super().__eq__(other):
            return self.original_version_string < other.original_version_string
        return super().__lt__(other)

    def __eq__(self, other: Any) -> Any:
        return self.original_version_string == other.original_version_string

    def __gt__(self, other: Any) -> Any:
        if super().__eq__(other):
            return self.original_version_string > other.original_version_string
        return super().__gt__(other)

    def __repr__(self) -> str:
        return self.original_version_string + " - " + super().__repr__()


class ChangeRange:
    """Class representing an update of a git repository.

    Either there are before and after sha1s or alternatively based on a since date.
    The since date can be passed to git to get only commits after that date (for testing).
    """
    def __init__(self, repository: str, branch: str, before: Optional[str], after: str, since: Optional[str] = None) -> None:
        self.repository = repository
        self.branch = branch
        self.before = before
        self.after = after
        self.since = since

    def __repr__(self) -> str:
        return f"<Change(repository='{self.repository}', branch='{self.branch}', before='{self.before}', after='{self.after}', since='{self.since}')>"


class FixedByTag:
    """Class representing the "Fixes:" and "Task-number:" lines in a git commit message."""
    def __init__(self, repository: str, branch: str, sha1: str, author: str, subject: str, version: Optional[str], task_numbers: List[str], fixes: List[str]) -> None:
        self.repository = repository
        self.branch = branch
        self.sha1 = sha1
        self.author = author
        self.subject = subject
        self.version = version  # Can be None in case we failed to guess it. E.g. wip/foobar does not result in anything.
        self.task_numbers = task_numbers
        self.fixes = fixes

    def __eq__(self, other: object) -> bool:
        return self.__dict__ == other.__dict__

    def __repr__(self) -> str:
        return f"<FixedByTag(repository='{self.repository}', branch='{self.branch}', version='{self.version}', sha1='{self.sha1}', author='{self.author}', fixes={self.fixes}, task_numbers={self.task_numbers}, subject='{self.subject}')>"

    def __hash__(self) -> int:
        return hash(self.__dict__.values())
