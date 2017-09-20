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

clone_tqtc_coin_ci() {
 git clone -b production ssh://codereview.qt-project.org:29418/qtqa/tqtc-coin-ci $1
}

########### Main #############

is_user_vmbuilder

if [ ! -z "$1" ]; then
 master_commit_id=$1
 echo "Merging master commit-id:" $master_commit_id "into production"
fi

# if local coin repo does not exist, clone it from git
if [[ ! -d $repodir ]]; then
 echo "Local coin repository $repodir does not exist. Cloning from git.."
 mkdir -p $repodir
 clone_tqtc_coin_ci $repodir
fi

cd $repodir
echo "Changed working directory:" $(pwd)

# save current branch state that can be restored later
git branch -f old_state
# checkout current production head, update git refs and perform hard reset to discard local changes
git checkout production && git fetch && git reset --hard origin/production

ask_user_to_exec "Do you want to discard old cache/untracked files/binaries and remake the project from scratch? " "clean_install"

# merge master into production
commit_old=$(git rev-parse HEAD)
if [ ! -z "$master_commit_id" ]; then
 if git branch -r --contains $master_commit_id | grep -q 'master'; then
  echo "Merging commit" $master_commit_id $suffix_text "from origin/master into production..."
  git merge "$master_commit_id" -m "$(cat $commit_template_file)" --no-edit
 else
  echo "Remote-tracking (master) branch has no commit: $master_commit_id !"
  exit 2
 fi
else
 master_commit_id=$(git rev-parse origin/master)
 suffix_text="(HEAD)"
 git merge origin/master -m "$(cat $commit_template_file)" --no-edit
fi

if [ ! -f env/bin/activate ]; then
 # creating coin binaries and webui
 make -j1
fi

merge_tip_commit=$(git log --no-merges -1)
merge_tip_commit_short=$(git log --no-merges -1 --oneline)
echo -e "\nCommits added on top of the previous successful merge:\n"
git log origin/production..HEAD --no-merges --decorate --oneline
echo -e "\n******** PRODUCTION MERGE TIP COMMIT *******\n$(git log --no-merges -1)\n***********************************\n"

# display commits that were added on top of the current production
if [[ ! -z "$skip" ]]; then
 gitdir=$(git rev-parse --git-dir)
 scp -p -P 29418 codereview.qt-project.org:hooks/commit-msg .git/hooks/
 git submodule update --init --checkout secrets
 echo -e "\nProduction baseline has been created in $workdir/$repo"
 git log -1 --merges
else
 skip=
 git reset --hard old_state -q
 git branch -D old_state
 exit 2
fi

echo "To continue testing the baseline, run script" $test_script
