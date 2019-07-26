#!/usr/bin/env python3
#############################################################################
##
## Copyright (C) 2019 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:GPL-EXCEPT$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3 as published by the Free Software
## Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################

import asyncio
import asyncssh  # type: ignore
import os
from typing import Any, Callable, Coroutine, List
from logger import get_logger
log = get_logger("gerrit_stream")

codereview = "codereview.qt-project.org"
port = 29418
user = 'qt_ci_bot'
file_path = os.path.dirname(os.path.abspath(__file__))
cibot_key_file = os.path.abspath(os.path.join(file_path, '../jira_gerrit_bot_id_rsa'))
loop = asyncio.get_event_loop()


class GerritSshClientSession(asyncssh.SSHClientSession):  # type: ignore
    def __init__(self) -> None:
        self._buffer: str = ""
        self._callback: Callable[[str], Coroutine[Any, Any, None]]

    def setDataCallback(self, callback: Callable[[str], Coroutine[Any, Any, None]]) -> None:
        self._callback = callback

    def data_received(self, data: str, datatype: Any) -> None:
        # Very long messages can be split in two, so we read into a buffer until we get
        # a newline '\n' (which is the common case).
        log.debug("Data received: '%s'", data)
        self._buffer += data
        if self._buffer.endswith('\n'):
            if self._callback:
                loop.create_task(self._callback(self._buffer))
            self._buffer = ""

    def eof_received(self) -> None:
        log.warning('EOF received.')

    def connection_lost(self, exc: Exception) -> None:
        if exc:
            log.error('SSH session error: "%s"', str(exc))
        else:
            log.warning('Connection lost (no exception).')


class GerritSshClient(asyncssh.SSHClient):  # type: ignore
    def connection_made(self, conn: asyncssh.SSHClientConnection) -> None:
        log.info('Connection made to %s.' % conn.get_extra_info('peername')[0])

    def auth_completed(self) -> None:
        log.info('Authentication successful.')

    def connection_lost(self, exc: Exception) -> None:
        log.warning('connection_lost %s', str(exc))


class GerritStreamEvents():
    def __init__(self) -> None:
        self._session = None
        self._connection = None
        self._client = None
        self._connection_lock = asyncio.Lock()

    async def _create_connection(self) -> None:
        async with self._connection_lock:
            if self._connection:
                return
            conn, client = await asyncssh.create_connection(
                GerritSshClient, host=codereview, port=port, username=user,
                client_keys=[cibot_key_file])
            log.info("Gerrit SSH client connected.")
            self._connection = conn
            self._client = client

    def setDataCallback(self, callback: Callable[[str], Coroutine[Any, Any, None]]) -> None:
        self._callback = callback
        if self._session:
            self._session.setDataCallback(callback)

    async def list_all_projects(self) -> List[str]:
        while True:
            connection_attempts = 0
            try:
                await self._create_connection()
                connection_attempts = 0
                gerrit_process = await self._connection.run('gerrit ls-projects', check=True)  # type: ignore
                if gerrit_process.exit_status == 0:
                    projects = [project for project in gerrit_process.stdout.splitlines() if not project.startswith('{graveyard}')]
                    return projects
                else:
                    raise Exception("failed to list gerrit projects")
            except Exception:
                self._connection = None
                log.exception("Error listing gerrit projects:", exc_info=True)
                connection_attempts += 1
                await asyncio.sleep(connection_attempts * 2)

    async def _run_client(self) -> None:
        async with self._connection:  # type: ignore
            chan, session = await self._connection.create_session(GerritSshClientSession, 'gerrit stream-events')  # type: ignore
            self._session = session
            if self._callback:
                session.setDataCallback(self._callback)

            # at the moment there seems to be no way
            # for asyncssh to keep the connection alive
            # so just manually do what openssh does.
            while True:
                channel_closed = chan.wait_closed()
                done, _ = await asyncio.wait((asyncio.sleep(100), channel_closed), return_when=asyncio.FIRST_COMPLETED)
                if channel_closed in done:
                    break
                chan.write('keepalive@openssh.com')
                log.debug("Sent SSH keep alive.")

            log.warning("Session done.")

    async def run(self) -> None:
        connection_attempts = 0
        while True:
            try:
                await self._create_connection()
                connection_attempts = 0
                await self._run_client()
            except Exception:
                log.exception('SSH connection failed.')
                self._connection = None
                connection_attempts += 1
                await asyncio.sleep(connection_attempts * 2)
