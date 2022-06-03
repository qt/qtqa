#!/bin/bash -e
# Copyright (C) 2017 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

# This script will prepare the coin repository for testing.
# NOTE: Any active Coin sessions will be terminated

########### Variables #############

. utils
basepath=$(dirname $(readlink -f test_baseline.sh))  # absolute script path
mode=remote

########### Main #############

if [ ! "$1" == "local" ]; then
 mode="remote"
 # if the script is run in non-local mode, verify user/network information
 is_user_vmbuilder
 check_network_interface
else
 mode="local"
fi

cd $repodir
./run_ci -m "Rebuilding..."
sleep 2
git clean -xdff
make
./run_ci -r --skip-make --tmux-no-attach
echo "Scheduling builds..."
/bin/bash -x $basepath/schedules/run_builds

display_webserver_link $mode

cat <<EOF
If test are successful, you may push the production merge to gerrit:
 cd $repodir
 git push origin HEAD:refs/for/production%r=aapo.keskimolo@qt.io,r=tony.sarajarvi@qt.io,r=simo.falt@qt.io
EOF
