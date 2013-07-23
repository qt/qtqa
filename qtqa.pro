TEMPLATE = subdirs

!isEmpty(QTQA_BUILD_PARTS): QT_BUILD_PARTS = $$QTQA_BUILD_PARTS

scripts.subdir = scripts
scripts.CONFIG = no_default_install
!contains(QT_BUILD_PARTS,tests):scripts.CONFIG += no_default_target

tests.subdir = tests
tests.CONFIG = no_default_install
!contains(QT_BUILD_PARTS,tests):tests.CONFIG += no_default_target

SUBDIRS +=  \
    scripts \
    tests
