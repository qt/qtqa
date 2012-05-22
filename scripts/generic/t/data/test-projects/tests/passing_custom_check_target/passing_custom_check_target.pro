TEMPLATE=subdirs
# This custom target chdirs to a different directory to check if that
# is correctly reflected in the testplan
check.commands = cd ../dummy && $(TESTRUNNER) perl -E \"say q{Custom passing}; exit 0\" $(TESTARGS)
QMAKE_EXTRA_TARGETS += check

testcase.timeout = -120
