#!/usr/bin/env python3
# ###########################################################################
#
# Copyright (C) 2019 The Qt Company Ltd.
# Contact: https://www.qt.io/licensing/
#
# This file is part of the Quality Assurance module of the Qt Toolkit.
#
# $QT_BEGIN_LICENSE:GPL-EXCEPT$
# Commercial License Usage
# Licensees holding valid commercial Qt licenses may use this file in
# accordance with the commercial license agreement provided with the
# Software or, alternatively, in accordance with the terms contained in
# a written agreement between you and The Qt Company. For licensing terms
# and conditions see https://www.qt.io/terms-conditions. For further
# information use the contact form at https://www.qt.io/contact-us.
#
# GNU General Public License Usage
# Alternatively, this file may be used under the terms of the GNU
# General Public License version 3 as published by the Free Software
# Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
# included in the packaging of this file. Please review the following
# information to ensure the GNU General Public License requirements will
# be met: https://www.gnu.org/licenses/gpl-3.0.html.
#
# $QT_END_LICENSE$
#
# ############################################################################


from enum import Enum
import os
import subprocess
import sys
import shutil
import tempfile

desc = """
Qt Package testing script for testing examples of an installed package.

Run it with the environment for building (compiler and qtenv.bat on Windows)
set up. It will build a selection of examples with console logging enabled
and run them.

Supported platforms: Linux, Windows (MSVC/MinGW), Windows UWP
"""

qt_version = (0, 0, 0)
qt_mkspec = ''
qt_examples_path = ''
qt_install_bins = ''
make_command = ''
PATH = os.environ.get('PATH')
deploy_test_path = '' # path with qt_install_bins removed


class Deployment(Enum):
    NO_DEPLOYMENT = 1
    """The platform supports deployment, for example Win32, macOS"""
    DEPLOYMENT_SUPPORTED = 2
    """The platform requires deployment, for example WinRT"""
    DEPLOYMENT_REQUIRED = 3


def deployment():
    """Returns whether the platform requires/supports deployment"""
    if qt_mkspec.startswith('winrt'):
        return Deployment.DEPLOYMENT_REQUIRED
    if qt_mkspec.startswith('win32'):
        return Deployment.DEPLOYMENT_SUPPORTED
    return Deployment.NO_DEPLOYMENT


def deploy_tool_command(binary):
    """Returns the command to deploy an example"""
    if qt_mkspec.startswith('win32') or qt_mkspec.startswith('winrt'):
        return ['windeployqt', '--no-translations', binary]
    return []


def example_command(binary):
    """Returns the command to launch an example"""
    if qt_mkspec.startswith('winrt'):
        return ['winrtrunner', '--profile', 'appx', '--device', '0',
                '--wait', '0', '--start', binary]
    return [binary]


def normalize_path(p):
    return os.path.normcase(os.path.normpath(p))


def build_deploy_test_path():
    """Build a path with qt_install_bins removed for testing the deployed binary"""
    path_sep = ':' if sys.platform != 'win32' else ';'
    result = []
    for p in PATH.split(path_sep):
        if normalize_path(p) != qt_install_bins:
            result.append(p)
    return path_sep.join(result)


def qt_version_less_than(major, minor, patch):
    return qt_version < (major, minor, patch)


def examples():
    """Compile a list of examples to be tested"""
    global qt_mkspec
    result = ['widgets/mainwindows/mdi', 'charts/qmlchart',
              'multimedia/declarative-camera']
    if not qt_mkspec.startswith('winrt'):
        result.append('sensors/sensor_explorer')
    if qt_version_less_than(5, 12, 0):
        result.append('quick/demos/stocqt')
    result.extend(['location/mapviewer', 'quickcontrols/extras/gallery',
                   'quickcontrols2/gallery'])
    if not qt_mkspec.startswith('winrt') and qt_mkspec != 'win32-g++':
        result.append('webengine/quicknanobrowser')
    return result


def determine_make_command(mkspec):
    """Determine the make call (silent to emphasize warnings)"""
    if mkspec == 'win32-g++':
        return ['mingw32-make', '-s']
    if mkspec.startswith('win'):
        return ['nmake', '/s', '/l']
    return ['make',  '-s']


