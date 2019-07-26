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
