# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import datetime
import unittest

import coordinator
from tests import dummy


class TestConnection(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.info = coordinator.Info(url="http://localhost:3330", secret="pearl")
        self.connection = coordinator.Connection(
            coordinator_info=self.info, hostname="clam", logger=None
        )
        # Use short timeouts to speed up tests.
        self.coordinator = dummy.Coordinator(info=self.info, ping_interval=1, ping_timeout=1)
        self.work_item = coordinator.WorkItem(
            integration_id=4567,
            integration_url=None,
            integration_timestamp=datetime.datetime.fromisoformat("2000-01-01"),
            integration_data=[],
            branch="main",
            revision="abcd",
        )

    async def test_connect(self) -> None:
        """Connect to the coordinator and send the idle status"""
        await self.coordinator.start()
        async with self.connection:
            auth = await self.coordinator.wait_for_connect()
            status = await self.coordinator.wait_for_status()
        await self.coordinator.wait_for_disconnect()
        await self.coordinator.stop()
        self.assertEqual(auth["secret"], self.info.secret)
        self.assertEqual(auth["hostname"], self.connection.hostname)
        self.assertEqual(status["status"], "idle")

    async def test_send_work_status(self) -> None:
        """Send a work status to the coordinator"""
        await self.coordinator.start()
        async with self.connection:
            await self.coordinator.wait_for_connect()
            await self.coordinator.wait_for_status()
            await self.connection.send_status(
                "new",
                message="Received work item 7",
                work_item=self.work_item,
                logger=None,
            )
            status = await self.coordinator.wait_for_status()
        await self.coordinator.wait_for_disconnect()
        await self.coordinator.stop()
        self.assertEqual(status["status"], "new")
        self.assertEqual(status["detailMessage"], "Received work item 7")

    async def test_fetch_work_item(self) -> None:
        """Fetch a work item from the coordinator"""
        await self.coordinator.start()
        async with self.connection:
            await self.coordinator.wait_for_connect()
            work_item = await self.connection.fetch_work(use_query_event=False, logger=None)
        await self.coordinator.wait_for_disconnect()
        await self.coordinator.stop()
        self.assertEqual(work_item.integration_id, self.coordinator.work_item.integration_id)
        self.assertEqual(work_item.revision, self.coordinator.work_item.revision)

    async def test_fetch_work_item_again(self) -> None:
        """Fetch a second work item from the coordinator"""
        await self.coordinator.start()
        async with self.connection:
            await self.coordinator.wait_for_connect()
            work_item = await self.connection.fetch_work(use_query_event=False, logger=None)
            self.coordinator.work_item = self.work_item
            work_item = await self.connection.fetch_work(use_query_event=False, logger=None)
        await self.coordinator.wait_for_disconnect()
        await self.coordinator.stop()
        self.assertEqual(work_item.integration_id, self.work_item.integration_id)
        self.assertEqual(work_item.revision, self.work_item.revision)

    async def test_resend_current_status(self) -> None:
        """Reconnect and send the current status after a connection drop"""
        await self.coordinator.start()
        async with self.connection:
            await self.coordinator.wait_for_connect()
            await self.coordinator.wait_for_status()
            await self.connection.send_status(
                "git",
                message="Fetching Git refs",
                work_item=self.work_item,
                logger=None,
            )
            await self.coordinator.wait_for_status()
            await self.coordinator.stop()
            await self.coordinator.wait_for_disconnect()
            await self.coordinator.start()
            await self.coordinator.wait_for_connect()
            status = await self.coordinator.wait_for_status()
        await self.coordinator.wait_for_disconnect()
        await self.coordinator.stop()
        self.assertEqual(status["status"], "git")
        self.assertEqual(status["detailMessage"], "Fetching Git refs")

    async def test_resend_pending_status(self) -> None:
        """Save a status during a connection drop, then reconnect and send it"""
        await self.coordinator.start()
        async with self.connection:
            await self.coordinator.wait_for_connect()
            await self.coordinator.stop()
            await self.coordinator.wait_for_disconnect()
            await self.connection.send_status(
                "git",
                message="Resetting Git repository",
                work_item=self.work_item,
                logger=None,
            )
            await self.coordinator.start()
            await self.coordinator.wait_for_connect()
            status = await self.coordinator.wait_for_status()
        await self.coordinator.wait_for_disconnect()
        await self.coordinator.stop()
        self.assertEqual(status["status"], "git")
        self.assertEqual(status["detailMessage"], "Resetting Git repository")
