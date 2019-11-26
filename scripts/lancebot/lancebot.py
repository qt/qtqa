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

import subprocess
from subprocess import PIPE
import platform
import os
import shutil
import stat
import re
import atexit
from pathlib import Path
from packaging import version
from xml.dom import minidom
import json

isWindowsOS = (platform.system() == 'Windows')
exeExt = '.exe' if isWindowsOS else ''

# Set up our global variables

thisScriptDir = os.path.dirname(os.path.realpath(__file__))
os.environ["QT_LANCELOT_SERVER"] = "lancelot.intra.qt.io"
exitStatus = 0
gitUser = os.environ.get("GIT_USER") if os.environ.get(
    "GIT_USER") else "Your Name"
gitEmail = os.environ.get("GIT_EMAIL") if os.environ.get(
    "GIT_EMAIL") else "you@example.com"
testMode = "patchtest" if os.environ.get('GERRIT_EVENT_TYPE') else "headtest"
if testMode == "patchtest":
    eventType = os.environ.get('GERRIT_EVENT_TYPE')
    gerritProject = os.environ.get('GERRIT_PROJECT')
    gerritOwner = os.environ.get('GERRIT_CHANGE_OWNER_NAME')
    gerritUploaderEmail = os.environ.get('GERRIT_PATCHSET_UPLOADER_EMAIL')
    subject = os.environ.get('GERRIT_CHANGE_SUBJECT')
    refSpec = [os.environ.get('GERRIT_REFSPEC')] if os.environ.get(
        'GERRIT_REFSPEC') else ""  # Needs to be in list format
    repo = gerritProject if gerritProject.find(
        '/') == -1 else gerritProject[gerritProject.find('/') + 1: len(gerritProject)]

    try:
        temp = refSpec[0].split(" ")
        if temp.find(" ") > -1:
            refSpec = temp
            temp = ""
    except Exception:
        pass

# Only use the gerrit event type if this is a patchtest
branch = os.environ.get('GERRIT_BRANCH') if os.environ.get('GERRIT_BRANCH') and os.environ.get(
    'GERRIT_EVENT_TYPE') else os.environ.get('BRANCH')
workspace = os.environ.get("WORKSPACE")
baseDir = f'{os.environ.get("WORKSPACE")}/{branch}'
rebuildAll = os.environ.get(
    'LB_REBUILD') if os.environ.get('LB_REBUILD') else False
refBaseDir = baseDir + "/ref"
commentfile = f"{workspace}/gerrit-comment.txt"
outputfile = f"{workspace}/output.txt"
buildCores = os.environ.get(
    "BUILD_CORES") if os.environ.get("BUILD_CORES") else str(os.cpu_count())
VSDevEnv = os.environ.get("VS_DEV_ENV")
flexBisonDir = os.environ.get("FLEX_BISON_DIR") if os.environ.get(
    "FLEX_BISON_DIR") else os.path.normpath(f"{workspace}/flex_bison")  # Windows only
JOMPath = os.environ.get("JOM_PATH") if os.environ.get(
    "JOM_PATH") else f"{workspace}/JOM/jom.exe"  # Windows only
defaultLancelotConfigureOpts = [os.environ.get("LANCELOT_CONFIGURE_OPTIONS")] if os.environ.get(
    "LANCELOT_CONFIGURE_OPTIONS") else []

try:
    temp = defaultLancelotConfigureOpts[0].split(" ")
    if temp.find(" ") > -1:
        defaultLancelotConfigureOpts = temp
        temp = ""
except Exception:
    pass


compiler = "make"  # Windows will set this to JOM
defaultPATH = os.environ.get("PATH")
# Used for title headers to make logs more human readable.
hr = "#######################"
hhr = "###########"


