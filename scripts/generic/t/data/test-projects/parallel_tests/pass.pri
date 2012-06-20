TEMPLATE=subdirs
CONFIG += testcase
CONFIG += parallel_test
check.commands = $(TESTRUNNER) perl -e 1
QMAKE_EXTRA_TARGETS += check
