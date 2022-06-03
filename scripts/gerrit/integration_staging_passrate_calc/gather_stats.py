# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

import argparse
import base64
import datetime
import json
import os
import re
import traceback
import urllib.parse
from shutil import copyfile
from subprocess import run, PIPE
from time import time_ns
from typing import Iterable, List

import requests
from influxdb import InfluxDBClient
from requests.auth import HTTPBasicAuth


LINE_BLANKER = " " * 123  # Use to clear a console line

class Namespace(object):
    def __init__(self, **kwargs): self.__dict__.update(kwargs)

    @property  # For use when serializing, to dump back to JSON
    def as_map(self): return self.__dict__

    def __repr__(self):
        return str(self.as_map)


class Config(Namespace):
    args: Namespace
    GERRIT_URL: str
    _GERRIT_AUTH: HTTPBasicAuth
    GERRIT_USERNAME: str
    GERRIT_PASSWORD: str
    INFLUXDB_URL: str
    _INFLUXDB_HOST: str
    _INFLUXDB_PATH: str
    INFLUXDB_USERNAME: str
    INFLUXDB_PASSWORD: str
    range: dict


class Result(Namespace):
    merges_in_period: int = 0
    count_fail: int = 0
    highest_restage: int = 0
    total_restage: int = 0
    no_restage: int = 0
    average_restage: float = 0.0
    restage_per_100: float = 0.0
    staging_branch_conflict: int = 0

    def __init__(self, merges=0, fails=0, worst=0, total=0, clean=0, mean=0.0, rate=0.0, conflict=0, **kwargs):
        super().__init__(**kwargs)
        self.merges_in_period = merges
        self.count_fail = fails
        self.highest_restage = worst
        self.total_restage = total
        self.no_restage = clean
        self.average_restage = mean
        self.restage_per_100 = rate
        self.staging_branch_conflict = conflict

    def __add__(self, other):
        return Result(self.merges_in_period + other.merges_in_period,
                      self.count_fail + other.count_fail,
                      max(self.highest_restage, other.highest_restage),
                      self.total_restage + other.total_restage,
                      self.no_restage + other.no_restage,
                      # Abusing these in the sum, relying on caller to renormalise later
                      self.average_restage + other.average_restage,
                      self.restage_per_100 + other.restage_per_100,
                      self.staging_branch_conflict + other.staging_branch_conflict)


def parse_args() -> Namespace:
    parser = argparse.ArgumentParser(
        description="Gather statistics on integration restage and pass/fail rates")
    parser.add_argument('--writeDB', dest='write_db', action='store_true',
                        help="Write results to the database. "
                             "Leave unset to only print results to screen. Use with caution!")
    parser.add_argument('--branch', dest='branch', type=str,
                        help="Branch of qt5.git to examine for module list.")
    parser.add_argument('--repos', dest="custom_repolist", type=str,
                        help="Comma-separated list of fully scoped repos. "
                             "Overwrites the default set of qt5 repos.")
    parser.add_argument('--ageafter', dest='agefrom', type=str, default="1days",
                        help="Relative start of the time range to examine. Default: 1days")  # . Exclusive with --mergedafter")
    parser.add_argument('--agebefore', dest='ageuntil', type=str, default="0seconds",
                        help="Relative end of the time range to examine. Default: {now}")  # . Exclusive with --mergedbefore")
    parser.add_argument('--query', dest="custom_query", type=str,
                        help="Run only a custom query. Enclose desired query in quotes. Do not escape special"
                             " characters. Exclusive - Cannot be combined with other parameters. ")
    # mergedafter / mergedbefore not available until gerrit 3.4
    # parser.add_argument('--mergedafter', dest='mergedafter', type=str,
    #                     help="Explicit start of the merge time range to examine. Exclusive with --ageafter. "
    #                          "Must be in format 2021-01-02[ 15:04:05[.890][ -0700]]")
    # parser.add_argument('--mergedbefore', dest='mergedbefore', type=str,
    #                     help="Explicit start of the merge time range to examine. Exclusive with --agebefore. "
    #                          "Must be in format 2021-01-02[ 15:04:05[.890][ -0700]]")

    args = parser.parse_args()

    return args


