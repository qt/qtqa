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
