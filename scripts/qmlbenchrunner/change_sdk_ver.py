#!/usr/bin/env python3
# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

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
