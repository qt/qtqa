#!/bin/bash
# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

# XAUTHORITY must be set and DISPLAY must be set
# Usage: build_and_test.sh <main branch> <hardwareId> <jobs> [qtdeclarative-branch]
# XAUTHORITY must be accessible

dir=$(pwd)
prefix=''
moduleConfig=''
makecmd=''
install=''
QtverGtEq6=0
module_set=''
benchmark_set=':benchmarks/auto/creation/ :benchmarks/auto/changes/ :benchmarks/auto/js :benchmarks/auto/animations :benchmarks/auto/bindings'
module_revisions=() # List of submodules and respective git SHA1-hashes used during benchmark run

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

# storeSha1s <module name> <branch>
function storeSha1s {
    local file="$1_$2_sha1.txt"
    if [[ -e "$file" ]]; then
        local sha1
        sha1=$(<"$file")
        module_revisions+=("$1-$sha1")
    fi
}

branch_label="$1+$4"
qtdeclarative_branch=$4
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
    prefix="-prefix $prefix_dir"
    moduleConfig="$dir/install/bin/qt-configure-module ."
    makecmd="cmake --build . --parallel $3"
    install="cmake --install ."
    module_set="$module_set qtshadertools qtsvg qtdeclarative qtquicktimeline qtquick3d qt5compat qtlottie"
    benchmark_set="$benchmark_set :benchmarks/auto/quick3d/"
else
    makecmd="make -j$3"
    moduleConfig="../qtbase/bin/qmake"
    qmlbenchBranch=5.15
    module_set="$module_set qtdeclarative qtquickcontrols qtgraphicaleffects"
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

# Add qtbase and qmlbench in for iterating over the module set
module_set="qtbase $module_set"
for module in $module_set; do
    storeSha1s $module $branch_label
done
# Qmlbench only runs dev, in order to store the sha1 it needs to be separated
storeSha1s "qmlbench" $qmlbenchBranch
module_set="qmlbench $module_set"

# Turn the list into a string to use it as argument for upload_results.py
module_revisions_str=$(IFS=, ; echo "${module_revisions[*]}")
cd $dir
python3 qtqa/scripts/qmlbenchrunner/upload_results.py results.json $branch_label $2 $module_revisions_str

for module in $module_set; do
    rm -rf $dir/$module
done
if [[ -n "$install" ]]; then
    rm -rf $prefix_dir
fi
rm -rf $dir/qmlbench
