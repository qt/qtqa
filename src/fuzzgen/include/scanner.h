#pragma once
// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// QtFuzz/scanner.h
// Scans a qtbase source tree for Qt classes and reports which module each
// class belongs to, along with whether each class has the Q_OBJECT macro.

#include "skiplist.h"
#include "modulemap.h"

#include <filesystem>
#include <optional>
#include <string>
#include <vector>
#include <cassert>
#include <cstdint>

namespace fs = std::filesystem;

namespace QtFuzz {

enum class Platform : uint32_t {
    None = 0,
    Linux = 1 << 0,
    Windows = 1 << 1,
    macOS = 1 << 2,
    iOS = 1 << 3,
    Android = 1 << 4,
    WASM = 1 << 5,
    All = ~0u
};

inline Platform operator|(Platform a, Platform b) {
    return static_cast<Platform>(static_cast<uint32_t>(a) | static_cast<uint32_t>(b));
}
inline Platform operator&(Platform a, Platform b) {
    return static_cast<Platform>(static_cast<uint32_t>(a) & static_cast<uint32_t>(b));
}
inline bool operator!(Platform a) {
    return static_cast<uint32_t>(a) == 0;
}


// A single parameter in a method signature.
struct MethodParam {
    std::string type; // e.g. "const QString &", "std::chrono::nanoseconds"
    std::string name; // e.g. "text" (may be empty for unnamed params)
    bool isNonConstRef = false;
};

// A public method signature extracted from a class header.
struct MethodSignature {
    std::string name;
    std::string returnType; // raw return type, e.g. "QCborArray", "const QString &"
    std::vector<MethodParam> params;
    bool isConst = false;
    bool hasDefault = false; // true if any param has a default
};

// DiscoveredClass:
struct DiscoveredClass {
    std::string className;
    std::string baseClassName;
    fs::path headerPath;
    std::string moduleSrcDir;
    ModuleInfo module;
    bool isAbstract = false;
    bool isDefaultConstructible = true;
    bool hasQObject = false; // true if class body contains Q_OBJECT
    Platform availableOn = Platform::All;
    std::vector<MethodSignature> publicMethods;
};

// Scans submoduleRoot/src recursively for all default-constructible Qt classes.
//
// For each public header file:
//   1. Extracts all Q-prefixed class declarations.
//   2. Checks each candidate class body for pure virtual methods.
//   3. Detects whether the class body contains the Q_OBJECT macro.
//      Classes with Q_OBJECT support introspection-based fuzzing via
//      QMetaObject in addition to direct-call fuzzing of public methods.
//      Classes without Q_OBJECT are fuzzed via direct-call only.
//   4. Associates each class with its module.
//
// moduleFilter: if non-empty, only classes in these src-dir names are
//               returned (e.g. {"network","widgets"}).
// verbose:      print progress to stdout.
std::vector<DiscoveredClass> scanClasses(const fs::path &submoduleRoot,
                                         const std::vector<std::string> &moduleFilter = { },
                                         bool verbose = false,
                                         const SkipList &skipList = SkipList{ });

// Determine which module a header path belongs to by examining its path
// relative to submoduleRoot/src/<module>/...
std::optional<std::pair<std::string /*srcDir*/, ModuleInfo>>
moduleForHeader(const fs::path &headerPath, const fs::path &submoduleRoot);

// Given a submodule root, find the header that likely declares className.
// Looks for <lowercase(className)>.h under submoduleRoot/src.
std::optional<fs::path> findHeader(const std::string &className,
                                   const fs::path &submoduleRoot);

// Find and parse a single class by name from the submodule source tree.
// Returns all discovered information including public methods and module
// membership. Faster than scanClasses() because it processes only the
// header that declares className.
// Note: does not propagate inherited abstract status. A class that is only
// abstract due to unresolved inherited pure virtuals will still compile-fail
// when instantiated — the build step in the fuzz tool catches this.
std::optional<DiscoveredClass> scanSingleClass(const std::string &className,
                                               const fs::path &submoduleRoot);

// Returns true if source (the text of a header) contains a pure virtual
// method declaration inside the class body of className.
//
// Detection strategy: locate the class declaration, walk the brace-balanced
// body at depth 1 for "= 0 ;" patterns. Errs on the side of marking classes
// abstract — false positives are safe; we simply skip generation for them.
bool classIsAbstract(const std::string &source, const std::string &className);

// Returns true if the class body of className in source contains the
// Q_OBJECT macro. Only classes with Q_OBJECT support QMetaObject-based
// introspection; all other classes are fuzzed via direct method calls only.
bool classHasQObjectMacro(const std::string &source, const std::string &className);

} // namespace QtFuzz
