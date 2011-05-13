TEMPLATE = subdirs

scripts.subdir = scripts
scripts.CONFIG = no_default_install
!contains(QT_BUILD_PARTS,tests):scripts.CONFIG += no_default_target

tests.subdir = tests
tests.CONFIG = no_default_install
!contains(QT_BUILD_PARTS,tests):tests.CONFIG += no_default_target

SUBDIRS +=  \
    scripts \
    tests
