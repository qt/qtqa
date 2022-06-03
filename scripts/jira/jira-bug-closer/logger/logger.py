#!/usr/bin/env python3
# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import coloredlogs
import logging

level = logging.INFO


def get_logger(name: str) -> logging.Logger:
    log = logging.getLogger(name)
    log.setLevel(level)
    log_format = "%(asctime)s %(filename)s:%(lineno)d %(levelname)s %(message)s"
    coloredlogs.install(level=level, logger=log, fmt=log_format)
    return log
