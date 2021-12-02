#!/usr/bin/env python3
# ###########################################################################
#
# Copyright (C) 2021 The Qt Company Ltd.
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


from argparse import ArgumentParser, RawTextHelpFormatter
import os
import subprocess
import sys
import tempfile


"""
Qt Package testing script for testing Qt for Python wheels
"""

PYINSTALLER_EXAMPLE_6 = 'widgets/tetrix/tetrix.py'
PYINSTALLER_EXAMPLE_2 = 'widgets/widgets/tetrix.py'
OPCUAVIEWER = 'opcua/opcuaviewer/main.py'


VERSION = (0, 0, 0)


def get_pyside_version_from_import():
    """Determine the exact Qt version by importing."""
    qversion_string = None
    try:
        from PySide6.QtCore import qVersion
        qversion_string = qVersion()
    except ImportError:
        try:
            from PySide2.QtCore import qVersion
            qversion_string = qVersion()
        except ImportError:
            print('Unable to determine PySide version; could not import any version',
                  file=sys.stderr)
    if qversion_string:
        major, minor, patch = qVersion().split('.')
        return int(major), int(minor), int(patch)
    return 0, 0, 0


def pyside2_examples():
    """List of examples to be tested (PYSIDE 2)"""
    return ['widgets/mainwindows/mdi/mdi.py',
            'opengl/hellogl.py',
            'multimedia/player.py',
            'charts/donutbreakdown.py',
            'webenginewidgets/tabbedbrowser/main.py']


def commercial_examples(examples_root):
    result = []
    if os.path.exists(os.path.join(examples_root, OPCUAVIEWER)):
        result.append(OPCUAVIEWER)
    return result


def examples(examples_root):
    """Compile a list of examples to be tested"""
    if VERSION[0] < 6:
        return pyside2_examples() + commercial_examples(examples_root)

    result = ['widgets/mainwindows/mdi/mdi.py',
              'declarative/extending/chapter5-listproperties/listproperties.py',
              '3d/simple3d/simple3d.py']
    if VERSION[1] >= 1:
        result.extend(['charts/chartthemes/main.py',
                       'datavisualization/bars3d/bars3d.py'])
    if VERSION[1] >= 2:
        result.extend(['multimedia/player/player.py',
                       'webenginewidgets/tabbedbrowser/main.py'])
    return result + commercial_examples(examples_root)


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
    return popen.returncode, lines


def run_process_output(args):
    """Execute a command and print output"""
    result = run_process(args)
    print(result[1])
    return result[0]


def run_example(root, path):
    print('Launching {}'.format(path))
    exit_code = run_process_output([sys.executable, os.path.join(root, path)])
    print('{} returned {}\n\n'.format(path, exit_code))


def has_module(name):
    """Checks for a module"""
    code, lines = run_process([sys.executable, "-m", "pip", "list"])
    for l in lines:
        tokens = l.split(' ')
        if len(tokens) >= 1 and tokens[0] == name:
            return True
    return False


def test_cxfreeze(example):
    name = os.path.splitext(os.path.basename(example))[0]
    print('Running CxFreeze test of {}'.format(name))
    current_dir = os.getcwd()
    result = False
    with tempfile.TemporaryDirectory() as tmpdirname:
        try:
            os.chdir(tmpdirname)
            cmd = ['cxfreeze', example]
            execute(cmd)
            binary = os.path.join(tmpdirname, 'dist', name)
            if sys.platform == "win32":
                binary += '.exe'
            execute([binary])
            result = True
        except RuntimeError as e:
            print(str(e))
        finally:
            os.chdir(current_dir)
    return result


def test_pyinstaller(example):
    name = os.path.splitext(os.path.basename(example))[0]
    print('Running PyInstaller test of {}'.format(name))
    current_dir = os.getcwd()
    result = False
    with tempfile.TemporaryDirectory() as tmpdirname:
        try:
            os.chdir(tmpdirname)
            level = "CRITICAL" if sys.platform == "darwin" else "WARN"
            cmd = ['pyinstaller', '--name={}'.format(name),
                   '--log-level=' + level, example]
            execute(cmd)
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
    parser = ArgumentParser(description='Qt for Python package tester',
                            formatter_class=RawTextHelpFormatter)
    parser.add_argument('--no-pyinstaller', '-p', action='store_true',
                        help='Skip pyinstaller test')

    options = parser.parse_args()
    do_pyinst = not options.no_pyinstaller

    VERSION = get_pyside_version_from_import()
    if do_pyinst and sys.version_info[0] < 3:  # Note: PyInstaller no longer supports Python 2
        print('PyInstaller requires Python 3, test disabled')
        do_pyinst = False
    root = None
    path_version = 0
    for p in sys.path:
        if os.path.basename(p) == 'site-packages':
            root = os.path.join(p, 'PySide6')
            if os.path.exists(root):
                path_version = 6
            else:
                root = os.path.join(p, 'PySide2')
                path_version = 2
            root_ex = os.path.join(root, 'examples')
            break
    if VERSION[0] == 0:
        VERSION[0] == path_version
    print('Detected Qt version ', VERSION)
    if not root or not os.path.exists(root):
        print('Could not locate any PySide module.')
        sys.exit(1)
    if not os.path.exists(root_ex):
        m = "PySide{} module found without examples. Did you forget to install wheels?".format(VERSION)
        print(m)
        sys.exit(1)
    print('Detected PySide{} at {}.'.format(VERSION, root))
    for e in examples(root_ex):
        run_example(root_ex, e)

    if not do_pyinst:
        sys.exit(0)

    if VERSION >= (6, 1, 0):
        print("Launching Qt Designer. Please check the custom widgets.")
        execute([f'pyside{VERSION[0]}-designer'])

    if VERSION[0] >= 6:
        if not has_module('cx-Freeze'):
            print('cx_Freeze not found, skipping test')
            sys.exit(0)

        if test_cxfreeze(os.path.join(root_ex, PYINSTALLER_EXAMPLE_6)):
            print("\ncx_Freeze test successful")
        else:
            print("\nProblem running cx_Freeze")
            sys.exit(1)
    else:
        if not has_module('PyInstaller'):
            print('PyInstaller not found, skipping test')
            sys.exit(0)

        if test_pyinstaller(os.path.join(root_ex, PYINSTALLER_EXAMPLE_2)):
            print("\nPyInstaller test successful")
        else:
            print("\nProblem running PyInstaller")
            sys.exit(1)
