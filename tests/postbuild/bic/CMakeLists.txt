# Generated from bic.pro.

#####################################################################
## tst_bic Test:
#####################################################################

# special case begin

# The test needs to have support for building it as a standalone project,
# due to Coin calling qmake on the test directory directly when
# doing BiC tests on Linux in the Coin test phase.

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    cmake_minimum_required(VERSION 3.16)
    include(../../../.cmake.conf)
    project(QtQualityAssuranceBinaryCompatibilityTest
        VERSION "${QT_REPO_MODULE_VERSION}"
        DESCRIPTION "Qt6 Quality Binary Compatibility Test"
        HOMEPAGE_URL "https://qt.io/"
        LANGUAGES CXX C
    )
    find_package(Qt6 ${PROJECT_VERSION} CONFIG REQUIRED COMPONENTS BuildInternals Core Test)
    qt_prepare_standalone_project()
    set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/fake_install_prefix" CACHE STRING "" FORCE)
endif()

# special case end

qt_add_test(tst_bic
    SOURCES
        ../global.h
        qbic.cpp qbic.h
        tst_bic.cpp
    DEFINES
        SRCDIR=\\\"${CMAKE_CURRENT_SOURCE_DIR}/\\\"
    INCLUDE_DIRECTORIES
        ..
)
