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
from enum import Enum
from functools import cache
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile


"""
Qt Package testing script for testing Qt for Python wheels
"""

PYINSTALLER_EXAMPLE_6 = "widgets/mainwindows/mdi/mdi.py"  # Sth with "About Qt"
PYINSTALLER_EXAMPLE_6_2 = "widgets/tetrix/tetrix.py"
PYINSTALLER_EXAMPLE_2 = 'widgets/widgets/tetrix.py'
OPCUAVIEWER = 'opcua/opcuaviewer/main.py'
WEBENGINE_EXAMPLE = 'webenginewidgets/tabbedbrowser/main.py'
PROJECT_TOOL = "pyside6-project"
TOOLS = ["deploy", "genpyi", ("lrelease", "-help"), "lupdate", "metaobjectdump",
         "project", "qml", "qmlformat", ("qmlimportscanner", "-importPath", "."), "qmllint",
         "qmlls", "qmltyperegistrar", "qtpy2cpp", "rcc", "uic"]

VERSION = (0, 0, 0)


class InstalledWheels(Enum):
    Essentials = 0
    AddOns = 1
    M2M = 2


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


def list_modules():
    """List the installed Qt modules."""
    if VERSION[0] > 5:
        import PySide6
        installed_modules = PySide6.__dict__["__all__"]
    else:
        import PySide2
        installed_modules = PySide2.__dict__["__all__"]
    installed_modules.sort()
    module_string = ", ".join(installed_modules)
    print(f"\nInstalled_modules ({len(installed_modules)}): {module_string}\n")


@cache
def get_installed_modules():
    """Return installed modules"""
    result = []
    _, lines = run_process([sys.executable, "-m", "pip", "list"])
    for l in lines:
        tokens = l.split(' ')
        if len(tokens) >= 1:
            result.append(tokens[0].lower())
    return result


def has_module(name):
    """Checks for a module"""
    return name.lower() in get_installed_modules()


def get_installed_wheels(examples_root):
    """Determine install type."""
    # 6.5: Examples are no longer in wheels
    if VERSION >= (6, 5, 0):
        if has_module("PySide6-M2M"):
            return InstalledWheels.M2M
        if has_module("PySide6-Addons"):
            return InstalledWheels.AddOns
        return InstalledWheels.Essentials

    # Check M2M
    if (examples_root / OPCUAVIEWER).is_file():
        return InstalledWheels.M2M

    # Wheel split in 6.3.0
    if VERSION < (6, 3, 0):
        return InstalledWheels.AddOns

    # 6.4: Check existence of add-ons
    if (examples_root / WEBENGINE_EXAMPLE).is_file():
        return InstalledWheels.AddOns

    return InstalledWheels.Essentials


def pyside2_examples():
    """List of examples to be tested (PYSIDE 2)"""
    return ['widgets/mainwindows/mdi/mdi.py',
            'opengl/hellogl.py',
            'multimedia/player.py',
            'charts/donutbreakdown.py',
            'webenginewidgets/tabbedbrowser/main.py']


def get_addon_examples():
    datavis_example = ('examples/datavisualization/graphgallery/main.py'
                       if VERSION >= (6, 5, 0) else
                       'datavisualization/bars3d/bars3d.py')
    return ['3d/simple3d/simple3d.py', 'charts/chartthemes/main.py',
            datavis_example, 'multimedia/player/player.py',
            WEBENGINE_EXAMPLE]


def get_m2m_examples():
    return [OPCUAVIEWER]


def examples(examples_root):
    """Compile a list of examples to be tested"""

    wheels = get_installed_wheels(examples_root)
    print(f"\nDetected: {wheels}\n")

    if VERSION[0] < 6:
        result = pyside2_examples()
        if wheels == InstalledWheels.M2M:
            result.extend(get_m2m_examples())
        return result

    result = ['widgets/mainwindows/mdi/mdi.py',
              'qml/tutorials/extending/chapter5-listproperties/listproperties.py']
    if wheels != InstalledWheels.Essentials:
        result.extend(get_addon_examples())
    if wheels == InstalledWheels.M2M:
        result.extend(get_m2m_examples())
    return result


def execute(args):
    """Execute a command and print output"""
    dir = os.path.basename(os.getcwd())
    arg_string = ' '.join(args)
    log_string = f'[{dir}] {arg_string}'
    print(log_string)
    exit_code = subprocess.call(args)
    if exit_code != 0:
        raise RuntimeError(f'FAIL({exit_code}): {log_string}')


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
    print(f'Launching {path}')
    exit_code = run_process_output([sys.executable, os.fspath(root / path)])
    print(f'{path} returned {exit_code}\n\n')
    return exit_code == 0


def test_deploy(example):
    """Test pyside6-deploy."""
    base_name = example.name
    name = example.stem
    print(f"Running deploy test of {name}")
    current_dir = Path.cwd()
    result = False
    with tempfile.TemporaryDirectory() as tmpdirname:
        try:
            os.chdir(tmpdirname)
            for py_file in example.parent.glob("*.py"):
                shutil.copy(py_file, tmpdirname)
            cmd = ["pyside6-deploy", "-f", base_name]
            execute(cmd)
            suffix = "exe" if sys.platform == "win32" else "bin"
            binary = f"{tmpdirname}/{name}.{suffix}"
            execute([binary])
            result = True
        except RuntimeError as e:
            print(str(e))
        finally:
            os.chdir(os.fspath(current_dir))
    return result


