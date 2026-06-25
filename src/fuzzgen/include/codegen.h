#pragma once
// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// QtFuzz/codegen.h
// Generates a fuzz-test .cpp and a CMakeLists.txt for a Qt class.
//
// Two fuzzing strategies are used depending on the class:
//   hasQObject == true:  introspection-based (QMetaObject slots/Q_INVOKABLE)
//                        AND direct-call (all extracted public methods).
//   hasQObject == false: direct-call only (all extracted public methods).

#include "skiplist.h"
#include "modulemap.h"
#include "scanner.h"

#include <filesystem>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace QtFuzz {

// ---------------------------------------------------------------------------
// FuzzCppGenerator
//
// Produces the self-contained fuzz test source.
//
// For classes with Q_OBJECT (hasQObject == true):
//   Uses QMetaObject at runtime to discover and call all slots /
//   Q_INVOKABLE methods, AND calls extracted public methods directly.
//
// For classes without Q_OBJECT (hasQObject == false):
//   Calls extracted public methods directly only. No QMetaObject machinery
//   is emitted — the generated code compiles for any default-constructible
//   Qt class regardless of QObject ancestry.
// ---------------------------------------------------------------------------
class FuzzCppGenerator
{
public:
    // className:     The class to fuzz, e.g. "QDir".
    // outputPath:    Destination file (will be created/overwritten).
    // appType:       The Qt application object this class requires.
    //                Defaults to Core (QCoreApplication).
    // publicMethods: Extracted public method signatures for direct-call fuzzing.
    // hasQObject:    true  → emit introspection-based fuzzing via QMetaObject
    //                        in addition to direct-call fuzzing.
    //                false → emit direct-call fuzzing only.
    // classInclude:  The include directive text (e.g. "<QLottieAnimation>" or
    //                "<QtLottie/private/qlottieanimation_p.h>").
    //                Empty means use the default "<ClassName>" form.
    FuzzCppGenerator(std::string className,
                     fs::path outputPath,
                     AppType appType = AppType::Core,
                     std::vector<MethodSignature> publicMethods = {},
                     bool hasQObject = true,
                     std::string classInclude = {});

    // Write the generated .cpp to outputPath. Returns true on success.
    bool generate() const;

    const std::string &className() const { return m_className; }
    const fs::path &outputPath() const { return m_outputPath; }
    AppType appType() const { return m_appType; }
    bool hasQObject() const { return m_hasQObject; }

private:
    std::string m_className;
    fs::path m_outputPath;
    AppType m_appType;
    std::vector<MethodSignature> m_publicMethods;
    bool m_hasQObject;
    std::string m_classInclude; // e.g. "<QtLottie/private/qlottieanimation_p.h>"

    std::string buildSource() const;

    // Template for classes that have Q_OBJECT: introspection + direct-call.
    static const char *kTemplateQObject;

    // Template for classes without Q_OBJECT: direct-call only.
    static const char *kTemplateDirectOnly;
};

// ---------------------------------------------------------------------------
// CMakeGenerator
//
// Produces a CMakeLists.txt that builds the fuzz executable and registers
// it with CTest.
// ---------------------------------------------------------------------------
class CMakeGenerator
{
public:
    struct Config {
        std::string className;
        std::string fuzzCppFilename; // just the filename, not full path
        ModuleInfo module;
        std::vector<std::string> components; // resolved deps, dep-first order
        std::string qtPrefix; // installed Qt prefix, may be empty
        int fuzzTimeSec = 30;
        std::vector<std::string> privateComponents; // e.g. {"LottiePrivate"}
    };

    explicit CMakeGenerator(Config cfg, fs::path outputPath);

    // Write the CMakeLists.txt to outputPath. Returns true on success.
    bool generate() const;

    const fs::path &outputPath() const { return m_outputPath; }

private:
    Config   m_cfg;
    fs::path m_outputPath;

    std::string buildContent() const;
};

// ---------------------------------------------------------------------------
// TreeGenerator
//
// Orchestrates generation of the full qtbase/tests/fuzzing subtree:
//
//   qtbase/tests/fuzzing/
//     CMakeLists.txt              (top-level, adds all module subdirs)
//     core/
//       CMakeLists.txt            (adds all class subdirs in this module)
//       QTimer/
//         fuzz_QTimer.cpp
//         CMakeLists.txt
//     network/
//       ...
// ---------------------------------------------------------------------------
class TreeGenerator
{
public:
    struct Options {
        fs::path submoduleRoot;
        fs::path outputRoot; // usually submoduleRoot/tests/fuzzing
        std::string qtPrefix; // may be empty
        int fuzzTimeSec = 30;
        bool verbose = false;
        SkipList skipList;
    };

    explicit TreeGenerator(Options opts);

    // Generate the entire tree for classes.
    // Also emits the top-level and per-module CMakeLists.txt files.
    // Abstract classes, non-default-constructible classes, and non-QObject
    // classes with no extracted public methods are skipped automatically.
    // Returns true if all files were written without error.
    bool generate(const std::vector<DiscoveredClass> &classes) const;

private:
    Options m_opts;

    bool writeTopLevel(const std::vector<std::string> &moduleDirs) const;
    bool writeModuleLevel(const std::string &moduleSrcDir,
                          const std::vector<std::string> &classDirs,
                          const ModuleInfo &mod) const;
};

// Returns the FuzzData struct source text for embedding in generated fuzz tests.
// Exposed so that the fuzz runner tool can embed the same struct without
// duplicating the definition.
const char *fuzzDataStructSource();

} // namespace QtFuzz
