# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" This script listens for incoming webhook requests of change-merged type
    from Gerrit.
"""
import json
import asyncio
from aiohttp import web

HTTP_CALLBACK = None


async def _handle(request):
    """ Handle the incoming webhook request. """
    body = await request.text()
    data = json.loads(body)

    # make sure it's a change-merged event
    if data['type'] != 'change-merged':
        return web.Response(status=200)

    try:
        print(f'{data["change"]["number"]},{data["change"]["project"]}({data["change"]["branch"]}):'
              f'Received webhook for revision: {data["patchSet"]["revision"]}')
        # pylint: disable=W0602
        global HTTP_CALLBACK
        HTTP_CALLBACK(data['change']['project'], data['change']['branch'], data["patchSet"]["revision"])
    # pylint: disable=W0718
    except Exception as e:
        print("Error: %s", str(e))
        return web.Response(status=200)

    return web.Response(status=200)


async def run_web_server(callback, port):
    """ Run the web server. """
    # pylint: disable=W0603
    global HTTP_CALLBACK
    HTTP_CALLBACK = callback
    app = web.Application()
    app.add_routes([web.post('/', _handle)])
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, 'localhost', port)
    await site.start()
    print(f"Web server started on port {port}")
    while True:
        await asyncio.sleep(3600)