def query_qmake():
    """Run a qmake query to obtain version, mkspec and path"""
    global make_command, qt_examples_path, qt_install_bins, qt_mkspec
    global qt_version
    for line in run_process_output(['qmake', '-query']):
        print_line = True
        if line.startswith('QMAKE_XSPEC:'):
            qt_mkspec = line[12:]
        elif line.startswith('QT_VERSION:'):
            qt_version = tuple(int(v) for v in line[11:].split('.'))
        elif line.startswith('QT_INSTALL_EXAMPLES:'):
            qt_examples_path = normalize_path(line[20:])
        elif line.startswith('QT_INSTALL_BINS:'):
            qt_install_bins = normalize_path(line[16:])
        else:
            print_line = False
        if print_line:
            print(line)

    make_command = determine_make_command(qt_mkspec)


def execute(args):
    """Execute a command and print output"""
    log_string = '[{}] {}'.format(os.path.basename(os.getcwd()),
                                  ' '.join(args))
    print(log_string)
    exit_code = subprocess.call(args)
    if exit_code != 0:
        raise RuntimeError('FAIL({}): {}'.format(exit_code, log_string))


def run_process_output(args):
    """Execute a command and capture stdout"""
    std_out = subprocess.Popen(args, universal_newlines=1,
                               stdout=subprocess.PIPE).stdout
    result = [line.rstrip() for line in std_out.readlines()]
    std_out.close()
    return result


def run_example(example, test_deployment):
    """Build and run an example"""
    global qt_mkspec
    name = os.path.basename(example)
    # Disambiguate identical directory names of for example QQC1/2 'gallery'
    dir_name = name
    while os.path.exists(dir_name):
        dir_name += '_1'
    result = False
    print('#### Running {} #####'.format(name))
    os.mkdir(dir_name)
    os.chdir(dir_name)
    try:
        execute(['qmake', 'CONFIG+=console',
                 os.path.join(qt_examples_path, example)])
        execute(make_command)

        binary = name if not name == 'mapviewer' else 'qml_location_mapviewer'
        if qt_mkspec.startswith('win'):
            binary += '.exe'
            # Note: After QTBUG-78445, MinGW has release/debug folders only
            # up to 5.14 and sensor_explorer has none
            if not os.path.exists(binary):
                binary = os.path.join('release', binary)
        binary = os.path.join(os.getcwd(), binary)

        do_deploy = (deployment() == Deployment.DEPLOYMENT_REQUIRED
                     or (test_deployment and deployment() != Deployment.NO_DEPLOYMENT))

        if do_deploy:
            execute(deploy_tool_command(binary))
            os.environ['PATH'] = deploy_test_path

        execute(example_command(binary))
        result = True
        print('#### ok {} #####'.format(name))
    except Exception as e:
        print('#### FAIL {} #####'.format(name), e)
    finally:
        os.environ['PATH'] = PATH
    os.chdir('..')
    return result


if __name__ == "__main__":
    if sys.version_info[0] < 3:
        raise Exception('This script requires Python 3')

    query_qmake()
    deploy_test_path = build_deploy_test_path()
    print('#### Found Qt {}.{}.{}, "{}", examples at {}'.format(
          qt_version[0], qt_version[1], qt_version[2],
          qt_mkspec, qt_examples_path))
    if qt_version[0] != 5 or not qt_mkspec or not qt_examples_path:
        print('No suitable Qt version could be found')
        sys.exit(1)

    current_dir = os.getcwd()
    temp_dir = tempfile.mkdtemp(prefix='qtpkgtest{}{}{}'.format(
                                qt_version[0], qt_version[1], qt_version[2]))
    os.chdir(temp_dir)
    error_count = 0
    for index, example in enumerate(examples()):
        if not run_example(example, index == 0):
            error_count = error_count + 1
    os.chdir(current_dir)
    shutil.rmtree(temp_dir)
    print('#### Done ({} errors) #####'.format(error_count))
    sys.exit(error_count)
