# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
import asyncio
import datetime
import logging
from typing import Any, Dict, List, Optional

import socketio  # type: ignore


class Info:
    """
    Information about the work coordinator.

    It monitors integrations and sends work to the runner.
    """

    def __init__(self, url: str, secret: str) -> None:
        self.url = url
        self.secret = secret


class WorkItem:
    """
    Item of work, containing a Git revision.

    The runner should check out the revision, run benchmarks, and upload results.
    """

    timestamp_format = "%Y-%m-%dT%H:%M:%S.%fZ"

    def __init__(
        self,
        integration_id: int,
        integration_url: Optional[str],
        integration_timestamp: datetime.datetime,
        integration_data: List[Dict[str, Any]],
        branch: str,
        revision: str,
    ) -> None:
        self.integration_id = integration_id
        self.integration_url = integration_url
        self.integration_timestamp = integration_timestamp
        self.integration_data = integration_data
        self.branch = branch
        self.revision = revision

    def to_dictionary(self) -> Dict[str, Any]:
        timestamp = self.integration_timestamp.strftime(WorkItem.timestamp_format)
        return {
            "integrationId": self.integration_id,
            "integrationURL": self.integration_url,
            "integrationTimestamp": timestamp,
            "integrationData": self.integration_data,
            "branch": self.branch,
            "sha": self.revision,
        }

    @staticmethod
    def from_dictionary(dictionary: Dict[str, Any]) -> "WorkItem":
        timestamp = datetime.datetime.strptime(
            dictionary["integrationTimestamp"], WorkItem.timestamp_format
        )
        return WorkItem(
            integration_id=dictionary["integrationId"],
            integration_url=dictionary["integrationURL"],
            integration_timestamp=timestamp,
            integration_data=dictionary["integrationData"],
            branch=dictionary["branch"],
            revision=dictionary["sha"],
        )


class Connection:
    """
    Connection to the work coordinator. The runner uses it to fetch work and send status updates.
    """

    client_type = "agent"
    fetch_delay = 30

    def __init__(
        self, coordinator_info: Info, hostname: str, logger: Optional[logging.Logger]
    ) -> None:
        self.coordinator_info = coordinator_info
        self.hostname = hostname

        # Used to send events to and receive events from the coordinator.
        self.client = socketio.AsyncClient(
            handle_sigint=False,
            logger=False if logger is None else logger.getChild("socketio"),
            engineio_logger=False if logger is None else logger.getChild("engineio"),
        )
        self.client.on("sendWork")(self._handle_send_work_event)
        self.client.on("connect")(self._handle_connect_event)

        # Used to pass work items from the "sendWork" callback threads to the main thread.
        self.work_item: Optional[Dict[str, Any]] = None
        self.work_event_received = asyncio.Condition()

        # Used to send status updates after establishing a connection.
        self.status: Dict[str, Any] = {"status": "idle"}
        self.status_lock = asyncio.Lock()

    async def __aenter__(self) -> "Connection":
        auth = {
            "clientType": Connection.client_type,
            "hostname": self.hostname,
            "secret": self.coordinator_info.secret,
        }
        await self.client.connect(url=self.coordinator_info.url, auth=auth)
        return self

    async def __aexit__(self, exception_type: Any, exception_value: Any, traceback: Any) -> bool:
        await self.client.disconnect()
        return False

    async def send_status(
        self, status: str, message: str, work_item: WorkItem, logger: Optional[logging.Logger]
    ) -> None:
        """
        Inform the coordinator about the progress of a work item.
        """
        dictionary = {
            "status": status,
            "detailMessage": message,
            "updateTimestamp": datetime.datetime.now().strftime(WorkItem.timestamp_format),
        }
        dictionary.update(work_item.to_dictionary())
        async with self.status_lock:
            try:
                await self.client.emit(event="statusUpdate", data=dictionary)
            except socketio.exceptions.BadNamespaceError as error:
                if logger is not None:
                    logger.warning(f"Could not send status: {error}")  # Will be sent on reconnect.
            finally:
                self.status = dictionary

    async def fetch_work(self, use_query_event: bool, logger: Optional[logging.Logger]) -> WorkItem:
        async with self.work_event_received:
            self.work_item = None
            while self.work_item is None:
                # Send an event.
                try:
                    await self._send_fetch_work_event(use_query_event)
                except socketio.exceptions.BadNamespaceError as error:
                    if logger is not None:
                        logger.warning(f"Could not fetch work: {error}")
                    await asyncio.sleep(Connection.fetch_delay)
                    continue
                # Wait for the response.
                try:
                    await asyncio.wait_for(self.work_event_received.wait(), Connection.fetch_delay)
                except asyncio.TimeoutError:
                    if logger is not None:
                        logger.debug("Waiting for work")
            if logger is not None:
                logger.debug(
                    "\n\t".join(
                        ["Received a work object with these values:"]
                        + [f"{key}: {value}" for key, value in self.work_item.items()]
                    )
                )
            return WorkItem.from_dictionary(self.work_item)

    async def _send_fetch_work_event(self, use_query_event: bool) -> None:
        await self.client.emit("queryWork" if use_query_event else "fetchWork")

    async def _handle_connect_event(self) -> None:
        async with self.status_lock:
            await self.client.emit(event="statusUpdate", data=self.status)

    async def _handle_send_work_event(self, data: Optional[Dict[str, Any]]) -> None:
        async with self.work_event_received:
            self.work_item = data
            self.work_event_received.notify()
