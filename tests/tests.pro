TEMPLATE = subdirs
SUBDIRS += prebuild postbuild

# These tests are a special case.  They do _not_ contain autotests
# specifically for qtqa - rather they contain autotests which may be applied to
# any Qt module.  They are not supposed to be run by default when doing
# `make check' in qtqa - if you want to run them, you need to explicitly opt-in
# by doing `make check' under tests/prebuild or tests/postbuild .
prebuild.CONFIG  += no_check_target
postbuild.CONFIG += no_check_target
