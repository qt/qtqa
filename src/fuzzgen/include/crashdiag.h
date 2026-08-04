#pragma once
// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// QtFuzzRuntime — crash attribution for generated fuzz-test binaries.
//
// A generated fuzz test dispatches into many different API calls per run
// (one class, many methods). When the process crashes, CTest only sees that
// the "[fuzz_<Class>] Done." success marker never appeared — nothing says
// which call caused it.
//
// setCurrentCall() records the call about to be attempted; installCrashHandler()
// installs a fatal-signal handler (POSIX) / unhandled-exception filter
// (Windows) that reports it before the process terminates, then re-raises so
// normal crash semantics (exit code/signal, ASan's own reporting, etc.) are
// preserved.
//
// Header-only (inline functions/variables, C++17) so every generated fuzz
// test can #include it verbatim with zero Qt dependency, and so this tool's
// own autotests can exercise the real mechanism directly.

#include <cstdint>
#include <cstdio>
#include <cstring>

#ifdef _WIN32
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  include <windows.h>
#  include <csignal>
#else
#  include <csignal>
#  include <unistd.h>
#endif

namespace QtFuzzRuntime {

// The API call currently in flight — a string literal for direct calls, or
// a caller-owned formatted buffer for meta-invoke calls. Read by the crash
// handler, written by setCurrentCall() immediately before every call site.
inline const char *g_currentCall = "(startup)";

// Iteration count as of the last update — reported on crash as a repro aid
// (the fuzz loop's PRNG stream is deterministic given the same --seed).
inline volatile uint64_t g_iterationCount = 0;

// Name used in the "[fuzz_<name>]" prefix of the crash report.
inline const char *g_className = "?";

inline void setCurrentCall(const char *call) { g_currentCall = call; }
inline void setIteration(uint64_t n) { g_iterationCount = n; }

#ifndef _WIN32

// Async-signal-safe: writes an unsigned integer in decimal via write().
inline void writeUInt(uint64_t v)
{
    char buf[24];
    int i = 24;
    do {
        buf[--i] = char('0' + static_cast<int>(v % 10));
        v /= 10;
    } while (v != 0);
    (void)write(STDERR_FILENO, buf + i, static_cast<size_t>(24 - i));
}

inline const char *signalName(int sig)
{
    switch (sig) {
    case SIGSEGV: return "SIGSEGV";
    case SIGABRT: return "SIGABRT";
    case SIGFPE:  return "SIGFPE";
    case SIGILL:  return "SIGILL";
    case SIGBUS:  return "SIGBUS";
    default:      return "signal";
    }
}

inline constexpr int kFatalSignals[] = { SIGSEGV, SIGABRT, SIGFPE, SIGILL, SIGBUS };
inline constexpr int kNumFatalSignals = sizeof(kFatalSignals) / sizeof(kFatalSignals[0]);

inline struct sigaction g_prevHandlers[kNumFatalSignals];

// Only async-signal-safe primitives here: write(), strlen(), sigaction(), raise().
inline void crashHandler(int sig)
{
    (void)write(STDERR_FILENO, "\n[fuzz_", 7);
    (void)write(STDERR_FILENO, g_className, strlen(g_className));
    (void)write(STDERR_FILENO, "] CRASHED (", 11);
    const char *name = signalName(sig);
    (void)write(STDERR_FILENO, name, strlen(name));
    (void)write(STDERR_FILENO, ") at iteration ", 15);
    writeUInt(g_iterationCount);
    (void)write(STDERR_FILENO, " while calling: ", 16);
    (void)write(STDERR_FILENO, g_currentCall, strlen(g_currentCall));
    (void)write(STDERR_FILENO, "\n", 1);

    // Chain to whatever handler (e.g. ASan's) was installed before ours,
    // rather than unconditionally resetting to SIG_DFL — a naive clobber
    // would silently discard ASan's own, more detailed crash report for
    // wild-pointer faults it can't catch via inline instrumentation.
    for (int i = 0; i < kNumFatalSignals; i++) {
        if (kFatalSignals[i] == sig) {
            sigaction(sig, &g_prevHandlers[i], nullptr);
            break;
        }
    }
    raise(sig);
}

inline void installCrashHandler(const char *className)
{
    g_className = className;
    struct sigaction act;
    memset(&act, 0, sizeof(act));
    act.sa_handler = crashHandler;
    sigemptyset(&act.sa_mask);
    act.sa_flags = 0;
    for (int i = 0; i < kNumFatalSignals; i++)
        sigaction(kFatalSignals[i], &act, &g_prevHandlers[i]);
}

#else // _WIN32

inline LONG WINAPI crashFilter(EXCEPTION_POINTERS *)
{
    std::fprintf(stderr,
                 "\n[fuzz_%s] CRASHED (access violation) at iteration %llu while calling: %s\n",
                 g_className, static_cast<unsigned long long>(g_iterationCount), g_currentCall);
    std::fflush(stderr);
    return EXCEPTION_CONTINUE_SEARCH;
}

inline void abortHandler(int)
{
    std::fprintf(stderr,
                 "\n[fuzz_%s] CRASHED (SIGABRT) at iteration %llu while calling: %s\n",
                 g_className, static_cast<unsigned long long>(g_iterationCount), g_currentCall);
    std::fflush(stderr);
    std::signal(SIGABRT, SIG_DFL);
    std::raise(SIGABRT);
}

inline void installCrashHandler(const char *className)
{
    g_className = className;
    SetUnhandledExceptionFilter(crashFilter);
    std::signal(SIGABRT, abortHandler);
}

#endif // _WIN32

} // namespace QtFuzzRuntime
