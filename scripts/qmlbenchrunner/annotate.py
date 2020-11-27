#!/usr/bin/env python3
#############################################################################
##
## Copyright (C) 2020 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the build configuration tools of the Qt Toolkit.
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
import subprocess
import logging
import requests
import json

#HOSTNAME = "10.213.255.45:8086"
#HOSTNAME = "localhost:8086"
HOSTNAME = "testresults.qt.io:443/influxdb"

def post_annotation(title, text, tag, branch):
    # TODO: we could consider splitting tag on , and inserting multiple annotations
    # this is required, unfortunately, as Grafana's InfluxDB source requires that you
    # fetch tags from multiple fields rather than turning a single field into
    # multiple tags..
    fields = ('title=\"%s\"' % title,
              'text=\"%s\"' % text,
              'tagText=\"%s\"' % tag,
              'branch=\"%s\"' % branch,
              )
    data = 'annotations %s' % (','.join(fields))
    result = requests.post("https://%s/write?db=qmlbench" % HOSTNAME,
                           auth=requests.auth.HTTPBasicAuth(os.environ["INFLUXDBUSER"], os.environ["INFLUXDBPASSWORD"]),
                           data=data.encode('utf-8'))

    print(data)
    print(result)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", help="title of the annotation (e.g. --title=\"qtbase update\")")
    parser.add_argument("--tag", help="a tag for the annotation")
    parser.add_argument("--text", help="text for the annotation")
    parser.add_argument("--branch", help="the branch the annotation is relevant to (e.g. 5.6, dev")
    args = parser.parse_args(sys.argv[1:])
    print("Adding annotation: " + args.title)
    post_annotation(args.title, args.text, args.tag, args.branch)


