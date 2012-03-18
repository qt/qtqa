TEMPLATE=subdirs
check.commands = $(TESTRUNNER) perl -E \"say q{Custom passing}; exit 0\" $(TESTARGS)
QMAKE_EXTRA_TARGETS += check
