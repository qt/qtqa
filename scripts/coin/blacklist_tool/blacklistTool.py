############################################################################
##
# Copyright (C) 2019 The Qt Company Ltd.
# Contact: https://www.qt.io/licensing/
##
# This file is part of the Quality Assurance module of the Qt Toolkit.
##
# $QT_BEGIN_LICENSE:GPL-EXCEPT$
# Commercial License Usage
# Licensees holding valid commercial Qt licenses may use this file in
# accordance with the commercial license agreement provided with the
# Software or, alternatively, in accordance with the terms contained in
# a written agreement between you and The Qt Company. For licensing terms
# and conditions see https://www.qt.io/terms-conditions. For further
# information use the contact form at https://www.qt.io/contact-us.
##
# GNU General Public License Usage
# Alternatively, this file may be used under the terms of the GNU
# General Public License version 3 as published by the Free Software
# Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
# included in the packaging of this file. Please review the following
# information to ensure the GNU General Public License requirements will
# be met: https://www.gnu.org/licenses/gpl-3.0.html.
##
# $QT_END_LICENSE$
##
#############################################################################


from __future__ import print_function, unicode_literals
import os
import sys
import argparse
import time
import atexit
import re
from prettytable import PrettyTable
from influxdb import InfluxDBClient
from influxdb import exceptions
from platformEnums import OS, COMPILER, PLATFORM
from enum import Enum
from PyInquirer import style_from_dict, Token, prompt, Separator
from pathlib import Path


# Setup a clear screen function for cleaning the output window.
def clear():
    """Clear the console screen using the OS built-in methods."""
    if sys.platform == "win32":
        os.system('cls')
    else:
        os.system('clear')


# Set style for interactive interface
style = style_from_dict({
    Token.QuestionMark: '#E91E63 bold',
    Token.Selected: '#673AB7 bold',
    Token.Separator: '#e9c01e bold',
    Token.Disabled: '#8D021F bold',
    Token.Instruction: '',  # default
    Token.Answer: '#2196f3 bold',
    Token.Question: '#ffff99 bold',
})


class PlatformData(Enum):
    """Enum to make accessing database results more human readable in code."""
    host_arch = 0
    host_compiler = 1
    host_os = 2
    host_os_version = 3
    target_arch = 4
    target_compiler = 5
    target_os = 6
    target_os_version = 7

INFLUX_DB_URL = "testresults.qt.io" if not os.environ.get("INFLUX_DB_URL") else os.environ.get("INFLUX_DB_URL")
INFLUX_DB_PORT = 443 if not os.environ.get("INFLUX_DB_PORT") else int(os.environ.get("INFLUX_DB_PORT"))
fastForward = False
modifiedFiles = set()
partialMatchesSkipped = list()


def onExit():
    """Print out a report following completion of the script."""

    print("\n\n\nModified files during this run:")
    print("\n".join(modifiedFiles))

    print("\nBlacklist test cases that found parial matches (NOT MODIFIED):")
    for item in partialMatchesSkipped:
        print(f"""
Test: [{item['testname']}]
        File path:
            {item['blacklistPath']}
        Partial match found in file: {item['matchText']}
        Existing platforms for {item['matchText']}:
            {item['existingBlacklist']}
        Suggested new platforms:
            {item['newBlacklistItems']}
        Test Results dashboard:
            {item['testCaseDashboardURL']}
""")


atexit.register(onExit)


clear()  # Clear the screen and get ready!