def setWindowsEnv():
    global compiler

    print("Configuring Windows environment variables...")
    os.environ["PATH"] = defaultPATH
    # runs the vsDevCmd file from the visual studio installation
    vars = subprocess.check_output([VSDevEnv, '&&', 'set'])

    # splits the output of the batch file and saves PATH variables from
    # the batch to the local os.environ
    for var in vars.splitlines():
        var = var.decode('cp1252')
        k, _, v = map(str.strip, var.strip().partition('='))
        if k.startswith('?'):
            continue
        os.environ[k] = v

    if os.path.lexists(flexBisonDir):
        os.environ["PATH"] += (";" + os.path.normpath(flexBisonDir))
    if os.path.lexists(JOMPath):
        os.environ["PATH"] += (";" + os.path.dirname(os.path.normpath(JOMPath)))

    compiler = shutil.which("jom.exe")
    if compiler:
        print(f"Found JOM at {compiler}")
    else:
        print(f"{hr} ERROR: JOM NOT FOUND ON SYSTEM. ABORTING... {hr}")
        print("See README.md for more information on how to specify a JOM location.")
        exit(1)

    flex = shutil.which("flex.exe")
    bison = shutil.which("bison.exe")
    if not flex or not bison:
        print(f"{hr} ERROR: FLEX OR BISON NOT FOUND ON SYSTEM. ABORTING... {hr}")
        print("See README.md for more information on how to acquire flex bison.")
        exit(1)


# catch for deleting files to try a less clean way of forcing deletion.
def on_rm_error(func, path, exc_info):
    # path contains the path of the file that couldn't be removed
    # let's just assume that it's read-only and unlink it.
    try:
        os.chmod(path, stat.S_IWRITE)
        os.unlink(path)
    except Exception as e:
        print(
            "There was an error removing a file from disk. Exception: {0}".format(e))


def resetOutput():
    print(f"{hhr} Resetting output and comment files...")
    with open(commentfile, "w") as comment_file:
        comment_file.write("TestRunAborted")

    if os.path.exists(outputfile):
        try:
            os.remove(outputfile)
        except OSError as e:
            print(e)


def version_gt(branch: str, reference: str):
    return version.parse(branch) > version.parse(reference)


def setConfigureOptions():
    extraopts = []
    lancelotConfigureOpts = defaultLancelotConfigureOpts

    if version_gt(branch, "5.8"):
        extraopts.extend(["-no-feature-sql", "-no-feature-vnc"])
    if version_gt(branch, "5.9"):
        extraopts.extend(["-no-feature-xcb-native-painting"])

    lancelotConfigureOpts.extend([
        "-prefix", f"{os.path.normpath(os.path.join(os.getcwd(), '..', 'Install'))}",
        "-release",
        "-opensource",
        "-confirm-license",
        "-nomake", "examples",
        "-nomake", "tests",
        "-no-widgets",
        "-no-feature-concurrent",
        "-no-openssl",
    ])

    if isWindowsOS:
        print("Running on windows. Forcing '-opengl desktop' configure option")
        lancelotConfigureOpts.extend([
            "-opengl", "desktop"
        ])
    else:
        print("Running on Linux or macOS. Forcing '-no-eglfs' and '-no-linuxfb' configure options")
        lancelotConfigureOpts.extend([
            "-no-eglfs",
            "-no-linuxfb"
        ])

    return lancelotConfigureOpts


def checkResult():
    if (os.access(outputfile, os.R_OK)):
        with open(outputfile, 'r') as output_file:
            content = output_file.readlines()
            lastLine = ""
            for line in content:
                if 'http://' in line and 'fuzzy match' not in line.lower():
                    lastLine = line.strip()[line.strip().rfind(
                        "description: \"") + 1:-1]
            with open(commentfile, "w") as comment_file:
                comment_file.write(lastLine if lastLine else "Okay")
            if lastLine:
                print(f"Check Result found mismatches.")
                return 1  # Some mismatches were found
    return 0


def exitTrap():
    if (checkResult()):
        print("Mismatch detected: ")
        with open(commentfile, 'r') as content:
            for line in content.readlines():
                print(line)

    exit(exitStatus)


