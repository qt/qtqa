TEMPLATE = subdirs
SUBDIRS += shared

# The `shared' directory is a special case.  It does _not_ contain autotests
# specifically for qtqa - rather it contains autotests which may be applied to
# any Qt module.  They are not supposed to be run by default when doing
# `make check' in qtqa - if you want to run them, you need to explicitly opt-in
# by doing `make check' under tests/shared .
check.CONFIG         = recursive
check.recurse        = $$SUBDIRS
check.recurse       -= shared
check.recurse_target = check
QMAKE_EXTRA_TARGETS += check