class editHelper():

    def displayModifiedTable(deletedLines: str, addedLines: str) -> None:
        """Displays the proposed edits to a blacklist file in a table format."""
        addRemoveTable = PrettyTable(
            ["Old Blacklist Entry", "New Blacklist Entry"])
        addRemoveTable.align["Old Blacklist Entry"] = "l"
        addRemoveTable.align["New Blacklist Entry"] = "l"
        addRemoveTable.add_row([deletedLines.strip(), addedLines.strip()])
        print(f"\n\n Updated Blacklist for [{testname[2]}]:\n{addRemoveTable}")

    def printFailingConfigs(failedPlatforms: list) -> None:
        """Displays failing configurations as reported by the database
        in a table format."""
        # Prepare the table for display. It's pretty, and informational too!
        failingConfigs = PrettyTable(["Host Arch", "Host Compiler", "Host OS", "Host OS Version",
                                      "Target Arch", "Target Compiler", "Target OS",
                                      "Target OS Version"])
        for platform in failedPlatforms:
            failingConfigs.add_row(platform)

        print(
            f"\nFAILING CONFIGS for {os.path.normpath(os.sep.join(testname))}:\n{failingConfigs}")

    def paintHeader(testname: tuple, blacklistedTestData: dict, failedPlatforms: list = []) -> None:
        """Clears the screen and prints information relating
        to the current blacklist and test case"""
        clear()
        print(f"\nOpening {blacklistedTestData['filePath']}")
        print(f"Test Case: [{testname[2]}]")
        print(f"""\nTestresults dashboard for [\
{testname[2] if testname[2].find(':') < 0 else testname[2][:testname[2].find(':') + 1]}\
]:\n
{blacklistedTestData['dashboardURL']}""")
        if blacklistedTestData['blacklistSnip']:
            print("\nCurrent Blacklist entry:\n=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=")
            print(blacklistedTestData['blacklistSnip'])
            print("=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=\n")
        else:
            print(f"\nTest [{testname[2]}] not found in blacklist...\n")
        if failedPlatforms:
            editHelper.printFailingConfigs(failedPlatforms)

    def checkFailingPlatformSaturation(platforms: list, platformType: str = "") -> bool:
        """Returns true of the count of platforms passed is more than 3/5
        of the count list of active platforms of the same OS or platform type.
        Platforms passed are assumed to be of the same OS family such
        as ['windows-10 msvc-2017', 'windows7-sp1'] and will check against that
        type if platformType (such as 'xcb') is not passed

        Example: ubuntu-18.04 is failing, and ubuntu-18.04, rhel-7.4, rhel-7.6, and opensuse-leap
        are acive. This would mean only 25% of linux type platforms are failing, so don't use the
        general term 'linux' here.
        """

        activePlatformCountofThisType = 0

        if not platformType:  # check against the OS type passed.
            try:
                # Get the actual type of the platforms passed.
                platformType = [OS(x).isOfType for x in OS if OS(
                    x).normalizedValue == platforms[0].split()[0]][0]
            except IndexError:
                pass

            for platform in activePlatforms:
                try:
                    # Count how many active platforms of the same type there currently are
                    if [OS(x).isOfType for x in OS if OS(x).normalizedValue == platform.split()[0]
                        ][0] == platformType:
                        activePlatformCountofThisType += 1
                except IndexError:
                    pass

        else:  # Check against the platformType passed.
            for platform in activePlatforms:
                try:
                    if platformType in OS.getCanBe(platform.split(" ")[0]):
                        activePlatformCountofThisType += 1
                except IndexError:
                    pass

        for platform in platforms.copy():
            if platform not in activePlatforms:
                platforms.pop(platforms.index(platform))

        if activePlatformCountofThisType and float(len(platforms) /
                                                   activePlatformCountofThisType) >= 0.6:
            return True
        else:
            return False

    def locateBlacklist(blacklistPath: str, testnameTuple: tuple) -> dict:
        """Open the BLACKLIST file and try to locate the test in question.
        Returns a dict object with data relating to the test case."""

        returnObject = {
            "filePath": "",
            "fileExists": False,
            "startPos": None,
            "endPos": None,
            "blacklistSnip": "",
            "partialMatch": False,
            "matchText": "",
            "notFound": False,
            "AdditionalLinesToKeep": set(),
            "dashboardURL": ""
        }

        returnObject["dashboardURL"] = f"\
https://testresults.qt.io/grafana/d/000000009/coin-single\
-test-details?orgId=1&var-project={testnameTuple[0]}&var-\
testcase={testnameTuple[1]}&var-testfunction\
={testnameTuple[2] if testnameTuple[2].find(':') < 0 else testnameTuple[2][:testnameTuple[2].find(':') + 1] + ']'}\
&var-branch=dev&var-inter=24h&from=now-60d&to=now"

        # Our initial path begins with 'qt/' and ends with the testname. Drop that and add BLACKLIST
        # Raw blacklist path appears as "qt/[module]/tests/auto/[testname]/[testCase]"
        path = Path(args.qt5dir, os.sep.join(
            Path(blacklistPath).parts[1:-1]), "BLACKLIST")
        # Some tests are run from a "/test/" subdirectory, but the blacklist is in the main
        # directory, one level up.
        if not path.exists() and f"{os.sep}test{os.sep}" in str(path):
            path = Path(os.sep.join(path.parts[:-2]), "BLACKLIST")
        # Clean up the path in case there are any non-uniform path separators.
        path = os.path.normpath(path)
        print(f"opening {path}\n")
        print(f"Searching for test: [{testnameTuple[2]}]...")
        if not os.path.exists(path):
            returnObject["filePath"] = path
            returnObject["fileExists"] = False
            print("BLACKLIST File does not exist...")
            return returnObject

        returnObject["filePath"] = path
        returnObject["fileExists"] = True

        with open(path, mode="r", newline='') as blacklist:
            blacklistRaw = blacklist.read()
            # Locate the test name and get the bounds up until the next test item.
            testnameLoc = blacklistRaw.find(f"[{testnameTuple[2]}]")
            if testnameLoc < 0:
                print(f"Test [{testnameTuple[2]}] not found in blacklist...\n")
                returnObject["notFound"] = True
                # Try to find a match with a sub-test and save it for manual review.
                testnameLoc = blacklistRaw.find(f"[{testnameTuple[2]}:")
                if testnameLoc >= 0:
                    endOfLine = blacklistRaw.find("\n", testnameLoc)
                    returnObject["partialMatch"] = True
                    returnObject["startPos"] = testnameLoc
                    returnObject["matchText"] = blacklistRaw[testnameLoc: endOfLine]
                    print(
                        f"Partial test match in blacklist: \
'{blacklistRaw[testnameLoc: endOfLine]}'")
                else:
                    returnObject["notFound"] = True
            else:
                returnObject["startPos"] = testnameLoc
                endOfLine = blacklistRaw.find("\n", testnameLoc)
                returnObject["matchText"] = blacklistRaw[testnameLoc: endOfLine]

            if not returnObject["notFound"] or returnObject["partialMatch"]:
                # Look for the position of the next test name, or return -1 (end of file)
                # if our test is the last test.
                returnObject["endPos"] = blacklistRaw.find("[", endOfLine) if blacklistRaw.find(
                    "[", endOfLine) > 0 else len(blacklistRaw) - 1
                returnObject["blacklistSnip"] = blacklistRaw[returnObject["startPos"]: returnObject["endPos"]]
                # Find comments to keep and add them to the list.
                for line in returnObject["blacklistSnip"].splitlines():
                    if line.strip().startswith('#'):
                        returnObject["AdditionalLinesToKeep"].add(line.strip())

        return returnObject

    def generateNewBlacklist(blacklistedTestData: dict, failedPlatforms: list) -> set:
        """Use the target OS and compiler versions to write up a list of properly formatted
           blacklist entries.\nThis does not preserve the existing list."""
        newBlacklist = set()

        if blacklistedTestData["AdditionalLinesToKeep"]:
            newBlacklist.update(blacklistedTestData["AdditionalLinesToKeep"])
        for target in failedPlatforms:
            if target[PlatformData.target_os_version.value] == OS.Windows_10.name:
                newBlacklist.add(
                    f"{OS[target[PlatformData.target_os_version.value]].normalizedValue} \
{COMPILER[target[PlatformData.target_compiler.value]].value}")
            else:
                newBlacklist.add(
                    OS[target[PlatformData.target_os_version.value]].normalizedValue)
        return sorted(newBlacklist)

    def deleteLines(blacklistedTestData: dict, preserveFile: bool, dryRun: bool) -> str:
        """Delete the old blacklist entry from the file. If the deleted
        entry was the only entry in the file and deleteLines was not told to keep
        the BLACKLIST file, it will be deleted.\n
        Set 'dryRun' if no changes should be made.\n
        Returns a snip of what was cut out from the file, or what would
        be if dryRun is set."""
        existingBlacklistData = ""
        delete = False
        if blacklistedTestData["startPos"] == 0 and blacklistedTestData["endPos"] is None:
            delete = True  # The given test spans the whole file. Delete it.
            with open(blacklistedTestData["filePath"], mode="r+", newline='') as blacklist:
                existingBlacklistData = blacklist.read()
        else:  # Snip out the test and rewrite the file.
            with open(blacklistedTestData["filePath"], mode="r+", newline='') as blacklist:
                existingBlacklistData = blacklist.read()
                if not blacklistedTestData["startPos"] == 0:
                    beforeTestText = existingBlacklistData[0:
                                                           blacklistedTestData["startPos"]]
                else:
                    beforeTestText = ""
                if blacklistedTestData["endPos"] and not (blacklistedTestData["endPos"] >=
                                                          len(existingBlacklistData)):
                    afterTestText = existingBlacklistData[blacklistedTestData["endPos"]:]
                else:
                    afterTestText = ""

                if len(beforeTestText + afterTestText) < 3:
                    beforeTestText = ""
                    afterTestText = ""
                    delete = True
                if not dryRun:
                    blacklist.seek(0)  # Reset position in file.
                    blacklist.write(beforeTestText + afterTestText)
                    blacklist.truncate()

        if delete and not preserveFile and not dryRun:
            print("Deleted blacklist with 0 entries...")
            # Delete the empty blacklist file. We'll create a new one if another test needs adding.
            os.remove(blacklistedTestData["filePath"])

        # Return the snippet of what's being deleted.
        return existingBlacklistData[blacklistedTestData['startPos']: blacklistedTestData['endPos']]

    def writeNewEntry(blacklistedTestData: dict, linesToAdd: list, linesToDelete: str) -> dict:
        """Delete the old entry (if applicable) and write the new one.\n
        Returns a dict of the added and deleted snippets."""
        addedLinesSet = set(linesToAdd)
        deletedLinesSet = set()
        if linesToDelete:
            deletedLinesSet.update(linesToDelete.splitlines()[1:])

        # Don't rewrite the file if the lines to write are the same as the existing lines
        # regardless of ordering.
        if addedLinesSet.symmetric_difference(deletedLinesSet):
            deletedLines = ""
            if linesToDelete:
                deletedLines = editHelper.deleteLines(
                    blacklistedTestData, True, False)
            with open(blacklistedTestData["filePath"], mode="r+", newline='') as blacklist:
                blacklistRaw = blacklist.read()
                blacklist.seek(0)
                if blacklistedTestData['startPos'] is None:
                    startPos = len(blacklistRaw)
                else:
                    startPos = blacklistedTestData['startPos']
                linesToWrite = '' + f'[{testname[2]}]\n' + \
                    '\n'.join(linesToAdd) + '\n'
                blacklist.write(
                    blacklistRaw[:startPos] + linesToWrite + blacklistRaw[startPos:])
                blacklist.truncate()
                # Return what's being changed.
                return {"addedLines": linesToWrite, "deletedLines": deletedLines}
        else:
            # No change to the file was necessary
            return {"addedLines": "", "deletedLines": ""}

    def determineEditRequired(existingItems: list, newItems: list) -> bool:
        """Compare the list of new and old items in the blacklist
        entry. Determine if there's any changes."""
        if set(existingItems).symmetric_difference(set(newItems)):
            return True
        else:
            return False

    def getEdits(testname: tuple, blacklistedTestData: dict, failedPlatforms: list,
                 existingBlacklistItems: list, action: str) -> list:
        """Ask the user a series of prommpts to generate a new blacklist
        and provide feedback to confirm if the new list if correct."""
        success = False
        while not success:
            # Start the interactive editor
            linesToAdd = editEntry(
                testname[2], False, failedPlatforms, existingBlacklistItems, action)
            # Add comment lines back in at the top. This is slightly destructive
            # and may result in a comment relating to a specific platform
            # appearing out of order, but it's better than dropping it.
            for index, line in enumerate(blacklistedTestData['AdditionalLinesToKeep']):
                linesToAdd.insert(index, line)
            editHelper.displayModifiedTable(
                "\n".join(existingBlacklistItems), "\n".join(linesToAdd))
            usrinput = prompt([
                {
                    "type": 'confirm',
                    'message': "Is the new blacklist correct?",
                    "name": "confirm"
                }
            ])
            if usrinput['confirm']:
                success = True
                usrinput = prompt(
                    [{
                        "type": 'confirm',
                        'message': "Do you wish to perform any manual edits?",
                        "name": "confirm",
                        "default": False
                    }]
                )
                if usrinput['confirm']:
                    success = False
                    usrinput = prompt([
                        {
                            "type": 'editor',
                            'message': "Manually edit the new entries for the blacklist.",
                            "name": "editor",
                            "default": "\n".join(linesToAdd),
                            "eargs": {
                                "editor": "default",
                                "ext": ".txt"
                            }
                        }
                    ])
                    linesToAdd = usrinput['editor'].splitlines()
                    editHelper.displayModifiedTable(
                        "\n".join(existingBlacklistItems), "\n".join(linesToAdd))
                    usrinput = prompt([
                        {
                            "type": 'confirm',
                            'message': "Is the new blacklist correct?",
                            "name": "confirm"
                        }
                    ])
                    if usrinput['confirm']:
                        success = True

            if not success:
                print("Resetting editor...")
                time.sleep(1)
                clear()
                editHelper.paintHeader(
                    testname, blacklistedTestData, failedPlatforms)
        return linesToAdd