def test_cxfreeze(example):
    assert(example.is_file())
    print(f'Running CxFreeze test of {example.stem}')
    current_dir = os.getcwd()
    result = False
    with tempfile.TemporaryDirectory() as tmpdirname:
        try:
            os.chdir(tmpdirname)
            cmd = ['cxfreeze', os.fspath(example)]
            execute(cmd)
            binary = os.path.join(tmpdirname, 'dist', example.stem)
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
    assert(example.is_file())
    print(f'Running PyInstaller test of {example.stem}')
    current_dir = os.getcwd()
    result = False
    with tempfile.TemporaryDirectory() as tmpdirname:
        try:
            os.chdir(tmpdirname)
            level = "CRITICAL" if sys.platform == "darwin" else "WARN"
            cmd = ['pyinstaller', f'--name={example.stem}'
                   '--log-level=' + level, os.fspath(example)]
            execute(cmd)
            binary = os.path.join(tmpdirname, 'dist', example.stem, example.stem)
            if sys.platform == "win32":
                binary += '.exe'
            execute([binary])
            result = True
        except RuntimeError as e:
            print(str(e))
        finally:
            os.chdir(current_dir)
    return result


def test_project_generation():
    print("Testing project generation and deployment")
    result = False
    current_dir = os.getcwd()
    project_name = "test"
    with tempfile.TemporaryDirectory() as tmpdirname:
        try:
            os.chdir(tmpdirname)
            execute([PROJECT_TOOL, "new-ui", project_name])
            execute([PROJECT_TOOL, "build", project_name])
            result = test_deploy(Path(tmpdirname) / project_name / "main.py")
        except RuntimeError as e:
            print(str(e))
        finally:
            os.chdir(current_dir)
    return result


def test_tools():
    result = True
    print("\nTesting command line tools...")
    for tool in TOOLS:
        if isinstance(tool, tuple):
            tool_name, *arguments = tool
            binary = f"pyside6-{tool_name}"
        else:
            binary = f"pyside6-{tool}"
            arguments = ["--help"]
        exit_code = 0
        error = ""
        try:
            cmd = [binary]
            cmd.extend(arguments)
            exit_code, error = run_process(cmd)
        except Exception as e:
            error = str(e)
            exit_code = 1
        if exit_code == 0:
            print(f"  {binary}: succeeded.")
        else:
            result = False
            print(f"  {binary}: FAILED: {error}")
    return result


def test_deployment(examples_root):
    if VERSION >= (6, 4, 0):
        if not has_module("Nuitka"):
            print("Nuitka not found, skipping test")
            return True

        if VERSION >= (6, 5, 0):
            result = test_project_generation()
        else:
            result = test_deploy(examples_root / PYINSTALLER_EXAMPLE_6)
        if result:
            print("\ndeploy test successful")
        else:
            print("\nProblem running deploy")
        return result

    if VERSION[0] >= 6:
        if not has_module('cx-Freeze'):
            print('cx_Freeze not found, skipping test')
            return True

        result = test_cxfreeze(examples_root / PYINSTALLER_EXAMPLE_6_2)
        if result:
            print("\ncx_Freeze test successful")
        else:
            print("\nProblem running cx_Freeze")
        return result

    if not has_module('PyInstaller'):
        print('PyInstaller not found, skipping test')
        return True

    result = test_pyinstaller(examples_root / PYINSTALLER_EXAMPLE_2)
    if result:
        print("\nPyInstaller test successful")
    else:
        print("\nProblem running PyInstaller")
    return result


if __name__ == "__main__":
    parser = ArgumentParser(description='Qt for Python package tester',
                            formatter_class=RawTextHelpFormatter)
    parser.add_argument('--no-pyinstaller', '-p', action='store_true',
                        help='Skip pyinstaller test')
    parser.add_argument("--examples", "-e", action="store",
                        help="Examples directory")

    options = parser.parse_args()
    do_pyinst = not options.no_pyinstaller
    root_ex = Path(options.examples) if options.examples else None

    VERSION = get_pyside_version_from_import()
    if do_pyinst and sys.version_info[0] < 3:  # Note: PyInstaller no longer supports Python 2
        print('PyInstaller requires Python 3, test disabled')
        do_pyinst = False
    root = None
    path_version = 0
    for p in map(Path, sys.path):
        if p.name == 'site-packages':
            root = p / 'PySide6'
            if root.is_dir():
                path_version = 6
            else:
                root = p / 'PySide2'
                path_version = 2
            if not root_ex:
                root_ex = root / 'examples'
            break
    if VERSION[0] == 0:
        VERSION[0] == path_version
    print('Detected Qt version ', VERSION)
    if not root or not root.is_dir():
        print('Could not locate any PySide module.')
        sys.exit(1)
    if not root_ex.is_dir():
        m = f"PySide{VERSION} module found without examples. "
        m += ("Specify --examples <dir>." if VERSION >= (6, 5, 0)
              else "Did you forget to install wheels?")
        print(m)
        sys.exit(1)
    print(f'Detected PySide{VERSION} at {root}.')

    list_modules()

    exit_code = 0
    if VERSION >= (6, 4, 0):
        if not test_tools():
            exit_code += 1

    for e in examples(root_ex):
        if not run_example(root_ex, e):
            exit_code += 1

    if VERSION >= (6, 1, 0):
        print("Launching Qt Designer. Please check the custom widgets.")
        execute([f'pyside{VERSION[0]}-designer'])

    if do_pyinst and not test_deployment(root_ex):
        exit_code += 1

    print("Success" if exit_code == 0 else "Failure")
    sys.exit(exit_code)
