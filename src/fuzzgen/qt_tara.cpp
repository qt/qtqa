// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// qt_tara — TARA (Threat And Risk Assessment) launcher for Qt source files.
//
// Walks .cpp / .mm / .h files in the given directory (default: the current
// working directory), selects every file that carries the marker
//
//   Qt-Security score:critical
//
// extracts the unique set of Q-prefixed class names declared in those files,
// and for every class spawns
//
//   qt_fuzz_gen <ClassName> --qt-prefix <prefix>
//
// as a parallel background process.  All children are started before any is
// waited on, so the work runs concurrently.  The tool exits with the count
// of non-zero child exit codes (0 means all succeeded).
//
// Usage:
//   qt_tara --qt-prefix <path> [<directory>]
//
// Options:
//   --qt-prefix <path>   Qt install prefix passed through to qt_fuzz_gen (required)
//   <directory>          Directory to scan (default: current working directory)
//   -h / --help          Print this help and exit

#include <filesystem>
#include <fstream>
#include <iostream>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  define NOMINMAX
#  include <windows.h>
#else
#  include <sys/wait.h>
#  include <unistd.h>
#endif

namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
// Cross-platform background-process helpers
// ---------------------------------------------------------------------------

#ifdef _WIN32

using ProcessHandle = HANDLE;
static const ProcessHandle kInvalidHandle = INVALID_HANDLE_VALUE;

static ProcessHandle spawnBackground(const std::string &exe, const std::vector<std::string> &args)
{
    // Build a quoted command line: "exe" "arg1" "arg2" ...
    std::string cmd = "\"" + exe + "\"";
    for (const auto &a : args)
        cmd += " \"" + a + "\"";

    STARTUPINFOA si = { };
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = { };

    if (!CreateProcessA(nullptr, const_cast<char *>(cmd.c_str()), nullptr, nullptr, FALSE, 0,
                        nullptr, nullptr, &si, &pi)) {
        std::cerr << "[qt_tara] CreateProcess failed (error " << GetLastError() << "): " << cmd
                  << "\n";
        return kInvalidHandle;
    }
    CloseHandle(pi.hThread); // handle not needed
    return pi.hProcess;
}

static int waitAll(std::vector<ProcessHandle> &handles)
{
    int failed = 0;
    for (auto h : handles) {
        if (h == kInvalidHandle) {
            ++failed;
            continue;
        }
        WaitForSingleObject(h, INFINITE);
        DWORD code = 0;
        if (GetExitCodeProcess(h, &code) && code != 0)
            ++failed;
        CloseHandle(h);
    }
    return failed;
}

#else // POSIX

using ProcessHandle = pid_t;
static const ProcessHandle kInvalidHandle = -1;

static ProcessHandle spawnBackground(const std::string &exe, const std::vector<std::string> &args)
{
    const pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "[qt_tara] fork() failed: " << exe << "\n";
        return kInvalidHandle;
    }
    if (pid == 0) {
        std::vector<const char *> argv;
        argv.push_back(exe.c_str());
        for (const auto &a : args)
            argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execv(exe.c_str(), const_cast<char **>(argv.data()));
        _exit(127);
    }
    return pid;
}

static int waitAll(std::vector<ProcessHandle> &handles)
{
    int failed = 0;
    for (auto pid : handles) {
        if (pid == kInvalidHandle) {
            ++failed;
            continue;
        }
        int wstatus = 0;
        waitpid(pid, &wstatus, 0);
        if (!WIFEXITED(wstatus) || WEXITSTATUS(wstatus) != 0)
            ++failed;
    }
    return failed;
}

#endif

// ---------------------------------------------------------------------------
// File / class-name helpers
// ---------------------------------------------------------------------------

