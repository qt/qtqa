# Link against gui for X11,etc.
CONFIG += testcase

DEFINES += SRCDIR=\\\"$$PWD/\\\"
TARGET = tst_guiapplauncher
CONFIG += console
CONFIG -= app_bundle
QT += testlib
TEMPLATE = app
SOURCES += tst_guiapplauncher.cpp \
    windowmanager.cpp
HEADERS += windowmanager.h

# process enumeration,etc.
win32:LIBS+=-luser32
contains(QT_CONFIG, xlib) {
    LIBS += $$QMAKE_LIBS_X11
    DEFINES += Q_WS_X11
}

CONFIG += insignificant_test    # QTQAINFRA-323
