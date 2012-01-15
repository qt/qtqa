CONFIG += testcase
TARGET = tst_bic
INCLUDEPATH += ..
SOURCES += tst_bic.cpp qbic.cpp
QT = core testlib

wince*:{
    DEFINES += SRCDIR=\\\"\\\"
} else {
    DEFINES += SRCDIR=\\\"$$PWD/\\\"
}

CONFIG += insignificant_test    # QTQAINFRA-321
