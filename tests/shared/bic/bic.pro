load(qttest_p4)
INCLUDEPATH += ../../shared
SOURCES += tst_bic.cpp qbic.cpp
QT = core

wince*:{
    DEFINES += SRCDIR=\\\"\\\"
} else {
    DEFINES += SRCDIR=\\\"$$PWD/\\\"
}

CONFIG += insignificant_test    # QTQAINFRA-321
