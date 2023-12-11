#!/usr/bin/env python3

# Copyright (C) 2023 The Qt Company Ltd.
# Contact: https://www.qt.io/licensing/
#
# You may use this file under the terms of the 3-clause BSD license.
# See the file LICENSE in qt/qtrepotools for details.
#

import argparse
import json
import os
import getpass
import re
import urllib.parse

import requests
from requests.auth import HTTPBasicAuth

usage_text = """
Warn about cherry-picking changes which do not contain the latest branch.

This script should be run after branching Qt to a new stable branch version.
It is expected that changes committed to the dev branch which contain a
"Pick-to:" footer in the commit should target the latest stable branch.
After a branching operation is complete, the Pick-to: footer must be
updated to target the current stable branch in addition to the now
latest-1 stable branch.

This script will give a -1 and post a comment when an open change targets the
latest-1 stable branch and is missing the newly branched stable branch.

This script will also remove any Code-Review +2 votes from open changes on dev
which do not target the latest stable branch. This is to force a reevaluation
of the change to determine if it should be included in the latest stable
branch, or if can merge normally for the next release.

Requires package: "python-requests", installable via `pip3 install requests`
"""


def trim_response(text) -> str:
    """Trim off Gerrit's magic prefix from JSON responses"""
    return text.removeprefix(")]}'")


class Gerrit:
    """Class for interacting with Gerrit's REST API"""
    def __init__(self):
        if not os.environ.get("GERRIT_USERNAME") or not os.environ.get("GERRIT_PASS"):
            print('Notice: You can set your username and password via environment variables'
                  ' "GERRIT_USERNAME" and "GERRIT_PASSWORD"')
        self.gerrit_user = os.environ.get("GERRIT_USERNAME") or input("Gerrit Username: ")
        gerrit_pass = os.environ.get("GERRIT_PASS") or getpass.getpass("Gerrit Password: ")
        self.auth = HTTPBasicAuth(self.gerrit_user, gerrit_pass)
        if self.get("projects").status_code == 401:
            print("Gerrit Authorization failure. Please ensure your credentials are correct.")
            exit(1)

    @property
    def _gerrit_user(self):
        return self.gerrit_user

    @staticmethod
    def __to_url(tail):
        return f"https://codereview.qt-project.org/a/{tail}"

    def get(self, query):
        return requests.get(self.__to_url(query), auth=self.auth)

    def post(self, query, data):
        return requests.post(self.__to_url(query), json=data, auth=self.auth)


class Stable:
    """A Major branch contains numerical, ascending-ordered stable branches"""
    def __init__(self, stable_ver: int, release_branches: list[int]):
        self.stable_ver = stable_ver
        self.release_branches = sorted(release_branches)
        self.latest: int = self.release_branches[-1] if release_branches else -1
        self.previous: int = -1

    @property
    def latest_name(self):
        return f"{self.stable_ver}.{self.latest}"

    @property
    def previous_name(self):
        return f"{self.stable_ver}.{self.previous}"

    def append(self, item: int):
        if item not in self.release_branches:
            self.release_branches.append(item)
            self.release_branches = sorted(self.release_branches)
            self.latest = self.release_branches[-1]
            if len(self.release_branches) >= 2:
                self.previous = self.release_branches[-2]

    def __repr__(self):
        return ", ".join([f"{self.stable_ver}.{stable}" for stable in self.release_branches])

    def __int__(self):
        return self.stable_ver

    def __str__(self):
        return str(self.stable_ver)

class Major:
    """A Major branch contains numerical, ascending-ordered stable branches"""
    def __init__(self, major_ver: int, stable_branches: list[int]):
        self.major_ver = major_ver
        self.stable_branches = sorted(stable_branches, key=int)
        self.latest: Stable = self.stable_branches[-1] if stable_branches else -1
        self.previous: int = -1

    @property
    def latest_name(self):
        return f"{self.major_ver}.{self.latest}"

    @property
    def previous_name(self):
        return f"{self.major_ver}.{self.previous}"

    @property
    def next_name(self):
        return f"{self.major_ver}.{int(self.latest)+1}"

    def append(self, item: int):
        if item not in self.stable_branches:

            self.stable_branches.append(Stable(item, []))
            self.stable_branches = sorted(self.stable_branches, key=int)
            self.latest = self.stable_branches[-1]
            if len(self.stable_branches) >= 2:
                self.previous = self.stable_branches[-2]

    def __repr__(self):
        return ", ".join([f"{self.major_ver}.{stable}" for stable in self.stable_branches])


