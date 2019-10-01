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

qt_version = [0, 0, 0]
qt_mkspec = ''
qt_examples_path = ''
make_command = ''


def qt_version_less_than(major, minor, patch):
    if major < qt_version[0]:
        return True
    elif major > qt_version[0]:
        return False
    if minor < qt_version[1]:
        return True
    elif minor > qt_version[1]:
        return False
    return patch < qt_version[2]


def examples():
    """Compile a list of examples to be tested"""
    global qt_mkspec
    result = ['charts/qmlchart', 'multimedia/declarative-camera']
    if not qt_mkspec.startswith('winrt'):
        result.append('sensors/sensor_explorer')
    if qt_version_less_than(5, 12, 0):
        result.append('quick/demos/stocqt')
    result.extend(['location/mapviewer', 'quickcontrols/extras/gallery'])
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
    global make_command, qt_examples_path, qt_mkspec, qt_version
    for line in run_process_output(['qmake', '-query']):
        print_line = True
        if line.startswith('QMAKE_XSPEC:'):
            qt_mkspec = line[12:]
        elif line.startswith('QT_VERSION:'):
            for v, version_string in enumerate(line[11:].split('.')):
                qt_version[v] = int(version_string)
        elif line.startswith('QT_INSTALL_EXAMPLES:'):
            qt_examples_path = line[20:]
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


def run_example(example):
    """Build and run an example"""
    global qt_mkspec
    name = os.path.basename(example)
    result = False
    print('#### Running {} #####'.format(name))
    os.mkdir(name)
    os.chdir(name)
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

        if qt_mkspec.startswith('winrt'):
            execute(['windeployqt', '--no-translations', binary])
            execute(['winrtrunner', '--profile', 'appx', '--device', '0',
                     '--wait', '0', '--start', binary])
        else:
            execute([binary])
        result = True
        print('#### ok {} #####'.format(name))
    except Exception as e:
        print('#### FAIL {} #####'.format(name), e)

    os.chdir('..')
    return result


if __name__ == "__main__":
    if sys.version_info[0] < 3:
        raise Exception('This script requires Python 3')

    query_qmake()
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
    error_count = sum(1 for ex in examples() if not run_example(ex))
    os.chdir(current_dir)
    shutil.rmtree(temp_dir)
    print('#### Done ({} errors) #####'.format(error_count))
