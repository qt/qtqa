TEMPLATE=subdirs
CONFIG += testcase
CONFIG += parallel_test
check.commands = "$(TESTRUNNER) perl -e \"sleep 5; exit 5\""
QMAKE_EXTRA_TARGETS += check
