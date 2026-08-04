// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// codegen_selftest — exercises FuzzCppGenerator (the real generator, not a
// reimplementation) with hand-built MethodSignature lists, and asserts on
// the generated source text. No Qt dependency, no scanner/parsing needed —
// MethodSignature is constructed directly in-memory — so this runs
// identically and quickly on macOS, Windows, and Linux.
//
// Specifically guards against the two ways this generator has been shown to
// break in review: the switch-case / kDirectCallNames[] index alignment
// (buildDirectFuzzFunction) and unresolved @@..@@ template placeholders
// left in the final output (a forgotten replace() call).

#include "codegen.h"

#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

using namespace QtFuzz;

namespace {

int g_failures = 0;

void check(bool cond, const std::string &what)
{
    if (!cond) {
        std::cerr << "FAIL: " << what << "\n";
        ++g_failures;
    } else {
        std::cout << "ok: " << what << "\n";
    }
}

std::string readFile(const std::string &path)
{
    std::ifstream f(path);
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

MethodParam makeParam(std::string type)
{
    MethodParam p;
    p.type = std::move(type);
    return p;
}

} // namespace

int main()
{
    // ── Scenario 1: mixed trivial/non-trivial methods (hasQObject = false) ──
    {
        MethodSignature crashy;
        crashy.name = "crashyMethod";
        crashy.params.push_back(makeParam("int"));

        MethodSignature safe;
        safe.name = "safeMethod"; // zero params -> allBraces is false (see
                                  // buildDirectFuzzFunction: !params.empty()),
                                  // so this is also a real, emitted case.

        std::vector<MethodSignature> methods = { crashy, safe };

        const std::string outPath = "codegen_selftest_mixed.cpp";
        FuzzCppGenerator gen("FakeClass", outPath, AppType::Core, methods,
                             /*hasQObject=*/false, "\"fakeclass.h\"");
        check(gen.generate(), "mixed: generate() succeeds");

        const std::string src = readFile(outPath);
        check(!src.empty(), "mixed: output file is non-empty");
        check(src.find("@@") == std::string::npos,
              "mixed: no unresolved @@..@@ placeholder tokens remain");
        check(src.find("static const char *const kDirectCallNames[] = {") != std::string::npos,
              "mixed: kDirectCallNames[] array is emitted");
        check(src.find("\"FakeClass::crashyMethod(int)\",") != std::string::npos,
              "mixed: kDirectCallNames contains crashyMethod's signature");
        check(src.find("\"FakeClass::safeMethod()\",") != std::string::npos,
              "mixed: kDirectCallNames contains safeMethod's signature");
        check(src.find("case 0:\n        QtFuzzRuntime::setCurrentCall(kDirectCallNames[0]);\n"
                       "        (void)obj.crashyMethod(") != std::string::npos,
              "mixed: case 0 sets current call before invoking crashyMethod");
        check(src.find("case 1:\n        QtFuzzRuntime::setCurrentCall(kDirectCallNames[1]);\n"
                       "        (void)obj.safeMethod();") != std::string::npos,
              "mixed: case 1 sets current call before invoking safeMethod");
        check(src.find("QtFuzzRuntime::installCrashHandler(\"FakeClass\");") != std::string::npos,
              "mixed: installCrashHandler() is called with the class name");
        check(src.find("QtFuzzRuntime::setIteration(iterations);") != std::string::npos,
              "mixed: setIteration() is called in the fuzz loop");
    }

    // ── Scenario 2: every method trivially skipped -> no dispatch array ──────
    {
        MethodSignature trivial;
        trivial.name = "trivialMethod";
        // An unrecognized lowercase-leading type name falls through
        // fuzzExprForType's final fallback to the bare "fd.nextInt()"
        // sentinel — one of the four expressions buildDirectFuzzFunction's
        // allBraces check treats as trivial enough to skip entirely.
        trivial.params.push_back(makeParam("weirdlowercasetype"));

        std::vector<MethodSignature> methods = { trivial };

        const std::string outPath = "codegen_selftest_alltrivial.cpp";
        FuzzCppGenerator gen("FakeClass2", outPath, AppType::Core, methods,
                             /*hasQObject=*/false, "\"fakeclass.h\"");
        check(gen.generate(), "all-trivial: generate() succeeds");

        const std::string src = readFile(outPath);
        check(src.find("@@") == std::string::npos,
              "all-trivial: no unresolved @@..@@ placeholder tokens remain");
        check(src.find("kDirectCallNames") == std::string::npos,
              "all-trivial: kDirectCallNames[] is NOT emitted (would be unused)");
    }

    // ── Scenario 3: Q_OBJECT path wires up the meta-invoke call site too ─────
    {
        std::vector<MethodSignature> methods; // empty: only test the QObject scaffolding
        const std::string outPath = "codegen_selftest_qobject.cpp";
        FuzzCppGenerator gen("FakeQObjectClass", outPath, AppType::Core, methods,
                             /*hasQObject=*/true, "\"fakeclass.h\"");
        check(gen.generate(), "qobject: generate() succeeds");

        const std::string src = readFile(outPath);
        check(src.find("@@") == std::string::npos,
              "qobject: no unresolved @@..@@ placeholder tokens remain");
        check(src.find("QtFuzzRuntime::setCurrentCall(metaCallBuf);") != std::string::npos,
              "qobject: invokeWithFuzzData records the meta-call before invoking");
        check(src.find("QtFuzzRuntime::installCrashHandler(\"FakeQObjectClass\");") != std::string::npos,
              "qobject: installCrashHandler() is called with the class name");
        check(src.find("namespace QtFuzzRuntime {") != std::string::npos,
              "qobject: crashdiag.h content is spliced into the output");
    }

    if (g_failures > 0) {
        std::cerr << g_failures << " check(s) failed.\n";
        return 1;
    }
    std::cout << "All checks passed.\n";
    return 0;
}
