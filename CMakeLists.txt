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

find_package(Qt6 ${PROJECT_VERSION} CONFIG REQUIRED COMPONENTS BuildInternals Core)
find_package(Qt6 ${PROJECT_VERSION} QUIET CONFIG OPTIONAL_COMPONENTS Gui Widgets Test)

# special case begin
qt_build_repo_begin()

if(QT_BUILD_TESTS)
    add_subdirectory(scripts)
    if(Qt6Core_VERSION VERSION_GREATER_EQUAL 6.7.0)
        qt_build_repo_post_process()
    endif()
    add_subdirectory(tests)

    if(NOT QT_BUILD_TESTS_BY_DEFAULT)
        set_property(DIRECTORY scripts PROPERTY EXCLUDE_FROM_ALL TRUE)
        set_property(DIRECTORY tests PROPERTY EXCLUDE_FROM_ALL TRUE)
    endif()
endif()

qt_build_repo_end()
# special case end
