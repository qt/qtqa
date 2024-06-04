#!/usr/bin/env python3
# PYTHON_ARGCOMPLETE_OK
# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" Main executable """
import sys
import asyncio
import datetime
import traceback
import threading
import json
import argparse
import queue
from functools import partial
import argcomplete
import coin_api
import binarysizetest
import database
import trigger_ssh
import trigger_webhook
import email_alert
import gerrit_api


# pylint: disable=R0902
class CallbackHandler:
    """ Class implements main functionality of this program.
     1. It handles callbacks from webhook or SSH triggers from Gerrit
     2. Variables from callback is pushed into queue, which handles them in different thread
     3. Thread fetches COIN job id for SHA that is given in callback
     4. If COIN is still processing it will trigger new update after 60 seconds
     5. Thread fetches artifacts for the COIN job id and updates InfluxDB
     6. If the result is above the threshold, it fetches email addresses that match
        with SHA's and sends an email notification
    """
    # pylint: disable=R0903
    def __init__(self, main_config) -> None:
        db = database.Database(
            main_config['database_info']['server_url'],
            main_config['database_info']['database_name'],
            main_config['database_info']['username'],
            main_config['database_info']['password'])

        self.date = db.get_last_timestamp()
        if self.date is None:
            # In case of empty database start from yesterday's timestamp
            self.date = datetime.datetime.now(tz=datetime.timezone.utc) - datetime.timedelta(days=1)

        print(f"Starting update from {self.date}")
        self.tests = binarysizetest.BinarySizeTest(main_config['tests_json'], db)
        self.smtp_server = main_config['email_info']['smtp_server']
        self.gerrit_url = main_config['gerrit_info']['server_url']
        self.email_sender = main_config['email_info']['email_sender']
        self.email_cc = main_config['email_info']['email_cc']
        self.gerrit_api = gerrit_api.GerritApi(main_config["gerrit_info"]["server_url"])
        self._processed_coin_ids = []
        self._workqueue = queue.Queue()
        threading.Thread(target=self._thread_loop, daemon=True).start()

    def callback(self, project: str, branch: str, git_sha: str):
        """ Process callbacks from triggers """
        if self.tests.matches(project, branch):
            self._workqueue.put((project, branch, git_sha))

    def _thread_loop(self):
        while True:
            project, branch, git_sha = self._workqueue.get()
            if project is None:
                return
            try:
                coin_task_id = self.gerrit_api.get_coin_task_id(git_sha)
                if coin_task_id not in self._processed_coin_ids:
                    self._execute_test(coin_task_id, project, branch, git_sha)
                    self._processed_coin_ids.append(coin_task_id)
                else:
                    print(f"COIN Id {coin_task_id} already processed (GIT SHA {git_sha})")
            # pylint: disable=W0718
            except Exception as e:
                print(f"Fetching coin task id failed for {git_sha}\n exception:{e}")

            self._workqueue.task_done()

    def _execute_test(self, coin_task_id: str, project: str, branch: str, git_sha: str):
        try:
            dictionary = coin_api.get_coin_task_details(coin_task_id)
            if dictionary['coin_update_ongoing'] is True:
                print(f"COIN task {coin_task_id} still running. Schedule new update after 10 seconds")
                t = threading.Timer(10, partial(self._execute_test,
                                                coin_task_id=coin_task_id,
                                                project=project,
                                                branch=branch,
                                                git_sha=git_sha))
                t.start()
                return
            print(f"{datetime.datetime.now()}: New coin task {coin_task_id}"
                  f" completed at {dictionary['last_timestamp']} for shas: {dictionary['git_shas']}")
            [email_topic, email_message] = self.tests.email_content(
                coin_task_id, self.date, dictionary['last_timestamp'], dictionary['git_shas'])
            if self.tests.run(
                    coin_task_id,
                    dictionary['last_timestamp'],
                    dictionary['git_shas']):
                authors = email_alert.get_authors(self.gerrit_url, project, dictionary['git_shas'])
                print(f"Sending email to: {authors}")
                email_alert.send_email(
                    self.smtp_server,
                    self.email_sender,
                    authors,
                    self.email_cc,
                    email_topic,
                    email_message)

            self.date = dictionary['last_timestamp']

        # pylint: disable=W0718
        except Exception as e:
            print(f"Database update failed. Last processed timestamp was {self.date}\nReason: {e}")
            traceback.print_exc()
            email_alert.send_email(
                self.smtp_server, self.email_sender, [self.email_cc], "", "Error in qt-binary-size-bot", f"Reason: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
    )
    parser.add_argument(
        "--configuration",
        required=False,
        default="config.json",
        action="store",
        metavar="FILE",
        help="load configuration from FILE (default: config.json)",
    )
    parser.add_argument(
        "--ssh",
        required=False,
        action="store_true",
        help="Listen gerrit SSH stream (.ssh/config credentials required)",
    )
    argcomplete.autocomplete(parser)
    parsed_arguments = parser.parse_args()

    with open(parsed_arguments.configuration, 'r', encoding="utf-8") as f:
        config = json.load(f)

    sys.stdout.reconfigure(line_buffering=True)
    callback_instance = CallbackHandler(config)
    loop = asyncio.get_event_loop()
    if parsed_arguments.ssh is True:
        trigger_task = loop.create_task(trigger_ssh.run_client(
            callback_instance.callback,
            config["gerrit_info"]["server_url"],
            config["gerrit_info"]["server_port"]))
    else:
        trigger_task = loop.create_task(trigger_webhook.run_web_server(
            callback_instance.callback, config["webhook_server_info"]["port"]))

    loop.run_until_complete(trigger_task)
