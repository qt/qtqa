QMLBenchrunner
==============
QMLBenchrunner is a simple script and python application to programmatically
clone a Qt Git repository, run associated QML Benchmark tests, and post
results to the qt testresults timeseries database.


Prerequisites
-------------
- Python3
    - 'requests' module

Windows-specific Prerequisites:
* ActivePerl - Download and install from http://www.activestate.com/Products/activeperl/index.mhtml
* GPerf - Download and install from http://gnuwin32.sourceforge.net/downlinks/gperf.php
* (Qt 5.x) Flex & Bison for windows - Included with qmlbenchrunner, or downloadable from
    http://sourceforge.net/projects/winflexbison/files/win_flex_bison-2.5.5.zip/download
    If Win Flex-Bison is downloaded, you must rename the executables to "flex.exe" and "bison.exe"
    and specify the location of your flex-bison executables using the powershell parameter specified
    in the parameters section below.
* VS Build Tools 2019 (VS 2017 is supported for Qt 5.x) - https://visualstudio.microsoft.com/downloads/
* JOM - A version is included with qmlbenchrunner. If a new version is required, it can be found at
    https://wiki.qt.io/Jom
* (Optional) IncrediBuild - https://www.incredibuild.com/


Usage
-----
QMLBenchrunner will clone copies of required Qt Git repositories as well as qmlbench into the working directory.
Is is best practice to run qmlbenchrunner from a parent directory so that the cloned repos are not
cloned into the qmlbenchrunner directory directly. See the examples below.

Always set environment variables INFLUXDBUSER and INFLUXDBPASSWORD in the console before calling the build_and_test
script. Results will still be saved to disk in "results.json" even if unable to write to the database.

Optional environment variables:

        INFLUXDBUSER=username #Set if writing to a database.
        INFLUXDBPASSWORD=password #Set if writing to a database.
        BADTESTS=/path/to/bad/test #Specify a space-separated list of known bad tests or directories
            that are too difficult for the client to complete and would cause a crash.
        EXTRA_CONFIGURE_ARGS="string of additional Configure arguments"

### Linux: ###
Some machines may require XAUTHORITY to be specified. If problems are encountered, set XAUTHORITY
and DISPLAY in the console before running this script.

**build_and_test.sh arguments are strictly positional. Do not skip arguments that are required.**

    Args:
        QtVersion (required) | MachineName (required) | BuildCores (required) |
        Annotate (required, set to "False" if not desired) |
        QtDeclarativeVersion (optional, leave missing if same as main QtVersion)

    Example:
        export INFLUXDBUSER=dbuser1
        export INFLUXDBPASSWORD=dbuser1password
        export XAUTHORITY=/home/user1/.Xauthority
        export DISPLAY=:0
        qmlbenchrunner/build_and_test.sh 5.15 $NODE_NAME 8 annotate

### Windows: ###
Qmlbenchrunner should be executed from Powershell for best compatibility. Because QMLBench is a
graphical application, if qmlbenchrunner is being executed via a jenkins slave, the slave must use
the java web start method. Running jenkins as a Windows service will not display QMLBench on the
real user desktop.

    Args:
        QtVersion (Required)
        MachineName (Required)
        BuildCores (Optional)
        Annotate (Optional)
        QtDeclarativeVersion (Optional)
        FlexBisonDir = (Optional, defaults to "[current working directory]\flex_bison\" if omitted)

    Example:
        $env:INFLUXDBUSER=dbuser1
        $env:INFLUXDBPASSWORD=dbuser1password
        $env:BADTESTS=""
        .\qmlbenchrunner\build_and_test_windows.ps1 -QtVersion 5.15 -BuildCores 7 -MachineName
            $ENV:NODE_NAME -FlexBisonDir C:\flex_bison -Annotate

### macOS: ###
See instructions for Linux. Some trouble has been observed with Jenkins macOS clients not setting
PATH correctly. If you experience issues when submitting results to a database, make sure that
Python3 is set in the PATH environment variable used by Jenkins scripts.

    Example:
        export PATH+=:/Library/Frameworks/Python.framework/Versions/3.6/bin/
        qmlbenchrunner/build_and_test.sh dev $NODE_NAME 6 annotate

### Embedded ###
The build_and_test_embedded.sh script is intended to be used with a Jenkins host, but can be used
on it' own. The script file will need to be modified based on your specific environment as detailed
below.

Terminology for this section:
* Host - The machine this script will run on.
* Client - The target embedded device that will execute QMLBench.

    Assumptions:
    1) The host is configured for cross-compilation to a given target device.
    2) An official Boot2Qt SDK is installed on the host.
    3) The target embedded device (client) is accessible via SSH over a local network by IP and the
        host has connected to it at least once.
    4) The host is accessible via ssh over a local network by IP and the host's ssh configuration is configured to accept connections from the client.

    Required script alterations:
    1) Update the sysrootDir with your Boot2Qt version number.
    2) Update the user and IP of the host in order to pass the results.json file back from the
        client.

    Qt5 Required host configuration (customize for your target device):

        DEVMKSPEC=linux-imx6-g++
        DEVNAME=apalis-imx6
        CROSSCOMPILE=x86_64-pokysdk-linux/usr/bin/arm-poky-linux-gnueabi/arm-poky-linux-gnueabi-
        ARMSYSROOT=cortexa9hf-neon-poky-linux-gnueabi
        DEVIP=IP of the target device to execute the tests on.

    Qt6 Required host configuration:
        CMAKE_GENERATOR="Unix Makefiles"
        LB_TOOLCHAIN: Full path of the Boot2Qt sdk toolchain to use when cross-compiling.
        TOOLCHAIN_FILE: Full path of the cmake toolchain file to use when cross-compiling.
        DEVIP: IP of the target device to execute the tests on.

    Running the script:

    **build_and_test_embedded_[qt5|qt6].sh arguments are strictly positional. Do not skip arguments that are
    required.**

        Args:
            QtVersion (required) | MachineName (required) | BuildCores (required for qt5, omit in qt6) |
            Annotate (required, set to "False" if not desired) |
            QtDeclarativeVersion (optional, leave missing if same as main QtVersion)

    qmlbenchrunner/build_and_test_embedded.sh 5.15 $NODE_NAME 8 annotate

    Required client configuration:
    1) Verify that at least 1GB of free space exists on the client.

    NB! This script will wipe out /opt/qt on the device. Verify that this directory does not
    contain anything you want to keep.
