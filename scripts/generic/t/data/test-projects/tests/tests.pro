TEMPLATE=subdirs
SUBDIRS=\
    passing_significant_test\
    passing_insignificant_test\
    failing_significant_test\
    failing_insignificant_test\
    failing_disabled_test\
    passing_custom_check_target\
    failing_custom_check_target\

failing_disabled_test.CONFIG += no_check_target