def getActionToPerform(testname: str, blacklistedTestName: str,
                       hasFailures: bool, notInBlacklist: bool) -> str:
    """Prompt the user for an appropriate action to take for a given test.\n
    Options available change based on the context of the test in question."""
    questions = list()
    # Set a bool if the found testname and the original search name are the same
    isFullMatch = testname == f"[{blacklistedTestName}]"
    message = ""

    if not notInBlacklist:
        if isFullMatch:
            message = f"Select the action to take on {testname}"
        else:
            message = f"""{testname} is a partial match
{f', but [{blacklistedTestName}] has 0 failures...' if not hasFailures else '.'}
What should we do?"""
        questions.append(
            {
                'type': 'list',
                'name': 'action',
                'message': message,
                'default': 'edit',
                'choices': [
                    {
                        'name': 'Edit existing',
                        'value': 'edit'
                    }
                ]
            }
        )

        if hasFailures and not isFullMatch:
            questions[0]['choices'].append(
                {
                    'name': f"Replace with [{testname[1:testname.find(':')]}]",
                    'value': 'replace'
                }
            )
        else:
            questions[0]['choices'].append(
                {
                    'name': 'Delete entry',
                    'value': 'delete'
                }
            )

        questions[0]['choices'].append(
            {
                'name': f'Abort / Skip',
                'value': 'abort'
            }
        )

    elif notInBlacklist and hasFailures:
        questions.append(
            {
                'type': 'list',
                'name': 'action',
                'message': f"{testname} is not in the existing blacklist. What should we do?",
                'default': 'abort',
                'choices': [
                    {
                        'name': f'Abort / Skip',
                        'value': 'abort'
                    },
                    {
                        'name': f'Add [{testname}]',
                        'value': 'add'
                    }
                ]
            }
        )
    else:
        return 'edit'

    # Abort is always available.

    answers = prompt(questions, style=style)
    return (answers["action"])


