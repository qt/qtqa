# qtbase/src/tools/fuzzgen/CMakeLists.txt
#
# Builds qt_fuzzgen — the host tool that scans qtbase/src for QObject
# subclasses and writes the qtbase/tests/fuzzing/ tree.
#
# Follows the same convention as moc, rcc, qlalr, etc.:
#   • Host-only executable, no Qt runtime dependency.
#   • When built inside Qt's configure umbrella: qt_add_tool() is used,
#     the binary lands in $prefix/libexec/ alongside the other tools.
#   • When built standalone (e.g. for development/testing): a plain
#     project() + add_executable() path is taken.
#
# ─────────────────────────────────────────────────────────────────────────────
# Adding to an existing qtbase checkout
# ─────────────────────────────────────────────────────────────────────────────
# Append this line to qtbase/src/tools/CMakeLists.txt:
#
#   add_subdirectory(fuzzgen)
#
# ─────────────────────────────────────────────────────────────────────────────
# Standalone build (no Qt configure required — tool has zero Qt deps)
# ─────────────────────────────────────────────────────────────────────────────
#   cmake -B build -S qtbase/src/tools/fuzzgen
#   cmake --build build
#   # Produces: build/qt_fuzzgen  and  build/qt_fuzz_gen
#
# ─────────────────────────────────────────────────────────────────────────────
# Qt-internal build
# ─────────────────────────────────────────────────────────────────────────────
#   # (normal Qt configure + build — fuzzgen is compiled as part of tools/)
#   configure -prefix /opt/Qt6 && cmake --build .
#   # Installed to: $prefix/libexec/qt_fuzzgen

# ── Source list (used by both build paths) ───────────────────────────────────

set(_FUZZGEN_LIB_SOURCES
    modulemap.cpp include/modulemap.h
    scanner.cpp include/scanner.h
    codegen.cpp include/codegen.h
    qtdetect.cpp include/qtdetect.h
    skiplist.cpp include/skiplist.h
)

