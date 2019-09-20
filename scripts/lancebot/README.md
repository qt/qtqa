# Lancebot Usage Guide

### Overview
lancebot.py is designed to automate graphical testing of qtbase and
qtdeclarative functions. These tests require a real renderer and
cannot be used on headless systems.

Lancebot relies on environment variables and takes no command line parameters.

The script has two modes:
1. HEAD/nightly testing
2. Change testing

### Prerequisites
1. Python 3.5+
    - Packaging:  `pip install packaging`

#### Linux Prerequisites
1. Package "build-essential"
2. Qt for X11 recommended packages, [maintained here](http://doc.qt.io/qt-5/linux-requirements.html)

#### Windows Prerequisites
1. ActivePerl [3rd Party Download](https://www.activestate.com/products/activeperl/)
2. GPerf [3rd Party Download](http://gnuwin32.sourceforge.net/downlinks/gperf.php)
3. Visual Studio 2015+ or [Build Tools for Visual Studio](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2017)
4. JOM [Download from Qt](https://wiki.qt.io/Jom)
4. Flex & Bison latest release [3rd Party Download](https://github.com/lexxmark/winflexbison)
    - **(Required)** Rename the executables to flex.exe and bison.exe

#### Global required environment variables
- `WORKSPACE`: directory where reference and test builds will be
    compiled.
- `VS_DEV_ENV`: {Windows Only} Specify the full file path to
    VsDevCmd.bat. Part of a Visual Studio or VS Build Tools
    installation.
- `LANCELOT_PROJECT`: Specify the project to be used when connecting
    to the lancelot server. Defaults to Raster, Scenegraph, or
    Other based on the test executable being run.
- `GERRIT_PROJECT`: The project for where to access repos. Typically
    set to "qt/qtbase"

#### Global Optional variables
- `GIT_USER`: Specify a name for "git config --global user.name"
  - Only required if no global name is currently set.
  - Defaults to "Your Name"
- `GIT_Email`: Specify an email for "git config --global user.email"
  - Only required if no global email is currently set.
  - Defaults to "you@example.com"
- `GIT_CLONE_REF_DIR`: An exising directory with qtbase and
    qtdeclarative repos. Defaults to ~/qt5/
- `LB_REBUILD`: when set to true, forces a full rebuild of all repos.
- `BUILD_CORES`: Number of CPUs to use when compiling. Default: 8
- `LANCELOT_CONFIGURE_OPTIONS`: Additional configure options to be
    passed when configuring QtBase
- `QT_LANCELOT_SERVER`: hostname of the lancelot server. Defaults to
    The Qt Company's internal server.
- `LANCELOT_FAKE_MISMATCH`: Set to true to force mismatches in the
    test for testing purposes.
- `BUILD_TAG`: Specify a custom tag to identify this build in the
    Lancelot report. Typically used with a build system like
    Jenkins.
- `Build_URL`: Specify a custom URL to display in the lancelot
    report to link to this build in your build system.
- `GERRIT_CHANGE_URL`: Specify the gerrit URL of the change to
    display in the lancelot report.
- `GERRIT_CHANGE_SUBJECT`: Specify the gerrit change subject to
    display on the lancelot report.
- `GERRIT_PATCHSET_NUMBER`: Specify the gerrit change patchset number
    to display on the lancelot report.

#### Windows Optional variables
- `FLEX_BISON_DIR`: Specify the absolute path to a directory containing `flex.exe` and `bison.exe`
    - Flex and Bison are otherwise assumed to be in PATH. Setting this variable prepends PATH.
    - Fallback search directory is `$WORKSPACE/flex_bison/`
- `JOM_PATH`: Specify the absolute path to `JOM.exe`
    - JOM is otherwise assumed to be in PATH. Setting this variable prepends PATH.
    - Fallback search directory is `$WORKSPACE/JOM/`

#### HEAD/nightly test mode
- `BRANCH`: The branch of Qt to test such as "5.12" or "dev"
    - Note: Exclusive with GERRIT_BRANCH.

#### Change test mode
- `GERRIT_BRANCH`: {Required} The branch of Qt to test such as
    "5.12" or "dev"
    - Note: Exclusive with BRANCH
- `GERRIT_REFSPEC`: {Required} The Change to test, usually formatted
    as "refs/changes/98/246598/2"
- `GERRIT_EVENT_TYPE`: {Required} Set to "patchtest" to use this
    test mode.

### Running the lancelot.py script
1. Set The required environment variables as outlined above. (Works great with the Gerrit Trigger Jenkins plug-in)
2. Clone the lancelot repo to a directory.
3. Run lancelot.py

### Other information
- Lancelot testing requires a "baseline server".
    - The baseline server code resides in qtbase/tests/baselineserver and is designed for use on a linux host.
    - Set QT_LANCELOT_SERVER as above to connect to a custom server.
- This script executes two tests:
    - qtbase/tests/auto/other/lancelot
    - qtdeclarative/tests/manual/scenegraph_lancelot
