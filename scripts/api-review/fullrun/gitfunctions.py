#############################################################################
##
## Copyright (C) 2021 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##

import os
import subprocess

# get the current branch of git repo
def get_branch(git_repo : str = '.') -> str:
    cwd = os.getcwd()

    os.chdir(git_repo)

    cmd = 'git rev-parse --abbrev-ref HEAD'.split(' ')
    completed_process = subprocess.run(cmd, capture_output=True)
    output = completed_process.stdout.decode('utf-8').strip()

    #print(output)

    os.chdir(cwd)

    return output

# Gets a list of submodules from given git repo path and optionally, branch
# Where each module is represented by a dict
def get_submodules(git_repo : str = '.', branch : str = 'current') -> {}:
    cwd = os.getcwd()

    os.chdir(git_repo)
    current_branch = get_branch()

    if branch != 'current':
        os.system(f'git checkout {branch}')

    modules = {}

    modules_path = '.gitmodules'

    if not os.path.exists(modules_path):
        print(f'Error: {modules_path} not found')
        return modules

    modules_file = open(modules_path, 'r')

    read_state = 0
    current_module = {}

    for line in modules_file:
        if line.startswith('[submodule'):
            if 'name' in current_module:
                modules[current_module['name']] = current_module

            read_state = 1
            module_name = line.split(' ')[1].replace('"', '').replace(']', '').strip()

            current_module = {'name': module_name}
        elif read_state == 1:
            if '=' in line:
                elements = line.split('=')
                key = elements[0].strip()
                value = elements[1].strip()

                current_module[key] = value

    if branch != 'current':
        os.system(f'git checkout {current_branch}')

    os.chdir(cwd)

    return modules

# Returns a list of active submodules for the given repo and branch
def get_active_submodules(git_repo : str = '.', branch : str = 'current') -> []:
    modules = []

    for module_name, module in get_submodules(git_repo, branch).items():
        if module['status'] != 'ignore':
            modules.append(module_name)

    return modules
