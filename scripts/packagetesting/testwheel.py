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
import tempfile


"""
Qt Package testing script for testing Qt for Python wheels
"""

PYINSTALLER_EXAMPLE = 'widgets/widgets/tetrix.py'

def examples():
    """Compile a list of examples to be tested"""
    return ['opengl/hellogl.py',
            'multimedia/player.py',
            'charts/donutbreakdown.py',
            'widgets/mainwindows/mdi/mdi.py',
            'webenginewidgets/tabbedbrowser/main.py']


def execute(args):
    """Execute a command and print output"""
    log_string = '[{}] {}'.format(os.path.basename(os.getcwd()),
                                  ' '.join(args))
    print(log_string)
    exit_code = subprocess.call(args)
    if exit_code != 0:
        raise RuntimeError('FAIL({}): {}'.format(exit_code, log_string))

def run_process(args):
    """Execute a command and return a tuple of exit code/stdout"""
    popen = subprocess.Popen(args, universal_newlines=1,
                             stdout=subprocess.PIPE)
    lines = popen.stdout.readlines()
    popen.wait()
    return (popen.returncode, lines)


def run_process_output(args):
    """Execute a command and print output"""
    result = run_process(args)
    print(result[1])
    return result[0]


def run_example(root, path):
    print('Launching {}'.format(path))
    exit_code = run_process_output([sys.executable, os.path.join(root, path)])
    print('{} returned {}\n\n'.format(path, exit_code))


def has_pyinstaller():
    """Checks for PyInstaller"""
    process_result = run_process(["pip", "list"])
    for line in process_result[1]:
        if line.startswith("PyInstaller"):
            return True
    return False


def test_pyinstaller(example):
    name = os.path.basename(example)[:-3]
    print('Running PyInstaller test of {}'.format(name))
    current_dir = os.getcwd()
    result = False
    with tempfile.TemporaryDirectory() as tmpdirname:
        try:
            os.chdir(tmpdirname)
            cmd = ['pyinstaller', '--name={}'.format(name),
                   '--log-level=WARN', example]
            execute(cmd)
            if sys.platform != 'darwin':
                binary = os.path.join(tmpdirname, 'dist', name, name)
                if sys.platform == "win32":
                    binary += '.exe'
                execute([binary])
            result = True
        except RuntimeError as e:
            print(str(e))
        finally:
            os.chdir(current_dir)
    return result


if __name__ == "__main__":
    if sys.version_info[0] < 3:  # Note: PyInstaller no longer supports Python 2
        raise Exception('This script requires Python 3')
    root = None
    for p in sys.path:
        if p.endswith('site-packages'):
            root = os.path.join(p, 'PySide2/examples')
            break
    if not root or not os.path.exists(root):
        print('Could not locate the PySide2 module.')
        sys.exit(1)
    print('Detected PySide2 at {}.'.format(root))
    for e in examples():
        run_example(root, e)

    if has_pyinstaller():
        test_pyinstaller(os.path.join(root, PYINSTALLER_EXAMPLE))
    else:
        print('PyInstaller not found, skipping test')