def applyPatches(module, cherryPickType):
    args = ""
    print("Applying patches...")
    ### Temporary Patches ###

    if (cherryPickType == "no-commit"):
        args = "-n"

    skipArgs = (not args)

    if (module == "qtbase"):
        try:  # merge-base gives no output if not ancestor.
            subprocess.run(["git", "merge-base", "--is-ancestor", "c23e3f4822", "HEAD"],
                           stdout=PIPE, universal_newlines=True,
                           shell=isWindowsOS).stdout.splitlines()[0]
        except IndexError:
            # 'Add commandline option to lancelot tests for forcing baseline update'
            print(
                'PATCH: Add commandline option to lancelot tests for forcing baseline update')
            subprocess.run(["git", "cherry-pick", "c23e3f4822"] if skipArgs else ["git",
                                                                                  "cherry-pick",
                                                                                  args,
                                                                                  "c23e3f4822"],
                           universal_newlines=True, shell=isWindowsOS)

        # 'WIP: exclude a blending test from qpainter lancelot on macOS core gl'
        print('PATCH: Exclude a blending test from qpainter lancelot on macOS core gl')
        subprocess.run(["git", "fetch", "https://codereview.qt-project.org/qt/qtbase",
                        "refs/changes/58/238358/1"], universal_newlines=True, shell=isWindowsOS)

        # Fails for old Qt where coregl test did not exist, revert if so
        print("PATCH: Fails for old Qt where coregl test did not exist, revert if so")
        if(subprocess.run(["git", "cherry-pick", "FETCH_HEAD"] if skipArgs else ["git",
                                                                                 "cherry-pick",
                                                                                 args,
                                                                                 "FETCH_HEAD"],
                          stdout=PIPE, universal_newlines=True, shell=isWindowsOS).stdout):
            subprocess.run(["git", "checkout", "HEAD", "tests/auto/other/lancelot/tst_lancelot.cpp"],
                           universal_newlines=True, shell=isWindowsOS)

    print("Done Applying patches...\n")


def clone(directory, module):
    print(f"Cloning module [{module}] into {directory}")
    if (not os.path.isdir(f"{directory}/{module}")):
        # Set git user and email if it's not set on this machine.
        try:
            email = subprocess.run(["git", "config", "--global", "--get", "user.email"],
                                   stdout=PIPE, universal_newlines=True,
                                   shell=isWindowsOS).stdout.splitlines()[0]
            if (email == "you@example.com" or (gitEmail != email and gitEmail != "you@example.com")):
                subprocess.run(["git", "config", "--global", "user.email",
                                gitEmail], universal_newlines=True, shell=isWindowsOS)
        except IndexError:
            subprocess.run(["git", "config", "--global", "user.email",
                            gitEmail], universal_newlines=True, shell=isWindowsOS)
        try:
            name = subprocess.run(["git", "config", "--global", "--get", "user.name"],
                                  stdout=PIPE, universal_newlines=True,
                                  shell=isWindowsOS).stdout.splitlines()[0]
            if (name == "Your Name" or (gitUser != name and gitUser != "Your Name")):
                subprocess.run(["git", "config", "--global", "user.name",
                                gitUser], universal_newlines=True, shell=isWindowsOS)
        except IndexError:
            subprocess.run(["git", "config", "--global", "user.name",
                            gitUser], universal_newlines=True, shell=isWindowsOS)

        subprocess.run(["git", "clone", f"git://code.qt.io/qt/{module}.git", "--branch",
                        branch, f"{directory}/{module}"], universal_newlines=True,
                       shell=isWindowsOS)
    else:
        print("Path exists. No new clone required.")