def editEntry(testname: str, isPartialMatch: bool, failedPlatformsRaw: list,
              alreadyBlacklisted: list, action: str) -> list:
    """Present the user with a series of prompts that make blacklisting and whitelisting
    suggestions.\n
    Failing Platform Saturation is tested against activePlatforms. If >60% of the active platforms
    of a given type are failing, the general platform term will be used instead. Whitelist
    suggestions will be made for the remaining acive, but passing platforms in this case."""

    # There are a lot of lambda function here that generate or filter down lists.
    # Often, the purpose is looking at the list of options to present to the user,
    # but removing "Separator" objects from the list that would otherwise cause
    # exceptions when examining the list data.

    # Other lambdas generate lists of related items from platformEnums.py,
    # looking at various relationships between platform targets, os families
    # and how a given target relates to general platform terms.

    print(f"\nEntry {action} mode for {testname}")

    allPlatforms = list()
    failedPlatforms = list()
    relatedPlatforms = set()
    markedAsCIFlaky = False
    platformCollection = dict()
    whitelistPreChecked = dict()

    # Build a checkbox list for failed platforms.
    # Pre-tick the options that are already in the blacklist.
    if failedPlatformsRaw:
        for platform in failedPlatformsRaw:
            if platform[-1] == OS.Windows_10.name:
                newitem = {
                    'checked': True, 'name': f"{OS[platform[-1]].normalizedValue} \
{COMPILER[platform[-3]].value}"}
            else:
                newitem = {'checked': True,
                           'name': OS[platform[-1]].normalizedValue}

            if newitem not in failedPlatforms:
                failedPlatforms.append(newitem)

            generalPlatform = OS[platform[-1]].osFamily
            if generalPlatform in [PLATFORM(x).normalizedValue for x in PLATFORM]:
                if generalPlatform not in platformCollection:
                    platformCollection[generalPlatform] = set()
                platformCollection[generalPlatform].add(
                    f"{OS[platform[-1]].normalizedValue} {COMPILER[platform[-3]].value}"
                    if platform[-1] == OS.Windows_10.name else OS[platform[-1]].normalizedValue)
                relatedPlatforms.add(generalPlatform)

    # Write a separator with information about general platform names to the list of options.
    if alreadyBlacklisted or relatedPlatforms:
        failedPlatforms.append(Separator(
            '== General platform Types:==\n       See https://doc.qt.io/qt-5/qguiapplication.html#\
platformName-prop'))

    # Build the general platforms list to present in the first prompt. Avoid duplicates
    # Since we're looking at platform names like 'osx', 'windows', 'rhel'
    for item in alreadyBlacklisted:
        # Set a flag if the existing line contains 'ci' such as "macos-10.12 ci"
        # Use this flag later to pop ci back onto edited entries.
        if re.search(r'\bci\b', item):
            markedAsCIFlaky = True
        item = item.split(" ")[0]
        if item not in failedPlatforms and item in [PLATFORM(x).normalizedValue for x in PLATFORM]:
            relatedPlatforms.add(item)

    # Add the general platform names if it doesn't already exist in the first half
    # of the list (already blacklisted).
    # If an item passes the failing platforms saturation test, pre-check it.
    for item in relatedPlatforms:
        if item not in [
            x for x in filter(lambda y: type(y) !=
                              Separator, failedPlatforms) if x['name'] == item
        ]:
            if item == "*" and not editHelper.checkFailingPlatformSaturation(
                    [x['name'] for x in filter(lambda y: type(y) !=
                                               Separator, failedPlatforms)
                     ], "*"):
                failedPlatforms.append({'checked': False, 'name': item})
            else:
                failedPlatforms.append({'checked': True, 'name': item})

    # Run the saturation test on all other targets to determine which
    # general platform names we should use instead of blacklisting individual targets.
    for item in platformCollection:
        useGlobalPlatformTerm = editHelper.checkFailingPlatformSaturation(
            list(platformCollection[item]), item)
        index = None
        try:
            index = failedPlatforms.index([x for x in filter(lambda y: type(
                y) != Separator, failedPlatforms) if x['name'] == item][0])
        except IndexError:
            print(f"WARN: {item} not in list of Failed Platforms")
            # Generally shouldn't happen, as any platform in platformCollection
            # Should theoretically be in the failedPlatforms list.
            continue
        if useGlobalPlatformTerm:
            failedPlatforms[index]['checked'] = True
        else:
            failedPlatforms[index]['checked'] = False

    # Look at each of the failed platforms and determine if
    # a majority of that platform failed. If so, add the
    # platform family name / type to the list of options
    # and check it.
    tempFailedPlatforms = [x['name'] for x in filter(
        lambda y: type(y) != Separator, failedPlatforms)]
    for platformType in set([OS.getType(x) for x in tempFailedPlatforms]):
        # Filter the list of platforms to pass down to ones of the same type.
        checked = False
        index = None
        try:
            index = failedPlatforms.index([x for x in filter(lambda y: type(
                y) != Separator, failedPlatforms) if x['name'] == item][0])
        except IndexError:
            pass

        if editHelper.checkFailingPlatformSaturation(
            [x for x in
                filter(lambda y: OS.getType(y) ==
                       platformType, tempFailedPlatforms)
             ], platformType):
            checked = True
            # What platforms are in the active platforms of this type
            # but have not failed? Save this for later so we can
            # auto-check whitelist options.
            if not whitelistPreChecked.get(platformType, []):
                whitelistPreChecked[platformType] = list()
            tempSet = set(
                [x for x in filter(lambda y: OS.getType(y) ==
                                   platformType, activePlatforms)
                 ]
            ).difference([
                x for x in filter(lambda y: OS.getType(y) == platformType,
                                  tempFailedPlatforms)
            ])
            if tempSet:
                whitelistPreChecked[platformType].extend(list(tempSet))

        # Check off msvc compilers in whitelist choices if windows 10 was a failed platform.
        if OS.Windows_10.normalizedValue in tempFailedPlatforms and (platformType in [
            OS.Windows_10.normalizedValue,
            PLATFORM.WINDOWS.normalizedValue
        ]):
            # Search through the raw list of failed platforms. The target compiler exists at
            # index -3, and the target OS version at index -1
            failedWin10Compilers = set([COMPILER.getNormalizedValue(
                x[-3]) for x in filter(lambda y: OS.Windows_10.name == y[-1], failedPlatformsRaw)])
            if not whitelistPreChecked.get(platformType, []):
                whitelistPreChecked[platformType] = list()

            # Gather the list of compilers (x), and check to see which ones are currently
            # active in the CI (y), but filter the active list down to only MSVC compilers (z).
            # Get the difference of the sets, returning only a set of passing compilers
            # which are active in the CI.
            passingWin10Compilers = set([x.value for x in COMPILER if [
                x.value for y in filter(lambda z: 'msvc' in z, activePlatforms)
                if x.value in y]
            ]
            ).difference(failedWin10Compilers)
            whitelistPreChecked[platformType].extend(passingWin10Compilers)

        if index:
            failedPlatforms[index]['checked'] = checked
        else:
            failedPlatforms.append({'name': platformType, 'checked': checked})

    # build a checkbox list for all possible platform configs.
    for key in OS:
        checked = False
        if key == OS.Windows_10:
            for compiler in COMPILER:
                if compiler.value.lower().startswith('msvc'):
                    allPlatforms.append(
                        {'checked': checked, 'name': f"{key.normalizedValue} {compiler.value}"})
        else:
            allPlatforms.append(
                {'checked': checked, 'name': key.normalizedValue})

    if alreadyBlacklisted:
        allPlatforms.append(Separator(
            '== General platform Types:==\n        See https://doc.qt.io/qt-5/qguiapplication.html#\
platformName-prop')
        )

    for key in [PLATFORM(x).normalizedValue for x in PLATFORM]:
        allPlatforms.append({'checked': False, 'name': key})

    # Get ready to show the first prompt.
    # This prompt will show platforms that are already in the blacklist,
    # any new failed platforms, and general platform name suggestions.
    firstAnswers = list()

    # Only present the prompt if there were any new failed platforms.
    # It's possible we're in edit mode without any failures, in the case
    # that the user is adding a new test or editing one that the database
    # reported all-passing.
    if failedPlatforms:
        questions = [
            {
                'type': 'checkbox',
                'name': 'platformEdit',
                'message': '[BLACKLIST] The below have failed at least once in the past 60 days. \
Select any to add to the blacklist. (All pre-selected by default)',
                'choices': failedPlatforms
            }
        ]
        firstAnswers = prompt(questions, style=style)

        # Clear the list of related platforms and re-add only the ones that the user selected.
        relatedPlatforms.clear()
        for answer in firstAnswers['platformEdit']:
            if answer in [PLATFORM(x).normalizedValue for x in PLATFORM]:
                relatedPlatforms.add(answer)

        print("\n")  # Visual spacer in-between prompts.

        keywordDisabledItems = list()
        # Tick checkbox in allPlatforms for platforms that were selected in the first prompt.
        for index, platform in enumerate(allPlatforms):
            if type(platform) == Separator:
                continue

            # The following block checks the selected list of platforms and disables
            # specific entries that are covered by a general term such as 'osx' or
            # 'xcb'. This avoids needing to manually uncheck platforms in the list
            # in order to avoid redundant blacklisting.
            tempOSEnumIs = None

            # The line below will return the list of "canBe" from the OS enum if
            # the item exists in OS and was selected. If a value is passed in
            # "platform" that isn't in OS, None will be returned.
            tempOSEnum = [OS(x).canBe for x in OS if x.normalizedValue in platform['name']
                          or platform['name'] in x.osFamily or platform['name'] in x.isOfType]

            # If not None or empty, check to see if the selected platform's canBe list
            # contains a keyword from the list of selected related platforms.
            # If it is, deselect the item so only the general platform keyword is selected.
            if tempOSEnum:
                tempOSEnumIs = [x for x in tempOSEnum[0]
                                if x in relatedPlatforms]

            if platform['name'] in firstAnswers['platformEdit'] and not tempOSEnumIs and platform['name'] != '*':
                platform['checked'] = True
            elif tempOSEnumIs or (platform['name'] == '*' and '*' in relatedPlatforms):
                platform['disabled'] = f"Already selected for blacklisting by keyword \
'{tempOSEnumIs[0] if tempOSEnumIs else '*'}'"
                # Keep a list of indexes we mark as disabled.
                keywordDisabledItems.append(index)
            else:
                platform['checked'] = False

    # Second prompt. Asks to add any additional platforms from the list of all possible
    # blacklist options.
    blacklistAnswers = list()

    # Only prompt for additional platforms if '*' was not selected.
    if '*' not in relatedPlatforms:

        questions = [
            {
                'type': 'checkbox',
                'name': 'allPlatforms',
                'message': f'[BLACKLIST] Check any {"additional " if failedPlatforms else ""}\
platforms to add.',
                'choices': allPlatforms
            }
        ]

        # Ask the prompt.
        # Includes a quick conversion to set and back to list to strip out duplicates
        blacklistAnswers = list(
            set(prompt(questions, style=style)['allPlatforms']))

        # Add disabled platform blacklist choices back into the list of blacklist answers
        try:
            # Find the separator in the list if there is one, start looking at
            # platforms after that index.
            sepIndex = allPlatforms.index(
                [x for x in allPlatforms if type(x) == Separator][0])
        except ValueError or IndexError:
            sepIndex = 0
        # Make a set of the disabled platform choices
        tempDisabledGeneralPlatforms = set()
        for item in allPlatforms[sepIndex + 1:]:
            if item.get('disabled', None):
                tempDisabledGeneralPlatforms.add(item['name'])
        blacklistAnswers.extend(tempDisabledGeneralPlatforms)
    else:
        blacklistAnswers = ['*']

    # Reset general platforms to ask about in the whitelist.
    generalPlatforms = set()

    for blindex, item in enumerate(blacklistAnswers):
        # Filter out unselectable separator choices from the allPlatforms
        # list and search for the dict item that was selected in
        # blacklistAnswers. Disable those items so they cannot be selected
        # when whitelisting.

        # TODO: Is this redundant now that the whitelist options get filtered down anyway???

        for index, platform in enumerate(allPlatforms):
            if type(platform) == Separator:
                continue
            if platform["name"] == item:
                allPlatforms[index]["disabled"] = "Already selected for blacklisting"
                # Only ask for whitelisting if a blanket platform type is selected.
                if item in [PLATFORM(x).normalizedValue for x in PLATFORM]:
                    generalPlatforms.add((item, blindex))

    # Un-disable the items that would be blacklisted by the general platform keyword
    # So they can be selected in the whitelist.
    for index in keywordDisabledItems:
        if allPlatforms[index]['name'] not in [x[0] for x in generalPlatforms]:
            allPlatforms[index]["disabled"] = False

    # remove options from the list that are not of the same family.
    for answer in blacklistAnswers.copy():
        if not PLATFORM.getIsRootType(answer) and [
            True for x in filter(lambda y:
                                 PLATFORM.getFamily(y) == PLATFORM.getFamily(
                                     answer), blacklistAnswers
                                 )
            if PLATFORM.getIsRootType(x) is True
        ]:
            blacklistAnswers.pop(blacklistAnswers.index(answer))

    for index, blAnswer in enumerate(blacklistAnswers):
        whitelistChoices = set()

        # Get the basic list of whitelist choices based on explicitly related platforms to blAnswer
        tempList = PLATFORM.getCanBe(blAnswer)
        if tempList:
            for choice in tempList:
                # Don't add self. i.e. Don't add 'ubuntu' if 'ubuntu' is being blacklisted.
                if choice not in ["*", blAnswer, f"{OS.getFamily(blAnswer)}",
                                  f"{OS.getType(blAnswer)}"]:
                    whitelistChoices.add(choice)

        # Build the list of other related platforms and OSes that
        # would be blacklisted by blAnswer. Duplicates are okay
        # and will be stripped out later.
        tempList = list()
        tempList.extend(OS.getCanBe(blAnswer))
        tempList.extend(OS.getFamilyMembers(blAnswer))
        for member in OS.getTypeMembers(blAnswer):
            tempList.extend([member, OS.getFamily(member)])

        for choice in tempList:
            if choice not in ["*", blAnswer, f"{OS.getFamily(blAnswer)}",
                              f"{OS.getType(blAnswer)}"]:
                whitelistChoices.add(choice)

        # Add msvc options to the whitelist for windows 10.
        if ('windows' in blAnswer and 'windows-10' in [x['name'] for x in
                                                       filter(lambda y: type(y) != Separator,
                                                              failedPlatforms)
                                                       ]) or blAnswer == '*':
            for compiler in [COMPILER(x) for x in COMPILER if 'msvc' in COMPILER(x).value]:
                whitelistChoices.add(compiler.value)

        whitelistChoicesFormatted = [{'name': x} for x in whitelistChoices]

        # Pre-check choices that would be blacklisted by a general term
        # but have not failed recently and are active platforms in the CI.
        for choice in whitelistPreChecked.get(blAnswer, []):
            if PLATFORM.getIsRootType(blAnswer):
                if choice in [x for x in whitelistChoices]:
                    whitelistChoicesFormatted[whitelistChoicesFormatted.index(
                        {
                            'name': choice
                        }
                    )] = {
                        'name': choice, 'checked': True
                    }
            else:
                if choice in [x for x in whitelistChoices]:
                    whitelistChoicesFormatted[whitelistChoicesFormatted.index(
                        {
                            'name': choice
                        }
                    )] = {
                        'name': choice, 'checked': True
                    }

        # Prompt the user for whitelist options for this blacklisted
        # answer if there are any possible combinations.
        if whitelistChoices:
            questions = [
                {
                    'type': 'checkbox',
                    'name': 'exceptions',
                    'message': f'[WHITELIST] Check any exceptions to \
add to the WHITELIST for {blAnswer}.',
                    'choices': sorted(whitelistChoicesFormatted, key=lambda i: i['name'])
                }
            ]

            whitelistAnswers = prompt(questions, style=style)['exceptions']

            # Build up the whitelist on top of any applicable general terms provided.
            # See platformEnums::OS for more information about what can be applied
            # to which platform terms.
            for item in whitelistAnswers:
                if 'windows-10' in item and 'msvc' in item:
                    for compiler in [
                        COMPILER(x) for x in COMPILER if x.value == item.split(' ')[1]
                    ]:
                        blacklistAnswers[index] = f"{blacklistAnswers[index]} !{compiler.value}"
                else:
                    blacklistAnswers[index] = f"{blacklistAnswers[index]} !{item}"

    # Prompt the user for which options to mark with 'ci' if any existing
    # blacklist items were marked with 'ci'
    # Marking a blacklist line with 'ci' makes the line only take effect
    # inside of COIN. This is useful if the test is flaky or failing explicitly
    # due to a known COIN bug or infrastructure issue, but passes normally in
    # a real-world environment.
    if markedAsCIFlaky:

        choices = [{'name': x} for x in blacklistAnswers]
        questions = [
            {
                'type': 'checkbox',
                'name': 'markForCI',
                'message': f'[CI ONLY] At least one item in the existing blacklist was marked \
with \'ci\'. Select any new items to mark with the \'ci\' designation.',
                'choices': choices
            }
        ]

        flakyAnswers = prompt(questions, style=style)['markForCI']

        for item in flakyAnswers:
            blacklistAnswers[blacklistAnswers.index(item)] = f"{item} ci"

    return blacklistAnswers


