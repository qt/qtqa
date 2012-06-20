# Under this directory are various test projects, used for testing
# testplanner / testscheduler.

TEMPLATE=subdirs
SUBDIRS=\
    tests \
    not_tests \
    parallel_tests

parallel_tests.CONFIG += no_check_target
