CONFIG += testcase
TARGET = tst_bic
INCLUDEPATH += ..
SOURCES += tst_bic.cpp qbic.cpp
HEADERS += qbic.h ../global.h

QT = core testlib

wince*:{
    DEFINES += SRCDIR=\\\"\\\"
} else {
    DEFINES += SRCDIR=\\\"$$PWD/\\\"
}