def build(directory, module, sha, testType):
    print(f"\n{hhr} Building {module} {testType} {hhr}\n")
    print(f"Changing directory to {directory}/{module}")
    os.chdir(f"{directory}/{module}")
    print("Cleaning repo...")
    subprocess.run(["git", "clean", "-dqfx"],
                   universal_newlines=True, shell=isWindowsOS)
    print("Fetching changes...")
    subprocess.run(["git", "fetch"], universal_newlines=True,
                   shell=isWindowsOS)
    print(f"Resetting repo to SHA: {sha}...")
    subprocess.run(["git", "reset", "--hard", sha],
                   universal_newlines=True, shell=isWindowsOS)
    if (testMode == "patchtest" and testType == "test" and repo == module):
        print(f"Entering Test Mode: [patchtest: {module}/test]")
        applyPatches(module, "commit")
        print("Fetching refspecs from gerrit...")
        for ref in refSpec:
            print(f"Fetching {module}/{ref}")
            subprocess.run(
                ["git", "fetch",
                    f"https://codereview.qt-project.org/{gerritProject}", ref],
                universal_newlines=True, shell=isWindowsOS)
            confirmCherryPickSHA = subprocess.run(['git', 'rev-parse', 'FETCH_HEAD'],
                                                  stdout=PIPE, stderr=PIPE, shell=False,
                                                  universal_newlines=True).stdout
            print(f"Cherry picking {confirmCherryPickSHA}")
            subprocess.run(["git", "cherry-pick", "FETCH_HEAD"],
                           universal_newlines=True, shell=isWindowsOS)
    else:
        print(f"Entering Test Mode: [{testType}: {module}]")
        applyPatches(module, "no-commit")

    if (module == "qtbase"):
        lancelotConfigureOpts = setConfigureOptions()
        if isWindowsOS:
            configurecmd = ["configure.bat"]
        else:
            configurecmd = ["./configure"]

        if lancelotConfigureOpts:
            configurecmd.extend(lancelotConfigureOpts)

        print("Now configuring qtbase with", configurecmd)

        with open("configure.out", "w") as configure_log:
            proc = subprocess.run(configurecmd, stdout=configure_log,
                                  stderr=configure_log, universal_newlines=True, shell=isWindowsOS)
            if proc.returncode:
                print(f"{hr} ERROR Configuring {module}. Failing build {hr}")
                if os.path.exists("config.summary"):
                    print(f"{hhr} Dumping Configure Summary {hhr}")
                    with open("config.summary") as configSummary:
                        print(configSummary.read())
                    print(f"{hhr} End of Configure Summary {hhr}")
                else:
                    print(f"{hhr} Dumping Configure log tail {hhr}")
                    with open("configure.out") as configure_log_readback:
                        print("\n".join(configure_log_readback.readlines()[-20:]))
                    print(f"{hhr} End of Configure log tail {hhr}")
                exit(proc.returncode)
    else:
        print("Running qmake...")
        subprocess.run(
            [f"{directory}/Install/bin/qmake{exeExt}"], universal_newlines=True)

    with open("build.out", "a") as build_log:
        print(f"Running Make for {module}/{testType}...")
        proc = subprocess.run([compiler, "-j", buildCores], stdout=build_log,
                              stderr=build_log, universal_newlines=True, shell=isWindowsOS)
        if proc.returncode:
            print(f"{hr} ERROR Building {module}. Failing build {hr}")
            print(f"{hhr} Dumping Build log tail {hhr}")
            with open("build.out") as build_log_readback:
                print("\n".join(build_log_readback.readlines()[-20:]))
            print(f"{hhr} End of Build log tail {hhr}")
            exit(proc.returncode)

        print(f"Running Make Install for {module}/{testType}...")
        proc = subprocess.run([compiler, "install", "-j", buildCores],
                              stdout=build_log, stderr=build_log, universal_newlines=True,
                              shell=isWindowsOS)
        if proc.returncode:
            print(f"{hr} ERROR Installing {module}. Failing build {hr}")
            exit(proc.returncode)

    if (isWindowsOS):
        print("Cloning WinDeployQt...")
        clone(directory, "qttools")

        print(f"Changing directory to {directory}/qttools/src/windeployqt")
        os.chdir(f"{directory}/qttools/src/windeployqt")

        print("\nRunning QMake for WindeployQt...")
        subprocess.run([f"{directory}/Install/bin/qmake{exeExt}"],
                       universal_newlines=True, shell=isWindowsOS)
        print("Running Make for WindeployQt...")
        proc = subprocess.run([compiler, "-j", buildCores],
                              universal_newlines=True, shell=isWindowsOS)
        if proc.returncode:
            print(f"{hr} ERROR Building windeployqt. Failing build {hr}")
            exit(proc.returncode)
        print("\nRunning Make Install for WindeployQt...")
        proc = subprocess.run([compiler, "install", "-j", buildCores],
                              universal_newlines=True, shell=isWindowsOS)
        if proc.returncode:
            print(f"{hr} ERROR Installing windeployqt. Failing build {hr}")
            exit(proc.returncode)
        print("Done building WinDeployQt. Success!")


