#!/usr/bin/env python3

# Copyright (C) 2021 The Qt Company Ltd.
# Contact: https://www.qt.io/licensing/
#
# You may use this file under the terms of the 3-clause BSD license.
# See the file LICENSE in qt/qtrepotools for details.
#

import argparse
import json
import logging
import os
import re
import requests
import subprocess
import sys
import typing

from typing import List
from configparser import ConfigParser
from enum import Enum
from textwrap import dedent

import git  # type: ignore


Mode = Enum('Mode', 'branch sync merge bump')

qt5_extra_repositories = [
    'qt/qtcoap',
    'qt/qtknx',
    'qt/qtmqtt',
    'qt/qtopcua',
    'qt/qtdeviceutilities'
]

qt6_extra_repositories = [
    'qt/qtdeviceutilities',
    'yocto/meta-boot2qt',
    'yocto/meta-qt6'
]


skipped_submodules = ('qtqa', 'qtrepotools')

GERRIT_HOST = 'codereview.qt-project.org'
GERRIT_REST_URL = 'https://' + GERRIT_HOST


log_level = logging.INFO
log_format = "%(asctime)s %(filename)s:%(lineno)d %(levelname)s: %(message)s"
logging.basicConfig(format=log_format, level=log_level)
log = logging.getLogger('branch_qt')
log.setLevel(log_level)
try:
    import coloredlogs  # type: ignore
    coloredlogs.install(level=log_level, logger=log, fmt=log_format)
except:
    pass


example_config_file = dedent(f"""\
    [gerrit]
    username = my_username
    password = some_password""")

class Credentials:
    """ Reads ~/.config/branch_qt.ini for Gerrit username and password. """
    def __init__(self) -> None:
        config_path = os.path.expanduser("~/.config/branch_qt.ini")
        self.config = ConfigParser()
        if not self.config.read(config_path):
            log.warning(f"File '{config_path}' does not exist or could not be parsed. Example file: {example_config_file}")
            exit(1)

    @property
    def username(self) -> str:
        return self.config['gerrit']['username']

    @property
    def password(self) -> str:
        return self.config['gerrit']['password']


def is_major_minor(version: str) -> bool:
    """ Check if a version string is of the format x.y """
    parts = version.split('.')
    return len(parts) == 2 and all(x.isdigit() for x in parts)


def is_major_minor_patch(version: str) -> bool:
    """ Check if a version string is of the format x.y.z """
    parts = version.split('.')
    return len(parts) == 3 and all(x.isdigit() for x in parts)

def get_repo_name(repo: git.Repo) -> str:
    return os.path.basename(repo.working_dir)

def versionCompare(version1: str, version2: str):
    def normalize(v):
        return [int(x) for x in re.sub(r'(\.0+)*$', '',v).split(".")]

    def cmp(a, b):
        return (a > b) - (a < b)

    return cmp(normalize(version1), normalize(version2))

