# Copyright (C) 2019 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import os
from typing import Dict
from configparser import ConfigParser


from logger import get_logger
log = get_logger('config')


class Config:
    def __init__(self, section: str) -> None:
        self.section = section
        self.file_path = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.abspath(os.path.join(self.file_path, "..", "config.ini"))
        self.config = ConfigParser()
        self.config.read(config_path)

    @property
    def jira_url(self) -> str:
        return self.config[self.section]['jira_url']

    def get_oauth_data(self) -> Dict[str, str]:
        section = self.config[self.section]
        cert_file = section['key_cert_file']
        cert_path = os.path.abspath(os.path.join(self.file_path, "..", cert_file))
        with open(cert_path, 'r') as key_cert_file:
            key_cert_data = key_cert_file.read()

        oauth_data = {
            'access_token': section['oauth_token'],
            'access_token_secret': section['oauth_token_secret'],
            'consumer_key': section['consumer_key'],
            'key_cert': key_cert_data
        }
        return oauth_data

    @property
    def add_comment_to_issues(self) -> bool:
        try:
            return self.config[self.section].getboolean('add_comment_to_issues')
        except KeyError:
            return False
