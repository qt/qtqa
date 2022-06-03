# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import asyncio
from typing import Optional
from gerrit import GerritStreamEvents, GerritStreamParser
from logger import get_logger
from git import Repository
from jiracloser import JiraCloser
from config import Config
from .args import Args


log = get_logger("bot")


class Bot:
    def __init__(self) -> None:
        self.loop = asyncio.get_event_loop()
        self.g = GerritStreamEvents()
        self.parser = GerritStreamParser()
        self.args = Args()
        log.info("Using '%s' configuration", self.args.config_section)
        config = Config(self.args.config_section)
        self.jira_closer = JiraCloser(config)

    async def update_project(self, name: str, since: Optional[str] = None) -> None:
        async with Repository(name) as repo:
            changes = await repo.new_changes(since=since)
            for change in changes:
                log.info("Checking changes for relevant tags: '%s'", change)
                # check commit message
                fixes = await repo.parse_commit_messages(change)
                for fix in fixes:
                    # do jira magic
                    self.jira_closer.run(fix)

    async def event_handler(self, data: str) -> None:
        event = self.parser.parse(data)
        log.debug(f"Gerrit Event: {event} - raw data: >>>{data}<<<")
        if event.is_branch_update():
            log.info(event)
            await self.update_project(event.project)

    async def check_gerrit_projects(self) -> None:
        projects = await(self.g.list_all_projects())
        # we could parallelize, but we cannot have too many git connections
        # at the same time, and this is not the common case, so do it sequential for now.
        # updates = []
        # for project in projects:
        #     updates.append(self.update_project(project))
        # await asyncio.gather(*updates)
        for project in projects:
            await self.update_project(project, since=self.args.since)

    def run(self) -> None:
        while True:
            try:
                check_projects_on_startup = asyncio.ensure_future(self.check_gerrit_projects())
                self.g.setDataCallback(self.event_handler)
                run_monitor = asyncio.ensure_future(self.g.run())
                self.loop.run_until_complete(asyncio.gather(check_projects_on_startup, run_monitor))
            except Exception as exc:
                log.exception('Caught exception: ' + str(exc))
