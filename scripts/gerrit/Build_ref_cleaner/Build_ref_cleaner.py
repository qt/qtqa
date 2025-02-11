# Copyright (C) 2023-2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import subprocess
import time
import datetime
import os
# Sleep time after every 1000 build refs (in seconds)
_sleeptime = 1
# Determine how many months worth of refs should be kept
_months = 3
# List of folders which subfolders need cleaning of build refs
"""_
clean_these = ["../test", "../git_testrepo"] # Test
"""
_clean_these = ["installer-framework",
                "pyside",
                "qt",
                "qt-apps",
                "qt-extensions",
                "qt-labs",
                "qt3dstudio",
                "qtqa",
                "qtsdk",
                "tqtc-boot2qt",
                "yocto",
                "license-tools",
                ]

def run_git_command(command, path_to_folder = None, splitter = "", index = 1, return_output = True):
    """
    Runs git commands in python as a subprocess
    Returns the output of the git command as a list of the lines it produces

    Parameters

    command (list): git command without the word git
    for example if you want to run "git status" give "status" as the parameter
    splitter (str): choose a string used for splitting lines (default = "")
    index (int): choose the index of the split line you want to save (default = 1)
    """
    full_command = ["git"] + command

    result = subprocess.run(full_command, cwd=path_to_folder, capture_output=True)
    temp = result.stdout
    if (return_output):
        stdout = temp.decode('utf-8')
        output_lines = stdout.splitlines()
        output_list = []
        for line in output_lines:
            if "refs/builds/" in line:
                output_list.append(line.split(splitter)[index])
        return output_list
    return 0

def get_git_folders(root_folder):
    print("checking {}".format(root_folder))
    git_dirs = []

    for (dirpath, subdirs, _) in os.walk(root_folder):
        for dir in subdirs:
            full_path = os.path.join(dirpath, dir)
            if dir.endswith(".git"):
                git_dirs.append(full_path)

    return git_dirs

def remove_old_builds(path_for_command, months_old, splitter):
    """
    This function removes all the builds in path (in git_command after ls-remove)
    that are older than {months_old} months and also those builds which do not
    correspond to the naming scheme (files should be named with the count in seconds
    from 1.1.1970 to the date the file was created)
    All files which name corresponds to a time in the future will also be removed.

    Parameters

    path_for_command (str): path which specifies the execution location for the git command

    months_old (int): number of months the which determines
        how old the oldest files to keep should be

    splitter (str): used for splitting the output of ls-remote
        into the sha1 and path inside the run_git_command function
    """
    not_deleted = []
    deleted = ""
    filePaths = run_git_command(["show-ref"], path_for_command, splitter)
    reference_age = int(time.time()) - int(60*60*24*30*months_old)
    timestamp = datetime.datetime.fromtimestamp(time.time()).strftime('%Y/%m/%d %H:%M:%S')
    print(timestamp + " Deleting old builds from " + path_for_command + " older than " +
           str(reference_age) + " seconds " + "(" + str(months_old) + " months)")

    for i, filePath in enumerate(filePaths):
        # Report the percentage of refs covered and which refs were removed
        # in the current repo after every 1000 refs
        if i % 1000 == 0:
            print(deleted)
            print("{} complete".format(str(round(i/float(len(filePaths))*100.0, 2)) + "%"))
            time.sleep(_sleeptime)
            deleted = ""
        # Extract the ref name from the filePath variable
        _, file = filePath.rsplit("/", 1)
        # Determine if the ref name is valid and if the ref should be deleted or not
        if file.isdigit() and (int(file) < reference_age or
                               int(file) > int(time.time()) + int(60*60*24*30*months_old)):
            run_git_command(["update-ref", "-d", filePath], path_for_command, return_output=False)
            deleted += filePath + " removed\n"
        elif file.isdigit() and (int(file) > reference_age):
            not_deleted.append(filePath)
        else:
            run_git_command(["update-ref", "-d", filePath], path_for_command, return_output=False)
            deleted += filePath + " removed\n"
    print(deleted)
    print("100%" + "complete")
    timestamp = datetime.datetime.fromtimestamp(time.time()).strftime('%Y/%m/%d %H:%M:%S')
    print(timestamp + " Old builds deleted")
    return not_deleted

def main():
    for folder in _clean_these:
        if ".git" in folder:
            print("Removing old build refs from " + folder)
            remove_old_builds(folder, _months, " ")
        else:
            git_folders = get_git_folders(folder)
            for git_folder in git_folders:
                print("Removing old build refs from " + git_folder)
                remove_old_builds(git_folder, _months, " ")
    return 0

if __name__ == "__main__":
    main()
