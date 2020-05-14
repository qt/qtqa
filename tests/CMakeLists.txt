# Generated from tests.pro.

if(QT_BUILD_STANDALONE_TESTS)
    # Add qt_find_package calls for extra dependencies that need to be found when building
    # the standalone tests here.
endif()

# special case begin

# It should be possible to build the tests/CMakeLists.txt project as a standalone project
# (not via qtqa/CMakeLists.txt + QT_BUILD_STANDALONE_TESTS) because that's what Coin does
# with qmake.
# This is somewhat similar to qtbase/src/plugins/sqldrivers.
if(NOT QT_BUILD_STANDALONE_TESTS AND CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    cmake_minimum_required(VERSION 3.16)
    include(../.cmake.conf)
    project(QtQualityAssuranceTests
        VERSION "${QT_REPO_MODULE_VERSION}"
        DESCRIPTION "Qt6 Quality Assurance tests"
        HOMEPAGE_URL "https://qt.io/"
        LANGUAGES CXX C
    )
    find_package(Qt6 ${PROJECT_VERSION} CONFIG REQUIRED COMPONENTS BuildInternals Core Test)
    find_package(Qt6 ${PROJECT_VERSION} CONFIG OPTIONAL_COMPONENTS Gui Widgets)
    qt_prepare_standalone_project()
    set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/fake_install_prefix" CACHE STRING "" FORCE)
endif()

# We can't use qt_build_tests because the test folder layout is different,
# so we need to copy paste some of the functionality.
if(QT_BUILD_STANDALONE_TESTS)
    qt_set_language_standards()
    if(NOT QT_SUPERBUILD)
        qt_restore_backed_up_install_prefix()
    endif()
endif()

# add_subdirector(prebuild) # TODO Port if needed
add_subdirectory(postbuild)

# special case end