def appendPartialMatchSkipped(testname: list, blacklistedTestData: dict, failedPlatforms: list):
    partialMatchesSkipped.append(
        {
            "blacklistPath": blacklistedTestData["filePath"],
            "testname": testname[2],
            "matchText": blacklistedTestData["matchText"],
            "existingBlacklist": '\n            '.join(blacklistedTestData["blacklistSnip"].split("\n")),
            "newBlacklistItems": '\n\
            '.join(editHelper.generateNewBlacklist(blacklistedTestData, failedPlatforms)),
            "testCaseDashboardURL": blacklistedTestData['dashboardURL']
        }
    )


def processItem(testname: list, failedPlatforms: list):

    global fastForward  # Make this global editable in this scope.

    if fastForward:
        # Fast-Forward takes a test name (see arg parsing in main())
        # This skips forward in the results to the selected test if it exists.
        print(f"Fast Forwarding to {args.fastForward}...")
        if testname[2] == args.fastForward:
            clear()
            # If we found the test, cancel the fast forward.
            fastForward = False
        else:
            return

    blacklistPath = os.sep.join(testname)

    # Find the current test in the blacklist or touch a new file.
    # Return start and end bounds for the test.
    blacklistedTestData = editHelper.locateBlacklist(blacklistPath, testname)

    # Abort is the default action in automatic mode.
    # This skips the test if a partial match is found.
    action = "abort"
    haveAction = False

    if not blacklistedTestData:
        # Return this iteration if there was a critical error
        # such as being unable to touch a new file.
        return
    elif not blacklistedTestData['fileExists'] or (blacklistedTestData['notFound']
                                                   and not blacklistedTestData['partialMatch']):
        editHelper.paintHeader(testname, blacklistedTestData, failedPlatforms)
        if args.interactive:
            # If in interactive mode, ask the user if the test should be added.
            if failedPlatforms:
                action = getActionToPerform(testname[2], "", True, True)
                haveAction = True
                if action == 'abort':
                    input(f"\nEdit Aborted...\nPress Return to continue...")
                    clear()
                    return  # Skip this test
                elif action == 'add' and not blacklistedTestData['fileExists']:
                    # Touch the file since it doesn't exist and try to create it.
                    # This can only occur in interactive mode.
                    try:
                        # Initialize a blank file if it doesn't exist.
                        open(
                            blacklistedTestData['filePath'], mode="a", newline="")
                    except FileNotFoundError:
                        print(
                            f"Error writing to file at {blacklistedTestData['filePath']}... \
Is your qt5 repository fully up-to-date?")
                        input(
                            f"Press Return to continue. Please update [{testname[2]}] in \
{blacklistedTestData['filePath']} manually.")
                clear()
            else:
                print(
                    f"\nDatabase provided no failing platforms for [{testname[2]}]. \
Nothing to do...")
                input(f"\nPress Return to continue...")
                clear()
                return  # Skip this test
        else:
            # Return this iteration if the blacklist file doesn't exist or
            # the test isn't in the blacklist.
            return

    existingBlacklistItems = list()

    # Did we find a whole or partial match? Print the current blacklist
    # and ask for action if in interactive mode.
    if not blacklistedTestData["notFound"] or blacklistedTestData["partialMatch"]:
        existingBlacklistItems = blacklistedTestData['blacklistSnip'].splitlines()[
            1:]
        for index, item in enumerate(existingBlacklistItems):
            existingBlacklistItems[index] = existingBlacklistItems[index].strip(
            )
        existingBlacklistItems = sorted(existingBlacklistItems)

        if args.interactive and blacklistedTestData["partialMatch"]:
            # Get the action to perform if we found a partial match since this is a special case.
            # The user may wish to update the partial match, delete it and add a new test case,
            # or abort and skip the case.
            if not haveAction:
                editHelper.paintHeader(
                    testname, blacklistedTestData, failedPlatforms)
                action = getActionToPerform(
                    blacklistedTestData["matchText"], testname[2],
                    True if failedPlatforms else False, False)
                haveAction = True

    if (action == "edit" and blacklistedTestData["partialMatch"]) or action == "delete":
        # Update the testname used for both display and editing
        # if the user is editing the partial match.
        testname = (testname[0], testname[1],
                    blacklistedTestData["matchText"][1:-1])

    deletedLines = ""
    addedLines = ""

    if failedPlatforms:
        # So we have failed platforms. What should be done?
        editHelper.paintHeader(testname, blacklistedTestData, failedPlatforms)
        if not editHelper.determineEditRequired(existingBlacklistItems.copy(),
                                                editHelper.generateNewBlacklist(blacklistedTestData,
                                                                                failedPlatforms)):
            print(f"\nBlacklist for {testname[2]} is already up-to-date.")
            if args.interactive:
                usrinput = prompt(
                    [{
                        "type": 'confirm',
                        'message': "Force editing?",
                        "name": "force",
                        "default": False
                    }]
                )
                if not usrinput['force']:
                    return  # Skip this test.
            else:
                return  # Skip this test.

        if not haveAction:
            # So the test wasn't up to date and needs editing? ask what to do.
            if args.interactive:
                action = getActionToPerform(
                    blacklistedTestData["matchText"], testname[2], True, False)
            else:
                if blacklistedTestData["partialMatch"]:
                    # Never overwrite, replace, or edit partial matches in automatic mode.
                    # Just log it and let the user know what was skipped.
                    appendPartialMatchSkipped(testname, blacklistedTestData, failedPlatforms)
                    return
                else:
                    action = 'edit'
            haveAction = True

        # Initialize the add/delete lists
        linesToAdd = list()
        linesToDelete = list()
        if action in ['edit', 'replace', 'add']:
            if args.interactive:
                linesToAdd = editHelper.getEdits(
                    testname, blacklistedTestData, failedPlatforms, existingBlacklistItems, action)
            else:
                linesToAdd = editHelper.generateNewBlacklist(
                    blacklistedTestData)
        elif action == "abort":
            if blacklistedTestData["partialMatch"]:
                # Just log the partial match and let the user know what was skipped.
                appendPartialMatchSkipped(testname, blacklistedTestData, failedPlatforms)
            print("\nNothing modified...")
            if args.interactive:
                input("Press Return to continue...")
            clear()  # Clear the screen after each test
            return

        if (not blacklistedTestData["notFound"]
                or blacklistedTestData["partialMatch"]) and action != "delete":
            # Dry run the delete to see what we're deleting. It will be executed later.
            linesToDelete = editHelper.deleteLines(
                blacklistedTestData, True, True)
        # Execute the edits.
        result = editHelper.writeNewEntry(
            blacklistedTestData, linesToAdd, linesToDelete)
        addedLines = result['addedLines']
        deletedLines = result['deletedLines']

    # Occurs when a user wants to edit a partial match with no failed platforms.
    elif args.interactive and action == 'edit':
        linesToAdd = editHelper.getEdits(
            testname, blacklistedTestData, failedPlatforms, existingBlacklistItems, action)
        linesToDelete = editHelper.deleteLines(blacklistedTestData, True, True)
        result = editHelper.writeNewEntry(
            blacklistedTestData, linesToAdd, linesToDelete)
        addedLines = result.get['addedLines']
        deletedLines = result['deletedLines']

    # Delete partial matches too, since the database doesn't track individual test cases,
    # just function names and if the test function is reported as only pass, the specific test
    # cases must have also passed. Don't delete it if the user selected edit in interactive mode.
    elif not blacklistedTestData["notFound"] or blacklistedTestData["partialMatch"]:
        action = "delete"

    if action == "delete":
        print(
            f"\nRemoving blacklisted test {testname[2]}\
{'...' if failedPlatforms else ' with 0 failing configurations...'}")
        deletedLines = editHelper.deleteLines(
            blacklistedTestData, False, False)

    # Display a table with the changes.
    if addedLines or deletedLines:
        if not args.interactive:
            editHelper.displayModifiedTable(deletedLines, addedLines)

        # Save the file path since we modified it.
        modifiedFiles.add(blacklistedTestData["filePath"])

        if os.path.exists(blacklistedTestData["filePath"]):
            with open(blacklistedTestData["filePath"], newline='') as blacklist:
                print(
                    f"\nNew Blacklist file:\n=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=\n\
{blacklist.read()}=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=\n")

    else:
        print("\nNothing modified...")
    if args.interactive:
        input("Press Return to continue...")
    clear()  # Clear the screen after each test


