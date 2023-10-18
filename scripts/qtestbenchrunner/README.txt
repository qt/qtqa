--------------------------
  QTest Benchmark Runner
--------------------------
A benchmark runner that runs the QTest benchmarks in the QtBase repository.

It fetches Git revisions from a server, checks them out, runs the benchmarks, and uploads results to
a database.

-----------------------
  Starting the runner
-----------------------
First you must prepare a Python environment. The minimum version required is 3.10, since some new
features are used.

    python3 -m venv venv
    . venv/bin/activate
    pip install -r requirements.txt

The runner also needs some system privileges. It will use these to tune system performance and
reduce noise in the benchmark results. A makefile script is used to apply the changes and the
computer must be rebooted for the changes to take effect. Note that performance tuning is only
supported on machines with a Linux OS and an Intel processor. If you wish to start the runner on a
different machine, you can skip this step and start it with --skip-tuning. This will disable
performance tuning and prevent any use of the privileges.

    make install
    # reboot

The runner needs SSH credentials to access the Git repository. These must be set up in the ~/.ssh
directory. Probably you will already have them set up, but if you don't, add them according to
the steps on the wiki.

    https://wiki.qt.io/Setting_up_Gerrit

The final step is to fill out any empty fields in config.json. This file contains connection details
that the runner will use to connect to the server that provides Git revisions, the database, and the
QtBase Git repository.

    # edit config.json

Now you should be ready to start the runner:

    python3 runner.py --configuration config.json --output output
    python3 runner.py --help

If you are making any changes to the source files, you might want to run checkers, tests, and code
formatters. This is a quick way to catch bugs and keep the code tidy.

    # checkers and tests
    mypy
    flake8
    python3 -m unittest

    # code formatters
    black .
    isort .