class Project:
    """A project contains Major branches which in turn have stable branches."""
    def __init__(self, proj_id: str = "", branch_list: list = None):
        self.id = proj_id
        self.branch_list = branch_list
        majors_temp: dict[str, Major] = {}
        branch_re = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?$")
        if proj_id == "qt/qt5":
            pass
        for branch in self.branch_list:
            matches = branch_re.findall(branch)
            if matches:
                match = matches.pop()
                if match[0] not in majors_temp:
                    majors_temp[match[0]] = Major(int(match[0]), [int(match[1])])
                else:
                    majors_temp[match[0]].append(int(match[1]))
        self.majors: list[Major] = list(majors_temp.values())

    def get_latest_branches(self):
        return [b.latest_name for b in self.majors]


parser = argparse.ArgumentParser(description=usage_text,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--simulate', dest='sim', action='store_true',
                    help='Perform a dry run and print proposed actions.')
parser.add_argument('--skip-warn', dest='skip_warn', action='store_true',
                    help='Skip evaluation and warning of missing branches.')
parser.add_argument('--skip-votecheck', dest='skip_votecheck', action='store_true',
                    help='Skip removal of +2 votes on open changes on dev.')
args = parser.parse_args()

print("Starting project branch scan...\n")

gerrit = Gerrit()
projects: dict[str, Project] = {}

# Query qt/qt* projects
# Response schema: https://gerrit-review.googlesource.com/Documentation/rest-api-projects.html#list-projects
r = gerrit.get("projects/?r=^qt/qt.*&state=ACTIVE")
projects_list = json.loads(trim_response(r.text)).keys()  # Get just the project names from response

# Get project branches
for project in projects_list:
    # Response schema https://gerrit-review.googlesource.com/Documentation/rest-api-projects.html#list-branches
    # project id must be URL quoted to retrieve project correctly.
    r = gerrit.get(f"projects/{urllib.parse.quote(project, safe='')}/branches")

    branch_list = []
    for branch in json.loads(trim_response(r.text)):
        matches = re.findall(r"heads/(\d+\.\d+(?:\.\d+)?)$", branch["ref"])
        if matches:
            branch_list.append(matches.pop())

    if branch_list:
        # Populate Project objects
        projects[project] = Project(project, branch_list)
        print(f"Got project {project} with highest branches"
              f" {', '.join(projects[project].get_latest_branches())}")
    else:
        print(f"Project {project} has no applicable branches.")

print("\nFinished project branch scan...\n")


# Keep track of actions taken
added_comment = 0
has_comment = 0


if args.skip_warn:
    print("Skipping branch pick-target evaluation.")
else:
    print("Starting open change discovery...\n")
    for project in projects.values():
        for major in project.majors:
            print(f'Pulling changes for {project.id} on major version "{major.major_ver}"')
            # Get the list of open changes that are missing the latest stable
            # branch in the pick-to footer
            # Response Schema https://gerrit-review.googlesource.com/Documentation/rest-api-changes.html#list-changes
            r = gerrit.get('changes/?q=(is:open)+'
                        f'and+project:{project.id}+'
                        'and+branch:dev+'
                        f'and+message:"{major.previous_name}"'
                        '&o=CURRENT_REVISION&o=CURRENT_COMMIT')
            changes = json.loads(trim_response(r.text))

            for change in changes:
                current_revision = change["current_revision"]
                line_no = 0
                pick_targets = []
                message_body = change["revisions"][current_revision]["commit"]["message"]
                for i, line in enumerate(message_body.split("\n"), 7):
                    if line.startswith("Pick-to:"):
                        # Compensate line_no for hidden commit message headers since
                        # they aren't considered when posting a review
                        line_no = i
                        # Append because sometimes people write multiple lines of pick targets
                        # instead of a single line with multiple targets
                        pick_targets += line.removeprefix("Pick-to: ").split()

                # Our gerrit query can't perform regexes on the commit message,
                # so check to make sure that the old branch was actually in the
                # pick-to targets, and the newer branch was not.
                if major.latest_name in pick_targets:
                    continue  # Nothing to do, has the latest branch already.
                if major.previous_name not in pick_targets:
                    continue  # Must have seen the older target somewhere else in the commit message.

                review_comment = f"Omission of {major.latest_name} is probably incorrect"
                # Response schema: https://gerrit-review.googlesource.com/Documentation/rest-api-changes.html#list-comments
                r = gerrit.get(f'changes/{change["id"]}/revisions/current/comments')
                messages = json.loads(trim_response(r.text))
                skip = False
                if any(m["author"]["username"] == gerrit.gerrit_user and m["message"] == review_comment
                    for m in messages.get("/COMMIT_MSG", [])):
                    # The gerrit user already posted a message to this change. Skip it.
                    print(f"Skipping {change['id']}."
                        f" Already posted a warning on the current patchset for {major.latest_name}.")
                    has_comment += 1
                    continue
                print(f"Post message to {change['id']}."
                    f" Has {major.previous_name}, missing {major.latest_name}")
                added_comment += 1
                data = {
                    "message": f"This change targets {major.previous_name} for cherry-picking,"
                            f" but omits the latest stable branch {major.latest_name}."
                            f" Please either add {major.latest_name} or override"
                            " this sanity message.",
                    "labels": {
                        "Sanity-Review": "-1"
                    },
                    "comments": {
                        "/COMMIT_MSG": [{
                            "line": line_no,
                            "message": f"Omission of {major.latest_name} is probably incorrect"
                        }]
                    },
                    "add_to_attention_set": [{
                        "user": change["revisions"][current_revision]["commit"]["author"]["email"],
                        "reason": "Sanity warning: Pick-to targets missing"
                    }]
                }
                if args.sim:
                    print(f"SIM: Post comment to {change['id']}")
                else:
                    # Set Review schema: https://gerrit-review.googlesource.com/Documentation/rest-api-changes.html#set-review
                    r = gerrit.post(f"changes/{change['id']}/revisions/current/review", data=data)
                    print(f"Posted comment to {change['id']}. Response -> [{r.status_code}]: {r.text}")


    print(f"\nPosted comments to {added_comment} changes")
    print(f"Found existing comment on {has_comment} changes")


