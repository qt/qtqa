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