def getInfluxClient() -> InfluxDBClient:
    client = InfluxDBClient(
        host=INFLUX_DB_URL,
        port=INFLUX_DB_PORT,
        ssl=True,
        verify_ssl=True,
        username=os.environ.get("INFLUX_DB_USER") if os.environ.get(
            "INFLUX_DB_USER") else "",
        password=os.environ.get("INFLUX_DB_PASSWORD") if os.environ.get(
            "INFLUX_DB_PASSWORD") else "",
        database="coin"
    )
    client._InfluxDBClient__baseurl = "{0}://{1}:{2}/{3}".format(
        client._scheme,
        client._host,
        client._port,
        "influxdb"
    )

    return client


def doQuery(module: str) -> dict:
    """Query the database and put together a dictionary of blacklisted
    tests which had at least one failure in the last 60 days."""
    client = getInfluxClient()

    def setClientProp(prop: str) -> None:
        """Set the username or password with which to connect to the database"""
        if prop == 'username':
            os.environ["INFLUX_DB_USER"] = prompt(
                [{
                    "type": "input",
                    'message': f"Influx DB Username:",
                    "name": "username",
                    'default': client._username
                }]
            )['username']
            client._username = os.environ.get("INFLUX_DB_USER")
        else:
            os.environ["INFLUX_DB_PASSWORD"] = prompt(
                [{
                    "type": "password",
                    'message': f"Influx DB Password:",
                    "name": "password"
                }]
            )['password']
            client._password = os.environ.get("INFLUX_DB_PASSWORD")

    def showDBKeysFields(message: str) -> bool:
        """Print out the list of field names and tag names in the coin database
        This assists with modifying the query if the user is not explicitly
        familiar with the database structure."""
        if prompt(
            [{
                "type": "confirm",
                'message': f"{message} Show tags/fields before editing?:",
                "name": "help",
                'default': False
            }]
        )['help']:
            clear()
            newlinesep = '\n'  # Workaround for not allowing '\' inside f-strings
            print(
                f"""TAG KEYS:\n{
                    newlinesep.join([point['tagKey'] for point in
                    client.query('SHOW TAG KEYS from blacklisted_test').get_points()])
                    }\n""")
            print(
                f"""FIELD KEYS:\n{
                    newlinesep.join([point['fieldKey'] for point in
                    client.query('SHOW field KEYS from blacklisted_test').get_points()])
                    }\n""")
            return True
        else:
            return False

    if args.interactive:
        # Try the pre-set user and password if they're in environment variables
        if os.environ.get("INFLUX_DB_USER") and os.environ.get("INFLUX_DB_PASSWORD"):
            try:
                # Dummy query to check credentials. Verify read permisison.
                client.query("SHOW FIELD KEYS FROM integrations")
                success = True
                print("Username OK...\nPassword OK...")
            except exceptions.InfluxDBClientError:
                print(
                    "Environment variable Username or password incorrect. \
Please re-enter your credentials...")
                success = False
        else:
            success = False

        while not success:
            setClientProp('username')
            setClientProp('password')
            try:
                # Dummy query to check credentials. Verify read permisison.
                client.query("SHOW FIELD KEYS FROM integrations")
                success = True
            except exceptions.InfluxDBClientError as e:
                print(
                    "Username or password incorrect. Please re-enter your credentials...")
                print(e)
                time.sleep(2)
                clear()

    # Get the full list of blacklisted tests that had any passes at all in the last 7 days.

    selectString = "SELECT project, testCase, testFunction, id FROM blacklisted_test "
    moduleString = f"and project='qt/{module}' " if module != 'qt5' else ''
    whereString = f"WHERE result = 'Passed' and branch = 'dev' {moduleString}and time > now() - 7d"

    success = False

    while not success:
        if args.interactive:
            # Allow for editing the query.
            whereString = prompt([{"type": "input", 'message': f"Edit WHERE clause:",
                                   "name": "query", 'default': whereString}])['query']
            print("OK...")
            try:
                blPoints = client.query(selectString + whereString)
                success = True
                # The query didn't return anything in the generator. Maybe the query was bad.
                if not next(blPoints.get_points(), None):
                    if showDBKeysFields("Query returned 0 results."):
                        success = False
                    else:
                        success = False
                        clear()
            except exceptions.InfluxDBClientError as e:
                showDBKeysFields(
                    f"\nError while running query: {e}Please modify the query and try again...\n")
                success = False
        else:
            blPoints = client.query(selectString + whereString)
            success = True

    # Generate a dictionary of the testnames, each with an empty dict.
    tests = {}
    for point in blPoints.get_points():
        tests[(point["project"], point["testCase"], point["testFunction"])] = {}

    # Query for all executed configurations that had at least one failure in the last 60 days.
    for test in tests:
        # The whitespace line below lets us use carriage return and overwrite the current line
        # for each test name being processed. Getting the actual console window width is not
        # lightweight or pretty, so this works fine without much risk of garbage being displayed.
        print("\r                                                                                 \
                                                                                          ", end="")
        print(
            f"\rProcessing blacklisted test: \
\"{os.path.normpath(os.sep.join(test).strip())}\"", end="")
        queryForFail = f"SELECT id, host_arch, host_compiler, host_os, host_os_version, \
target_arch, target_compiler, target_os, target_os_version FROM blacklisted_test WHERE \
project = '{test[0]}' and testCase = '{test[1]}' and testFunction = '{test[2]}' \
and branch = 'dev' and result = 'Failed' and time> now()-60d"

        failures = client.query(queryForFail)

        failedPlatforms = {}
        # Verify that the query returned at least one point (one failed configuration).
        if next(failures.get_points(), None) is not None:
            for point in failures.get_points():
                if test not in failedPlatforms:
                    # Make the test name a set object so it will be unique.
                    # This seems redundant at the moment because the configurations are
                    # addressed as tests[testname][testname] in  __main__
                    # Maybe it can be fixed elegantly.
                    failedPlatforms[test] = set()
                # Add the configuration to the set object.
                # If it's an exact duplicate it will be ignored.
                failedPlatforms[test].add(
                    (point["host_arch"], point["host_compiler"], point["host_os"],
                     point["host_os_version"], point["target_arch"], point["target_compiler"],
                     point["target_os"], point["target_os_version"])
                )
            tests[test] = failedPlatforms
        else:
            # The query returned 0 points.
            # Set the object in tests to None so we can safely check for it later.
            tests[test] = None

    print("\nDone...")
    if args.interactive:
        # Cosmetic sleep for the UI  # Everyone needs their beauty rest!
        time.sleep(2)
    return tests