def getSha(directory, module, shaType):
    print(f"Retrieving SHA for {module}/{shaType}")
    shafile = ""
    sha = "none"
    if (shaType == "head"):
        subprocess.run(["git", "fetch"], cwd=f'{directory}/{module}',
                       stdout=PIPE, stderr=PIPE, universal_newlines=True)
        sha = subprocess.run(["git", "rev-parse", f"origin/{branch}"], cwd=f"{directory}/{module}",
                             stdout=PIPE, stderr=PIPE,
                             universal_newlines=True).stdout.splitlines()[0]
        if (module != "qtbase"):
            sha = f"{sha}_{getSha(directory, 'qtbase', 'build')}"
    else:
        shafile = f"{directory}/{module}_{shaType}.sha"
        print(f"Pulling SHA from file: '{shafile}'")
        if (os.path.isfile(shafile)):
            with open(shafile) as sha_file:
                try:
                    sha = sha_file.readlines()[0]
                except IndexError:
                    print(
                        f"Unexpected error: The shafile at {shafile} seems to be empty.")
                    return
        else:
            print(f"SHA file {directory}/{module}_{shaType}.sha not found.")

    print(f"SHA for {module}/{shaType}: {sha}")
    return sha


def storeSha(directory, module, shaType, sha):
    shaFile = f"{directory}/{module}_{shaType}.sha"
    with open(shaFile, "w") as sha_file:
        sha_file.writelines(sha)

    with open(shaFile, "r") as sha_file:
        print(
            f"Wrote data for {module}/{shaType} '{sha_file.readlines()}' to {shaFile}")


def clearShas(directory):
    # print(f"Clearing shas: {', '.join(Path(directory).glob('*.sha'))}")
    for f in Path(directory).glob("*.sha"):
        try:
            f.unlink()
        except Exception as e:
            print(e)


def updateRefBuild(module):
    print(f"{hhr} Starting update to reference build...")
    clone(refBaseDir, module)
    headSHA = getSha(refBaseDir, module, "head")
    buildSHA = getSha(refBaseDir, module, "build")

    if (buildSHA == headSHA):
        print("Build SHA matches HEAD SHA. No need to update the ref build now.")
        return

    print(
        f"Build and HEAD shas do not match. Rebuilding {module}\n\
Build SHA: {buildSHA}\nHEAD SHA: {headSHA}")

    if (module == "qtbase"):
        # Rebuilding qtbase invalidates the other builds and baselines
        print("Clearing shas since we're updating qtbase...")
        clearShas(refBaseDir)

    build(refBaseDir, module, headSHA[0: headSHA.find(
        '_') if headSHA.find('_') > 0 else len(headSHA)], "ref")
    storeSha(refBaseDir, module, "build", headSHA)


