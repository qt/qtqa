#############################################################################
##
## Copyright (C) 2021 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##

import os
import json
import pprint
import subprocess

import gitfunctions as gf
import config as c


### Helpers

def run_list(cmd : [], **kwargs):
    print(' '.join(cmd))
    #cmd = cmd.replace('"', '').split(' ')
    return subprocess.run(cmd, **kwargs)

# Basic run wrapper for commands. Will not work for command elements with spaces
def run(cmd : str, **kwargs):
    return run_list(cmd.split(' '), **kwargs)

# Get the path to the hooks of the specified repo
def get_hooks_dir(repo : str = '.') -> str:
    cwd = os.getcwd()
    os.chdir(repo)

    result = run('git rev-parse --git-path hooks', capture_output=True)
    output = result.stdout.decode('utf-8').strip()

    os.chdir(cwd)

    return output

# Get the absolute path of the api review script
def get_api_review_script() -> str:
    relative_path = os.path.join(
        os.path.dirname(os.path.dirname(__file__)),
        'api-review-gen')

    return os.path.abspath(relative_path)

# Write module data to json file
def export_modules(modules : {}, filename : str):
    outfile = open(filename, 'w')
    outfile.write(json.dumps(modules, indent=4))
    outfile.close()

def branch_exists(branch : str, repo : str = '.') -> bool:
    cwd = os.getcwd()

    os.chdir(repo)

    result = run('git branch --list', capture_output=True).stdout.decode('utf-8')

    os.chdir(cwd)

    return branch in result

# diffs the given change and returns if its empty or not
def is_nonempty_change(module : str, previous_version : str) -> bool:
    cwd = os.getcwd()

    module_path = os.path.join(c.qt5_repo, module)
    os.chdir(module_path)

    change = f'api-review-{previous_version}-{c.next_version}'

    cmd = f'git diff {previous_version} {change}'
    result = run(cmd, capture_output=True).stdout.decode('utf-8').strip()

    os.chdir(cwd)

    return result != ''

# maps the module to which version API review should be based on
def map_modules() -> {}:
    cwd = os.getcwd()

    os.chdir(c.qt5_repo)

    module_version_mapping = {}

    next_version_modules = list(filter(
        lambda module: module not in c.exclude_modules,
        gf.get_active_submodules()))

    for module in next_version_modules:
        module_version_mapping[module] = 'unknown'

    previous_versions_modules = {}

    for version in c.previous_versions:
        previous_versions_modules[version] = gf.get_active_submodules('.', version)

    # try to map all modules in next version
    for module in next_version_modules:
        for previous_version, previous_version_modules in previous_versions_modules.items():
            if module in previous_version_modules:
                module_version_mapping[module] = previous_version
                break

        if module_version_mapping[module] == 'unknown':
            print('No previous version found for ' + module)

    os.chdir(cwd)

    return module_version_mapping

### Main steps

def update_repo():
    print(f'### Updating repo...')
    cwd = os.getcwd()

    if os.path.exists(c.qt5_repo):
        os.chdir(c.qt5_repo)
    else:
        os.system(f'git clone {c.qt5_url} {c.qt5_repo}')
        os.chdir(c.qt5_repo)
        print(os.getcwd())
        hook_cmd = c.commit_hook_cmd.split(' ')
        hook_cmd.append(get_hooks_dir())
        run_list(hook_cmd)
        run_list(['git', 'config', 'user.email', c.git_email])

    run(f'git checkout {c.next_version}')

    run('git pull --ff-only')

    os.chdir(cwd)

# Updates specified submodule, and fetch given previous version
def update_module(module : str, previous_version : str):
    print(f'### Updating module {module}...')
    cwd = os.getcwd()

    gitfile = os.path.join(c.qt5_repo, module, '.git')

    if not os.path.exists(gitfile):
        os.chdir(c.qt5_repo)

        run(f'git submodule update --init --recursive {module}')

        os.chdir(module)

        hooks_dir = get_hooks_dir()

        hook_cmd = c.commit_hook_cmd.split(' ')
        hook_cmd.append(hooks_dir)

        run_list(hook_cmd)
        run_list(['git', 'config', 'user.email', c.git_email])
        run(f'git fetch origin {previous_version}:{previous_version}')
    else:
        os.chdir(os.path.join(c.qt5_repo, module))

    run(f'git checkout {c.next_version}')
    run('git pull --ff-only')

    os.chdir(cwd)

# Generate and upload the Gerrit change for specified module and version
def generate_change(module : str, previous_version : str):
    print(f'### Generating change for {module}...')

    cwd = os.getcwd()

    api_review_script = get_api_review_script()
    module_path = os.path.join(c.qt5_repo, module)
    os.chdir(module_path)

    branch = f'api-review-{previous_version}-{c.next_version}'

    cmd_base = api_review_script
    cmd_options = f'-t {c.task_id}'

    if branch_exists(branch):
        cmd_options += ' --amend'

    cmd_full = f'{cmd_base} {cmd_options} {previous_version} {c.next_version}'

    run(cmd_full)

    os.chdir(cwd)

def review_change(module : str, previous_version : str):
    print(f'### Reviewing change for {module}...')

    cwd = os.getcwd()

    module_path = os.path.join(c.qt5_repo, module)

    os.chdir(module_path)

    input(f'Reviewing BORING changes for {module}. Press any key to continue...')
    run('git diff -b -D')

    input(f'Reviewing INTERESTING changes for {module}. Press any key to continue...')
    run(f'git log -p {previous_version}..')

    os.chdir(cwd)

def ask_to_upload(module : str) -> bool:
    while True:
        r = input(f'Upload change for {module}? [y/n] > ')

        if r in 'yn':
            return r == 'y'

        print('Invalid response. Expected y or n.')

def upload_change(module : str, previous_version : str):
    print(f'### Uploading change for {module}...')

    cwd = os.getcwd()
    module_path = os.path.join(c.qt5_repo, module)

    os.chdir(module_path)

    current_branch = gf.get_branch()
    branch = f'api-review-{previous_version}-{c.next_version}'

    run(f'git checkout {branch}')
    run(f'git push origin HEAD:refs/for/{c.next_version}%topic=api-change-review-{c.next_version}')
    run(f'git checkout {current_branch}')

    os.chdir(cwd)

def reset_module(module : str):
    print(f'### Resetting module {module}...')

    cwd = os.getcwd()

    module_path = os.path.join(c.qt5_repo, module)

    os.chdir(module_path)

    run('git reset --hard HEAD')
    run(f'git checkout {c.next_version}')

    os.chdir(cwd)

def main():
    update_repo()
    module_version_mapping = map_modules()

    for module, previous_version in module_version_mapping.items():
        print(f'### Processing {module}')
        input('Press any key to continue...')
        update_module(module, previous_version)
        generate_change(module, previous_version)
        if is_nonempty_change(module, previous_version):
            review_change(module, previous_version)
            if ask_to_upload(module):
                upload_change(module, previous_version)
        else:
            print(f'Change for {module} in uninteresting. Skipping.')

        reset_module(module)

if __name__ == '__main__':
    main()
