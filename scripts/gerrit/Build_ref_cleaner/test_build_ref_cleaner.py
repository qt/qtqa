# Copyright (C) 2023 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

import random
import subprocess
import time
import unittest
from unittest.mock import MagicMock, patch
import os
import Build_ref_cleaner
from Build_ref_cleaner import remove_old_builds, run_git_command, get_git_folders

def create_test_filepaths(
    nbr_of_files_per_dir = 20,
    dirs=4,
    subdirs=3,
    files_per_month = 3,
    invalids = 10,
):
    """
    Used for creating fake paths to fake build refs for testing the remove_old_builds function

    Parameters:

    nbr_of_files_per_dir (int): the number of build refs per fake subdirectory
    dirs (int): the number of fake directories which contain the fake subdirectories
    subdirs (int): number of fake subdirectories
    files_per_month (int): number of fake build refs per month (creation time)
    """
    # Used in the test for determining if the function being tested kept the right files
    save_these = []
    # The list which contains all of the fake paths made by this function
    list_of_paths = []
    month = 60*60*24*30 # as seconds
    file_age = 0 # in months
    next_age = 0 # used for determining when to change the age
    for invalid in range(invalids):
        path = "test_folder_{}/test_subfolder_{}.git/refs/builds/".format(invalid, invalid)
        file_name = path + "invalid_{}".format(invalid)
        list_of_paths.append(file_name)

    for i in range(dirs):
        for j in range(subdirs):
            path = "test_folder_{}/test_subfolder_{}.git/refs/builds/".format(i, j)

            for _ in range(nbr_of_files_per_dir):
                if next_age == files_per_month:
                    file_age += 1
                    next_age = 0
                name = str(int(time.time())-random.randint(month*file_age, month*(file_age+1)))
                file_name = path + name
                if (file_age < Build_ref_cleaner._months):
                    save_these.append(file_name)

                list_of_paths.append(file_name)
                next_age += 1

    return list_of_paths, save_these

class Test_Build_ref_cleaner(unittest.TestCase):

    @patch('Build_ref_cleaner.run_git_command')
    def test_remove_old_builds(self, mock_run_git_command):
        """
        Test for remove_old_builds function.
        Checks if the function keeps the build refs that are newer than the specified age in months
        """
        mock_run_git_command.return_value, desired_output = create_test_filepaths()
        result = remove_old_builds("abc", Build_ref_cleaner._months, " ")
        self.assertEqual(result, desired_output)

    @patch('subprocess.run')
    def test_run_git_command(self, mock_run):
        """
        Test for the output sorting logic in run_git_command function
        (does not test if the subprocess.run actually executes the git command)
        """
        mock_process = MagicMock()
        mock_process.stdout= (
            b"qwer refs/builds/1\nqwer refs/builds/2\n"
            b"qwer refs/test/3\nqwer refs/test/4\n"
            b"qwer refs/ref/5\nqwer refs/builds/6\n"
        )

        mock_run.return_value = mock_process
        result = run_git_command(["update-ref", "-d", "qwer"], splitter = " ")
        result2 = run_git_command(["update-ref", "-d", "qwer"], return_output = False)

        desired_output = ["refs/builds/1", "refs/builds/2",  "refs/builds/6"]

        self.assertEqual(result, desired_output)
        self.assertEqual(result2, 0)

    @patch('os.walk')
    def test_get_git_folders(self, mock_walk):
        root_folder = "current/path"
        mock_walk.return_value = [
            ("current/path", ["sub1.git", "sub2", "sub3.git", "sub4"], ["file1", "file2"]),
            ("current/path/sub1.git", ["sub5", "sub6"], ["file1", "file2"]),
            ("current/path/sub2", ["sub7"], ["file1", "file2"]),
            ("current/path/sub3.git", ["sub8"], ["file1", "file2"]),
            ("current/path/sub4", ["sub9"], ["file1", "file2"])]
        git_folders = get_git_folders(root_folder)
        self.assertEqual(git_folders, ["current/path\\sub1.git", "current/path\\sub3.git"])

    @patch('Build_ref_cleaner.remove_old_builds')
    @patch('Build_ref_cleaner.get_git_folders')
    def test_main(self, mock_get_git_folders, mock_remove_old_builds):
        mock_get_git_folders.return_value = ["subfolder1", "subfolder2"]
        Build_ref_cleaner._clean_these = ["folder1.git", "folder2"]
        result = Build_ref_cleaner.main()
        self.assertEqual(result, 0)

if __name__ == '__main__':
    unittest.main()
