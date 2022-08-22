# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause

# Generated from guiapplauncher.pro.

#####################################################################
## tst_guiapplauncher Test:
#####################################################################

qt_internal_add_test(tst_guiapplauncher
    SOURCES
        tst_guiapplauncher.cpp
        windowmanager.cpp windowmanager.h
    DEFINES
        SRCDIR=\\\"${CMAKE_CURRENT_SOURCE_DIR}/\\\"
    LIBRARIES
        Qt::Gui
)

#### Keys ignored in scope 1:.:.:guiapplauncher.pro:<TRUE>:
# TEMPLATE = "app"

## Scopes:
#####################################################################

qt_internal_extend_target(tst_guiapplauncher CONDITION WIN32
    LIBRARIES
        user32
)

qt_internal_extend_target(tst_guiapplauncher CONDITION QT_FEATURE_xlib # special case
    DEFINES
        Q_WS_X11
    LIBRARIES
        X11
)
