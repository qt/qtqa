# Generated from symbols.pro.

#####################################################################
## tst_symbols Test:
#####################################################################

qt_add_test(tst_symbols
    SOURCES
        tst_symbols.cpp
    INCLUDE_DIRECTORIES
        ..
)

## Scopes:
#####################################################################

qt_extend_target(tst_symbols CONDITION CMAKE_CROSSCOMPILING
    DEFINES
        QT_CROSS_COMPILED
)