def getActivePlatforms() -> list:
    """Runs a query on the database to gether a list of recently
    run targets. This list can be used to understand what platforms
    are currently active in the CI."""

    client = getInfluxClient()

    result = client.query(
        "SELECT id, target_os, target_os_version, target_compiler FROM workitem where branch = \
'dev' and time >= now()-30d GROUP BY target_os, target_os_version, target_compiler")

    activeTargets = set()
    # Create a unique set of the recently run platforms
    for point in result.get_points():
        activeTargets.add(
            (point['target_os'], point['target_os_version'], point['target_compiler']))

    friendlyTargetNames = set()
    ignoredPlatforms = set()
    for target in activeTargets:
        try:
            if target[1] == OS.Windows_10.name:
                friendlyTargetNames.add(
                    f"{OS[target[1]].normalizedValue} {COMPILER[target[2]].value}")
            else:
                friendlyTargetNames.add(OS[target[1]].normalizedValue)
        except KeyError:
            # A platform returned by the database that recently reported data
            # is "active", but we don't care about it because it's not in our
            # enums for platforms that run tests and can be blacklisted.
            # This is to be expected for any platform that has tests disabled
            # on all configurations, or for a platform that does not report
            # itself in a uniquely identifiable way to the blacklister.
            ignoredPlatforms.add(
                target[1] if not target[1] == OS.Windows_10.name else f'{target[1]} {target[2]}')

    if ignoredPlatforms:
        printableIgnoreList = '\n    '.join(sorted(ignoredPlatforms))
        print(f"""
WARN: The following platforms are not present in platformEnums.py,
    but have recently run workitems in the CI. If these platforms
    are not running tests, this message can be safely ignored.
    Otherwise, platformEnums.py may need to be updated.

    =-=-=-=-=-=-=-=-=-=-=-
    {printableIgnoreList}
    =-=-=-=-=-=-=-=-=-=-=-

""")
    if args.printActivePlatforms:
        prettyPlatforms = PrettyTable(["OS Type", "OS Version", "Compiler Target"])
        for platform in sorted(activeTargets):
            prettyPlatforms.add_row(platform)

        print("All active platforms:")
        print(prettyPlatforms)

    if args.interactive:
        input("Press return to continue...")
    return list(friendlyTargetNames)


