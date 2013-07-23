TEMPLATE = subdirs

testcase.timeout = 1200 # slow because we are running many autotests

# Override `make check' to run our script which knows how to test our perl
# scripts.  This requires a modern-ish CPAN setup, so we will enable it only
# for platforms as we test it.
win32|mac|linux* {
    check.commands = $(TESTRUNNER) perl $$_PRO_FILE_PWD_/test.pl
}
linux* {
    # On Linux, we can do a --clean test, which will verify that all needed CPAN
    # modules can be installed in a "clean" environment. This is possible because
    # we expect local::lib to be installed system-wide on Linux.
    #
    # We can't do this on e.g. Mac, because local::lib is expected to be installed
    # from CPAN on that platform, so a --clean test will wipe out local::lib and
    # leave us unable to install anything.
    check.commands = $$check.commands --clean
}

linux-*:system(". /etc/lsb-release && [ $DISTRIB_CODENAME = precise ]"):CONFIG+=insignificant_test # QTQAINFRA-708

# There are deliberately no SUBDIRS, this project should do nothing except
# override `check'
QMAKE_EXTRA_TARGETS += check