class QtBranching:
    def __init__(self,
                 mode: Mode,
                 fromBranch: str,
                 fromVersion: str,
                 toBranch: str,
                 pretend: bool,
                 skip_hooks: bool,
                 direct: bool,
                 reviewers: typing.Optional[typing.List[str]],
                 repos: typing.Optional[typing.List[str]]
                 ) -> None:
        self.mode = mode
        self.fromBranch = fromBranch
        self.fromVersion = fromVersion
        self.toBranch = toBranch
        self.pretend = pretend
        self.skip_hooks = skip_hooks
        self.direct = direct
        self.reviewers = reviewers
        self.repos = repos

        # Additional repositories that are not part of qt5.git:
        # use qt5_extra_repositories For Qt 5.x.y, otherwise use qt6 one(also for dev)
        if versionCompare(self.toBranch, "6.0") >= 0:
            self.extra_repositories = qt6_extra_repositories
        else:
            self.extra_repositories = qt5_extra_repositories

        log.info(f"{mode.name} from '{fromVersion} (on {fromBranch})' to '{toBranch}'")

    def subprocess_or_pretend(self, *args: typing.Any, **kwargs: typing.Any) -> None:
        if self.pretend:
            log.info(f"PRETEND: {args}, {kwargs}")
        else:
            subprocess.run(*args, **kwargs)

    def run(self) -> None:
        self.sanity_check()
        self.init_repository()

        if self.repos:
            # a list of custom repositories to process, instead of the default (everything)
            for repo_path in self.repos:
                self.process_repository(repo_path)
        else:
            self.process_qt5_repositories()
            for repo_path in self.extra_repositories:
                self.process_repository(repo_path)

        if self.mode == Mode['branch']:
            log.info("Adjusting submodule branches in .gitmodules")
            self.subprocess_or_pretend(['git', 'commit', '-m', 'Adjust submodule branches', '.gitmodules'])
            # update the new and staging branch
            self.subprocess_or_pretend(['git', 'push', 'gerrit', f'HEAD:refs/heads/{self.toBranch}', f'HEAD:refs/staging/{self.toBranch}'])

    def process_qt5_repositories(self) -> None:
        repo = git.Repo('.')
        for submodule in repo.submodules:
            if submodule.name in skipped_submodules:
                continue
            # submodules that are ignored or in weird state need to be skipped
            if submodule.module_exists() and self.clean_submodule(submodule, self.fromBranch):
                repo = git.Repo(submodule.path)
                self.handle_module(repo)
            else:
                log.info(f"SKIPPING {submodule.name}")

    def process_repository(self, repo_path: str) -> None:
        log.info(f"Extra repository: '{repo_path}'")
        assert '/' in repo_path, f"Extra repository must be specified with namespace {repo_path}"
        repo = self.clone_extra_repo(path=repo_path, branch=self.fromBranch)
        if repo:
            self.handle_module(repo)
        else:
            log.warning(f"Could not handle '{repo_path}'.")

    def handle_module(self, repo: git.Repo) -> None:
        oldpath = os.path.abspath(os.curdir)
        try:
            os.chdir(repo.working_dir)
            if self.mode == Mode['merge']:
                self.merge_repo(repo)
            elif self.mode == Mode['branch']:
                self.branch_repo(repo)
            elif self.mode == Mode['sync']:
                self.sync_repo(repo)
            elif self.mode == Mode['bump']:
                self.version_bump_repo(repo)
            else:
                assert False, "This mode is not yet implemented"
        except FileNotFoundError:
            log.warning(f"{repo.path} does not exist, SKIPPING")
        finally:
            os.chdir(oldpath)

    def sanity_check(self) -> None:
        if self.mode == Mode['bump']:
            assert self.fromVersion, "'--version' not set!"
            assert is_major_minor_patch(self.toBranch), \
                   "Bumping must happen to a new minor version!"
        elif self.mode == Mode['branch']:
            if self.fromBranch == 'dev':
                assert is_major_minor(self.toBranch), \
                       f"Branching from dev must be to a minor version (a.b no {self.toBranch})"
            elif is_major_minor_patch(self.fromBranch):
                assert False, f"Cannot branch from release branch ({self.fromBranch})"
            elif is_major_minor(self.fromBranch):
                assert is_major_minor_patch(self.toBranch) \
                and self.toBranch.startswith(self.fromBranch + '.'), \
                    f"Branching from x.y ({self.fromBranch}) should result in x.y.z (not {self.toBranch})"

    def init_repository(self) -> None:
        log.info(f"Fetching super module...")
        repo = git.Repo('.')
        self.checkout_and_pull_branch(repo, self.fromBranch)

        log.info(f"Running init-repository...")
        # This makes sure we have all submodules, and only the ones we want.
        # It also updates the submodules, so we are on the right branches.
        # Note: don't use --branch here, as it breaks idempotence.
        self.subprocess_or_pretend('./init-repository -f --module-subset=all,-ignore'.split())

    def clean_submodule(self, submodule: git.Submodule, branch: str) -> bool:
        log.info(f"Cleaning repo: {submodule.path}")
        repo = git.Repo(submodule.path)
        try:
            self.checkout_and_pull_branch(repo, branch)
        except:
            return False
        return True

    @staticmethod
    def checkout_and_pull_branch(repo: git.Repo, branch: str) -> None:
        """Make sure the repository is on the given branch and up to date."""
        remote = repo.remotes['gerrit']
        remote.fetch()
        remote_branch = remote.refs[branch]
        # Now move to 'branch': either it already exists and we just check it out or we run git checkout -b
        if branch in repo.references:
            repo.head.reference = repo.branches[branch]
            repo.head.ref.set_commit(remote_branch)
        else:
            assert branch in remote.refs, f"Branch {branch} does not exist for {repo.working_dir}"
            repo.create_head(branch, remote_branch).set_tracking_branch(remote_branch).checkout()
        repo.head.ref.checkout(force=True)

    def clone_extra_repo(self, path: str, branch: str) -> git.Repo:
        # checkout target branch
        try:
            name = path.split('/')[-1]
            repo = git.Repo(name)
            self.checkout_and_pull_branch(repo, branch)
        except IndexError:
            log.error(f'Branch {branch} not found in {path}.')
            return None
        except git.exc.NoSuchPathError:
            log.info(f"Cloning '{path}' into '{name}'")
            try:
                remote_url = f"ssh://{GERRIT_HOST}/{path}"
                repo = git.Repo.clone_from(remote_url, to_path=name, branch=branch)
                git.remote.Remote.add(repo, 'gerrit', remote_url)
            except git.exc.GitCommandError:
                log.warning(f"SKIPPING {path} (does branch '{branch}' exist?)")
                return None
        assert repo.head.commit == repo.commit(branch), f"Repository {repo} should be on branch '{branch}'"
        return repo

    def branch_repo(self, repo: git.Repo) -> None:
        repo_name = get_repo_name(repo)
        if repo_name in skipped_submodules:
            log.info(f"Skipping {repo_name} (not branched)")
            return

        log.info(f"Module: {repo_name} ({repo.working_dir}) - creating branch '{self.toBranch}' from '{self.fromBranch}'")
        if not self.pretend:
            repo.remotes['gerrit'].fetch()
        self.subprocess_or_pretend(f"git push -q gerrit gerrit/{self.fromBranch}:refs/heads/{self.toBranch}".split())

        # We do not want to add the extra repos in .gitmodules
        if not repo_name in (extra_repo.split('/')[-1] for extra_repo in self.extra_repositories):
            self.subprocess_or_pretend(f"git config -f ../.gitmodules submodule.{repo_name}.branch {self.toBranch}".split())

    def merge_repo(self, repo: git.Repo) -> None:
        repo_name = get_repo_name(repo)
        log.info(f"Merge: {repo_name} ({self.fromBranch} -> {self.toBranch})")

        self.checkout_and_pull_branch(repo, self.toBranch)
        try:
            subprocess.run(f'git merge --ff-only --quiet gerrit/{self.fromBranch}'.split(), check=True, stderr=subprocess.PIPE)
            self.push(repo_name, self.toBranch)
        except subprocess.CalledProcessError:
            # The merge was not fast forward, try again
            try:
                log.info(f"  Attempting non ff merge for {repo_name}")
                subprocess.run(['git', 'merge', f'gerrit/{self.fromBranch}', '--quiet', '-m', f'Merge {self.fromBranch} into {self.toBranch}'], check=True)
                self.push(repo_name, self.toBranch)
            except subprocess.CalledProcessError:
                log.warning(f"  Merge had conflicts. {repo_name} needs to be merged manually!")

    def sync_repo(self, repo: git.Repo) -> None:
        repo_name = get_repo_name(repo)
        log.info(f"Sync: {repo_name} ({self.fromBranch} -> {self.toBranch})")
        self.checkout_and_pull_branch(repo, self.toBranch)
        try:
            subprocess.run(f'git merge --ff-only --quiet gerrit/{self.fromBranch}'.split(), check=True, stderr=subprocess.PIPE)
            self.push(repo_name, self.toBranch)
        except Exception as e:
            log.exception(f"Could not sync repository: {repo_name}")

    def version_bump(self, file: str, pattern: str, repo: str) -> bool:
        with open(file, mode='r', encoding='utf-8') as f:
            content = f.read()

        match = re.search(pattern, content, flags = re.MULTILINE)
        if match is not None:
            if match.group(1) != self.fromVersion:
                log.warning(f"--version ({self.fromVersion}) differs the one ({match.group(1)}) parsed from {file}, SKIPPING")
                return False
            log.info(f"bump {repo}:{file} from {self.fromVersion} to {self.toBranch}")
            i, j = match.span(1)
            with open(file, mode='w', encoding='utf-8') as f:
                f.write(content[:i] + self.toBranch + content[j:])
            return True

        log.warning(f"could not read version in {repo}, {file}, SKIPPING")
        return False

    def version_bump_repo(self, repo: git.Repo) -> None:
        repo_name = get_repo_name(repo)
        bumpers = {
        '.qmake.conf': r'^MODULE_VERSION *= *([0-9\.]+)\b.*',
        '.cmake.conf': r'^^set\(QT_REPO_MODULE_VERSION "([0-9.]+)"\)$',
        'conanfile.py': r'^ +version = "([0-9.]+)"$'
        }
        if repo_name == 'qtbase':
            cmake = r'set\(QT_REPO_MODULE_VERSION "([0-9.]+)"\)'
            bumpers.update({'util/cmake/pro2cmake.py': cmake})
            bumpers.update({'src/plugins/sqldrivers/.cmake.conf': cmake})

        bumped_files = [] # type: List[str]
        for file, pattern in bumpers.items():
            try:
                if self.version_bump(file, pattern, repo_name):
                    bumped_files.append(file)
            except FileNotFoundError:
                log.info(f"{repo_name}, {file} does not exist, SKIPPING")

        if repo_name == 'qtbase':
            bumped_files.extend(self.bump_qtbase_datastream())

        repo.git.add(bumped_files)
        if not repo.is_dirty():
            log.warning(f"nothing to do for {repo_name}, is the version bump already done?")
            return
        repo.index.commit(f"Bump version to {self.toBranch}", skip_hooks=self.skip_hooks)
        self.push(repo_name, self.fromBranch)

    def push(self, project: str, branch: str) -> None:
        # In case user wants to use direct push
        if self.direct:
            # TODO: make this work for projects that don't have 'qt' as namespace
            query = {'q': f'project:qt/{project} branch:{branch} (status:staging OR status:staged OR status:integrating)'}
            response = requests.get(f'{GERRIT_REST_URL}/changes/', params=query)
            response.raise_for_status()
            assert response.text.startswith(')]}')
            query_result = json.loads(response.text[4:])
            if query_result:
                log.warning(f"{project}, {branch} is busy (staged or integrating changes), SKIPPING!")
                return
            self.subprocess_or_pretend(['git', 'push', 'gerrit', f'HEAD:refs/heads/{branch}', f'HEAD:refs/staging/{branch}'])
        else: # Do formal codereview instead
            reviewerStr = f"%r={',r='.join(self.reviewers)}" if self.reviewers else ''
            self.subprocess_or_pretend(['git', 'push', 'gerrit',
                                        f'HEAD:refs/for/{branch}{reviewerStr}'])

    def bump_qtbase_datastream(self) -> typing.Iterable[str]:
        if self.fromVersion.split('.')[1] == self.toBranch.split('.')[1]:
            return []
        # For minor version changes we need to change qdatastream,
        # it has a version enum that must correspond to the Qt minor version:
        log.info("Adjusting src/corelib/serialization/qdatastream.[h/cpp]")
        datastream_h = 'src/corelib/serialization/qdatastream.h'
        datastream_cpp = 'src/corelib/serialization/qdatastream.cpp'

        # datastream.h
        datastream_h_content = open(datastream_h, mode='r', encoding='utf-8').read()
        split_target = self.toBranch.split('.')
        nextver = f'{split_target[0]}_{split_target[1]}'
        ver = f'{split_target[0]}_{str(int(split_target[1]) - 1)}'
        next_version_hex = f'{int(split_target[0]):02x}{int(split_target[1]):02x}00'
        next_next_version_hex = f'{int(split_target[0]):02x}{int(split_target[1])+1:02x}00'

        # Add new version to enum and bump up the hex version in #ifdef
        search = f'^( +)(Qt_DefaultCompiledVersion = Qt_)[0-9_]+\\n(#if QT_VERSION >= 0x){next_version_hex}(\\n#error [^\\n]+\\n#endif)$'
        replacement = f'\\g<1>Qt_{nextver} = Qt_{ver},\\n\\g<1>\\g<2>{nextver}\\n\\g<3>{next_next_version_hex}\\g<4>'
        datastream_h_content = re.sub(search, replacement, datastream_h_content, flags=re.MULTILINE)
        open(datastream_h, mode='w', encoding='utf-8').write(datastream_h_content)

        # datastream.cpp
        datastream_cpp_content = open(datastream_cpp, mode='r', encoding='utf-8').read()

        # Add Documentation (a line like '\value Qt_5_12 Same as Qt_5_11')
        search = f'^( +)(\\\\value Qt_{ver} [^\n]+\n)( +\\\\omitvalue Qt_DefaultCompiledVersion)$'
        replacement = f'\\1\\2\\1\\\\value Qt_{nextver} Same as Qt_{ver}\n\\3'
        datastream_cpp_content = re.sub(search, replacement, datastream_cpp_content, flags=re.MULTILINE)

        open(datastream_cpp, mode='w', encoding='utf-8').write(datastream_cpp_content)
        return datastream_h, datastream_cpp

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="branch_qt.py",
                                     formatter_class=argparse.RawTextHelpFormatter,
                                     description="Do various merge operations on Qt repositories")
    parser.add_argument("--mode", "-m",
                        type=str,
                        choices=["branch", "sync", "merge", "bump"],
                        required=True,
                        help=dedent("""\
                                    branch - start soft branching: create the "to" branch based on the "from" branch
                                        branch_qt.py -m branch --from 5.12 --to 5.12.4
                                            Now 5.12.4 will exist, based on 5.12.
                                    sync - intermediate sync, to update a branch during soft-branching
                                        branch_qt.py -m sync --from 5.12 --to 5.12.4
                                            Move the new branch fast-forward, assuming only 5.12 has new commits.
                                    merge - down-merge
                                        branch_qt.py -m merge --from 5.12 --to 5.12.4
                                            Merges 5.12 into 5.12.4.
                                    bump - version bump, to move from 5.12.3 to 5.12.4:
                                        branch_qt.py -m bump --from dev --version 5.12.0 --to 5.13.0"""))
    parser.add_argument("--from", "-f", required=True,
                        type=str, dest="fromBranch")
    parser.add_argument("--version", "-v", required=False,
                        type=str, dest="fromVersion")
    parser.add_argument("--to", "-t", required=True,
                        type=str, dest="toBranch")
    parser.add_argument("--pretend", action="store_true",
                        help="Make the changes to the repositories, but do not push to Gerrit.")
    parser.add_argument("--skip-hooks", action="store_true",
                        help="Do not run git commit hooks.")
    parser.add_argument("--direct", action="store_true",
                        help="Direct push changes in repos instead of sending changes for review")
    parser.add_argument("--reviewers", nargs="*",
                        help="Optional list of reviewers. Ignored when '--direct' is used.")
    parser.add_argument("--repos", nargs="*",
                        help="Optional list of repositories (instead of processing all repositories).")
    return parser.parse_args(sys.argv[1:])


