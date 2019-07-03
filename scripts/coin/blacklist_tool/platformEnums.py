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

from enum import Enum


class OS(Enum):
    """Defines properties of OS types.
    Enumeration names are exact matches for the platform targets reported by
    the database.\n
    Tuple values are as follows, with explanation:\n
    [1] OS name/version pair values that are read and accepted by the blacklist.
    This is what is written to BLACKLIST files.\n
    [2] The family os OSs the target belongs to. This is used when checking how
    many of a given OS family are currently failing.\n
    [3] "canBe" list. This list describes which platforms apply to a given OS target.
    This is used when determining which oses should be included under platform terms
    such as "xcb"\n
    [4] The general platform term used to describe the OS, such as "linux", "osx", or "windows"
    """
    openSUSE_15_0 = ("opensuse-leap", "suse",
                     ["*", "linux", "xcb", "wayland", "openwfd", "directfb", "minimal"], "linux")
    openSUSE_42_3 = ("opensuse-42.3", "suse",
                     ["*", "linux", "xcb", "wayland", "openwfd", "directfb", "minimal"], "linux")
    SLES_15 = ("sles-15.0", "suse", ["*", "linux", "xcb",
                                     "wayland", "openwfd", "directfb", "minimal"], "linux")
    SLED_15 = ("sled-15.0", "suse",
               ["*", "linux", "xcb", "wayland", "openwfd", "minimal"], "linux")
    Ubuntu_16_04 = ("ubuntu-16.04", "ubuntu", ["*", "linux", "ubuntu",
                                               "xcb", "directfb", "wayland", "openwfd", "minimal"], "linux")
    Ubuntu_18_04 = ("ubuntu-18.04", "ubuntu", ["*", "linux", "ubuntu",
                                               "xcb", "directfb", "wayland", "openwfd", "minimal"], "linux")
    RHEL_6_6 = ("rhel-6.6", "rhel", ["*", "linux", "rhel", "xcb",
                                     "wayland", "directfb", "openwfd", "minimal"], "linux")
    RHEL_7_4 = ("rhel-7.4", "rhel", ["*", "linux", "rhel", "xcb",
                                     "wayland", "directfb", "openwfd", "minimal"], "linux")
    RHEL_7_6 = ("rhel-7.6", "rhel", ["*", "linux", "rhel", "xcb",
                                     "wayland", "directfb", "openwfd", "minimal"], "linux")
    OSX_10_11 = ("osx-10.11", "osx",
                 ["*", "osx", "cocoa", "directfb", "minimal", "offscreen"], "osx")
    MacOS_10_12 = ("osx-10.12", "osx",
                   ["*", "osx", "cocoa", "directfb", "minimal", "offscreen"], "osx")
    MacOS_10_13 = ("osx-10.13", "osx",
                   ["*", "osx", "cocoa", "directfb", "minimal", "offscreen"], "osx")
    MacOS_10_14 = ("osx-10.14", "osx",
                   ["*", "osx", "cocoa", "directfb", "minimal", "offscreen"], "osx")
    Windows_7 = ("windows-7sp1", "windows-7sp1",
                 ["*", "windows", "windows-7", "kms", "minimal", "offscreen"], "windows")
    Windows_10 = ("windows-10", "windows-10",
                  ["*", "windows", "windows-10", "kms", "minimal", "offscreen"], "windows")
    WinRT_10 = ("winrt", "winrt", [
                "*", "windows", "winrt", "kms", "minimal", "offscreen"], "windows")
    Android_ANY = ("android", "android", [
                   "*", "linuxfb", "eglfs", "directfb", "openwfd", "minimal"], "android")
    QEMU = ("b2qt", "b2qt", ["*", "linuxfb",
                             "eglfs", "directfb", "minimal"], "b2qt")

    def __init__(self, normalizedValue: str, osFamily: str, canBe: list, isOfType: str):
        """Make the tuple values named so the can be retrieved with a
        simple accessor like OS.RHEL_7_4.normalizedValue"""
        self.normalizedValue = normalizedValue
        self.osFamily = osFamily
        self.canBe = canBe
        self.isOfType = isOfType

    @classmethod
    def count(cls, typeRequested: str) -> int:
        count = 0
        for entry in cls:
            if entry.isOfType == typeRequested or typeRequested in entry.normalizedValue:
                count += 1

        return count

    @classmethod
    def getFamily(cls, normalizedValue: str) -> str:
        for entry in cls:
            if entry.normalizedValue == normalizedValue:
                return entry.osFamily
        return ""

    @classmethod
    def getType(cls, normalizedValue: str) -> str:
        for entry in cls:
            if entry.normalizedValue == normalizedValue:
                return entry.isOfType
        return ""

    @classmethod
    def getCanBe(cls, normalizedValue: str) -> list:
        for entry in cls:
            if entry.normalizedValue == normalizedValue:
                return entry.canBe
        return []

    @classmethod
    def getFamilyMembers(cls, familyName: str) -> list:
        return [entry.normalizedValue for entry in cls if (entry.osFamily == familyName or
                                                           familyName == '*')]

    @classmethod
    def getTypeMembers(cls, typeName: str) -> list:
        return [entry.normalizedValue for entry in cls if (entry.isOfType == typeName or
                                                           typeName == '*')]


