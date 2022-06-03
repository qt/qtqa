#!/usr/bin/env python3
# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import pytest
from gerrit import GerritStreamEvents


@pytest.mark.asyncio
async def test_list_projects(event_loop):
    g = GerritStreamEvents()
    list = await g.list_all_projects()
    assert 'qt/qtbase' in list
    assert 'qt/qt5' in list
