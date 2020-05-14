# Generated from postbuild.pro.

if(TARGET Qt::Widgets)
    add_subdirectory(bic)
endif()
if(QT_FEATURE_process)
    add_subdirectory(headers)
endif()
if(QT_FEATURE_process AND TARGET Qt::Gui)
    add_subdirectory(guiapplauncher)
endif()
if(LINUX)
    add_subdirectory(symbols)
endif()