def load_config(file, args) -> Config:
    """Load the config from disk or environment variables"""
    c = dict()
    if os.path.exists(file):
        with open(file) as config_file:
            c = json.load(config_file)
    else:
        try:
            copyfile(file + ".template", file)
            print("Config file not found, so we created 'config.json' from the template.")
            with open(file) as config_file:
                c = json.load(config_file)
        except FileNotFoundError:
            try:
                p = run(["git", "show",
                         "85c7b8d0d8f0f4590882f8c3c3a8e174b649b5bc:./config.json.template"],
                        # TODO: Use origin/HEAD as source!
                        stdout=PIPE, stderr=PIPE,
                        cwd=os.path.dirname(__file__))
                if p.stdout:
                    c = json.loads(p.stdout)
                    with open(file, mode="w") as config_file:
                        config_file.write(json.dumps(c))
                    print("NOTE: The template was loaded from git because it didn't exist on disk.")
                else:
                    raise UserWarning(f"Unable to read template from git index. Error: {p.stderr}")
            except FileNotFoundError:
                raise UserWarning("Failed to run git to examine the config template."
                                  " Please ensure your system has Git installed.")

    for key in c.keys():
        try:
            # Override config variables with environment if set, even to an empty value.
            c[key] = os.environ[key]
        except KeyError:
            pass
    config = Config(**c)
    config._GERRIT_AUTH = HTTPBasicAuth(config.GERRIT_USERNAME, config.GERRIT_PASSWORD)
    parsed_gerrit_url = urllib.parse.urlparse(config.GERRIT_URL)
    config.GERRIT_URL = f"{parsed_gerrit_url.scheme}://{parsed_gerrit_url.netloc}/a"
    config.range = {"-age": args.agefrom, "age": args.ageuntil}
    # mergedafter / mergedbefore not available until gerrit 3.4
    # if args.mergedafter:
    #     config.range = {"mergedafter": args.mergedafter,
    #                     "mergedbefore": args.mergedbefore if args.mergedbefore else datetime.now().strftime("%Y-%d-%m %H:%M:%S +0300")}
    parsed_influx_url = urllib.parse.urlparse(config.INFLUXDB_URL)
    config._INFLUXDB_HOST = parsed_influx_url.hostname
    config._INFLUXDB_PATH = parsed_influx_url.path
    config.args = args
    if config.args.write_db and not all([config.INFLUXDB_URL, config.INFLUXDB_USERNAME, config.INFLUXDB_PASSWORD]):
        print("WARN: InfluxDB config incomplete. Continuing without writing to the database.")
        config.args.write_db = False
    return config


def timedelta_parser(input) -> int:
    """Convert gerrit search timedeltas passed as arguments to this script
    to a python timedelta int in nanoseconds"""
    pattern = re.compile(r"(\d+(?:mon|[smhdwy]))")
    placeholder_struct = {
        "days": 0,
        "seconds": 0,
        "minutes": 0,
        "hours": 0,
        "weeks": 0,
    }

    # Split up the input and match input durations with the
    # placeholder struct, then assign the associated value.
    valunit = re.compile(r'(\d+)(\w+)')
    for element in pattern.findall(input):
        val, unit = valunit.match(element).groups()
        if unit.startswith('y'):  # Python timedelta doesn't support 'years'. Convert to days.
            placeholder_struct['days'] += val * (365 + .97/4)
        else:
            placeholder_struct[
                [x for x in placeholder_struct if x.startswith(unit)].pop()] += int(val)

    return round(datetime.timedelta(**placeholder_struct).total_seconds() * 1e9)  # convert to ns


def get_qt5_submodules(config, types) -> Iterable[List[str]]:
    """Discover the list of modules in a branch of qt5.git, based on module types in .gitmodules"""
    assert types, "No types passed to get_qt5_submodules!"  # No point in continuing.
    r = requests.get(f"{config.GERRIT_URL}/projects/"
                     f"qt%2Fqt5/branches/{config.args.branch if config.args.branch else 'dev'}/files/.gitmodules/content",
                     auth=config._GERRIT_AUTH)
    raw_response = bytes.decode(base64.b64decode(r.text), "utf-8")
    for module_text in raw_response.split('[submodule '):
        if not module_text:
            continue
        split_module = module_text.split('\n')
        item = split_module.pop(0)  # was '[submodule "<name>"]' line before splitting
        assert item.startswith('"') and item.endswith('"]'), module_text
        item = item[1:-2]  # module name; followed by key = value lines, then an empty line
        data = dict(line.strip().split(' = ') for line in split_module if line)
        if data.get('status') in types:
            yield 'qt/' + item if data.get('url').startswith('../') else item


