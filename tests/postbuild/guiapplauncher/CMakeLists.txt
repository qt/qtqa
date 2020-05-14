# Generated from guiapplauncher.pro.

#####################################################################
## tst_guiapplauncher Test:
#####################################################################

qt_add_test(tst_guiapplauncher
    SOURCES
        tst_guiapplauncher.cpp
        windowmanager.cpp windowmanager.h
    DEFINES
        SRCDIR=\\\"${CMAKE_CURRENT_SOURCE_DIR}/\\\"
    PUBLIC_LIBRARIES
        Qt::Gui
)

#### Keys ignored in scope 1:.:.:guiapplauncher.pro:<TRUE>:
# TEMPLATE = "app"

## Scopes:
#####################################################################

qt_extend_target(tst_guiapplauncher CONDITION WIN32
    PUBLIC_LIBRARIES
        user32
)

qt_extend_target(tst_guiapplauncher CONDITION QT_FEATURE_xlib # special case
    DEFINES
        Q_WS_X11
)
