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
localmode=

########### Functions #############

function exec_builds() {
 ./run_ci -r --tmux-no-attach
 sleep 2
 echo "Scheduled builds:"
 /bin/bash -x $basepath/schedules/run_builds
}

########### Main #############

if [ "$1" == "local" ]; then
 localmode=1
else
 # if the script is run on the production server, verify user/network information
 is_user_vmbuilder
 check_network_interface
fi

cd $repodir
. env/bin/activate

# schedule integrations
ask_user_to_exec "This will terminate any active Coin sessions. Do you want to continue? " "exec_builds"

# display browser link
if [ ! -z $skip ]; then
 if [ ! -z $localmode ]; then
  webserver_ip=localhost
 else
  webserver_ip=$vmbuilder_ip
 fi
 if [ -z $QTCI_WEBSERVER_PORT ]; then
  webserver_port=8080
 else
  webserver_port=$QTCI_WEBSERVER_PORT
 fi
 echo "To see Coin status on your browser, open link:" http://$webserver_ip:$webserver_port/coin
fi
