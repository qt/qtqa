# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only WITH Qt-GPL-exception-1.0

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
