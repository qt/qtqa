# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import os
from typing import Optional, Union

import common

COMMAND_TIMEOUT = 5 * 60


class Remote:
    """A remote repository."""

    def __init__(self, url: str) -> None:
        self.url = url


class Repository:
    """
    A local repository cloned from a remote repository.
    """

    def __init__(self, directory: str) -> None:
        self.directory = directory

    @staticmethod
    async def clone(
        remote: Remote,
        parent_directory: str,
        log_directory: str,
    ) -> Union["Repository", common.Error]:
        try:
            name = remote.url.rsplit("/", maxsplit=1)[1]
        except IndexError:
            return common.Error("Failed to extract repository name from remote URL")

        directory = os.path.join(parent_directory, name)
        error = await common.Command.run(
            arguments=["git", "clone", "--", remote.url, directory],
            output_file=os.path.join(log_directory, "clone.log"),
            timeout=COMMAND_TIMEOUT,
        )
        match error:
            case common.Error() as error:
                return error

        return Repository(directory)

    async def reset(self, revision: str, log_directory: str) -> Optional[common.Error]:
        error = await common.Command.run(
            arguments=["git", "fetch", "origin", revision],
            output_file=os.path.join(log_directory, "fetch.log"),
            timeout=COMMAND_TIMEOUT,
            cwd=self.directory,
        )
        match error:
            case common.Error() as error:
                return error

        error = await common.Command.run(
            arguments=["git", "clean", "-dfx"],
            output_file=os.path.join(log_directory, "clean.log"),
            timeout=COMMAND_TIMEOUT,
            cwd=self.directory,
        )
        match error:
            case common.Error(message):
                return common.Error(message)

        error = await common.Command.run(
            arguments=["git", "reset", "--hard", revision],
            output_file=os.path.join(log_directory, "reset.log"),
            timeout=COMMAND_TIMEOUT,
            cwd=self.directory,
        )
        match error:
            case common.Error(message):
                return common.Error(message)

        return None
