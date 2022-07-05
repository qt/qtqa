# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

# Generated from symbols.pro.

#####################################################################
## tst_symbols Test:
#####################################################################

qt_internal_add_test(tst_symbols
    SOURCES
        tst_symbols.cpp
    INCLUDE_DIRECTORIES
        ..
)

## Scopes:
#####################################################################

qt_internal_extend_target(tst_symbols CONDITION CMAKE_CROSSCOMPILING
    DEFINES
        QT_CROSS_COMPILED
)
