# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import platform
import re
import socket
from typing import Union

import common


class Info:
    def __init__(self, name: str, os: str, cpu: str) -> None:
        self.name = name
        self.os = os
        self.cpu = cpu

    @staticmethod
    async def gather() -> Union["Info", common.Error]:
        name = socket.gethostname()
        os = platform.platform()
        cpu = await Info.get_cpu()
        match cpu:
            case common.Error() as error:
                return error

        return Info(name=name, os=os, cpu=cpu)

    @staticmethod
    async def get_cpu() -> Union[str, common.Error]:
        with open("/proc/cpuinfo") as f:
            match = re.search(
                pattern=r"^model name\s*: ([^ ].*)$", string=f.read(), flags=re.MULTILINE
            )
        if not match:
            return common.Error("Failed to parse /proc/cpuinfo")
        else:
            return match[1]