class COMPILER(Enum):
    """Mainly used when determining MSVC compilers
    to blacklist."""
    GCC = "gcc"
    Clang = "clang"
    Mingw73 = "mingw-7.3"
    MSVC2015 = "msvc-2015"
    MSVC2017 = "msvc-2017"
    MSVC2019 = "msvc-2019"

    @classmethod
    def getNormalizedValue(cls, requestName: str) -> str:
        for entry in cls:
            if entry.name == requestName:
                return entry.value
            elif entry.value == requestName:
                return entry.value
        return ""

    @classmethod
    def isCompiler(cls, requestName: str) -> bool:
        for entry in cls:
            if requestName == entry.value:
                return True
        return False


class PLATFORM(Enum):
    """Defines properties of PLATFORM types.
    Tuple values are as follows, with explanation:\n
    [1] Platform name values that are read and accepted by the blacklist.
    This is what is written to BLACKLIST files.\n
    [2] "canBe" list. This list describes which platforms apply to a given OS target.
    This is used when determining which oses should be included under platform terms
    such as "xcb"\n
    [3] Describes the base OS type if the platform itself describes some version or
    distribution of an OS.\n
    [4] Denotes if the platform type is a base type that cannot be whitelisted, such as linux,
    windows, or osx.\n
    General platform names that are acceptable in blacklists can be found at
    https://doc.qt.io/qt-5/qguiapplication.html#platformName-prop
    \n
    The canBe values show relations so the tool can blacklist
    platforms with exceptions such as "xcb !ubuntu"""

    ALL = ("*", [], "", True)
    ANDROID = ("android", ["eglfs", "linuxfb", "directfb",
                           "minimal", "offscreen", "linux", "*"], "", False)
    COCOA = ("cocoa", ["osx", "directfb", "minimal",
                       "directfb", "offscreen", "*"], "", False)
    # QSysInfo::ProductType() returns "osx" for all macOS systems,
    # regardless of Apple naming convention
    OSX = ("osx", ["directfb", "minimal", "directfb",
                   "offscreen", "*"], "osx", True)
    DIRECTFB = ("directfb", ["osx", "android", "cocoa",
                             "qnx", "linux", "rhel", "ubuntu", "*"], "", False)
    EGLFS = ("eglfs", ["android", "ios", "qnx", "windows",
                       "windows_10", "linux", "rhel", "ubuntu", "*"], "", False)
    IOS = ("ios", ["*"], "ios", True)
    KMS = ("kms", ["windows", "windows-10", "*"], "", False)
    LINUXFB = ("linuxfb", ["linux", "rhel", "ubuntu",
                           "windows", "windows-10", "osx", "*"], "", False)
    MINIMAL = ("minimal", ["linux", "rhel", "ubuntu",
                           "windows", "windows-10", "osx", "*"], "", False)
    OFFSCREEN = ("offscreen", ["osx", "android", "cocoa", "ios", "qnx",
                               "windows", "windows_10", "linux", "rhel", "ubuntu", "*"], "", False)
    OPENWFD = ("openwfd", ["osx", "android", "cocoa", "ios", "qnx",
                           "windows", "windows_10", "linux", "rhel", "ubuntu", "*"], "", False)
    QNX = ("qnx", ["*"], "", True)
    WINDOWS = ("windows", ["kms", "minimal", "*"], "windows", True)
    WINDOWS_10 = ("windows-10", ["kms", "windows",
                                 "minimal", "offscreen", "*"], "windows", False)
    WAYLAND = ("wayland", ["linux", "rhel", "ubuntu", "*"], "", False)
    XCB = ("xcb", ["linux", "rhel", "ubuntu", "*"], "", False)
    LINUX = ("linux", ["*", "eglfs", "directfb", "linuxfb",
                       "offscreen", "minimal", "xcb"], "linux", True)
    RHEL = ("rhel", ["linux", "directfb", "eglfs", "linuxfb",
                     "minimal", "offscreen", "openwfd", "xcb", "*"], "linux", False)
    UBUNTU = ("ubuntu", ["linux", "directfb", "eglfs", "linuxfb",
                         "minimal", "offscreen", "openwfd", "xcb", "*"], "linux", False)

    def __init__(self, normalizedValue: str, canBe: list, osFamily: str, isRootType: bool):
        self.normalizedValue = normalizedValue
        self.canBe = canBe
        self.osFamily = osFamily
        self.isRootType = isRootType

    @classmethod
    def getNormalizedValue(cls, requestName: str) -> str:
        for entry in cls:
            if entry.name == requestName:
                return entry.normalizedValue
            elif entry.normalizedValue == requestName:
                return entry.normalizedValue
        return ""

    @classmethod
    def getCanBe(cls, normalizedValue: str) -> list:
        if normalizedValue == '*':
            return [x.normalizedValue for x in cls if x.normalizedValue != '*']
        else:
            for entry in cls:
                if entry.normalizedValue == normalizedValue:
                    return entry.canBe
        return []

    @classmethod
    def getFamily(cls, normalizedValue: str) -> str:
        for entry in cls:
            if entry.normalizedValue == normalizedValue:
                return entry.osFamily
        return ""

    @classmethod
    def getIsRootType(cls, normalizedValue: str) -> bool:
        for entry in cls:
            if entry.normalizedValue == normalizedValue:
                return entry.isRootType
        return False
