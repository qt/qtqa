# Copyright (C) 2024 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
""" Wrapper for COIN API requests """
import json
import time
import datetime
from urllib3.util import Retry
from requests import Session
from requests.adapters import HTTPAdapter


class NoArtifactsFound(Exception):
    """ Exception Class for fetching artifacts """


def get_coin_task_details(coin_task_id: str) -> dict:
    """ Fetches and parses task details for given COIN task id """
    s = Session()
    retries = Retry(total=3)
    s.mount('https://', HTTPAdapter(max_retries=retries))
    resp = s.get(
        "https://coin.ci.qt.io/coin/api/taskDetail",
        params={"id": coin_task_id},
        timeout=60
    )
    if not resp.ok:
        raise ConnectionError(f"Failed to fetch task workitems, status: {resp.status_code}")

    tasks_json = json.loads(resp.content)
    git_shas = []
    return_dictionary = {
        'coin_update_ongoing': False,
        'last_timestamp': datetime.datetime(2000, 1, 1, tzinfo=datetime.timezone.utc),
        'git_shas': git_shas
    }

    if tasks_json['tasks'] is None:
        return return_dictionary
    task = tasks_json['tasks'][0]

    if task['state'] == "Running":
        return_dictionary['coin_update_ongoing'] = True
        return return_dictionary
    task_datetime = datetime.datetime.fromisoformat(
        task['completed_on'][0:19]).replace(tzinfo=datetime.timezone.utc)
    return_dictionary['last_timestamp'] = task_datetime

    for change in task['tested_changes']:
        return_dictionary['git_shas'].append(change['sha'])

    return return_dictionary


def get_artifacts_url(task_id: str, project: str, branch: str, identifier: str) -> str:
    """ Fetches url for artifacts tarball for given id """
    s = Session()
    retries = Retry(total=3)
    s.mount('https://', HTTPAdapter(max_retries=retries))
    attempts = 0
    max_attempts = 3
    while attempts < max_attempts:
        resp = s.get(
            "https://coin.ci.qt.io/coin/api/taskWorkItems",
            params={"id": task_id},
            timeout=60
        )
        if resp.ok:
            break
        if resp.status_code == 404:
            # Try again after one minute in case if COIN has not been updated
            time.sleep(60)
            attempts += 1
            continue
        if not resp.ok:
            raise NoArtifactsFound(f"Failed to fetch task workitems, status: {resp.status_code}")

    tasks_json = json.loads(resp.content)
    if tasks_json['tasks_with_workitems'] is None:
        raise NoArtifactsFound(f"No tasks_with_workitems was not found for {task_id}: {resp.content}")

    task_json = tasks_json['tasks_with_workitems'][0]

    if task_json['workitems'] is None:
        raise NoArtifactsFound(f"No workitems was not found for {task_id}")

    for workitem in task_json['workitems']:
        if workitem['identifier'] == identifier and workitem['project'] == project:
            if workitem['branch'] != branch:
                raise NoArtifactsFound(f"Wrong branch: {workitem['branch']}")
            if workitem['state'] != 'Done':
                raise NoArtifactsFound(f"Wrong state: {workitem['state']}")
            log_url = workitem['storage_paths']['log_raw']
            artifacts_url = log_url.replace('log.txt.gz', 'artifacts.tar.gz')
            return 'https://coin.intra.qt.io' + artifacts_url

    raise NoArtifactsFound(f"No artifact url found for {task_id}, {project}, {branch}, {identifier}:\n {task_json}")
