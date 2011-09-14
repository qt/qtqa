load(qttest_p4)

cross_compile: DEFINES += QT_CROSS_COMPILED
INCLUDEPATH += ../../shared
SOURCES += tst_symbols.cpp
QT = core