def trim_gerrit_response(input: str):
    """When gerrit responds with a json body, it prepends )]}' to the message,
    which must be trimmed before attempting to load the response as json."""
    return input[4:] if input.startswith(")]}'") else input


def do_query(config, params: dict):
    """Query gerrit and return the raw text response body"""
    query_url = f"{config.GERRIT_URL}/changes/?{urlencode(params)}&no-limit"
    print(f'Running: "{query_url}"')
    r = requests.get(query_url, auth=config._GERRIT_AUTH)
    if r.status_code != 200:
        print(f"Failed to query {r.request.url}\n"
              f"{r.status_code} {r.reason}\n"
              f"{r.text}")
    return trim_gerrit_response(r.text)


def build_gerrit_query(params: [dict, str]):
    """Concatenates key/value pairs with ':' and adds '+' in-between pairs"""
    if type(params) == str:  # not a dict! Probably already formatted as a custom query.
        return params
    return '+'.join(f"{p}:{v}" for p, v in params.items())


def urlencode(params: dict):
    """Not really url encoding, but concatenates key/value
    pairs with '=' and adds '&' in-between pairs"""
    return '&'.join([f"{p}={params[p]}" for p in params.keys()])


def build_query_list(config) -> dict:
    """Builds the list of queries to run based on the input repo list or custom query.
    Default list of queries is submodule update jobs + qt5 essential and addon modules"""
    branch = config.args.branch  # If not specified in args, branch is None
    if config.args.custom_query:
        return {"custom_query": config.args.custom_query}
    queries = {}
    if config.args.custom_repolist:
        repos = config.args.custom_repolist.split(',')
    else:
        queries = {
            "submodule_updates": {
                "owner": "qt_submodule_update_bot@qt-project.org",
                "status": "merged"
            }
        }
        if branch:
            queries["submodule_updates"]["branch"] = branch
        queries["submodule_updates"].update(config.range)
        repos = get_qt5_submodules(config, ["essential", "addon"])

    for repo in repos:
        queries[repo] = {
            "repo": repo,
            "status": "merged",
            "-owner": "qt_submodule_update_bot@qt-project.org"
        }
        if branch:
            queries[repo]["branch"] = branch
        queries[repo].update(config.range)
    return queries