def parseResults(file: str) -> ():
    testFunctionsXML = []
    testNames = []
    testFailures = {}
    testCount = 0

    try:
        xmldoc = minidom.parse(file)
        testFunctionsXML = xmldoc.getElementsByTagName('TestFunction')
        for item in testFunctionsXML:
            testFailures[item.attributes['name'].value] = []
            testNames.append(item.attributes['name'].value)
            incidentsXML = item.getElementsByTagName('Incident')
            for incident in incidentsXML:
                testCount += 1
                if incident.attributes['type'].value == 'fail':
                    testFailures[item.attributes['name'].value].append(
                        {
                            "file": incident.childNodes[1].firstChild.nodeValue,
                            "description": incident.childNodes[3].firstChild.nodeValue
                        })
    except FileNotFoundError:
        print(f"ERROR: No results file found. It's most likely that the test executable failed to complete.\n    file tried: {file}")
        return (False, False, "File Not Found")
    except Exception as e:
        print(e)

    for name in testNames:
        if len(testFailures[name]) == 0:
            del testFailures[name]

    return (testFailures, testCount, False)


def runTest(testBaseDir, module, testType):
    args = []
    out = ""
    testDir = ""
    testApp = ""
    testArgs = []
    baseSHA = ""
    baseCommit = ""

    if (module == "qtbase"):
        testDir = "tests/auto/other/lancelot"
        testApp = "tst_lancelot"
        testArgs = []
        quickbackends = "default"

    elif (module == "qtdeclarative"):
        testDir = "tests/manual/scenegraph_lancelot"
        testApp = "tst_scenegraph"
        testArgs.append("testRendering")

    if version_gt(branch, "5.9"):
        quickbackends = ["default"]
    else:
        quickbackends = ["default", "software"]

    print(f"\n{hr} Running {testApp} {testType} {hr}\n")
    print(f"Changing directory to {testBaseDir}/{module}/{testDir}")
    os.chdir(f"{testBaseDir}/{module}/{testDir}")
    print("Running qmake...")
    subprocess.run(
        [f"{testBaseDir}/Install/bin/qmake{exeExt}"], universal_newlines=True)

    with open("build.out", "w") as build_log:
        print(f"Running Make for {testApp}")
        subprocess.run([compiler, "-j", f"{buildCores}"], stdout=build_log,
                       universal_newlines=True, shell=isWindowsOS)

        if isWindowsOS:
            if testApp == "tst_lancelot":
                # Deploy DLL files to the test with windeployqt
                subprocess.run([f"{testBaseDir}/Install/bin/windeployqt.exe", f"{testApp}.exe"],
                               cwd=f"{testBaseDir}/{module}/{testDir}/release",
                               universal_newlines=True, shell=isWindowsOS)

            elif testApp == "tst_scenegraph":
                subprocess.run([f"{testBaseDir}/Install/bin/windeployqt.exe", f"{testApp}.exe"],
                               cwd=f"{testBaseDir}/{module}/{testDir}",
                               universal_newlines=True, shell=isWindowsOS)
                subprocess.run([f"{testBaseDir}/Install/bin/windeployqt.exe", "qmlscenegrabber.exe"],
                               cwd=f"{testBaseDir}/{module}/{testDir}",
                               universal_newlines=True, shell=isWindowsOS)

    try:
        os.remove("hostinfo.txt")
    except Exception:
        pass  # Error is expected if file doesn't exist yet.

    # Hostinfo.txt carries info about this testrun and the client running the
    # tests to baselinetest.cpp for use in connecting to the lancelot host.
    print(f"Writing hostinfo to {os.getcwd()}/hostinfo.txt")
    with open("hostinfo.txt", "w+") as host_info:
        if (module == "qtbase"):
            baseSHA = getSha(refBaseDir, "qtbase", "build")
            baseCommit = subprocess.run(["git", "show", "-s", "--pretty=\"%H [%an] [%ad] %s\"",
                                         baseSHA], stdout=PIPE, stderr=PIPE,
                                        universal_newlines=True).stdout
            host_info.writelines([f"QtBaseCommit: {baseCommit}\n"])
        if (os.environ.get("LANCELOT_PROJECT")):
            host_info.writelines(
                [f"Project: {os.environ.get('LANCELOT_PROJECT')}\n"])
        host_info.writelines([
            f"GitBranch: {branch}\n",
            f"BUILD_TAG: {os.environ.get('BUILD_TAG')}\n",
            f"BUILD_URL: {os.environ.get('BUILD_URL')}\n"
        ])
        if (testMode == "patchtest"):
            host_info.writelines([
                f"GERRIT_PROJECT: {gerritProject}\n",
                f"GERRIT_CHANGE_URL: {os.environ.get('GERRIT_CHANGE_URL')}\n",
                f"GERRIT_CHANGE_SUBJECT: {subject}\n",
                f"GERRIT_PATCHSET_NUMBER: {os.environ.get('GERRIT_PATCHSET_NUMBER')}\n",
                f"GERRIT_REFSPEC: {refSpec}\n"
            ])

    out = outputfile

    if (testMode == "patchtest"):
        if (testType == "ref"):
            print(f"{hhr} Setting test app output to devnull and uploading \
new baselines to Lancelot.")
            args.append("-setbaselines")
            out = os.devnull
        else:
            print(f"{hhr} Active Test run. Not setting any baselines.")
            args.append("-nosetbaselines")

    if (os.environ.get("LANCELOT_FAKE_MISMATCH")):
        print(f"{hhr} Forced fake mismatch run. Tests will always mismatch!")
        args.append("-simfail")

    for backend in quickbackends:
        with open("hostinfo.txt", "a") as host_info:
            host_info.writelines([f"QT_QUICK_BACKEND: {backend}\n"])
        if (backend == "default"):
            try:
                del os.environ["QT_QUICK_BACKENDS"]
            except KeyError:
                pass
        else:
            os.environ["QT_QUICK_BACKENDS"] = backend

        commandString = [f"{testBaseDir}/{module}/{testDir}/\
{'release' if isWindowsOS and testApp == 'tst_lancelot' else ''}/{testApp}{exeExt}",
                         "-o", "results.xml,xml"]
        if args:
            commandString.extend(args)
        if testArgs:
            commandString.extend(testArgs)

        print(
            f"About to run test {commandString} with QT_QUICK_BACKEND: {backend}")
        with open("hostinfo.txt", 'r') as host_info:
            print(
                f"\nHost information to be sent to Lancelot server:\n{hr}\n\
{''.join(host_info.readlines())}{hr}\n")

        with open(out, "w", newline='\n') as output_file:
            subprocess.run(
                commandString, universal_newlines=True, shell=False)
            print("Parsing results.xml...")
            resultsData, testCount, error = parseResults(
                f"{testBaseDir}/{module}/{testDir}/results.xml")
            if error:
                break
            elif not testCount:
                print("ERROR: Test executable ran, but no test cases were executed!")
                break

            formattedResults = json.dumps(resultsData, indent=2)
            output_file.write(
                formattedResults if resultsData else "ALL PASS")
            print(f"{testCount} total test cases run.")
            print(f"Results:\n{formattedResults if resultsData else 'ALL PASS'}")
            print(f"Dumping results to {out}\n")

        if (testType != "ref" and checkResult()):  # ignore mismatches if we're doing ref
            print("Found mismatches on a real test run. Aborting...")
            break


