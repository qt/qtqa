#!/bin/sh
# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
#
# This script deletes the branch given as parameter from origin for
# all submodules.
#
# The script is intented to be used to clean out old release
# branches from Gerrit. If a branch head doesn't match the release
# tag, deleting is skipped.
#
# Run the script in a qt5 project.
#

root_dir=$(pwd)
parameters_valid="true"

if ! [ -e "./.git" ]; then
    echo "Not in a git directory"
    parameters_valid="false"
fi

if [ -z "$1" ]; then
    echo "Branch parameter missing"
    parameters_valid="false"
fi

if [ -z "$2" ]; then
    echo "Release tag parameter missing"
    parameters_valid="false"
fi

if [ "$parameters_valid" == "false" ]; then
    echo "Usage: ./delete_remote_branches.sh <branch_name> <release_tag>"
    exit
fi

echo "Searching for remote branch..."
if ! git ls-remote --exit-code origin "refs/heads/$1"; then
    echo "Remote branch $1 not found"
    exit
else
    echo "found"
fi

echo "Checking out $1 branch..."
if git show-ref --quiet "refs/heads/$1"; then
    git checkout "$1"
else
    git checkout --track "origin/$1"
fi

echo "Updating submodules..."
git submodule update --recursive
git fetch --recurse-submodules

echo "Deleting $1 branches from all subrepositories..."
for subdir in $(find . -maxdepth 10 -type d); do
    if [ -e "$root_dir/$subdir/.git" ]; then
        cd "$root_dir/$subdir"

        branch_head_sha=$(git rev-parse --verify --quiet "origin/$1")
        release_tag_sha=$(git rev-list --ignore-missing -n 1 "$2")

        if [ "$branch_head_sha" == "" ]; then
            echo "$subdir NOTE: Branch $1 not found. Skipping..."
            continue
        fi

        if [ "$release_tag_sha" == "" ]; then
            echo "$subdir NOTE: Release tag $2 not found. Skipping..."
            continue
        fi

        if [ "$branch_head_sha" == "$release_tag_sha" ]; then
            # delete branch from origin (Gerrit)
            git push origin --delete "refs/heads/$1"
        else
            echo "$subdir NOTE: Branch head is not same as release tag. Skipping..."
        fi
    fi
done

cd $root_dir

echo "Deleting $1 branches done"
