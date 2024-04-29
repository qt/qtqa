# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" Gerrit API wrapper module for Qt purposes """
from pygerrit2.rest import GerritRestAPI


class GerritApiException(Exception):
    """ Exception class """


# pylint: disable=R0903
class GerritApi():
    """ Gerrit API wrapper class for Qt purposes """

    def __init__(self, gerrit_server) -> None:
        self._server_url = 'https://' + gerrit_server

    def get_coin_task_id(self, sha) -> str:
        """ Fetches COIN task id from gerrit review comments """
        client = GerritRestAPI(url=self._server_url)

        messages = client.get('changes/' + sha + '/messages')

        for message in messages:
            if "Continuous Integration: Passed" in message["message"]:
                return message["message"].split("tasks/", 1)[1].split("\n")[0]

        raise GerritApiException(f'Gerrit comment from COIN not found from {messages}')
