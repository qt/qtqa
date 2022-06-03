#!/usr/bin/env python3
# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

from bot import Bot
from logger import get_logger


log = get_logger("main")


if __name__ == "__main__":
    try:
        bot = Bot()
        bot.run()
    except KeyboardInterrupt:
        log.info("Stopped by keyboard interrupt.")
