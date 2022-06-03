#!/bin/bash
# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

# XAUTHORITY must be set and DISPLAY must be set
# Usage: build_and_test.sh <main branch> <hardwareId> <jobs> ["annotate"?] [qtdeclarative-branch]
# XAUTHORITY must be accessible

# checkoutQtModule <module name> <branch>

qtSdkDir=/home/$USER/Qt
qtSourceDir=$WORKSPACE/$BUILD_NUMBER
qtBuildDir=$WORKSPACE/$BUILD_NUMBER/build
qtHostPrefix=$qtBuildDir/hostbin
devicePrefix=/opt/qt
deviceName=$DEVNAME
deviceMkspec=$DEVMKSPEC
sysrootDir=$qtSdkDir/5.11.2/Boot2Qt/$deviceName/toolchain/sysroots
armSysrootDir=$sysrootDir/$ARMSYSROOT
crossCompile=$sysrootDir/$CROSSCOMPILE
installRoot=$WORKSPACE/$BUILD_NUMBER/Install/$devicePrefix
deviceIP=$DEVIP

mkdir build

function checkoutQtModule {
    git clone --progress https://code.qt.io/qt/$1
    cd $1
    git checkout $2
    git rev-parse HEAD > ../$1_$2_sha1.txt
    cd ..
}

# buildQtModule <module name> <branch> <jobs>
function buildQtModule {
    checkoutQtModule $1 $2
    cd $1
    $qtHostPrefix/bin/qmake
    make -j $3
    make install
    cd ..
}

# compareSha1sAndAnnotate <module name> <branch>
function compareSha1sAndAnnotate {
    if [[ -e ../$1_$2_sha1.txt && -e $1_$2_sha1.txt ]]; then
    local new_sha1=$(cat $1_$2_sha1.txt)
    local old_sha1=$(cat ../$1_$2_sha1.txt)
    if [[ "$new_sha1" != "$old_sha1" ]]; then
        qmlbenchrunner/annotate.py --title="$1 update" --tag="$1Update" --text="Updated $1 to $new_sha1 (previous was $old_sha1)" --branch="$2"
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

# checkout and configure Qt Base
checkoutQtModule qtbase $1
cd $qtBuildDir
$qtSourceDir/qtbase/configure -commercial -confirm-license -debug -prefix $devicePrefix -hostprefix $qtHostPrefix -extprefix $installRoot -device $deviceMkspec -device-option CROSS_COMPILE=$crossCompile -sysroot $armSysrootDir -nomake tests -nomake examples -device-option DISTRO_OPTS=boot2qt $EXTRAARGS
make -j $3
make install
cd $WORKSPACE/$BUILD_NUMBER

#other modules
buildQtModule qtdeclarative $qtdeclarative_branch $3
buildQtModule qtquickcontrols $1 $3
buildQtModule qtquickcontrols2 $1 $3
buildQtModule qtgraphicaleffects $1 $3

# qmlbench
git clone --progress https://code.qt.io/qt-labs/qmlbench.git
cd qmlbench

qmlbenchBranch=dev

if [[ ! "$1" =~ ^(v?6\.|dev) ]]; then
    # Revert a breaking change made to enable shader effects in qt6
    # if branch is not dev or major version 6.xx
    qmlbenchBranch=5.15
fi

git checkout $qmlbenchBranch
git rev-parse HEAD > ../qmlbench_${qmlbenchBranch}_sha1.txt

#Remove any bad tests that are too difficult for low-power hardware if the variable is set.
if [ ! -z "$BADTESTS" ]; then
    echo "deleting bad tests: $BADTESTS"
    rm -rf $BADTESTS
fi

$qtHostPrefix/bin/qmake qmlbench.pro
make -j $3
cp -r benchmarks $installRoot/
cp -r shared $installRoot/
cp src/qmlbench $installRoot/
cd ..
echo Label: $branch_label

#sync to device
sizeNeeded=$(du -hsk $installRoot | cut -f 1)
bytesFree=$(ssh -o UserKnownHostsFile=/home/dan/.ssh/known_hosts root@$deviceIP df / | awk '/[0-9]%/{print $(NF-2)}')
echo "$WORKSPACE/$BUILD_NUMBER/" > $installRoot/hostfilepath.txt

#Delete tests from device
ssh -o UserKnownHostsFile=/home/dan/.ssh/known_hosts root@$deviceIP rm -rf /opt/qt/benchmarks

echo "$sizeNeeded needed for qt libraries."

if [[ sizeNeeded -lt bytesFree ]]; then
    echo "$bytesFree bytes free on device."
    echo "Syncing libraries..."
    rsync -avz --exclude=doc --exclude=include --exclude=*.debug $installRoot/* root@$deviceIP:/opt/qt/
    echo "$bytesFree bytes remaining on device."
else
    echo "Not enough disk space on device. Trying to delete /opt/qt to free up space."
    echo "$bytesFree bytes free on device before deletion."
    ssh -o UserKnownHostsFile=/home/dan/.ssh/known_hosts root@$deviceIP rm -rf /opt/qt
    bytesFree=$(ssh -o UserKnownHostsFile=/home/dan/.ssh/known_hosts root@10.9.70.70 df / | awk '/[0-9]%/{print $(NF-2)}')
    echo "$bytesFree bytes free on device after deletion."
    if [[ sizeNeeded -lt bytesFree ]]; then
        rsync -avz --exclude=doc --exclude=include --exclude=*.debug $installRoot/* root@$deviceIP:/opt/qt/
        echo "$bytesFree bytes remaining on device."
    else
        echo "Not enough disk space on device to continue, and wiping out /opt/qt wasn't enough for some reason. Please investigate the device @ [IP]"
        exit 1
    fi
fi

echo "Beginning SSH session to device for local QMLBench run..."
ssh -o UserKnownHostsFile=/home/dan/.ssh/known_hosts root@$deviceIP /bin/bash << 'EOT'
export QT_EGLFS_IMX6_NO_FB_MULTI_BUFFER=1
cd /opt/qt/
./qmlbench --json --shell frame-count benchmarks/auto/creation/ benchmarks/auto/changes/ benchmarks/auto/js benchmarks/auto/animations benchmarks/auto/bindings > results.json
hostfilepath=$(cat hostfilepath.txt)
rsync -avz -e "ssh -i /home/root/.ssh/id_rsa" results.json dan@10.9.70.25:$hostfilepath
exit
EOT

echo "Closed SSH session. Parsing and uploading results..."

python3 qmlbenchrunner/run.py results.json $branch_label $2


if [ "$4" == "annotate" ]; then
    compareSha1sAndAnnotate qtbase $1
    compareSha1sAndAnnotate qtdeclarative $1
    compareSha1sAndAnnotate qtquickcontrols $1
    compareSha1sAndAnnotate qtquickcontrols2 $1
    compareSha1sAndAnnotate qtgraphicaleffects $1
    compareSha1sAndAnnotate qmlbench $qmlbenchBranch
fi
