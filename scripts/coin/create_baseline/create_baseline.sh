#!/bin/bash -e
#############################################################################
##
## Copyright (C) 2017 The Qt Company Ltd.
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

# This script will clone coin repository and build its binaries.
#
# Usage:
# ./create_baseline
# ./create_baseline {commit-id}

########### Variables #############

. utils
basepath=$(dirname $(readlink -f create_baseline.sh))  # absolute script path
commit_template_file=$basepath/commit-msg-template
test_script=$basepath/test_baseline.sh
workdir=$repodir

########### Functions #############

remove_dir() {
 rm -rf $1
}

clean_install() {
 echo "Git reset production branch to HEAD to discard untracked changes / local commits."
 # reset source/git files and clean all caches and untracked files
 git reset --hard origin/production && git clean -xdf -f
}

clone_coin_repo() {
 git clone -b production ssh://codereview.qt-project.org:29418/qtqa/tqtc-coin-ci $1
 scp citest@$vmbuilder_ip:hooks/pre-push $1/.git/hooks/ && chmod +x $1/.git/hooks/pre-push
}

amend_and_push_to_gerrit() {
 # append the commit with the change-id footer
 git commit --amend --no-edit
 # unlock the local repository and attempt git push
 gitdir=$(git rev-parse --git-dir)
 chmod -x $gitdir/hooks/pre-push && git push origin HEAD:refs/for/production && chmod +x $gitdir/hooks/pre-push
}

########### Main #############

is_user_vmbuilder

if [ ! -z "$1" ]; then
 master_commit_id=$1
 echo "Merging master commit-id:" $master_commit_id "into production"
fi

# if local coin repo does not exist, clone it from git
if [ ! -d $repodir/.git ]; then
 echo "Local coin repository $repodir does not exist. Cloning from git.."
 mkdir -p $rootdir
 clone_coin_repo $repodir
fi

cd $repodir
echo "Changed working directory:" $(pwd)

# checkout current production head, update git refs and perform hard reset to discard local changes
git checkout production && git fetch && git reset --hard origin/production

ask_user_to_exec "Do you want to discard old cache/untracked files/binaries and remake the project from scratch? " "clean_install"

# merge master into production branch
if [ -z "$master_commit_id" ]; then
 echo "Merging origin/master to production..."
 git merge origin/master --no-edit
else
 echo "Merging $master_commit to production..."
 git merge "$master_commit_id" --no-edit
fi

# amend commit message
commit_msg="$(cat $commit_template_file && echo "" && cat $basepath/schedules/run_builds | egrep -v '(^#.*|^$)')"
git commit --amend -m "$commit_msg"

if [ ! -f env/bin/activate ]; then
 # creating coin binaries and webui
 make -j1
fi

git commit --amend -m "$commit_msg"
merge_tip_commit=$(git log --no-merges -1)
merge_tip_commit_short=$(git log --no-merges -1 --oneline)

# display commits that were added on top of the current production
if [ ! -z "$skip" ]; then
 gitdir=$(git rev-parse --git-dir)
 scp -p -P 29418 codereview.qt-project.org:hooks/commit-msg .git/hooks/
 git submodule update --init --checkout secrets
 echo -e "\nProduction baseline has been created in $workdir/$repo"
else
 exit 2
fi

# ask user if change should be pushed to gerrit
echo -e "\nMerged commits origin/production..HEAD:"
git log origin/production..HEAD --no-merges --decorate --oneline
echo ""
git log -1
ask_user_to_exec "Push merge to $(git config --get remote.origin.url) [HEAD:refs/for/production] ? " "amend_and_push_to_gerrit"
echo ""

echo "To continue testing the baseline, run script" $test_script
