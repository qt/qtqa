# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import asyncio
import datetime
from typing import Any, Dict, Optional

import aiohttp
import socketio  # type: ignore

import coordinator


class Coordinator:
    """Dummy implementation of the coordinator for testing."""

    def __init__(
        self,
        info: coordinator.Info,
        # Default values from documentation.
        ping_interval: int = 25,
        ping_timeout: int = 5,
    ) -> None:
        self.info = info
        self.work_item = coordinator.WorkItem(
            integration_id=1234,
            integration_url=None,
            integration_timestamp=datetime.datetime.fromisoformat("2000-01-01"),
            integration_data=[],
            branch="dev",
            revision="816ca43b88893e06ea866c3edadd0ca26f64b533",
        )
        self.server = socketio.AsyncServer(ping_interval=ping_interval, ping_timeout=ping_timeout)
        self.app = aiohttp.web.Application()
        self.server.attach(self.app)
        self.runner = aiohttp.web.AppRunner(self.app)

        # Event setup.
        self.server.on("connect")(self.handle_connect)
        self.socket_id: Optional[str] = None
        self.auth: Optional[Dict[str, str]] = None
        self.connected = asyncio.Event()
        self.server.on("statusUpdate")(self.handle_status_update)
        self.status: Optional[Dict[str, Any]] = None
        self.status_updated = asyncio.Event()
        self.server.on("fetchWork")(self.handle_send_work)
        self.server.on("queryWork")(self.handle_send_work)
        self.server.on("disconnect")(self.handle_disconnect)
        self.disconnected = asyncio.Event()

    async def handle_connect(
        self, socket_id: str, environ: Dict[str, Any], auth: Dict[str, Any]
    ) -> None:
        self.socket_id = socket_id
        self.auth = auth
        self.connected.set()

    async def handle_status_update(self, socket_id: str, status: Dict[str, Any]) -> None:
        self.status = status
        self.status_updated.set()

    async def handle_send_work(self, socket_id: str) -> None:
        await self.server.emit("sendWork", self.work_item.to_dictionary())

    async def handle_disconnect(self, socket_id: str) -> None:
        self.disconnected.set()

    async def wait_for_connect(self) -> Dict[str, str]:
        await self.connected.wait()
        assert isinstance(self.auth, dict)
        auth = self.auth
        self.auth = None
        self.connected.clear()
        return auth

    async def wait_for_status(self) -> Dict[str, Any]:
        await self.status_updated.wait()
        assert isinstance(self.status, dict)
        status = self.status
        self.status = None
        self.status_updated.clear()
        return status

    async def wait_for_disconnect(self) -> None:
        await self.disconnected.wait()
        self.disconnected.clear()

    async def start(self) -> None:
        await self.runner.setup()
        address, port = self.info.url.removeprefix("http://").split(":")
        await aiohttp.web.TCPSite(self.runner, address, int(port)).start()

    async def stop(self) -> None:
        await self.runner.cleanup()


async def main() -> int:
    info = coordinator.Info(url="http://localhost:5000", secret="1234")
    dummy_coordinator = Coordinator(info)
    await dummy_coordinator.start()
    await asyncio.sleep(36000)
    return 0


if __name__ == "__main__":
    asyncio.run(main())
