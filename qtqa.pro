TEMPLATE = subdirs

tests.subdir = tests
tests.CONFIG = no_default_install
!contains(QT_BUILD_PARTS,tests):tests.CONFIG += no_default_target

SUBDIRS += tests