def updateBaselines(module):
    print(f"\n{hhr} Updating baselines for {module}")
    buildSHA = ""
    blSHA = ""
    updateRefBuild(module)
    buildSHA = getSha(refBaseDir, module, "build")
    blSHA = getSha(refBaseDir, module, "baselines")

    print(f"Build SHA:{buildSHA}\nBaseline SHA: {blSHA}")

    if (blSHA == buildSHA):
        print("baseline and Build SHAs match. No need to update baselines.")
        return

    print(
        f"Baseline and Build shas do not match. Updating baselines with new build.")
    runTest(refBaseDir, module, "ref")
    storeSha(refBaseDir, module, "baselines", buildSHA)


def updateQtBase(directory, repo):
    blSHA = ""
    blBaseSHA = ""
    buildSHA = ""

    blSHA = getSha(refBaseDir, "qtbase", "baselines")
    blBaseSHA = blSHA[0: blSHA.find(
        '_') if blSHA.find('_') > 0 else len(blSHA)]
    buildSHA = getSha(directory, "qtbase", "build")

    if (blBaseSHA == buildSHA):
        return  # No need to build since there's no change.

    clone(directory, "qtbase")
    build(directory, "qtbase", blBaseSHA, "ref")
    storeSha(directory, "qtbase", "build", blBaseSHA)


