# Copyright (C) 2022 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause

# Generated from qtqa.pro.

cmake_minimum_required(VERSION 3.16)

include(.cmake.conf)
project(QtQualityAssurance # special case
    VERSION "${QT_REPO_MODULE_VERSION}"
    DESCRIPTION "Qt Quality Assurance repo" # special case
    HOMEPAGE_URL "https://qt.io/"
    LANGUAGES CXX C
)

find_package(Qt6 ${PROJECT_VERSION} CONFIG REQUIRED COMPONENTS BuildInternals Core Test) # special case
find_package(Qt6 ${PROJECT_VERSION} CONFIG OPTIONAL_COMPONENTS Gui Widgets) # special case

# special case begin
qt_build_repo_begin()

if(BUILD_TESTING)
    add_subdirectory(scripts)
    add_subdirectory(tests)

    if(NOT QT_BUILD_TESTS_BY_DEFAULT)
        set_property(DIRECTORY scripts PROPERTY EXCLUDE_FROM_ALL TRUE)
        set_property(DIRECTORY tests PROPERTY EXCLUDE_FROM_ALL TRUE)
    endif()
endif()

qt_build_repo_end()
# special case end
