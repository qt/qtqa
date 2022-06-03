#!/bin/bash
# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

# Usage: build_and_test.sh <main branch> <hardwareId> ["annotate"?] [qtdeclarative-branch]

# Set the following environment variables before running:
# LB_TOOLCHAIN=Full path of the toolchain directory to use when cross-compiling.
# TOOLCHAIN_FILE: Full path of the cmake toolchain file to use when cross-compiling.
# CMAKE_GENERATOR="Unix Makefiles"
# DEVIP: IP of the target device to execute the tests on.

dir=$(pwd)
host_prefix="$dir/host_install"
target_prefix="$dir/target_install"
host_moduleConfig="$host_prefix/bin/qt-configure-module"
target_moduleConfig="$target_prefix/bin/qt-configure-module"
makecmd="cmake --build . --parallel"
install="cmake --install ."
module_set="$module_set qtshadertools qtdeclarative qtquickcontrols2 qtquick3d"
benchmark_set=':benchmarks/auto/creation/ :benchmarks/auto/changes/ :benchmarks/auto/js :benchmarks/auto/animations :benchmarks/auto/bindings :benchmarks/auto/quick3d/'
devicePrefix=/opt/qt
deviceIP=$DEVIP


# checkoutQtModule <module name> <branch>
function checkoutQtModule {
    git clone --progress https://codereview.qt-project.org/qt/$1
    cd $dir/$1
    git reset --hard origin/$2 && git clean -dqfx
    git checkout $2
    echo "Checked out $1 revision $(git rev-parse HEAD)"
    git rev-parse HEAD > ../$1_$2_sha1.txt
    if [[ $1 == 'qtquick3d' ]]; then
        git submodule init
        git submodule update
    fi
    cd $dir
}

# buildQtModule <module name> <branch> <module config tool>
function buildQtModule {
    echo "\n Configuring and building $1"
    checkoutQtModule $1 $2
    cd $dir/$1
    ($3 .)
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

branch_label="$1+$4"
qtdeclarative_branch=$4
if [[ -z $qtdeclarative_branch ]]; then
    qtdeclarative_branch=$1
    branch_label=$1
fi


echo "Using $1 as base and $qtdeclarative_branch for qtdeclarative. Using $branch_label as label in database."

echo 'Running test suites: ' $benchmark_set

# Do host build
echo "\n Starting host build"
# checkout and configure Qt Base
checkoutQtModule qtbase $1
python3 $dir/qtqa/scripts/qmlbenchrunner/change_sdk_ver.py
cd $dir/qtbase
./configure -developer-build -nomake tests -nomake examples -release -opensource -confirm-license -no-warnings-are-errors --prefix=$host_prefix $EXTRA_HOST_CONFIGURE_ARGS
($makecmd)
if [[ -n "$install" ]]; then
    ($install)
fi
cd $dir

# other modules
for module in $module_set; do
    buildQtModule $module $1 $host_moduleConfig
done

# Do target build
echo "\n Starting target build"
checkoutQtModule qtbase $1
cd qtbase
$dir/qtbase/configure -qt-host-path $host_prefix -no-rpath -nomake tests -nomake examples -release -opensource -confirm-license -no-warnings-are-errors -extprefix $target_prefix -prefix /opt/qt -- -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE -DQT_BUILD_TOOLS_WHEN_CROSSCOMPILING=ON
($makecmd)
if [[ -n "$install" ]]; then
    ($install)
fi
cd $dir

# other modules
for module in $module_set; do
    buildQtModule $module $1 $target_moduleConfig
done

# qmlbench
git clone --progress https://codereview.qt-project.org/qt-labs/qmlbench
cd $dir/qmlbench

# Remove any bad tests that are too difficult for low-power hardware if the variable is set.
if [ ! -z "$BADTESTS" ]; then
    echo "deleting bad tests: $BADTESTS"
    rm -rf $BADTESTS
fi
($target_moduleConfig .)
($makecmd)

cp -r benchmarks $target_prefix
cp -r shared $target_prefix
cp src/qmlbench $target_prefix

cd $dir

# Sync to device
sizeNeeded=$(du -hsk $target_prefix | cut -f 1)
bytesFree=$(ssh -o UserKnownHostsFile=/home/$USER/.ssh/known_hosts root@$deviceIP df / | awk '/[0-9]%/{print $(NF-2)}')
echo "$sizeNeeded needed for qt libraries."
# Nuke the current installation of qt on device.
ssh -o UserKnownHostsFile=/home/$USER/.ssh/known_hosts root@$deviceIP rm -rf /opt/qt
if [[ sizeNeeded -lt bytesFree ]]; then
    echo "$bytesFree bytes free on device."
    echo "Syncing libraries..."
    rsync -rauvz --exclude=doc $target_prefix/* root@$deviceIP:/opt/qt/
else
    echo "Not enough disk space on device. Cannot continue!"
fi


echo "Beginning SSH session to device for local QMLBench run..."
ssh -o UserKnownHostsFile=/home/$USER/.ssh/known_hosts root@$deviceIP /bin/bash << EOT
export LD_LIBRARY_PATH=/opt/qt/lib:\$LD_LIBRARY_PATH
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_KMS_CONFIG=/etc/kms.conf
cd /opt/qt/
./qmlbench --json --shell frame-count $benchmark_set > results.json
exit
EOT

echo "Closed SSH session. Parsing and uploading results..."
rsync -avz root@$deviceIP:/opt/qt/results.json results.json

$dir/qtqa/scripts/qmlbenchrunner/run.py results.json $branch_label $2

if [ "$3" == "annotate" ]; then
    for module in $module_set; do
        compareSha1sAndAnnotate $module $1
    done
    compareSha1sAndAnnotate qmlbench $qmlbenchBranch
fi

echo "Removing module checkouts..."
rm -rf $dir/qtbase
for module in $module_set; do
    rm -rf $dir/$module
done
echo "Removing host install..."
if [[ -n "$host_prefix" ]]; then
    rm -rf $host_prefix
fi
echo "Removing target install..."
if [[ -n "$target_prefix" ]]; then
    rm -rf $target_prefix
fi
echo "Removing qmlbench..."
rm -rf $dir/qmlbench
