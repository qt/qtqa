CONFIG += testcase
TARGET = tst_bic
INCLUDEPATH += ..
SOURCES += tst_bic.cpp qbic.cpp
HEADERS += qbic.h ../global.h

QT = core testlib

DEFINES += SRCDIR=\\\"$$PWD/\\\"
