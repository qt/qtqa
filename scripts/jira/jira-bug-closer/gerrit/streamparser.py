#!/usr/bin/env python3
# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import json
from logger import get_logger

log = get_logger(name="gerrit_stream_parser")


class GerritEvent:
    def __init__(self, type: str, project: str, branch: str) -> None:
        self.type = type
        self.project = project
        self.branch = branch

    def __eq__(self, other: object) -> bool:
        return self.__dict__ == other.__dict__

    def __repr__(self) -> str:
        return "<GerritEvent '%s': '%s' '%s'>" % (self.type, self.project, self.branch)

    def is_branch_update(self) -> bool:
        if self.type != 'ref-updated':
            return False
        if 'staging' in self.branch:
            return False
        if self.branch.startswith('refs/changes/'):
            return False
        return True


class GerritStreamParser:
    def parse(self, data: str) -> GerritEvent:
        try:
            event = json.loads(data)
        except json.decoder.JSONDecodeError:
            log.exception('Invalid JSON: "%s"', data)
            return GerritEvent(type='invalid', project='', branch='')
        eventType = event.get('type')
        if eventType in ('comment-added', 'change-abandoned', 'change-deferred', 'change-merged', 'change-restored',
                         'draft-published', 'merge-failed', 'patchset-created', 'reviewer-added', 'reviewer-deleted'):
            return GerritEvent(type=eventType, project=event['change']['project'], branch=event['change']['branch'])
        if eventType in ('ref-replication-scheduled', 'ref-replicated', 'ref-replication-done'):
            return GerritEvent(type=eventType, project=event['project'], branch=event['ref'])
        if eventType in ('ref-updated',):
            return GerritEvent(type=eventType, project=event['refUpdate']['project'], branch=event['refUpdate']['refName'])
        log.warning('unhandled event type in gerrit ssh stream: "%s" data: "%s"', eventType, data)
        return GerritEvent(type='invalid', project='', branch='')
