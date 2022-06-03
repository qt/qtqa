# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import argparse
import sys
from typing import Optional


class Args():
    def __init__(self) -> None:
        parser = argparse.ArgumentParser(description='JIRA bot to close issues according to Gerrit events')
        parser.add_argument('--production', action='store_true', help='Run in production mode (real jira instance)')
        parser.add_argument('--since', help='Scan all commits since the given date (passed to git as since)')
        self.parsed_args = parser.parse_args(args=sys.argv[1:])

    @property
    def config_section(self) -> str:
        if self.parsed_args.production:
            return 'production'
        return 'test'

    @property
    def since(self) -> Optional[str]:
        return self.parsed_args.since or None