def testRepo(workdir, module):
    print(f"Starting test process for {module}...")
    sha = ""

    clone(workdir, module)
    sha = getSha(refBaseDir, module, "baselines")
    build(workdir, module, sha[0: sha.find('_')
                               if sha.find('_') > 0 else len(sha)], "test")
    runTest(workdir, module, "test")
    # Don't bother continuing if we already have identified trouble
    if (checkResult()):
        exit(exitStatus)


def doPatchTest():
    print(f"{hr} Performing Patch test...")
    workdir = ""

    updateBaselines("qtbase")
    updateBaselines("qtdeclarative")

    print(f"{hhr} Finished updating baselines...")

    # Commit modifies qtbase. Test both qtbase and qtdeclarative rendering.
    if (repo == "qtbase"):
        print(f"{hhr} Starting full test")
        workdir = baseDir + "/fulltest"
        testRepo(workdir, "qtbase")
        resetOutput()
        testRepo(workdir, "qtdeclarative")
    else:
        # Only test modified repo
        print(f"{hhr} Starting qtdeclarative repo test...")
        workdir = baseDir + "/repotest"
        updateQtBase(workdir, repo)
        testRepo(workdir, repo)

    print(f"{hhr} Finished Patch Testing...")


def doHeadTest():
    print(f"{hr} Performing HEAD test...")
    global exitStatus
    updateBaselines("qtbase")
    exitStatus += checkResult()

    resetOutput()
    updateBaselines("qtdeclarative")
    exitStatus += checkResult()

    if (not exitStatus):  # Write Okay as comment if exitStatus is still 0.
        print(f"{hr} PASS: Head test completed with no errors or mismatches {hr}")
        with open(commentfile, "w") as comment_file:
            comment_file.write("Okay")


if __name__ == "__main__":

    resetOutput()  # Reset our output and comment files, just in case.
    atexit.register(exitTrap)  # Set the exit trap

    if isWindowsOS:
        setWindowsEnv()

    if (testMode == "patchtest"):
        print(f"{hhr}\n{gerritOwner}: {subject}\n{hhr}")
        if (eventType != "manualtrigger"):
            if (subject):
                # exit if the gerrit change is a WIP, DOC, or merge request.
                r = re.compile('(^doc\\b|^wip\\b|^merge\\b)')
                if r.search(subject.lower()):
                    print("WIP/Doc/Merge commit. Ignoring.")
                    exit(0)
            if gerritUploaderEmail == "qt_ci_bot@qt-project.org":
                print(f"{hhr} CI-Generated patchset, ignoring.")
                exit(0)

        if (repo != "qtbase" and repo != "qtdeclarative"):
            print(f"Error. Unknown Repo: {repo}")
            exit(0)

        if (not refSpec):
            print("In Patch mode, but no refspec given. Exiting.")
            exit(0)

    if (not branch):
        print("Error: No branch specifified. This is required. Exiting.")
        exit(0)

    if(rebuildAll):
        # Test to make sure the targets exist so we don't delete something unintentional.
        if (branch and os.path.isdir(workspace) and os.path.isdir(baseDir)):
            shutil.rmtree(baseDir, onerror=on_rm_error)

    if not os.path.exists(baseDir):
        os.makedirs(baseDir)

    if not os.path.exists(refBaseDir):
        os.makedirs(refBaseDir)

    if (testMode == "patchtest"):
        doPatchTest()
    else:
        doHeadTest()
