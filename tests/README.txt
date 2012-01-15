This directory contains autotests which can be applied over any Qt5 module.

The tests are separated into two categories, "prebuild" and "postbuild".
Prebuild tests are run before Qt is built, and generally consist of static
code checks (e.g. coding style or license header checks).
Postbuild tests are run after Qt is built, and may perform tests on the
Qt binaries themselves (e.g. binary compatibility tests).

The autotests must abide by the following conventions:

  - tests must be executable by `make check' and should respect the
    TESTRUNNER and TESTARGS variables where possible.

  - tests may read the path to the current module's source/build tree
    from the QT_MODULE_TO_TEST environment variable (note: shadow builds
    are currently not supported).

  - prebuild tests must not use any Qt libraries (e.g. they may be shell
    or perl scripts, but may not be QTestLib C++ tests).  They may use
    qmake (in which case they should do CONFIG-=qt to avoid some warnings).

  - prebuild tests should use 'git ls-files' to determine the list of
    source files in the tested module.

  - postbuild tests may use QTestLib and any other Qt libraries from
    qtbase.  Libraries from other qt gitmodules are not guaranteed to
    be present.