set(_FUZZGEN_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include")

# ── Embed include/crashdiag.h as a C++ string constant ───────────────────────
# codegen.cpp splices this verbatim into every generated fuzz test (see
# @@CRASH_DIAGNOSTICS@@ in FuzzCppGenerator's templates), so the crash-
# attribution runtime never depends on the source tree being present when a
# generated fuzz test is later compiled/run on its own.
set(_CRASHDIAG_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/include/crashdiag.h")
set(_CRASHDIAG_EMBED  "${CMAKE_CURRENT_BINARY_DIR}/crashdiag_embed.h")
file(READ "${_CRASHDIAG_HEADER}" _CRASHDIAG_CONTENTS)
# Strip "#pragma once" — meaningless (and warns under -Wall) once spliced
# directly into the middle of a generated .cpp instead of #included.
string(REPLACE "#pragma once" "" _CRASHDIAG_CONTENTS "${_CRASHDIAG_CONTENTS}")
file(WRITE "${_CRASHDIAG_EMBED}"
    "// Auto-generated from include/crashdiag.h by CMake — do not edit.\n"
    "static const char kCrashDiagSource[] = R\"QTFUZZ_CRASHDIAG(${_CRASHDIAG_CONTENTS})QTFUZZ_CRASHDIAG\";\n"
)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_CRASHDIAG_HEADER}")

# ── Qt-internal build path ───────────────────────────────────────────────────

if(COMMAND qt_add_tool)

    # qt_add_tool() is defined by Qt's cmake/QtToolHelpers.cmake.
    # It creates a host-only target that:
    #   • Is compiled for the build host in cross-compilation setups.
    #   • Gets installed to ${INSTALL_LIBEXECDIR} (e.g. libexec/).
    #   • Participates in Qt's tool dependency tracking.
    qt_add_tool(qt_fuzzgen
        TOOLS_TARGET    Core
        INSTALL_DIR     "${INSTALL_LIBEXECDIR}"
        SOURCES
            ${_FUZZGEN_LIB_SOURCES}
            qt_fuzz_tree.cpp
    )

    target_include_directories(qt_fuzzgen PRIVATE
        "${_FUZZGEN_INCLUDE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )

    # qt_fuzz_gen: single-class convenience tool, installed alongside
    qt_add_tool(qt_fuzz_gen
        TOOLS_TARGET    Core
        INSTALL_DIR     "${INSTALL_LIBEXECDIR}"
        SOURCES
            ${_FUZZGEN_LIB_SOURCES}
            qt_fuzz_gen.cpp
    )

    target_include_directories(qt_fuzz_gen PRIVATE
        "${_FUZZGEN_INCLUDE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )

    # fuzz: targeted single-function fuzzer runner
    qt_add_tool(fuzz
        TOOLS_TARGET    Core
        INSTALL_DIR     "${INSTALL_LIBEXECDIR}"
        SOURCES
            ${_FUZZGEN_LIB_SOURCES}
            fuzz.cpp
    )

    target_include_directories(fuzz PRIVATE
        "${_FUZZGEN_INCLUDE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )

    # qt_tara: TARA launcher — scans Qt-Security score:critical files and
    #          spawns qt_fuzz_gen in parallel for every class found
    qt_add_tool(qt_tara
        TOOLS_TARGET    Core
        INSTALL_DIR     "${INSTALL_LIBEXECDIR}"
        SOURCES
            qt_tara.cpp
    )

    # qtdiff: lists the Qt classes whose header/source files differ between
    #         the current branch's local HEAD and its upstream branch
    qt_add_tool(qtdiff
        TOOLS_TARGET    Core
        INSTALL_DIR     "${INSTALL_LIBEXECDIR}"
        SOURCES
            ${_FUZZGEN_LIB_SOURCES}
            qtdiff.cpp
    )

    target_include_directories(qtdiff PRIVATE
        "${_FUZZGEN_INCLUDE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )

# ── Standalone build path ─────────────────────────────────────────────────────

else()

    cmake_minimum_required(VERSION 3.19)
    project(qt_fuzzgen LANGUAGES CXX)

    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)

    # Shared library of generator logic
    add_library(QtFuzzLib STATIC ${_FUZZGEN_LIB_SOURCES})
    target_include_directories(QtFuzzLib PUBLIC
        "${_FUZZGEN_INCLUDE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )

    # GCC < 9 needs explicit -lstdc++fs for <filesystem>
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND
       CMAKE_CXX_COMPILER_VERSION VERSION_LESS "9")
        target_link_libraries(QtFuzzLib PUBLIC stdc++fs)
    endif()

    # Main tree-generation tool
    add_executable(qt_fuzzgen qt_fuzz_tree.cpp)
    target_link_libraries(qt_fuzzgen PRIVATE QtFuzzLib)

    # Single-class convenience tool
    add_executable(qt_fuzz_gen qt_fuzz_gen.cpp)
    target_link_libraries(qt_fuzz_gen PRIVATE QtFuzzLib)

    # Targeted single-function fuzzer runner (generate + compile + run)
    add_executable(fuzz fuzz.cpp)
    target_link_libraries(fuzz PRIVATE QtFuzzLib)

    # TARA launcher — scans Qt-Security score:critical files, spawns qt_fuzz_gen
    add_executable(qt_tara qt_tara.cpp)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND
       CMAKE_CXX_COMPILER_VERSION VERSION_LESS "9")
        target_link_libraries(qt_tara PRIVATE stdc++fs)
    endif()

    # qtdiff: lists the Qt classes whose header/source files differ between
    #         the current branch's local HEAD and its upstream branch
    add_executable(qtdiff qtdiff.cpp)
    target_link_libraries(qtdiff PRIVATE QtFuzzLib)

    install(TARGETS qt_fuzzgen qt_fuzz_gen fuzz qt_tara qtdiff
        RUNTIME DESTINATION bin
    )

    # ── Autotests (crash-attribution feature) ─────────────────────────────────
    enable_testing()
    add_subdirectory(tests)

    # ── Convenience: generate the fuzz tree immediately after build ───────────
    #    (mirrors what qtbase/tests/fuzzing/CMakeLists.txt does when this tool
    #     is already installed as part of a full Qt build)
    set(QTBASE_DIR "" CACHE PATH "qtbase source root for tree generation")
    set(FUZZ_OUTPUT_DIR "" CACHE PATH "Output root (default: <QTBASE_DIR>/tests/fuzzing)")
    set(FUZZ_TIME_SECONDS "30" CACHE STRING "Fuzz duration per test in seconds")
    set(FUZZ_MODULE_FILTER "" CACHE STRING "Comma-separated module filter (empty = all)")

    if(QTBASE_DIR AND EXISTS "${QTBASE_DIR}/src/corelib")
        if(NOT FUZZ_OUTPUT_DIR)
            set(FUZZ_OUTPUT_DIR "${QTBASE_DIR}/tests/fuzzing")
        endif()

        set(_STAMP "${CMAKE_CURRENT_BINARY_DIR}/fuzz_tree.stamp")

        set(_ARGS --qtbase "${QTBASE_DIR}" --out "${FUZZ_OUTPUT_DIR}"
                  --time   "${FUZZ_TIME_SECONDS}")
        if(FUZZ_MODULE_FILTER)
            list(APPEND _ARGS --modules "${FUZZ_MODULE_FILTER}")
        endif()

        add_custom_command(
            OUTPUT  "${_STAMP}"
            COMMAND qt_fuzzgen ${_ARGS}
            COMMAND "${CMAKE_COMMAND}" -E touch "${_STAMP}"
            DEPENDS qt_fuzzgen
            COMMENT "Generating qtbase/tests/fuzzing tree..."
            VERBATIM
        )
        add_custom_target(generate_fuzz_tree ALL DEPENDS "${_STAMP}")
    else()
        message(STATUS
            "qt_fuzzgen: set -DQTBASE_DIR=<path> to also generate the test tree.")
    endif()

endif() # COMMAND qt_add_tool