def gerrit_add_pushmaster() -> None:
    config = Credentials()
    auth = requests.auth.HTTPBasicAuth(config.username, config.password)
    r = requests.put(f'{GERRIT_REST_URL}/a/groups/Push Masters/members/{config.username}', auth=auth)
    r.raise_for_status()

def gerrit_remove_pushmaster() -> None:
    config = Credentials()
    auth = requests.auth.HTTPBasicAuth(config.username, config.password)
    r = requests.delete(f'{GERRIT_REST_URL}/a/groups/Push Masters/members/{config.username}', auth=auth)
    r.raise_for_status()

if __name__ == "__main__":
    args = parse_args()
    try:
        # If we want to do a review (or just pretend) user doesn't need to be in 'Push masters'
        if not args.pretend and args.direct:
            gerrit_add_pushmaster()

        branching = QtBranching(mode=Mode[args.mode],
                                fromBranch=args.fromBranch,
                                fromVersion=args.fromVersion,
                                toBranch=args.toBranch,
                                pretend=args.pretend,
                                skip_hooks=args.skip_hooks,
                                direct=args.direct,
                                reviewers=args.reviewers,
                                repos=args.repos)
        branching.run()
    finally:
        if not args.pretend and args.direct:
            gerrit_remove_pushmaster()
