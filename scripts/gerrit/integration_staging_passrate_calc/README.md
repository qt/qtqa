# Introduction
This script is designed to scan gerrit comments and extract statistics
regarding change restaging and merging.

The script breaks down results from gerrit by repo and branch.

Example output:
  ```
Processing changes in: qt/qtbase
Running: "https://codereview.qt-project.org/a/changes/?q=repo:qt/qtbase+status:merged+-owner:qt_submodule_update_bot@qt-project.org+-age:1days+age:0s&no-limit"
processing 56 changes
Processing 1 of 56 qt%2Fqtbase~dev~I419a5521dd0be7676fbb09b34b4069d4a76423b1

...

Branch: dev
Merged changes: 25
Count of integration failures: 16
Highest restage count: 2
Average restage count: 1.6
Changes integrated without restaging: 15
Count of staging cancellations due to staging branch conflicts (not failed): 0
Percentage of changes requiring restage: 40.0 %

Branch: 6.1
Merged changes: 18
Count of integration failures: 7
Highest restage count: 2
Average restage count: 1.75
Changes integrated without restaging: 14
Count of staging cancellations due to staging branch conflicts (not failed): 0
Percentage of changes requiring restage: 22.2 %
```

# Configuration
1. Modify the included `config.json.template` as necessary and rename to `config.json`
    - Any of the values of config.json can also be overridden via environment variables.

# Usage
Provided no arguments, the script will perform two operations:
1. Collect statistics on submodule updates performed by `qt_submodule_update_bot@qt-project.org`
   over the last 24 hours.
    - Gerrit query: `owner:qt_submodule_update_bot@qt-project.org+status:merged+-age:1days+age:0seconds&no-limit`
2. Collect statistics on submodules of qt5 in the dev branch over the last 24 hours.
    - Gerrit query (executed per-module): `repo:qt/qtbase+status:merged+-owner:qt_submodule_update_bot@qt-project.org+-age:1days+age:0seconds&no-limit`



```
usage: gather_stats.py [-h] [--writeDB] [--branch BRANCH] [--repos CUSTOM_REPOLIST] [--ageafter AGEFROM] [--agebefore AGEUNTIL] [--query CUSTOM_QUERY]

optional arguments:
  -h, --help            show this help message and exit
  --writeDB             Write results to the database. Leave unset to only print results to screen. Use with caution!
  --branch BRANCH       Branch of qt5.git to examine for module list.
  --repos CUSTOM_REPOLIST
                        Comma-separated list of fully scoped repos. Overwrites the default set of qt5 repos.
  --ageafter AGEFROM    Relative start of the time range to examine. Default: 1days
  --agebefore AGEUNTIL  Relative end of the time range to examine. Default: {now}
  --query CUSTOM_QUERY  Run only a custom query. Enclose desired query in quotes. Do not escape special characters. Exclusive - Cannot be combined with other parameters.
```
