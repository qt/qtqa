# This .pro file is used as a SUBDIR in another project.
# This may affect the name of the generated Makefile(s).
TEMPLATE=subdirs
SUBDIRS=\
    failing_disabled_test\
    passing_custom_check_target\
    failing_custom_check_target\

failing_disabled_test.CONFIG += no_check_target
