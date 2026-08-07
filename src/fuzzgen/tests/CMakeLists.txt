# src/fuzzgen/tests/CMakeLists.txt
#
# Autotests for the crash-attribution feature (QtFuzzRuntime / crashdiag.h
# and its wiring into FuzzCppGenerator's templates). Three tiers, all wired
# via plain CTest so they run unmodified on macOS, Windows, and Linux:
#
#   Tier 1 (crashdiag_test):    zero Qt dependency. Directly exercises the
#                               real crash handler with a deliberate SIGSEGV
#                               / abort(), asserting the crash line names
#                               the right call. Always runs.
#   Tier 2 (codegen_selftest):  zero Qt dependency. Calls the real
#                               FuzzCppGenerator with hand-built method
#                               lists, asserting on the generated source
#                               text (array/case alignment, no leftover
#                               @@..@@ placeholders). Always runs.
#   Tier 2 (scanner_diff_selftest): zero Qt dependency. Calls the real
#                               classesDeclaredIn()/classesDefinedIn()
#                               (used by qtdiff) against hand-written
#                               header/source fixtures. Always runs.
#   Tier 3 (crashdiag_e2e):     requires Qt6::Core. Generates, compiles, and
#                               runs a real fuzz harness against a synthetic
#                               crashy class, end to end. Skipped when no
#                               Qt6 install is available.
#
# Tiers 1 and 3 deliberately crash by design — CTest treats a subprocess that
# dies from a signal/structured exception as an automatic failure regardless
# of PASS_REGULAR_EXPRESSION (confirmed empirically: that property only
# overrides an ordinary nonzero exit code, not signal termination). They are
# therefore run through run_and_check, which spawns the crashing program,
# captures its output, and itself always exits cleanly — see
# run_and_check.cpp for the full rationale.

# ── Shared subprocess-capture helper ──────────────────────────────────────────

add_executable(run_and_check run_and_check.cpp)

# ── Tier 1: crashdiag_test ────────────────────────────────────────────────────

add_executable(crashdiag_test crashdiag_test.cpp)
target_include_directories(crashdiag_test PRIVATE "${_FUZZGEN_INCLUDE_DIR}")

add_test(NAME crashdiag_segv
    COMMAND run_and_check "CRASHED.*FakeClass::crashyMethod" $<TARGET_FILE:crashdiag_test> segv
)
add_test(NAME crashdiag_abort
    COMMAND run_and_check "CRASHED.*FakeClass::crashyMethod" $<TARGET_FILE:crashdiag_test> abort
)

# ── Tier 2: codegen_selftest ──────────────────────────────────────────────────

add_executable(codegen_selftest codegen_selftest.cpp)
target_link_libraries(codegen_selftest PRIVATE QtFuzzLib)

add_test(NAME codegen_selftest COMMAND codegen_selftest)

add_executable(scanner_diff_selftest scanner_diff_selftest.cpp)
target_link_libraries(scanner_diff_selftest PRIVATE QtFuzzLib)

add_test(NAME scanner_diff_selftest COMMAND scanner_diff_selftest)

# ── Tier 3: end-to-end, only when Qt6::Core is available ─────────────────────

find_package(Qt6 COMPONENTS Core QUIET)

if(TARGET Qt6::Core)
    add_executable(gen_fixture gen_fixture.cpp)
    target_link_libraries(gen_fixture PRIVATE QtFuzzLib)

    set(_FIXTURE_CPP "${CMAKE_CURRENT_BINARY_DIR}/generated/fuzz_FakeClass.cpp")
    add_custom_command(
        OUTPUT  "${_FIXTURE_CPP}"
        COMMAND gen_fixture "${_FIXTURE_CPP}"
        DEPENDS gen_fixture
        COMMENT "Generating end-to-end crash-attribution fixture..."
        VERBATIM
    )

    add_executable(crashdiag_e2e "${_FIXTURE_CPP}")
    target_include_directories(crashdiag_e2e PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
    target_link_libraries(crashdiag_e2e PRIVATE Qt6::Core)

    add_test(NAME crashdiag_e2e
        COMMAND run_and_check "CRASHED.*FakeClass::crashyMethod"
                $<TARGET_FILE:crashdiag_e2e> --seed 1 --time 5
    )
    set_tests_properties(crashdiag_e2e PROPERTIES TIMEOUT 30)
else()
    message(STATUS "fuzzgen tests: Qt6::Core not found — skipping Tier 3 end-to-end crashdiag_e2e test.")
endif()
