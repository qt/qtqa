############################################################################
##
## Copyright (C) 2019 The Qt Company Ltd.
## Contact: https://www.qt.io/licensing/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:GPL-EXCEPT$
## Commercial License Usage
## Licensees holding valid commercial Qt licenses may use this file in
## accordance with the commercial license agreement provided with the
## Software or, alternatively, in accordance with the terms contained in
## a written agreement between you and The Qt Company. For licensing terms
## and conditions see https://www.qt.io/terms-conditions. For further
## information use the contact form at https://www.qt.io/contact-us.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU
## General Public License version 3 as published by the Free Software
## Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
## included in the packaging of this file. Please review the following
## information to ensure the GNU General Public License requirements will
## be met: https://www.gnu.org/licenses/gpl-3.0.html.
##
## $QT_END_LICENSE$
##
#############################################################################

import re
import subprocess
import sys

usage = """
Usage:  parse_build_log.py [log_file]

Parses the output of COIN test runs and prints short summaries of compile
errors and test fails for usage as gerrit comment. Takes the file name
(either text or compressed .gz file). The zcat tool is required for
decompressing .gz files.
"""

# Match the log prefix "agent:2019/06/04 12:32:54 agent.go:262:"
prefix_re = re.compile(r'^agent:[\d :/]+\w+\.go:\d+: ')

# Match QTestlib output
start_test_re = re.compile(r'^\*{9} Start testing of \w+ \*{9}$')
end_test_re = re.compile(r'Totals: \d+ passed, (\d+) failed, \d+ skipped, \d+ blacklisted, \d+ms')
make_error_re = re.compile(r'make\[.*Error \d+$')


def read_file(file_name):
    """
    Read a text file into a list of of chopped lines.
    """
    with open(file_name) as f:
        return [prefix_re.sub('', l.rstrip()) for l in f.readlines()]


def zcat(file_name):
    """
    Read a gzip'ed text file into a list of of chopped lines by means of
    'zcat'. Note: Python's zipfile module cannot handle .gz
    """
    lines = []

    try:
        std_out = subprocess.Popen(['zcat', file_name],
                                   universal_newlines=1,
                                   stdout=subprocess.PIPE).stdout
        for line in std_out.readlines():
            lines.append(prefix_re.sub('', line.rstrip()))
        std_out.close()
    except FileNotFoundError:
        print("ERROR: command 'zcat' not found")
        sys.exit(-1)
    return lines


def is_compile_error(line):
    """
    Return whether a line is an error from one of the common compilers
    (g++, MSVC, Python) or from make
    """
    if any(e in line for e in (": error: ", ": error C", 'ERROR')):
        return True
    return make_error_re.match(line)


def print_failed_test(lines, start, end):
    """
    For a failed test, print 3 lines following the FAIL!/XPASS and
    header/footer.
    """
    last_fail = -50
    # Print 3 lines after a failure
    print('\n{}: {}'.format(start, lines[start]))
    for i in range(start + 1, end):
        line = lines[i]
        if 'FAIL!' in line or 'XPASS' in line:
            last_fail = i
        if i - last_fail < 4:
            print(line)
    print('{}\n'.format(lines[end]))


def parse(lines):
    """
    Parse the output and print compile/test errors.
    """
    test_start_line = -1
    within_configure_tests = False
    for i, line in enumerate(lines):
        if within_configure_tests:
            if line == 'Done running configuration tests.':
                within_configure_tests = False
        elif test_start_line >= 0:
            end_match = end_test_re.match(line)
            if end_match:
                fails = int(end_match.group(1))
                if fails:
                    print_failed_test(lines, test_start_line, i)
                test_start_line = -1
        # Do not report errors within configuration tests
        elif line == 'Running configuration tests...':
            within_configure_tests = True
        elif start_test_re.match(line):
            test_start_line = i
        elif is_compile_error(line):
            start = max(0, i - 10)
            sys.stdout.write('\n{}: '.format(start))
            for e in range(start, i + 1):
                print(lines[e])


if __name__ == '__main__':
    if sys.version_info[0] != 3:
        print("This script requires Python 3")
        sys.exit(-2)
    if len(sys.argv) < 2:
        print(usage)
        sys.exit(-1)
    file_name = sys.argv[1]

    lines = zcat(file_name) if file_name.endswith('.gz') else read_file(file_name)
    parse(lines)
