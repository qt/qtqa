#!/usr/bin/env python3
#############################################################################
##
## Copyright (C) 2021 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the qtqa module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU Lesser General Public License Usage
## Alternatively, this file may be used under the terms of the GNU Lesser
## General Public License version 3 as published by the Free Software
## Foundation and appearing in the file LICENSE.LGPL3 included in the
## packaging of this file. Please review the following information to
## ensure the GNU Lesser General Public License version 3 requirements
## will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 2.0 or (at your option) the GNU General
## Public license version 3 or any later version approved by the KDE Free
## Qt Foundation. The licenses are as published by the Free Software
## Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-2.0.html and
## https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################

import os
import sys
import re

cmake_ver = ""

with open("qtbase/.cmake.conf") as cmake:
    for line in cmake.readlines():
        if line.startswith("set(QT_REPO_MODULE_VERSION"):
            cmake_ver = re.match(".+(\d.\d+.\d+)", line).groups()[0]


for root, dirs, files in os.walk(os.path.expanduser(os.environ.get("LB_TOOLCHAIN"))):
    for name in files:
        with open(os.path.join(root, name), mode='r+') as f:
            start = f.read().find("set(PACKAGE_VERSION")
            if start < 0:
                continue
            f.seek(start)
            end = f.read().find("\n")
            f.seek(start)
            toWrite = f"set(PACKAGE_VERSION \"{cmake_ver}\")"
            if len(toWrite) == end:
                f.write(toWrite)
                print(f"Wrote '{toWrite}' to {os.path.join(root, name)}")
            else:
                print(f"Writing to {os.path.join(root, name)} would cause corruption.")
                print(f.read()[start:start+end])
