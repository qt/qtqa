TEMPLATE = subdirs

!isEmpty(QTQA_BUILD_PARTS): QT_BUILD_PARTS = $$QTQA_BUILD_PARTS

scripts.subdir = scripts
scripts.CONFIG = no_default_install
!contains(QT_BUILD_PARTS,tests):scripts.CONFIG += no_default_target

tests.subdir = tests
tests.CONFIG = no_default_install
!contains(QT_BUILD_PARTS,tests):tests.CONFIG += no_default_target

linux-*:system(". /etc/lsb-release && [ $DISTRIB_CODENAME = precise ]"):CONFIG+=insignificant_test # QTQAINFRA-708

SUBDIRS +=  \
    scripts \
    tests
