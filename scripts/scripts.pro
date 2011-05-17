TEMPLATE = subdirs

# Override `make check' to run our script which knows how to test our perl
# scripts.  This requires a modern-ish CPAN setup, so we will enable it only
# for platforms as we test it.
linux* {
    check.commands = perl $$_PRO_FILE_PWD_/test.pl --clean
}

# There are deliberately no SUBDIRS, this project should do nothing except
# override `check'
QMAKE_EXTRA_TARGETS += check
