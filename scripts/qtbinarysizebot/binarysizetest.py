# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" Module contains logic for updating binary sizes into database """
import os
import json
from datetime import datetime
import urllib.request
import tarfile
import tempfile
from pathlib import Path
from urllib.parse import urlparse
import database
import coin_api


EMAIL_ALERT_TOPIC = "Binary size increased over threshold"


class BinarySizeTest():
    """ Class for fetching, unpacking and pushing binary size results into database """
    def __init__(
            self,
            tests_json: str,
            binary_size_database: database.Database):

        with open(tests_json, 'r', encoding="utf-8") as f:
            test_cases = json.load(f)
        self.binary_size_database = binary_size_database
        self.branch = test_cases['branch']
        self.series = test_cases['series']
        self.integration = test_cases['integration']
        self.builds_to_check = test_cases['builds_to_check']
        self.coin_id = test_cases['coin_id']

    def email_content(self, coin_task_id, start_date, end_date, shas):
        """ Composes email content """
        email_body = (
            f"Hi, This alert comes from qt-binary-size-bot.\n\n"
            f"The bot is monitoring {self.coin_id} for {self.integration} integration in {self.branch} branch "
            f"with the following configuration:\n{self.builds_to_check}\n"
            f"You can find the histogram at: http://testresults.qt.io/grafana/goto/JDaMrUaSR?orgId=1\n"
            f"The failed build used artifacts from COIN job id: "
            f"https://coin.intra.qt.io/coin/integration/{self.integration}/tasks/{coin_task_id}\n"
            f"It's possible that the issue was introduced between {start_date} and {end_date} UTC.\n"
            f"Related commits: {shas}\n\n"
            f"For now, this alert is just an informal notification.\n"
            f"If you could add functionality behind existing or new Qt feature flags, please check your commit.\n"
            f"For more information, feel free to ask the person who is CC'd."
        )

        return EMAIL_ALERT_TOPIC, email_body

    def matches(self, project, branch) -> bool:
        """ Check if integration and branch matches with this instance """
        return project == self.integration and branch == self.branch

    def run(self, coin_task_id: str, coin_task_datetime: datetime, commits) -> bool:
        """ Executes class logic """
        send_email = False
        for build in self.builds_to_check:
            with tempfile.TemporaryDirectory() as tmpdirname:
                tempdir = Path(tmpdirname)
                self._fetch_and_unpack_tarball(coin_task_id, build['name'], tempdir)
                for test_param in build['size_comparision']:
                    send_email |= self._size_comparision_test(
                        commits,
                        coin_task_datetime,
                        tempdir,
                        test_param["file"],
                        test_param["threshold"])

        return send_email

    def _fetch_and_unpack_tarball(
            self, coin_task_id: str, build_name: str, target_directory: str) -> None:
        artifacts_url = coin_api.get_artifacts_url(
            coin_task_id,
            build_name,
            self.branch,
            self.coin_id)

        if not os.path.exists(target_directory):
            os.makedirs(target_directory)

        print(f"Fetching {artifacts_url}")
        artifacts_filename = os.path.basename(urlparse(artifacts_url).path)
        artifacts_filename = os.path.join(target_directory, artifacts_filename)
        local_path, http_response_code = urllib.request.urlretrieve(artifacts_url, artifacts_filename)
        if http_response_code != 200:
            raise ConnectionError(f"Error: HTTP {http_response_code} returned")

        print(f"Unpacking {artifacts_filename}")
        with tarfile.open(artifacts_filename) as tarball:
            tarball.extractall(target_directory)

    def _size_comparision_test(
            self,
            commit_url: str,
            coin_task_datetime: datetime,
            path: str,
            file: str,
            threshold_percentage: float) -> bool:
        # pylint: disable=R0913
        send_email = False
        file_with_path = os.path.join(path, 'install', file)
        previous_value = self.binary_size_database.pull(file)
        new_value = os.stat(os.path.expanduser(file_with_path)).st_size

        if previous_value == 0:
            print(f"Pushing initial value for {file}: {new_value}")
        else:
            print(f"Pushing value for {file}: {new_value} (previous value was:{previous_value})")
            threshold_value = previous_value * (threshold_percentage + 1)
            if new_value > threshold_value:
                send_email = True

        self.binary_size_database.push(self.series, commit_url, coin_task_datetime, file, new_value)
        return send_email
