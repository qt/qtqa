// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// crashdiag_test — deliberately crashes using the real QtFuzzRuntime crash
// handler (include/crashdiag.h), to verify that a fatal signal (POSIX) /
// structured exception (Windows) is correctly attributed to whatever call
// was recorded via setCurrentCall() immediately beforehand.
//
// This exercises the exact mechanism that generated fuzz tests rely on to
// answer "which API call actually crashed" — deterministically and with
// zero Qt dependency, so it runs identically on macOS, Windows, and Linux.
//
// Usage: crashdiag_test <segv|abort>

#include "crashdiag.h"

#include <cstdlib>
#include <cstring>
#include <iostream>

int main(int argc, char **argv)
{
    if (argc < 2) {
        std::cerr << "Usage: crashdiag_test <segv|abort>\n";
        return 2;
    }

    QtFuzzRuntime::installCrashHandler("FakeClass");
    QtFuzzRuntime::setCurrentCall("FakeClass::crashyMethod(int)");
    QtFuzzRuntime::setIteration(7);

    if (std::strcmp(argv[1], "abort") == 0) {
        std::abort();
    } else if (std::strcmp(argv[1], "segv") == 0) {
        volatile int *p = nullptr;
        *p = 1;
    } else {
        std::cerr << "Unknown mode: " << argv[1] << "\n";
        return 2;
    }

    return 0; // unreachable if the crash fired
}
