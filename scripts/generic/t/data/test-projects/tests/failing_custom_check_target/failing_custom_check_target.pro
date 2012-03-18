TEMPLATE=subdirs
check.commands = $(TESTRUNNER) perl -E \"say q{Custom failing}; exit 2\" $(TESTARGS)
QMAKE_EXTRA_TARGETS += check