def validateQt5Dir() -> dict:
    args.qt5dir = os.path.normpath(args.qt5dir)

    if not args.qt5dir.endswith(os.sep):
        args.qt5dir = args.qt5dir + os.sep

    if not os.path.exists(args.qt5dir):
        return({'exists': False, 'module': None})
    else:
        module = args.qt5dir.split(os.sep)[-2]
        if not module == 'qt5':
            # Strip off the module since the test returns it from the database
            args.qt5dir = args.qt5dir[:args.qt5dir[:-1].rfind(os.sep) + 1]
        return({'exists': True, 'module': module})


if __name__ == "__main__":

    parser = argparse.ArgumentParser()
    parser.add_argument('--interactive', '-i', action='store_true', dest="interactive",
                        help="Set --interactive or -i to confirm changes and edit entries.")
    parser.add_argument('--qt5dir', dest='qt5dir', type=str, required=True,
                        help='The full path to a checked-out qt5 supermodule or a single submodule')
    parser.add_argument('--fastForward', dest='fastForward',
                        type=str, help='Test Case name to Fast Forward to.')
    parser.add_argument('--printActivePlatforms', '-p', action='store_true', dest="printActivePlatforms",
                        help="Print out active COIN platforms on startup")
    args = parser.parse_args()

    if args.fastForward:
        fastForward = True

    moduleValidation = validateQt5Dir()
    if not moduleValidation['exists']:
        print(
            f"Path to qt5 or qt5 submodule does not exist. \
Please verify that the path is correct: {args.qt5dir}")
        exit(0)

    # Gather the list of blacklisted tests and their failed configurations from the last 60 days.
    tests = doQuery(moduleValidation['module'])

    # Query the most recent integration and see which platforms are currently active in COIN.
    # This is a global that gets used any time we check a given platform type's failing percentage.
    # See editHelper.checkFailingPlatformSaturation()
    activePlatforms = getActivePlatforms()

    for testname in tests:
        clear()
        # The test had no failures. See about removing it from the blacklist entirely.
        if tests.get(testname) is None:
            processItem(testname, None)
            print("\n\n")
        else:
            # Update the blacklist configurations with failed platforms.
            processItem(testname, tests[testname][testname])
            print("\n\n")
