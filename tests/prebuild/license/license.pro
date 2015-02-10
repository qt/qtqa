TEMPLATE = subdirs
CONFIG -= qt

# Not really any subdirs, just needed to let `make check' run the test.

check.commands = $(TESTRUNNER) prove $$PWD/tst_licenses.pl
QMAKE_EXTRA_TARGETS += check

CONFIG += insignificant_test # temporary solution to allow the license header update
