#!/bin/bash
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

# XAUTHORITY must be set and DISPLAY must be set
# Usage: build_and_test.sh <main branch> <hardwareId> <jobs>
# XAUTHORITY must be accessible

# Make sure any errors blocks the rest of the program
set -euo pipefail

dir=$(pwd)
module_set="qtbase,qtshadertools,qtsvg,qtdeclarative,qtquicktimeline,qtquick3d,qt5compat,qtlottie"
moduleConfig="-developer-build -nomake tests -release -opensource -confirm-license -nomake examples -no-warnings-are-errors -submodules $module_set"
benchmark_set=':benchmarks/auto/creation/ :benchmarks/auto/changes/ :benchmarks/auto/js :benchmarks/auto/animations :benchmarks/auto/bindings'
module_revisions=() # List of submodules and respective git SHA1-hashes used during benchmark run


branch_label=$1
echo "Benchmarking $1."
# Qt6 introduced breaking changes for qmlbench. Use qmlbench/dev for Qt6+ builds.
echo "Using CMake for qt6+"
echo "Rebasing to $1"
cd $dir/../../qt6

git fetch origin
git checkout $1
git pull --rebase origin $1
git submodule update --recursive

for module in ${module_set//,/ }; do
    sha1=$(git -C $module rev-parse HEAD)
    module_revisions+=("$module-$sha1")
done

echo "=== Building Qt ==="
cd ..
# Make sure previous build got deleted and the trap ensures that that if any error occurs
# after/during build, the build is deleted.
rm -rf build
cleanup() {
    rm -rf "$dir/../../build"
}
trap cleanup EXIT
mkdir -p build

cd build
../qt6/configure $moduleConfig
ninja -j $3

echo "=== Building qmlbench ==="
cd ../qmlbench
git pull
sha1=$(git rev-parse HEAD)
module_revisions+=("qmlbench-$sha1")

mkdir ../build/qmlbench_build
cd ../build/qmlbench_build
../qtbase/bin/qt-configure-module ../../qmlbench
cmake --build . --parallel $3

# Remove any bad tests that are too difficult for low-power hardware if the variable is set.
if [[ -n "${BADTESTS:-}" ]]; then
    echo "deleting bad tests: $BADTESTS"
    rm -rf $BADTESTS
fi

echo "=== Running benchmarks ==="
./src/qmlbench --json --shell frame-count $benchmark_set > ../results.json

# Move results.json to working directory
mv ../../results.json $dir

module_revisions_str=$(IFS=, ; echo "${module_revisions[*]}")

cd $dir
python3 qtqa/scripts/qmlbenchrunner/upload_results.py results.json $branch_label $2 $module_revisions_str
