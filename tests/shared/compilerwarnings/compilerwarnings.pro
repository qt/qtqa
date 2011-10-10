CONFIG += testcase
TARGET = tst_compilerwarnings
INCLUDEPATH += ../../shared
SOURCES += tst_compilerwarnings.cpp
QT = core testlib

CONFIG += insignificant_test    # QTQAINFRA-322