# Next, remove +2 votes for any changes on dev which don't already target the latest stable branch.
# This is to prevent people from merging changes which target the previous stable branch.


removed_votes = 0

if args.skip_votecheck:
    print("Skipping removal of +2 votes on open changes on dev.")
else:
    print("\nStarting merged change scan...\n")
    for project in projects.values():
        major = project.majors[-1]
        print(f'Pulling changes for {project.id} on major version "{major.major_ver}"')
        # Get the list of open changes that are missing the latest stable
        # branch in the pick-to footer
        # Response Schema https://gerrit-review.googlesource.com/Documentation/rest-api-changes.html#list-changes
        r = gerrit.get('changes/?q=(is:open)+'
                    f'and+project:{project.id}+'
                    'and+branch:dev+'
                    f'and+-message:"{major.latest_name}"'
                    '&o=CURRENT_REVISION&o=CURRENT_COMMIT')
        changes = json.loads(trim_response(r.text))

        for change in changes:
            # Response schema: https://gerrit-review.googlesource.com/Documentation/rest-api-changes.html#list-reviewers
            r = gerrit.get(f'changes/{change["id"]}/reviewers')
            reviewers = json.loads(trim_response(r.text))
            # Note any _account_id's which have given a Code-Review = "+2" approval.
            accounts = []
            didRemove = False
            for reviewer in reviewers:
                if reviewer["approvals"].get("Code-Review") == "+2":
                    print(f"Found +2 from {reviewer['username']} on {change['id']}")
                    accounts.append({"account_id": reviewer["_account_id"], "name": reviewer["name"]})
                    # Response schema: https://gerrit-review.googlesource.com/Documentation/rest-api-changes.html#delete-vote
                    if args.sim:
                        print(f"SIM: Remove +2 from {reviewer['username']} on {change['id']}")
                    else:
                        didRemove = True
                        if args.sim:
                            print(f"SIM: Remove +2 from {reviewer['username']} on {change['id']}")
                            continue
                        r = gerrit.post(f'changes/{change["id"]}/reviewers/{reviewer["_account_id"]}/votes/Code-Review/delete', data={
                            "reason": f"Removed +2 from {reviewer['username']}"
                            f" due to branching of {major.latest_name}."
                            f" Please re-evaluate if this change should be included in"
                            f" {major.latest_name} FF, or left to merge on dev for {major.next_name}."
                        })
                        print(f"Removed +2 from {reviewer['username']} on {change['id']}."
                            f" Response -> [{r.status_code}]: {r.text}")
                    removed_votes += 1

            # Add reviewers to the attention set
            if didRemove:
                for account in accounts:
                    data = {
                        "user": account["account_id"],
                        "reason": "Removed +2 due to branching of latest stable branch."
                    }
                    if args.sim:
                        print(f"SIM: Add reviewers to attention set on {change['id']}: {account}")
                    else:
                        r = gerrit.post(f"changes/{change['id']}/attention", data=data)
                        print(f"Added reviewers to attention set on {change['id']}."
                            f" Response -> [{r.status_code}]: {r.text}")

    print(f"\nRemoved +2 from {removed_votes} changes")
print("\nDone!")
