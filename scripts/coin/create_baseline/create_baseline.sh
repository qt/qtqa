#!/bin/bash -e
# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

# This script will clone coin repository and build its binaries.

########### Variables #############

. utils
basepath=$(dirname $(readlink -f create_baseline.sh))  # absolute script path
commit_template_file=$basepath/commit-msg-template
test_script=$basepath/test_baseline.sh
workdir=$repodir

########### Main #############

is_user_vmbuilder

# if local coin repo does not exist, clone it from git
if [ ! -d $repodir/.git ]; then
 echo "Local coin repository $repodir does not exist. Cloning from git.."
 mkdir -p $rootdir
 clone_coin_repo $repodir
fi

# merge master branch into production
cd $repodir
git checkout production 1>/dev/null
git fetch 1>/dev/null
git reset --hard origin/production 1>/dev/null
git merge origin/master --no-ff --no-edit 1>/dev/null

# amend commit template
commit_msg="$(cat $commit_template_file && echo "" && cat $basepath/schedules/run_builds | egrep -v '(^#.*|^$)')"
git commit --amend -m "$commit_msg"

# create change log
changelog=~/product_baseline_$(date +"%Y%m%d").log
git log origin/production..HEAD --no-merges > $changelog

# print log
git log origin/production..HEAD --no-merges --decorate --oneline

cat <<EOF

Changelog: $changelog

To continue testing baseline, execute:
 $test_script

EOF
