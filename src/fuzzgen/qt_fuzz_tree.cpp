// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// qt_fuzz_tree (installed as qt_fuzzgen) — scans a Qt submodule source tree for
// default-constructible Qt classes and generates the complete
// <submodule>/tests/fuzzing/ tree:
//
//   <submodule>/tests/fuzzing/
//     CMakeLists.txt              (top-level; adds all module subdirs)
//     core/
//       CMakeLists.txt            (adds all class subdirs)
//       QTimer/
//         fuzz_QTimer.cpp         (introspection + direct — has Q_OBJECT)
//         CMakeLists.txt
//       QDir/
//         fuzz_QDir.cpp           (direct-call only — no Q_OBJECT)
//         CMakeLists.txt
//     network/
//       ...
//
// Classes with Q_OBJECT are fuzzed via QMetaObject introspection (slots /
// Q_INVOKABLE) as well as direct public-method calls.
// Classes without Q_OBJECT are fuzzed via direct public-method calls only.
// Classes that are abstract, not default-constructible, or have neither
// Q_OBJECT nor any extracted public methods are skipped.
//
// Usage:
//   qt_fuzzgen --submodule <path> [options]
//
// Options:
//   --submodule <path>   Path to Qt submodule root (required)
//   --out       <path>   Output root (default: <submodule>/tests/fuzzing)
//   --modules   a,b,...  Comma-separated module src-dir filter (default: all)
//   --qt-prefix <path>   Installed Qt prefix (auto-detected)
//   --time      <sec>    Fuzz duration per test (default: 30)
//   --verbose            Print every discovered class

#include "skiplist.h"
#include "codegen.h"
#include "qtdetect.h"
#include "scanner.h"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static void usage(const char *prog)
{
    std::cerr
            << "Usage: " << prog << " --submodule <path> [options]\n"
            << "Options:\n"
            << "  --submodule <path>   Qt submodule source root (required)\n"
            << "  --out       <path>   Output root (default: <submodule>/tests/fuzzing)\n"
            << "  --modules   a,b,...  Module filter, e.g. corelib,network,widgets\n"
            << "  --skiplist <path>    Skip list file (optional; may be given multiple times)\n"
            << "  --qt-prefix <path>   Qt install prefix (auto-detected)\n"
            << "  --time      <sec>    Fuzz duration in seconds (default: 30)\n"
            << "  --qml                Also include QML-exposed private classes (_p.h)\n"
            << "  --embedded           Omit project()/find_package() for parent-project inclusion\n"
            << "  --verbose            Verbose output\n";
}

static std::vector<std::string> splitComma(const std::string &s)
{
    std::vector<std::string> result;
    std::istringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, ',')) {
        if (!tok.empty())
            result.push_back(tok);
    }
    return result;
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        usage(argv[0]);
        return 1;
    }

    fs::path submoduleRoot;
    fs::path outputRoot;
    fs::path skipListFile;
    std::string qtPrefix;
    std::vector<std::string> moduleFilter;
    int timeSec = 30;
    bool verbose = false;
    bool includeQml = false;
    bool embedded = false;

    for (int i = 1; i < argc; i++) {
        std::string a(argv[i]);
        if (a == "--help" || a == "-h") {
            usage(argv[0]);
            return 0;
        } else if (a == "--submodule" && i + 1 < argc) {
            submoduleRoot = argv[++i];
        } else if (a == "--out" && i + 1 < argc) {
            outputRoot = argv[++i];
        } else if (a == "--modules" && i + 1 < argc) {
            moduleFilter = splitComma(argv[++i]);
        } else if (a == "--skiplist" && i + 1 < argc) {
            skipListFile = argv[++i];
        } else if (a == "--qt-prefix" && i + 1 < argc) {
            qtPrefix = argv[++i];
        } else if ((a == "--time" || a == "-t") && i + 1 < argc) {
            timeSec = std::atoi(argv[++i]);
        } else if (a == "--qml") {
            includeQml = true;
        } else if (a == "--embedded") {
            embedded = true;
        } else if (a == "--verbose" || a == "-v") {
            verbose = true;
        }
    }

    if (submoduleRoot.empty()) {
        const char *qtdir = std::getenv("QTDIR");
        if (qtdir)
            submoduleRoot = fs::path(qtdir) / "qtbase";
    }
    if (submoduleRoot.empty() || !fs::exists(submoduleRoot)) {
        std::cerr << "[qt_fuzzgen] ERROR: --submodule must point to a valid Qt submodule directory.\n";
        usage(argv[0]);
        return 1;
    }

    if (outputRoot.empty())
        outputRoot = submoduleRoot / "tests" / "fuzzing";

    if (qtPrefix.empty())
        qtPrefix = QtFuzz::detectQtPrefix();

    std::cout << "[qt_fuzzgen] submodule: " << submoduleRoot << "\n"
              << "[qt_fuzzgen] output   : " << outputRoot << "\n";
    if (!qtPrefix.empty())
        std::cout << "[qt_fuzzgen] Qt pfx  : " << qtPrefix << "\n";
    if (!skipListFile.empty())
        std::cout << "[qt_fuzzgen] skiplist: " << skipListFile << "\n";
    if (!moduleFilter.empty()) {
        std::cout << "[qt_fuzzgen] Modules : ";
        for (const auto &m : moduleFilter)
            std::cout << m << " ";
        std::cout << "\n";
    }

    QtFuzz::SkipList skipList(skipListFile);

    if (includeQml)
        std::cout << "[qt_fuzzgen] QML mode: including QML-exposed private classes.\n";
    std::cout << "[qt_fuzzgen] Scanning submodule/src for default-constructible Qt classes...\n";
    auto classes = QtFuzz::scanClasses(submoduleRoot, moduleFilter, verbose, skipList, includeQml);

    if (classes.empty()) {
        std::cerr << "[qt_fuzzgen] No classes found. "
                     "Check that --submodule points to a populated Qt submodule tree.\n";
        return 1;
    }
    std::cout << "[qt_fuzzgen] Found " << classes.size() << " classes.\n";

    QtFuzz::TreeGenerator::Options opts{ submoduleRoot, outputRoot,          qtPrefix, timeSec,
                                         verbose,       std::move(skipList), embedded };
    QtFuzz::TreeGenerator treeGen(opts);
    if (!treeGen.generate(classes)) {
        std::cerr << "[qt_fuzzgen] Tree generation had errors.\n";
        return 1;
    }

    std::cout << "\n[qt_fuzzgen] Done.\n";
    if (embedded) {
        std::cout << "\n[qt_fuzzgen] Embedded mode: add the generated tree to your parent\n"
                  << "CMake project with:\n"
                  << "  add_subdirectory(" << outputRoot << " <build_sub_dir>)\n";
    } else {
        std::cout << "\nNext steps:\n"
                  << "  cmake -B build -S " << outputRoot;
        if (!qtPrefix.empty())
            std::cout << " -DCMAKE_PREFIX_PATH=" << qtPrefix;
        std::cout << "\n"
                  << "  cmake --build build\n"
                  << "  ctest --test-dir build --output-on-failure -L fuzz\n";
    }

    return 0;
}
