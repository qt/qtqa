#!/usr/bin/env python3
# Copyright (C) 2021 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

import os
import sys
import subprocess
import logging
import requests
import json
import platform

HOSTNAME = "testresults.qt.io/influxdb"

def submit_output(output, branch, hardwareId):
    tree = json.loads(output)
    for key in tree:
        if key.endswith(".qml"):
            mean = 0
            standardDeviation = 0
            coefficientOfVariation = 0

            # key is foo/bar/benchmarks/auto/<important_thing_here>/stuff.qml
            # dirname will trim off the last part, leaving us
            # foo/bar/benchmarks/auto/<important_thing_here>
            benchmarkSuite = os.path.dirname(key)

            # now cut off everything before <important_thing_here>.
            cutPos = benchmarkSuite.find("/benchmarks/auto/")
            benchmarkSuite = benchmarkSuite[cutPos + len("/benchmarks/auto/"):]

            try:
                mean = tree[key]["average"]
                standardDeviation = tree[key]["standard-deviation-all-samples"]
                coefficientOfVariation = tree[key]["coefficient-of-variation"]
            except:
                # probably means that the test didn't run properly.
                # (empty object). record it anyway, so it shows up,
                # and catch the exception so that other test results
                # are recorded.
                print("Test %s was malformed (empty run?)" % key)
                pass

            basename = key.split("/")[-1]
            tags = ('branch=' + branch, 'benchmark=' + basename, 'hardwareId=' + hardwareId, 'suite=' + benchmarkSuite)
            fields = ('mean=' + str(mean),
                      'coefficientOfVariation=' + str(coefficientOfVariation),
                      )

            data = 'benchmarks,%s %s' % (','.join(tags), ','.join(fields))
            result = requests.post("https://%s/write?db=qmlbench" % HOSTNAME,
                                   auth=requests.auth.HTTPBasicAuth(os.environ["INFLUXDBUSER"], os.environ["INFLUXDBPASSWORD"]),
                                   data=data.encode('utf-8'))
            print(data)
            print(result)

def run_benchmark(filename, branch, hardwareId):
    print("Loading %s" % filename)
    if (platform.system() == 'Windows'):
        output = subprocess.check_output(["Powershell.exe", "type", filename])
    else:
        output = subprocess.check_output(["cat", filename])
    submit_output(output.decode("utf-8"), branch, hardwareId)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("filename", help = "The .json file to post")
    parser.add_argument("branch", help = "The Qt branch tested")
    parser.add_argument("hardwareId", help = "Our unique hardware ID (e.g. linux_imx6_eskil)")
    args = parser.parse_args(sys.argv[1:])
    print("Posting results: " + args.filename)
    run_benchmark(args.filename, args.branch, args.hardwareId)
