#!/bin/bash
#############################################################################
##
## Copyright (C) 2021 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the qtqa module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU Lesser General Public License Usage
## Alternatively, this file may be used under the terms of the GNU Lesser
## General Public License version 3 as published by the Free Software
## Foundation and appearing in the file LICENSE.LGPL3 included in the
## packaging of this file. Please review the following information to
## ensure the GNU Lesser General Public License version 3 requirements
## will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 2.0 or (at your option) the GNU General
## Public license version 3 or any later version approved by the KDE Free
## Qt Foundation. The licenses are as published by the Free Software
## Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-2.0.html and
## https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################

# XAUTHORITY must be set and DISPLAY must be set
# Usage: build_and_test.sh <main branch> <hardwareId> <jobs> ["annotate"?] [qtdeclarative-branch]
# XAUTHORITY must be accessible

dir=$(pwd)
prefix=''
moduleConfig=''
makecmd=''
install=''
QtverGtEq6=0
module_set=''
benchmark_set='benchmarks/auto/creation/ benchmarks/auto/changes/ benchmarks/auto/js benchmarks/auto/animations benchmarks/auto/bindings'


# checkoutQtModule <module name> <branch>
function checkoutQtModule {
    git clone --progress https://codereview.qt-project.org/qt/$1
    cd $dir/$1
    git checkout $2
    echo "Checked out $1 revision $(git rev-parse HEAD)"
    git rev-parse HEAD > ../$1_$2_sha1.txt
    if [[ $1 == 'qtquick3d' ]]; then
        git submodule init
        git submodule update
    fi
    cd $dir
}

# buildQtModule <module name> <branch> <jobs>
function buildQtModule {
    checkoutQtModule $1 $2
    cd $dir/$1
    ($moduleConfig)
    ($makecmd)
    if [[ -n "$install" ]]; then
        ($install)
    fi
    cd $dir
}

# compareSha1sAndAnnotate <module name> <branch>
function compareSha1sAndAnnotate {
    if [[ -e ../$1_$2_sha1.txt && -e $1_$2_sha1.txt ]]; then
        local new_sha1=$(cat $1_$2_sha1.txt)
        local old_sha1=$(cat ../$1_$2_sha1.txt)
        if [[ "$new_sha1" != "$old_sha1" ]]; then
            $dir/qtqa/scripts/qmlbenchrunner/annotate.py --title="$1 update" --tag="$1Update" --text="Updated $1 to $new_sha1 (previous was $old_sha1)" --branch="$2"
        fi
    fi

    if [[ -e $1_$2_sha1.txt ]]; then
        cp $1_$2_sha1.txt ../$1_$2_sha1.txt
    fi
}

branch_label="$1+$5"
qtdeclarative_branch=$5
if [[ -z $qtdeclarative_branch ]]; then
    qtdeclarative_branch=$1
    branch_label=$1
fi

echo "Using $1 as base and $qtdeclarative_branch for qtdeclarative. Using $branch_label as label in database."

if [[ "$1" =~ ^(v?6\.|dev) ]]; then
    QtverGtEq6=1
    echo "Using CMake for qt6+"
    # Qt6 introduced breaking changes for qmlbench. Use qmlbench/dev for Qt6+ builds.
    qmlbenchBranch=dev
    # Qt6 makes cmake the default. Set up the build to use it.
    prefix_dir="$dir/install"
    prefix="--prefix=$prefix_dir"
    moduleConfig="$dir/install/bin/qt-configure-module ."
    makecmd="cmake --build . --parallel $3"
    install="cmake --install ."
    module_set="$module_set qtshadertools qtdeclarative qtquickcontrols2 qtquick3d"
    benchmark_set="$benchmark_set benchmarks/auto/quick3d/"
else
    makecmd="make -j$3"
    moduleConfig="../qtbase/bin/qmake"
    qmlbenchBranch=5.15
    module_set="$module_set qtdeclarative qtquickcontrols qtquickcontrols2 qtgraphicaleffects"
fi

echo 'Running test suites: ' $benchmark_set

# checkout and configure Qt Base
checkoutQtModule qtbase $1
cd $dir/qtbase
./configure -developer-build -nomake tests -nomake examples -release -opensource -confirm-license -no-warnings-are-errors $prefix $EXTRA_CONFIGURE_ARGS
($makecmd)
if [[ -n "$install" ]]; then
    ($install)
fi
cd $dir

# other modules
for module in $module_set; do
    buildQtModule $module $1 $3
done

# qmlbench
git clone --progress https://codereview.qt-project.org/qt-labs/qmlbench
cd $dir/qmlbench

git checkout $qmlbenchBranch
git rev-parse HEAD > ../qmlbench_${qmlbenchBranch}_sha1.txt

#Remove any bad tests that are too difficult for low-power hardware if the variable is set.
if [ ! -z "$BADTESTS" ]; then
    echo "deleting bad tests: $BADTESTS"
    rm -rf $BADTESTS
fi
($moduleConfig)
($makecmd)

./src/qmlbench --json --shell frame-count $benchmark_set > ../results.json
cd $dir
echo Label: $branch_label
qtqa/scripts/qmlbenchrunner/run.py results.json $branch_label $2

module_set="qtbase $module_set"  # Add qtbase back in for iterating over the module set.

if [ "$4" == "annotate" ]; then
    for module in $module_set; do
        compareSha1sAndAnnotate $module $1
    done
    compareSha1sAndAnnotate qmlbench $qmlbenchBranch
fi

for module in $module_set; do
    rm -rf $dir/$module
done
if [[ -n "$install" ]]; then
    rm -rf $prefix_dir
fi
rm -rf $dir/qmlbench