static std::string readFile(const fs::path &p)
{
    std::ifstream f(p);
    if (!f)
        return { };
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

static bool hasCriticalMarker(const std::string &src)
{
    return src.find("Qt-Security score:critical") != std::string::npos;
}

// Collect Q-prefixed class names: matches
//   class [Q_SOMETHING_EXPORT] QFoo
// Requires QFoo to start with Q followed by an upper-case letter so that
// template parameters and misc. identifiers are excluded.
static void collectClassNames(const std::string &src, std::set<std::string> &out)
{
    // Group 1: export macro (e.g. Q_CORE_EXPORT) — only exported classes are in scope.
    // Group 2: class name
    static const std::regex kRe(R"(\bclass\s+(Q_\w+_EXPORT)\s+(Q[A-Z]\w+)\b)",
                                std::regex::optimize);

    for (auto it = std::sregex_iterator(src.cbegin(), src.cend(), kRe);
         it != std::sregex_iterator(); ++it) {
        const std::string name = (*it)[2].str();
        // Skip macro-like tokens (e.g. QT_DEPRECATED_VERSION_X_6_15 appearing
        // as a deprecation annotation between the export macro and the real name).
        if (name.find('_') != std::string::npos)
            continue;
        out.insert(name);
    }
}

// A private header is in scope for --qml when it registers a QML type
// (QML_ELEMENT / QML_NAMED_ELEMENT) that exposes properties.
static bool hasQmlType(const std::string &src)
{
    const bool hasRegistration = src.find("QML_ELEMENT") != std::string::npos
            || src.find("QML_NAMED_ELEMENT") != std::string::npos;
    return hasRegistration && src.find("Q_PROPERTY") != std::string::npos;
}

// For _p.h files with QML_ELEMENT / QML_NAMED_ELEMENT: class names need not be
// Q-prefixed or exported (e.g. SphereGeometry, StateMachine, ColorGradient).
static void collectQmlClassNames(const std::string &src, std::set<std::string> &out)
{
    static const std::regex kRe(R"(\bclass\s+(?:Q_\w+_EXPORT\s+)?([A-Z][A-Za-z0-9]+)\b)",
                                std::regex::optimize);

    for (auto it = std::sregex_iterator(src.cbegin(), src.cend(), kRe);
         it != std::sregex_iterator(); ++it) {
        const std::string name = (*it)[1].str();
        if (name.find('_') != std::string::npos)
            continue;
        out.insert(name);
    }
}

// ---------------------------------------------------------------------------
// Locate qt_fuzz_gen next to our own binary, fall back to PATH
// ---------------------------------------------------------------------------

static std::string findFuzzGen(const char *argv0)
{
#ifdef _WIN32
    static const char kName[] = "qt_fuzz_gen.exe";
#else
    static const char kName[] = "qt_fuzz_gen";
#endif

    std::error_code ec;
    fs::path sibling = fs::absolute(fs::path(argv0), ec).parent_path() / kName;
    if (!ec && fs::exists(sibling))
        return sibling.string();
    return kName; // rely on PATH
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

int main(int argc, char *argv[])
{
    std::string qtPrefix;
    std::string scanDirArg;
    bool listOnly = false;
    bool includeQml = false;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--qt-prefix" && i + 1 < argc) {
            qtPrefix = argv[++i];
        } else if (a.rfind("--qt-prefix=", 0) == 0) {
            qtPrefix = a.substr(12);
        } else if (a == "--list-classes") {
            listOnly = true;
        } else if (a == "--qml") {
            includeQml = true;
        } else if (a == "-h" || a == "--help") {
            std::cout
                    << "Usage: qt_tara --qt-prefix <path> [<directory>]\n\n"
                    << "  Scans <directory> (default: current directory) for .cpp / .mm / .h\n"
                    << "  files that carry the 'Qt-Security score:critical' marker, extracts\n"
                    << "  all Q-prefixed class names, and spawns\n\n"
                    << "    qt_fuzz_gen <ClassName> --qt-prefix <path>\n\n"
                    << "  in parallel for every unique class found.\n\n"
                    << "Options:\n"
                    << "  --qt-prefix <path>   Qt install prefix (required unless --list-classes)\n"
                    << "  --list-classes        Print in-scope class names and exit without "
                       "running qt_fuzz_gen\n"
                    << "  --qml                Pass --qml to qt_fuzz_gen (include QML-exposed "
                       "private classes)\n"
                    << "  <directory>          Directory to scan (default: .)\n";
            return 0;
        } else if (a.rfind("--", 0) != 0) {
            scanDirArg = a;
        } else {
            std::cerr << "[qt_tara] Unknown option: " << a << "  (try --help)\n";
            return 1;
        }
    }

    if (qtPrefix.empty() && !listOnly) {
        std::cerr << "[qt_tara] Error: --qt-prefix <path> is required.\n";
        return 1;
    }

    const fs::path root = scanDirArg.empty() ? fs::current_path() : fs::path(scanDirArg);
    if (!fs::is_directory(root)) {
        std::cerr << "[qt_tara] Not a directory: " << root.string() << "\n";
        return 1;
    }

    // ── 1. Read all source files, collect security-critical class names ──────────

    std::set<std::string> classes;
    std::error_code ec;
    for (const auto &entry : fs::recursive_directory_iterator(root, ec)) {
        if (ec) {
            ec.clear();
            continue;
        }
        if (!entry.is_regular_file())
            continue;

        const auto &ext = entry.path().extension();
        if (ext != ".cpp" && ext != ".mm" && ext != ".h")
            continue;

        const std::string src = readFile(entry.path());
        if (!hasCriticalMarker(src))
            continue;

        const std::string stem = entry.path().stem().string();
        std::cout << "[qt_tara] critical: " << entry.path().filename().string() << "\n";

        // Private headers (*_p.h) contain implementation classes, not public API —
        // unless --qml is active and the file exposes a QML type + Q_PROPERTY.
        if (stem.size() >= 2 && stem[stem.size() - 2] == '_' && stem[stem.size() - 1] == 'p') {
            if (!includeQml || !hasQmlType(src))
                continue;
            collectQmlClassNames(src, classes);
            continue;
        }

        collectClassNames(src, classes);

        // A critical .cpp / .mm usually only contains definitions; the class
        // declaration (with the export macro) lives in the same-stem .h.
        // Scan that header too so classes like QImage are not missed.
        if (ext == ".cpp" || ext == ".mm") {
            const fs::path hFile = entry.path().parent_path() / (stem + ".h");
            if (fs::exists(hFile))
                collectClassNames(readFile(hFile), classes);

            // With --qml, QML types may be declared in the same-stem private
            // header instead, without the header carrying the marker itself.
            if (includeQml) {
                const fs::path pFile = entry.path().parent_path() / (stem + "_p.h");
                if (fs::exists(pFile)) {
                    const std::string pSrc = readFile(pFile);
                    if (hasQmlType(pSrc))
                        collectQmlClassNames(pSrc, classes);
                }
            }
        }
    }

    if (classes.empty()) {
        std::cout << "[qt_tara] No classes found in Qt-Security score:critical files.\n";
        return 0;
    }

    if (listOnly) {
        std::cout << "[qt_tara] " << classes.size() << " class(es) in scope:\n";
        for (const auto &cls : classes)
            std::cout << "  " << cls << "\n";
        return 0;
    }

    std::cout << "[qt_tara] Spawning qt_fuzz_gen for " << classes.size()
              << " class(es) in parallel:\n";

    // ── 2. Spawn one qt_fuzz_gen process per class ───────────────────────────

    const std::string fuzzGen = findFuzzGen(argv[0]);
    std::vector<ProcessHandle> handles;
    handles.reserve(classes.size());

    for (const auto &cls : classes) {
        std::cout << "[qt_tara]   → " << cls << "\n";
        std::vector<std::string> fgArgs = { cls, "--qt-prefix", qtPrefix };
        if (includeQml)
            fgArgs.push_back("--qml");
        handles.push_back(spawnBackground(fuzzGen, fgArgs));
    }

    // ── 3. Wait for all children ─────────────────────────────────────────────

    const int failed = waitAll(handles);
    if (failed > 0)
        std::cerr << "[qt_tara] " << failed << " process(es) exited with errors.\n";
    else
        std::cout << "[qt_tara] All done.\n";

    return failed > 0 ? 1 : 0;
}
