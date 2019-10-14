# Easy Blacklist Maintenance Tool

### Requirements
1. Python 3
2. COIN database read access (testresults.qt.io)
3. Python modules:
    1. argparse
    2. influxdb
    3. prettytable
    4. PyInquirer

### Usage
#### Example:
`python3 blacklistTool.py --qt5dir ~/qt5/ --interactive`

#### Parameters:
[Required] `--qt5dir <path to directory of a qt5 checkout or a single submodule inside qt5>`

[Optional] `--interactive` Enables interactive mode

[Optional] `--fastForward <testName>` Runs queries for blacklisted tests as usual, but fast forwards
the script to the specified test name.
[Optional] `--printActivePlatforms` Print out active platforms on startup.

#### Optional Environment variables
`INFLUX_DB_URL` The hostname where the coin database resides. Defaults to 'testresults.qt.io'
`INFLUX_DB_PORT` The port to connect to influxdb with. SSL is required. Defaults to port 443
`INFLUX_DB_USER` The username used to login to the COIN database
`INFLUX_DB_PASSWORD` The password used to login to the COIN database

#### Notes
- **Interactive mode:** This is the recommended mode of operation. You will be given
a chance to enter your database username and password manually, as well as edit
the query used to retrieve blacklisted tests.
- **Automatic mode:** If a testname is found but is only a partial match, f.ex.
`[tryAcquireWithTimeout:0.2s]` versus `[tryAcquireWithTimeout]`, a report of the
mismatch will be printed upon completion of the script.
**Interactive mode** you'll be asked what to do `(edit existing, replace, or delete)`.
- **All modes:** When a test is an exact match, and has had 0 failures on any platforms in
the past 60 days (default period), the test will be removed completely from the blacklist.
- **All modes:** If a test is deleted from the blacklist and no tests remain in it, the
BLACKLIST file will be deleted.
- **All modes:** If a blacklist item's failing configurations is unchanged, but the original
 file contains trailing newlines, it may be rewritten to remove the newlines.
