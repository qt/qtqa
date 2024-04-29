# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" This script listens for gerrit SSH session events of change-merged type """

import json
import sys
from typing import Optional
import asyncssh

SSH_CALLBACK = None


class _SSHClientSession(asyncssh.SSHClientSession):
    """ Class for SSH client session instance """
    def data_received(self, data: str, datatype: asyncssh.DataType) -> None:
        gerrit_json = json.loads(data)
        print(gerrit_json)
        # pylint: disable=W0602
        global SSH_CALLBACK
        if SSH_CALLBACK is not None and gerrit_json['type'] == "change-merged":
            SSH_CALLBACK(gerrit_json['change']['project'], gerrit_json['change']['branch'], gerrit_json['newRev'])

    def connection_lost(self, exc: Optional[Exception]) -> None:
        if exc:
            print('SSH session error: ' + str(exc), file=sys.stderr)


async def run_client(callback, url: str, port: int) -> None:
    """ Connects SSH session and starts listening events """
    # pylint: disable=W0603
    global SSH_CALLBACK
    SSH_CALLBACK = callback

    async with asyncssh.connect(url, port) as conn:
        async with conn:
            chan, _session = await conn.create_session(
                _SSHClientSession, 'gerrit stream-events -s change-merged')
            print(f"SSH session created to {url}:{port} -> {_session}")
            await chan.wait_closed()
