#!/usr/bin/env python3
# Copyright (C) 2020 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

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


