// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// qt_fuzz_gen — generates a fuzz test .cpp and optional CMakeLists.txt for
// a single Qt class.
//
// When --submodule is provided the tool detects whether the class has the
// Q_OBJECT macro and selects the appropriate fuzzing strategy:
//   - Q_OBJECT present : introspection (QMetaObject) + direct-call.
//   - Q_OBJECT absent  : direct-call only.
//
// Without --submodule the tool falls back to direct-call only (safe for all
// classes regardless of QObject ancestry).
//
// Usage:
//   qt_fuzz_gen <ClassName> [options]
//
// Options:
//   --out        <file>   Output .cpp (default: fuzz_<Class>.cpp)
//   --cmake      <file>   Also generate CMakeLists.txt
//   --submodule  <path>   Path to Qt submodule (used for module/AppType and Q_OBJECT detection)
//   --qt-prefix  <path>   Installed Qt prefix (auto-detected if omitted)
//   --time       <sec>    Fuzz duration passed to ctest (default: 30)

#include "skiplist.h"
#include "codegen.h"
#include "modulemap.h"
#include "qtdetect.h"
#include "scanner.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

namespace fs = std::filesystem;

static void usage(const char *prog)
{
    std::cerr << "Usage: " << prog << " <ClassName> [options]\n"
              << "Options:\n"
              << "  --out        <file>   Output .cpp (default: fuzz_<Class>.cpp)\n"
              << "  --cmake      <file>   Also emit a CMakeLists.txt\n"
              << "  --submodule  <path>   Qt submodule root (enables Q_OBJECT detection and module "
                 "lookup)\n"
              << "  --qt-prefix  <path>   Qt install prefix (auto-detected)\n"
              << "  --skiplist  <path>   Path to skip list file (optional)\n"
              << "  --time       <sec>    Fuzz duration for ctest (default: 30)\n";
}

static std::string readFile(const fs::path &p)
{
    std::ifstream f(p);
    if (!f)
        return { };
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        usage(argv[0]);
        return 1;
    }

    std::string className;
    std::string outFile;
    std::string cmakeFile;
    fs::path submoduleRoot;
    fs::path skipListFile;
    std::string qtPrefix;
    int timeSec = 30;

    for (int i = 1; i < argc; i++) {
        std::string a(argv[i]);
        if (a == "--help" || a == "-h") {
            usage(argv[0]);
            return 0;
        } else if (a == "--out" && i + 1 < argc) {
            outFile = argv[++i];
        } else if (a == "--cmake" && i + 1 < argc) {
            cmakeFile = argv[++i];
        } else if (a == "--submodule" && i + 1 < argc) {
            submoduleRoot = argv[++i];
        } else if (a == "--qt-prefix" && i + 1 < argc) {
            qtPrefix = argv[++i];
        } else if (a == "--skiplist" && i + 1 < argc) {
            skipListFile = argv[++i];
        } else if ((a == "--time" || a == "-t") && i + 1 < argc) {
            timeSec = std::atoi(argv[++i]);
        } else if (a.rfind("--", 0) != 0) {
            className = a;
        }
    }

    if (className.empty()) {
        usage(argv[0]);
        return 1;
    }
    if (outFile.empty())
        outFile = "fuzz_" + className + ".cpp";

    // Resolve module info (and AppType) if qtbase is available.
    // Fall back to Core when it is not — always safe, if suboptimal.
    QtFuzz::AppType appType = QtFuzz::AppType::Core;
    QtFuzz::ModuleInfo mod = { "Core", "Qt6::Core", { }, QtFuzz::AppType::Core };
    bool hasQObject = false; // default: direct-call only (always compiles)

    if (!submoduleRoot.empty() && fs::exists(submoduleRoot)) {
        auto headerOpt = QtFuzz::findHeader(className, submoduleRoot);
        if (headerOpt) {
            // Detect Q_OBJECT from the actual header source.
            std::string src = readFile(*headerOpt);
            hasQObject = !src.empty() && QtFuzz::classHasQObjectMacro(src, className);

            auto modOpt = QtFuzz::moduleForHeader(*headerOpt, submoduleRoot);
            if (modOpt) {
                mod     = modOpt->second;
                appType = mod.appType;
            }
        } else {
            std::cerr << "WARNING: header for " << className
                      << " not found under " << submoduleRoot
                      << ". Using Qt6::Core and direct-call-only as fallback.\n";
        }
    }

    QtFuzz::SkipList skipList(skipListFile);
    if (skipList.isClassSkipped(className)) {
        std::cerr << "[qt_fuzz_gen] " << className
                  << " is in the skip list — skipping generation.\n";
        return 0;
    }

    std::cout << "[qt_fuzz_gen] Class    : " << className << "\n"
              << "[qt_fuzz_gen] Strategy : "
              << (hasQObject ? "introspection + direct-call" : "direct-call only")
              << "\n";

    // Generate fuzz .cpp
    QtFuzz::FuzzCppGenerator cppGen(className, outFile, appType, {}, hasQObject);
    if (!cppGen.generate())
        return 1;
    std::cout << "Written: " << outFile
              << "  (app: " << QtFuzz::appTypeInfo(appType).className << ")\n";

    // Optionally generate CMakeLists.txt
    if (!cmakeFile.empty()) {
        if (qtPrefix.empty())
            qtPrefix = QtFuzz::detectQtPrefix();

        auto components = QtFuzz::resolveComponents(mod);
        const std::string fuzzFilename = fs::path(outFile).filename().string();

        QtFuzz::CMakeGenerator::Config cfg{
            className, fuzzFilename, mod, components, qtPrefix, timeSec
        };
        QtFuzz::CMakeGenerator cmakeGen(std::move(cfg), cmakeFile);
        if (!cmakeGen.generate())
            return 1;
        std::cout << "Written: " << cmakeFile << "\n";
    }

    return 0;
}