def gather_results(config, queries) -> dict:
    """Iterate the list of queries and calculate statistics per-query"""
    results = {}
    for query in queries:
        print(f"\nProcessing changes in: {query}")
        response = do_query(config, {"q": build_gerrit_query(queries[query])})
        try:
            response_json = json.loads(response)
        except json.JSONDecodeError:
            print(f"Failed to decode response json for {query}. Skipping...")
            continue

        changes = [result["id"] for result in response_json]

        if len(changes) == 0:
            print(f"No recent changes in {query}")
            continue

        results[query] = dict()
        print(f"processing {len(changes)} changes")
        for index, change in enumerate(changes, 1):
            restage = 0
            print(LINE_BLANKER, end="\r")  # Clear the current console line so we don't spam.
            print(f"Processing {index} of {len(changes)} {change}", end="\r")
            branch = change.split('~')[1]
            r = requests.get(f"https://codereview.qt-project.org/a/changes/{change}/messages",
                             auth=config._GERRIT_AUTH)
            messages = json.loads(r.text[4:])  # Trim gerrit response
            if any(m["message"].startswith("Change has been successfully cherry-picked") for m in messages):
                # Don't count stats for this change if it was cherry-picked and bypassed CI.
                print(f"Change {change} bypassed CI via cherry-pick. Skipping...")
                continue
            if branch not in results[query]:
                results[query][branch] = Result()
            branch_result = results[query][branch]
            # The CI merging the change creates a final patchset,
            # so we want to examine messages for the prior set.
            current_patchset = messages[-1]["_revision_number"] - 1
            for message in messages:
                if message["_revision_number"] < current_patchset:
                    continue
                if "Continuous Integration: Failed" in message["message"]:
                    branch_result.count_fail += 1
                    restage += 1
                elif "Continuous Integration: Passed" in message["message"]:
                    branch_result.merges_in_period += 1
                    if restage > branch_result.highest_restage:
                        branch_result.highest_restage = restage
                elif "Merge conflict in staging branch. Status changed back to new" in message[
                     "message"]:
                    branch_result.staging_branch_conflict += 1

            branch_result.total_restage += restage
            if not restage:
                branch_result.no_restage += 1

        for branch, branch_result in results[query].items():
            # Calculate averages
            merges_after_restage = branch_result.merges_in_period - branch_result.no_restage
            if merges_after_restage:
                branch_result.average_restage = round(branch_result.total_restage
                                                      / merges_after_restage, 2)
            else:
                branch_result.average_restage = 0.0
            if branch_result.merges_in_period > 0:
                branch_result.restage_per_100 = round(merges_after_restage
                                                      / branch_result.merges_in_period, 3) * 100
            else:
                branch_result.restage_per_100 = 0

            print(LINE_BLANKER)  # Clear the processing x of y changes message.
            print("Branch:", branch)
            print("Merged changes:", branch_result.merges_in_period)
            print("Changes integrated without restaging:", branch_result.no_restage)
            print("Percentage of changes requiring restage: "
                  f"{branch_result.restage_per_100} %")
            print("Total count of integration failures:", branch_result.count_fail)
            print("Highest restage count:", branch_result.highest_restage)
            print("Average restage count:", branch_result.average_restage)
            print("Count of staging cancellations due to staging branch conflicts (not failed):",
                  branch_result.staging_branch_conflict)

    return results


def collate_results(repos, results: dict[Result]) -> [Result, None]:
    """Generate total results per run of the script to avoid
    running these calculations on-database"""

    if not repos:
        repos = get_qt5_submodules(config, ["essential", "addon"])
    total_results = Result()
    measurement_counts = 0
    for repo in repos:
        if repo in results:
            measurement_counts += len(results[repo])
            for branch in results[repo]:
                total_results += results[repo][branch]
    if not measurement_counts:
        return None
    total_results.average_restage = round(total_results.average_restage / measurement_counts, 2)
    total_results.restage_per_100 = round(total_results.restage_per_100 / measurement_counts, 2)

    return total_results


def influx_point_builder(config, data: dict) -> list:
    """Assemble a list of points to write to Influxdb"""

    def build_point(measurement, reponame, timestamp, data, branch=None) -> [dict, None]:
        if data:
            return {
                "measurement": measurement,
                "tags": {"repo": reponame, "branch": branch} if branch else {"repo": reponame},
                "time": timestamp,
                "fields": data.__dict__
            }

    timedelta = timedelta_parser(config.args.ageuntil)
    timestamp = round(time_ns()) - timedelta
    points = []
    for query in data:
        if query in ["repos_combined", "submodule_updates_combined"]:
            point = build_point("statistics_overview", query, timestamp, data[query])
            if point:
                points.append(point)
        else:
            for branch, datum in data[query].items():
                point = build_point("statistics", query, timestamp, datum, branch)
                if point:
                    points.append(point)
    return points


if __name__ == '__main__':
    config = load_config("config.json", parse_args())
    queries = build_query_list(config)
    results = gather_results(config, queries)
    if not config.args.custom_query:
        results["repos_combined"] = collate_results(
            config.args.custom_repolist.split(',') if config.args.custom_repolist else [], results)
        results["submodule_updates_combined"] = collate_results(["submodule_updates"], results)

    if config.args.write_db:
        print("\nWriting results to the database...\n")
        try:
            influx_client = InfluxDBClient(host=config._INFLUXDB_HOST, path=config._INFLUXDB_PATH,
                                           port=443, ssl=True, verify_ssl=True,
                                           username=config.INFLUXDB_USERNAME,
                                           password=config.INFLUXDB_PASSWORD)
            influx_client.write_points(influx_point_builder(config, results),
                                       database="restage_statistics")
        except Exception as e:
            print(e)
    else:
        print("\nINFO: Skipping database write step.\n")

    print("Done!")
