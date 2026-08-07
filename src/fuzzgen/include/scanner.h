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
    bool isNestedStruct = false; // true when type was qualified from a nested struct
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
    bool isQmlExposed = false;           // true for classes from _p.h with QML macros
    std::string privateHeaderInclude;    // e.g. "QtLottie/private/qlottieanimation_p.h"
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
                                         const SkipList &skipList = SkipList{ },
                                         bool includeQmlPrivate = false);

// Determine which module a header path belongs to by examining its path
// relative to submoduleRoot/src/<module>/...
std::optional<std::pair<std::string /*srcDir*/, ModuleInfo>>
moduleForHeader(const fs::path &headerPath, const fs::path &submoduleRoot);

// Given a submodule root, find the header that likely declares className.
// Looks for <lowercase(className)>.h under submoduleRoot/src.
// When includeQmlPrivate is true, also tries <lowercase(className)>_p.h.
std::optional<fs::path> findHeader(const std::string &className,
                                   const fs::path &submoduleRoot,
                                   bool includeQmlPrivate = false);

// Find and parse a single class by name from the submodule source tree.
// Returns all discovered information including public methods and module
// membership. Faster than scanClasses() because it processes only the
// header that declares className.
// Note: does not propagate inherited abstract status. A class that is only
// abstract due to unresolved inherited pure virtuals will still compile-fail
// when instantiated — the build step in the fuzz tool catches this.
std::optional<DiscoveredClass> scanSingleClass(const std::string &className,
                                               const fs::path &submoduleRoot,
                                               bool includeQmlPrivate = false);

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

// A class's declaration/definition span in some file's text, as 1-based,
// inclusive line numbers: for a header, the span of "class Foo { ... }";
// for a source file, the span of one out-of-line "Foo::member(...) { ... }"
// definition. A class with several out-of-line definitions in the same
// source file (e.g. QDomDocument has many methods defined in qdom.cpp)
// appears once per definition, not once per class, so a caller (qtdiff) can
// test each definition's own line range against a specific diff hunk
// instead of treating "this file changed somewhere" as "every class this
// file mentions changed".
struct ClassSpan {
    std::string className;
    int startLine = 0;
    int endLine = 0;
};

// Returns the declaration span of every Q-prefixed class in headerContent.
// Uses the same class-declaration parser as scanClasses(), scoped to one
// file's text with no export/module/stem filtering.
std::vector<ClassSpan> classDeclarationSpansIn(const std::string &headerContent);

// Returns the span of every out-of-line "ClassName::member(...) { ... }"
// definition in sourceContent that has an actual body. A qualified name
// followed by "(...)" with no body — a plain call statement, or
// "= default;"/"= delete;" — is not a definition and is excluded:
// attributing a whole file to a class just because one of its static
// methods is *called* there would be a false positive.
std::vector<ClassSpan> classDefinitionSpansIn(const std::string &sourceContent);

// Returns the distinct class names from classDeclarationSpansIn(headerContent),
// discarding the per-class line spans. qtdiff itself calls
// classDeclarationSpansIn() directly (it needs the spans to test against a
// diff hunk's changed lines); this wrapper is for callers that just want
// "which classes does this header mention" with no line-range filtering.
std::vector<std::string> classesDeclaredIn(const std::string &headerContent);

// Returns the distinct class names from classDefinitionSpansIn(sourceContent),
// discarding the per-class line spans. qtdiff itself calls
// classDefinitionSpansIn() directly (it needs the spans to test against a
// diff hunk's changed lines); this wrapper is for callers that just want
// "which classes are implemented in this source file" with no line-range
// filtering.
std::vector<std::string> classesDefinedIn(const std::string &sourceContent);

} // namespace QtFuzz
