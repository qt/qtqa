# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" Module contains logic for sending email alerts for git commit authors """

import urllib
import smtplib
from email.message import EmailMessage
from pygerrit2 import GerritRestAPI


def get_authors(url, project, shas):
    """ Fetches authors for given shas"""
    https_url = f"https://{url}"
    authors = []

    rest_api = GerritRestAPI(https_url, auth=None)
    encoded_project = urllib.parse.quote(project, safe='')
    for sha in shas:
        res = rest_api.get(f"/projects/{encoded_project}/commits/{sha}")
        authors.append(res["author"]["email"])

    return authors


def send_email(smtp_server, sender, authors, cc, subject, message):
    # pylint: disable=R0913
    """ Sends email for authors """
    msg = EmailMessage()
    msg.set_content(message)
    msg['Subject'] = subject
    msg['From'] = sender
    msg['Cc'] = cc
    msg['To'] = ', '.join(authors)

    s = smtplib.SMTP(smtp_server)
    s.send_message(msg)
    s.quit()
