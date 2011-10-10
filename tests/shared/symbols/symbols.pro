CONFIG += testcase
TARGET = tst_symbols

cross_compile: DEFINES += QT_CROSS_COMPILED
INCLUDEPATH += ../../shared
SOURCES += tst_symbols.cpp
QT = core testlib

CONFIG += insignificant_test    # QTQAINFRA-325
