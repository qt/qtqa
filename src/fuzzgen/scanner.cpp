// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// Scans qtbase/src headers for Qt classes suitable for fuzz testing.
//
// Strategy:
//   For each .h file under qtbase/src/<module>/...
//     1. Read the file.
//     2. Strip block comments so that class declarations inside /* ... */
//        are never matched.
//     3. Search for all Q-prefixed class declarations (with or without
//        inheritance). No QObject ancestry is required.
//     4. For each candidate class, scan its own body for:
//          a. the Q_OBJECT macro — enables introspection-based fuzzing.
//          b. pure-virtual method names — for abstract detection.
//          c. constructors — for default-constructibility detection.
//          d. public non-signal methods with their parameter signatures —
//             for direct-call fuzzing.
//     5. Walk backwards from the class declaration for platform guards.
//     6. Record the canonical class name, module, and all flags.
//
// Fuzzing strategy per class:
//   - hasQObject == true:  introspection-based (QMetaObject slots/invokables)
//                          AND direct-call (all public methods).
//   - hasQObject == false: direct-call only (all public methods).
//
// Abstract detection uses pure-virtual name sets:
//   - A class is directly abstract if its own body declares any "= 0".
//   - A class inherits abstract status from a base only if the base has
//     unresolved pure virtuals that the subclass doesn't override.
//
// Universe construction (all Q-prefixed classes):
//   Phase 1 – collect all Q-prefixed class declarations from all headers.
//   Phase 2 – propagate unresolved pure virtuals through the chain.
//   Phase 3 – collect results for requested modules.

#include "scanner.h"

#include <algorithm>
#include <cassert>
#include <cstring>
#include <fstream>
#include <iostream>
#include <regex>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace QtFuzz {

namespace {

std::string readFile(const fs::path &p)
{
    std::ifstream f(p);
    if (!f)
        return {};
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

std::string stripBlockComments(const std::string &source)
{
    std::string result;
    result.reserve(source.size());
    size_t i = 0;
    while (i < source.size()) {
        if (i + 1 < source.size() && source[i] == '/' && source[i + 1] == '*') {
            i += 2;
            while (i < source.size()) {
                if (i + 1 < source.size() && source[i] == '*' && source[i + 1] == '/') {
                    i += 2;
                    break;
                }
                result += (source[i] == '\n') ? '\n' : ' ';
                ++i;
            }
        } else {
            result += source[i++];
        }
    }
    return result;
}

// Returns the preprocessor keyword of a source line, or "" if the line is not
// a preprocessor directive.  E.g. "#  if defined(X)" → "if", "#endif" → "endif".
static std::string ppKeyword(const std::string &line)
{
    size_t p = 0;
    while (p < line.size() && std::isspace(static_cast<unsigned char>(line[p])))
        ++p;
    if (p >= line.size() || line[p] != '#')
        return { };
    ++p;
    while (p < line.size() && std::isspace(static_cast<unsigned char>(line[p])))
        ++p;
    size_t kwStart = p;
    while (p < line.size() && std::isalpha(static_cast<unsigned char>(line[p])))
        ++p;
    return line.substr(kwStart, p - kwStart);
}

// Elides the entire content of any #if QT_*_REMOVED_SINCE(...) block by
// replacing all lines in the block — including the #if and #endif lines —
// with blank lines (newlines are preserved so offsets are unaffected).
//
// Rationale: QT_*_REMOVED_SINCE guards wrap API that has been removed from
// the compiled library.  A text-based scanner sees those declarations even
// though they will never be compiled, which causes the generator to emit
// fuzz calls for non-existent symbols.  Eliding the blocks before any
// further parsing prevents those false matches.
//
// Nested #if/#endif blocks are handled correctly via a depth counter.
std::string elideRemovedSinceBlocks(const std::string &source)
{
    std::string result;
    result.reserve(source.size());

    size_t i = 0;
    while (i < source.size()) {
        // Grab one line (not including the trailing '\n').
        size_t lineStart = i;
        while (i < source.size() && source[i] != '\n')
            ++i;
        size_t lineEnd = i;
        bool hasNewline = (i < source.size());
        if (hasNewline)
            ++i; // consume '\n'

        std::string line = source.substr(lineStart, lineEnd - lineStart);
        std::string kw = ppKeyword(line);

        // Detect #if / #ifdef / #ifndef lines that mention _REMOVED_SINCE.
        bool isRemovedIf = (kw == "if" || kw == "ifdef" || kw == "ifndef") &&
                           line.find("_REMOVED_SINCE") != std::string::npos;

        if (isRemovedIf) {
            // Blank out the opening #if line.
            result.append(lineEnd - lineStart, ' ');
            if (hasNewline)
                result += '\n';

            // Consume lines until the matching #endif, tracking nesting.
            int depth = 1;
            while (i < source.size() && depth > 0) {
                size_t bStart = i;
                while (i < source.size() && source[i] != '\n')
                    ++i;
                size_t bEnd = i;
                bool bHasNewline = (i < source.size());
                if (bHasNewline)
                    ++i;

                std::string bline = source.substr(bStart, bEnd - bStart);
                std::string bkw = ppKeyword(bline);

                if (bkw == "if" || bkw == "ifdef" || bkw == "ifndef")
                    ++depth;
                else if (bkw == "endif")
                    --depth;

                // Blank out every line inside the removed block.
                result.append(bEnd - bStart, ' ');
                if (bHasNewline)
                    result += '\n';
            }
        } else {
            result += line;
            if (hasNewline)
                result += '\n';
        }
    }
    return result;
}

// Elide method declarations inside blocks guarded exclusively by non-Linux
// platform macros (Q_OS_WIN*, Q_OS_MAC*, Q_OS_IOS, Q_OS_ANDROID, …).
//
// The heuristic: if the opening #if/#ifdef/#ifndef line mentions one of the
// non-Linux OS macros AND does NOT also mention Q_OS_LINUX or Q_OS_UNIX,
// blank the entire block (including the guard lines).  This prevents methods
// like QProcess::nativeArguments() (Windows-only) from being emitted.
std::string elideNonLinuxPlatformBlocks(const std::string &source)
{
    static const std::regex kNonLinuxOs(
        R"(\bQ_OS_(WIN\w*|WINDOWS|MAC\w*|DARWIN|IOS|TVOS|WATCHOS|VISIONOS|ANDROID\w*|WASM|VXWORKS|INTEGRITY|QNX)\b)",
        std::regex::optimize);
    static const std::regex kLinuxOs(
        R"(\bQ_OS_(LINUX|UNIX)\b)",
        std::regex::optimize);

    std::string result;
    result.reserve(source.size());

    size_t i = 0;
    while (i < source.size()) {
        size_t lineStart = i;
        while (i < source.size() && source[i] != '\n')
            ++i;
        size_t lineEnd    = i;
        bool   hasNewline = (i < source.size());
        if (hasNewline)
            ++i;

        std::string line = source.substr(lineStart, lineEnd - lineStart);
        std::string kw   = ppKeyword(line);

        bool isIfLike = (kw == "if" || kw == "ifdef" || kw == "ifndef");
        bool mentionsNonLinux = isIfLike && std::regex_search(line, kNonLinuxOs);
        bool mentionsLinux = isIfLike && std::regex_search(line, kLinuxOs);

        if (mentionsNonLinux && !mentionsLinux) {
            // Blank the opening guard line.
            result.append(lineEnd - lineStart, ' ');
            if (hasNewline)
                result += '\n';

            int depth = 1;
            while (i < source.size() && depth > 0) {
                size_t bStart = i;
                while (i < source.size() && source[i] != '\n')
                    ++i;
                size_t bEnd = i;
                bool bHasNewline = (i < source.size());
                if (bHasNewline)
                    ++i;

                std::string bline = source.substr(bStart, bEnd - bStart);
                std::string bkw   = ppKeyword(bline);

                if (bkw == "if" || bkw == "ifdef" || bkw == "ifndef")
                    ++depth;
                else if (bkw == "endif")
                    --depth;

                result.append(bEnd - bStart, ' ');
                if (bHasNewline)
                    result += '\n';
            }
        } else {
            result += line;
            if (hasNewline)
                result += '\n';
        }
    }
    return result;
}

// Elide blocks guarded by a simple '#ifdef X' where X is an optional
// compile-time feature macro that may not be defined in a standard Linux
// Qt desktop build (e.g. QT_KEYPAD_NAVIGATION, Q_QDOC, QT_NO_WHEELEVENT).
//
// In a standard desktop build, '#ifdef QT_KEYPAD_NAVIGATION' is inactive,
// so methods like setNavigationMode() inside that block do not exist and
// must not appear in generated fuzz tests.
//
// Safe macros (NOT elided):
//   Q_OS_LINUX, Q_OS_UNIX — Linux-platform code; already handled upstream.
//   QT_DEPRECATED_SINCE, QT_REMOVED_SINCE — handled by elideRemovedSinceBlocks.
//
// Only positive '#ifdef' guards are elided.  '#ifndef QT_NO_FEATURE' blocks
// are kept because in a standard Qt build those features ARE present and
// the enclosed methods DO exist.
std::string elideOptionalIfdefBlocks(const std::string &source)
{
    static const std::regex kSafeIfdef(
        R"(\b(Q_OS_LINUX|Q_OS_UNIX|QT_DEPRECATED_SINCE|QT_REMOVED_SINCE)\b)",
        std::regex::optimize);

    std::string result;
    result.reserve(source.size());

    size_t i = 0;
    while (i < source.size()) {
        size_t lineStart = i;
        while (i < source.size() && source[i] != '\n')
            ++i;
        size_t lineEnd = i;
        bool hasNewline = (i < source.size());
        if (hasNewline)
            ++i;

        std::string line = source.substr(lineStart, lineEnd - lineStart);
        std::string kw = ppKeyword(line);

        // Only elide simple '#ifdef X' blocks (not '#ifndef', '#if expr').
        bool isIfdef = (kw == "ifdef");
        bool isSafe = isIfdef && std::regex_search(line, kSafeIfdef);

        if (isIfdef && !isSafe) {
            // Blank the opening #ifdef line and everything through #endif.
            result.append(lineEnd - lineStart, ' ');
            if (hasNewline)
                result += '\n';

            int depth = 1;
            while (i < source.size() && depth > 0) {
                size_t bStart = i;
                while (i < source.size() && source[i] != '\n')
                    ++i;
                size_t bEnd = i;
                bool bHasNewline = (i < source.size());
                if (bHasNewline)
                    ++i;

                std::string bline = source.substr(bStart, bEnd - bStart);
                std::string bkw   = ppKeyword(bline);

                if (bkw == "if" || bkw == "ifdef" || bkw == "ifndef")
                    ++depth;
                else if (bkw == "endif")
                    --depth;

                result.append(bEnd - bStart, ' ');
                if (bHasNewline)
                    result += '\n';
            }
        } else {
            result += line;
            if (hasNewline)
                result += '\n';
        }
    }
    return result;
}

// Strip preprocessor directives (#if, #ifdef, #ifndef, #else, #elif,
// #endif, #define, #undef) from a string, replacing the directive line
// with spaces (preserving newlines so line counts are unaffected).
// This prevents macro names like QT_CONFIG, QT_CORE_REMOVED_SINCE, and
// `defined` from appearing as false method-name matches.
std::string stripPreprocessorLines(const std::string &source)
{
    std::string result;
    result.reserve(source.size());
    size_t i = 0;
    while (i < source.size()) {
        // Check for '#' at start of line (possibly preceded by whitespace).
        while (i < source.size() && source[i] != '\n') {
            if (source[i] == '#') {
                // Replace the rest of this line with spaces.
                while (i < source.size() && source[i] != '\n') {
                    result += ' ';
                    ++i;
                }
                goto next_line;
            } else if (!std::isspace(static_cast<unsigned char>(source[i]))) {
                // Non-whitespace before '#' — not a preprocessor line.
                break;
            }
            result += source[i++];
        }
        // Copy rest of line normally.
        while (i < source.size() && source[i] != '\n')
            result += source[i++];
next_line:
        if (i < source.size()) result += source[i++]; // '\n'
    }
    return result;
}

// ---------------------------------------------------------------------------
// Q_OBJECT macro detection
// ---------------------------------------------------------------------------

// Returns true if the class body at classPos (opening '{') contains the
// Q_OBJECT macro at depth 1 (directly inside the class, not in a nested
// class or method body).
bool bodyHasQObjectMacro(const std::string &source, size_t classPos)
{
    size_t pos = source.find('{', classPos);
    if (pos == std::string::npos)
        return false;

    int depth = 0;
    size_t i = pos;
    while (i < source.size()) {
        const char c = source[i];
        if (c == '{') {
            ++depth;
        } else if (c == '}') {
            --depth;
            if (depth == 0)
                break;
        }
        if (depth == 1 && source.compare(i, 8, "Q_OBJECT") == 0) {
            size_t after = i + 8;
            if (after >= source.size()
                || (!std::isalnum(static_cast<unsigned char>(source[after]))
                    && source[after] != '_')) {
                return true;
            }
        }
        ++i;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Pure-virtual detection and name extraction
// ---------------------------------------------------------------------------

std::string extractMethodName(const std::string &ctx)
{
    if (ctx.empty())
        return { };

    int depth = 1;
    size_t parenPos = std::string::npos;

    for (size_t i = ctx.size() - 1; i > 0; --i) {
        const char c = ctx[i - 1];
        if (c == ')') {
            ++depth;
        } else if (c == '(') {
            --depth;
            if (depth == 0) {
                parenPos = i - 1;
                break;
            }
        }
    }

    if (parenPos == std::string::npos || parenPos == 0)
        return {};

    size_t nameEnd = parenPos;
    while (nameEnd > 0 && std::isspace(static_cast<unsigned char>(ctx[nameEnd - 1])))
        --nameEnd;

    if (nameEnd == 0)
        return {};

    size_t nameStart = nameEnd;
    while (nameStart > 0 &&
           (std::isalnum(static_cast<unsigned char>(ctx[nameStart - 1]))
            || ctx[nameStart - 1] == '_'))
        --nameStart;

    if (nameStart == nameEnd)
        return {};

    return ctx.substr(nameStart, nameEnd - nameStart);
}

std::unordered_set<std::string>
collectPureVirtualNames(const std::string &source, size_t classPos)
{
    std::unordered_set<std::string> names;

    size_t pos = source.find('{', classPos);
    if (pos == std::string::npos)
        return names;

    static const std::regex kPureVirtualRe(
        R"(\)\s*(?:(?:const|volatile|noexcept|override|final|Q_DECL_\w+)\s*)*=\s*0\s*[;)])",
        std::regex::optimize);

    int depth = 0;
    bool inString = false;
    bool inChar = false;
    size_t i = pos;
    size_t bodyStart = pos + 1;

    while (i < source.size()) {
        const char c = source[i];

        if (!inChar && c == '"' && (i == 0 || source[i - 1] != '\\'))
            inString = !inString;
        else if (!inString && c == '\'' && (i == 0 || source[i - 1] != '\\'))
            inChar = !inChar;

        if (inString || inChar) {
            ++i;
            continue;
        }

        if (c == '/' && i + 1 < source.size() && source[i + 1] == '/') {
            i = source.find('\n', i);
            if (i == std::string::npos)
                break;
            continue;
        }
        if (c == '/' && i + 1 < source.size() && source[i + 1] == '*') {
            i = source.find("*/", i + 2);
            if (i == std::string::npos)
                break;
            i += 2;
            continue;
        }

        if (c == '{') {
            ++depth;
        } else if (c == '}') {
            --depth;
            if (depth == 0)
                break;
        }

        if (depth == 1 && c == ')') {
            auto sub = source.substr(i, std::min<size_t>(64, source.size() - i));
            if (std::regex_search(sub, kPureVirtualRe)) {
                size_t lookbackStart = (i > bodyStart + 512) ? i - 512 : bodyStart;
                std::string ctx = source.substr(lookbackStart, i - lookbackStart + 1);
                std::string name = extractMethodName(ctx);
                if (!name.empty())
                    names.insert(name);
            }
        }

        ++i;
    }
    return names;
}

bool bodyHasPureVirtual(const std::string &source, size_t classPos)
{
    return !collectPureVirtualNames(source, classPos).empty();
}

std::unordered_set<std::string>
collectDeclaredMethodNames(const std::string &source, size_t classPos)
{
    std::unordered_set<std::string> names;

    size_t pos = source.find('{', classPos);
    if (pos == std::string::npos)
        return names;

    std::string body;
    int depth = 0;
    size_t i = pos;
    while (i < source.size()) {
        const char c = source[i];
        if (c == '{') {
            ++depth;
            body += (depth > 1) ? ' ' : '{';
        } else if (c == '}') {
            --depth;
            if (depth == 0)
                break;
            body += ' ';
        } else if (depth >= 1) {
            body += c;
        }
        ++i;
    }

    static const std::regex kDeclRe(R"(\b([A-Za-z_]\w*)\s*\()", std::regex::optimize);

    static const std::unordered_set<std::string> kSkip = {
        "if", "for", "while", "switch", "return", "sizeof", "alignof",
        "decltype", "static_assert", "Q_OBJECT", "Q_GADGET", "Q_PROPERTY",
        "Q_DECLARE_FLAGS", "Q_DECLARE_PRIVATE", "Q_DISABLE_COPY",
        "Q_INVOKABLE", "Q_REVISION", "Q_SLOTS", "Q_SIGNALS", "signals",
        "slots", "emit", "connect", "disconnect", "override", "final",
        "explicit", "virtual", "inline", "constexpr", "static", "operator",
    };

    auto it  = std::sregex_iterator(body.begin(), body.end(), kDeclRe);
    auto end = std::sregex_iterator();
    for (; it != end; ++it) {
        std::string name = (*it)[1].str();
        if (!kSkip.count(name))
            names.insert(name);
    }
    return names;
}

// ---------------------------------------------------------------------------
// Public method signature extraction
// ---------------------------------------------------------------------------

std::string trim(const std::string &s)
{
    size_t a = s.find_first_not_of(" \t\n\r");
    if (a == std::string::npos)
        return { };
    size_t b = s.find_last_not_of(" \t\n\r");
    return s.substr(a, b - a + 1);
}

std::vector<std::string> splitParams(const std::string &paramList)
{
    std::vector<std::string> result;
    int anglDepth = 0;
    int parenDepth = 0;
    size_t start = 0;

    for (size_t i = 0; i < paramList.size(); ++i) {
        const char c = paramList[i];
        if (c == '<') {
            ++anglDepth;
        } else if (c == '>' && anglDepth > 0) {
            --anglDepth;
        } else if (c == '(') {
            ++parenDepth;
        } else if (c == ')' && parenDepth > 0) {
            --parenDepth;
        } else if (c == ',' && anglDepth == 0 && parenDepth == 0) {
            result.push_back(trim(paramList.substr(start, i - start)));
            start = i + 1;
        }
    }
    std::string last = trim(paramList.substr(start));
    if (!last.empty())
        result.push_back(last);
    return result;
}

MethodParam parseParam(const std::string &param)
{
    MethodParam mp;

    size_t eqPos = param.find('=');
    std::string decl = (eqPos != std::string::npos)
                       ? trim(param.substr(0, eqPos))
                       : trim(param);

    if (decl.empty())
        return mp;

    size_t nameEnd = decl.size();
    while (nameEnd > 0 && std::isspace(static_cast<unsigned char>(decl[nameEnd - 1])))
        --nameEnd;

    if (nameEnd > 0 && decl[nameEnd - 1] == '>') {
        mp.type = trim(decl);
        return mp;
    }

    size_t nameStart = nameEnd;
    while (nameStart > 0 &&
           (std::isalnum(static_cast<unsigned char>(decl[nameStart - 1]))
            || decl[nameStart - 1] == '_'))
        --nameStart;

    if (nameStart == nameEnd) {
        mp.type = trim(decl);
        return mp;
    }

    std::string lastName = decl.substr(nameStart, nameEnd - nameStart);

    // Qt parameter names never contain underscores — if the last token does,
    // it is a trailing macro (e.g. QT6_DECL_NEW_OVERLOAD_TAIL).  Strip it and
    // retry so the real param name (e.g. "thread") is found instead.
    while (lastName.find('_') != std::string::npos && nameStart > 0) {
        nameEnd = nameStart;
        while (nameEnd > 0 && std::isspace(static_cast<unsigned char>(decl[nameEnd - 1])))
            --nameEnd;
        nameStart = nameEnd;
        while (nameStart > 0 &&
               (std::isalnum(static_cast<unsigned char>(decl[nameStart - 1]))
                || decl[nameStart - 1] == '_'))
            --nameStart;
        if (nameStart == nameEnd)
            break;
        lastName = decl.substr(nameStart, nameEnd - nameStart);
    }

    static const std::unordered_set<std::string> kTypeKeywords = {
        "const", "volatile", "unsigned", "signed", "long", "short",
        "int", "char", "float", "double", "bool", "void", "auto",
        "struct", "class", "enum", "typename", "inline", "explicit",
    };

    if (kTypeKeywords.count(lastName) || lastName.empty()) {
        mp.type = trim(decl.substr(0, nameEnd));
        return mp;
    }

    if (nameStart > 0) {
        char prevChar = decl[nameStart - 1];
        if (prevChar == ':') {
            mp.type = trim(decl.substr(0, nameEnd));
            return mp;
        }
    }

    mp.name = lastName;
    mp.type = trim(decl.substr(0, nameStart));

    if (mp.type.empty() && nameStart > 0)
        mp.type = "auto";

    return mp;
}

// Returns true if the type is a Q* type that is likely forward-declared
// (and therefore cannot be default-constructed or referenced).
// We only allow Q* types that we know are complete value types.
static bool isLikelyForwardDeclared(const std::string &type)
{
    // Strip const, ref, ptr, whitespace to get the base type name.
    std::string t = type;
    while (!t.empty() && (t.back() == '&' || t.back() == '*' || t.back() == ' '))
        t.pop_back();
    while (t.size() >= 6 && t.substr(0, 6) == "const ")
        t = trim(t.substr(6));

    // Qualified types and templates are not simple forward decls.
    if (t.find("::") != std::string::npos)
        return false;
    if (t.find('<') != std::string::npos)
        return false;

    // Non-Q types are usually primitives or std types — not forward decls.
    if (t.empty() || t[0] != 'Q')
        return false;
    if (t.size() < 2 || !std::isupper(static_cast<unsigned char>(t[1])))
        return false;

    // These Q* types are always complete (defined in standard Qt headers
    // included transitively via qobject.h / qstring.h etc.)
    static const std::unordered_set<std::string> kAlwaysComplete = {
        "QObject", "QWidget",
        "QString", "QByteArray", "QVariant",
        "QUrl", "QChar", "QStringList",
        "QPoint", "QPointF", "QSize", "QSizeF",
        "QRect", "QRectF", "QLine", "QLineF",
        "QDate", "QTime", "QDateTime",
        "QModelIndex", "QPersistentModelIndex",
        "QLocale", "QMargins", "QMarginsF",
        "QVector2D", "QVector3D", "QVector4D",
        "QTimeZone",
    };

    return !kAlwaysComplete.count(t);
}

static const std::unordered_set<std::string> kDeclKeywords = {
    "virtual", "inline", "static", "explicit", "constexpr", "consteval",
    "constinit", "override", "final", "noexcept", "const", "volatile",
    "Q_INVOKABLE", "Q_REVISION",
    "QT_DEPRECATED_VERSION_X_6_0", "QT_DEPRECATED_VERSION_X_6_1",
    "QT_DEPRECATED_VERSION_X_6_2", "QT_DEPRECATED_VERSION_X_6_3",
    "QT_DEPRECATED_VERSION_X_6_4", "QT_DEPRECATED_VERSION_X_6_5",
    "QT_DEPRECATED_VERSION_X_6_6", "QT_DEPRECATED_VERSION_X_6_7",
    "QT_DEPRECATED_VERSION_X_6_8", "QT_DEPRECATED_VERSION_X_6_9",
    "Q_REQUIRED_RESULT", "Q_NODISCARD", "Q_DECL_COLD_FUNCTION",
    "Q_WEAK_OVERLOAD", "Q_ALWAYS_INLINE",
};

// C++ keywords that must never be treated as method names.
static const std::unordered_set<std::string> kCppKeywords = {
    // Common Qt/STL function/method names that appear in default argument
    // expressions and can be mis-parsed as param types or method names.
    "count", "size", "length", "indexOf", "data", "begin", "end",
    "value", "key", "at", "get", "first", "last", "front", "back",
    "top", "bottom", "left", "right", "width", "height", "x", "y", "z",
    "defaultTypeFor", "interval", "remainingTime",
    "bool", "int", "char", "float", "double", "void", "auto",
    "long", "short", "unsigned", "signed",
    "if", "else", "for", "while", "do", "switch", "case", "break",
    "continue", "return", "goto", "default",
    "class", "struct", "union", "enum", "namespace", "template",
    "typename", "typedef", "using", "static", "extern", "register",
    "const", "volatile", "mutable", "constexpr", "consteval",
    "inline", "virtual", "explicit", "friend", "operator",
    "new", "delete", "throw", "try", "catch", "noexcept",
    "public", "protected", "private",
    "true", "false", "nullptr", "this",
    "sizeof", "alignof", "decltype", "typeof",
    "override", "final",
    // Preprocessor-related identifiers that can appear after macro expansion
    // or inside #if blocks that weren't fully stripped.
    "defined",
};

// Method names that are known to be unsafe or unproductive for fuzzing.
static const std::unordered_set<std::string> kSkippedMethodNames = {
    "metaObject", "qt_metacall", "qt_metacast",
    "qt_check_for_QGADGET_macro", "qt_static_metacall",
    "deleteLater", "destroy",
    "winId", "effectiveWinId", "internalWinId",
    "nativeInterface", "handle", "platformInterface",
    "windowHandle", "platformWindow",
    "paintEngine", "sharedPainter", "redirected", "initPainter",
    "legacyDefaultTypeForOs",
    // Specific method names known to cause issues.
    "panel",    // lowercase enum value leaking as method name in QFrame
    "pointer",  // lowercase enum value / protected member leaking in QMenu
    // macOS-only methods that are exposed in headers but not available on Linux.
    "toNSMenu", "setAsDockMenu", "toNSToolBar",
    // setTimeZone: zero-param false match handled by post-processing below.
    // Platform-specific methods (mobile/embedded) exposed by preprocessor stripping.
    "hasEditFocus", "setEditFocus",
    // Methods taking std::initializer_list — skip by name as a safety net.
    "setTabOrder",
    // Internal/private methods exposed by macro expansion.
    "menuObject",
    // Methods that take/return QTextDocument internals not available in the widget.
    "setMetaInformation", "metaInformation",
    // Methods that would require complex setup not worth fuzzing directly.
    "addButton", "button", "rootIndex", "setRootIndex", "setCurrentModelIndex",
    // These return types that are forward-declared and not fully defined
    // in the class header — calling them triggers incomplete-type errors.
    "headerTextFormat", "weekdayTextFormat", "dateTextFormat",
    "dateEditFormat",
    // QPainterPath is forward-declared in qtransform.h
    "selectionArea", "clipPath", "shape", "opaqueArea",
    // QPalette is forward-declared in qmetatype.h
    "palette",
    // QRegion is forward-declared in various headers
    "visibleRegion", "childrenRegion",
    // QFont is forward-declared in various headers
    "font", "defaultFont",
    // QCursor is forward-declared in various headers
    "cursor",
};

std::vector<MethodSignature>
collectPublicMethods(const std::string &stripped,
                     size_t classPos,
                     const std::string &className)
{
    std::vector<MethodSignature> result;

    size_t pos = stripped.find('{', classPos);
    if (pos == std::string::npos)
        return result;

    // Collect depth-1 body text.
    // Rules:
    //   depth == 1 (class body): characters are copied verbatim.
    //   Opening '{' at depth 1 → 2 (method/nested-class body begins):
    //     replace with ' '.
    //   Characters at depth > 1 (inside method bodies, nested classes, etc.):
    //     replace with ' '.  This prevents names used in inline implementations
    //     (e.g. d.constData() inside size()) from being matched as method names.
    //   Closing '}' at depth 2 → 1 (method body ends):
    //     replace with ';' so the backward return-type scan has a clear
    //     statement boundary even for inline methods that have no explicit ';'.
    //   Closing '}' at depth > 2 → still inside a body: replace with ' '.
    //
    // Then:
    //   1. Elide QT_*_REMOVED_SINCE blocks so removed API is never parsed.
    //   2. Strip remaining preprocessor directive lines.
    std::string body;
    {
        int depth = 0;
        size_t i = pos;
        while (i < stripped.size()) {
            const char c = stripped[i];
            if (c == '{') {
                ++depth;
                body += (depth > 1) ? ' ' : '{';
            } else if (c == '}') {
                --depth;
                if (depth == 0)
                    break;
                // depth==1: closed a method body → synthetic statement boundary
                // depth >1: closed a brace nested inside a method body → space
                body += (depth == 1) ? ';' : ' ';
            } else if (depth == 1) {
                // Strip // line comments — their text (e.g. "min()" in
                // "suppress bogus reading of min() as a macro", or
                // "Feature (\w+)calendar…") must not be parsed as method calls.
                if (c == '/' && i + 1 < stripped.size() && stripped[i + 1] == '/') {
                    // Replace from here to end-of-line with spaces.
                    while (i < stripped.size() && stripped[i] != '\n') {
                        body += ' ';
                        ++i;
                    }
                    continue; // the \n (if any) will be handled on the next iteration
                }
                body += c;      // class-level declaration text
            } else {
                body += ' ';    // method-body content → suppress
            }
            ++i;
        }
    }
    body = elideRemovedSinceBlocks(body);
    body = elideNonLinuxPlatformBlocks(body);
    body = elideOptionalIfdefBlocks(body);
    body = stripPreprocessorLines(body);

    // Collect nested type names declared directly inside the class body.
    //
    // nestedStructs: simple value types (struct X) — qualify as ClassName::X
    //                and default-construct with {} in generated code.
    // nestedClasses: complex types (class X — iterators, handles, etc.) —
    //                methods taking these as params are SKIPPED because we
    //                cannot trivially construct them from raw bytes.
    // Enums (enum X, enum class X) get their :: added by the codegen's
    // existing "upper-case nested type" path; no separate qualification needed.
    std::unordered_set<std::string> nestedStructs;
    std::unordered_set<std::string> nestedClasses;
    {
        static const std::regex kNestedStructRe(
            R"(\bstruct\s+([A-Za-z_]\w*))",
            std::regex::optimize);
        static const std::regex kNestedClassRe(
            R"(\bclass\s+([A-Za-z_]\w*))",
            std::regex::optimize);
        for (auto it = std::sregex_iterator(body.begin(), body.end(), kNestedStructRe);
             it != std::sregex_iterator(); ++it)
            nestedStructs.insert((*it)[1].str());
        for (auto it = std::sregex_iterator(body.begin(), body.end(), kNestedClassRe);
             it != std::sregex_iterator(); ++it)
            nestedClasses.insert((*it)[1].str());
    }

    static const std::regex kAccessRe(
        R"(\b(public|protected|private)\s*(?:Q_SLOTS|Q_SIGNALS|signals|slots)?\s*:)",
        std::regex::optimize);

    enum class Section { Private, Protected, Public, Signals, Slots };

    struct SectionLabel {
        size_t  pos;
        Section section;
    };
    std::vector<SectionLabel> sections;

    {
        auto it  = std::sregex_iterator(body.begin(), body.end(), kAccessRe);
        auto end = std::sregex_iterator();
        for (; it != end; ++it) {
            std::string acc  = (*it)[1].str();
            std::string full = (*it)[0].str();
            Section sec = Section::Private;
            if (acc == "public") {
                if (full.find("Q_SLOTS") != std::string::npos ||
                    full.find("slots")   != std::string::npos)
                    sec = Section::Slots;
                else if (full.find("Q_SIGNALS") != std::string::npos ||
                         full.find("signals")   != std::string::npos)
                    sec = Section::Signals;
                else
                    sec = Section::Public;
            } else if (acc == "protected") {
                sec = Section::Protected;
            } else {
                sec = Section::Private;
            }
            sections.push_back({ static_cast<size_t>((*it).position()), sec });
        }
    }

    std::sort(sections.begin(), sections.end(),
              [](const SectionLabel &a, const SectionLabel &b) {
                  return a.pos < b.pos;
              });

    auto sectionAt = [&](size_t p) -> Section {
        Section cur = Section::Private;
        for (const auto &lbl : sections) {
            if (lbl.pos >= p)
                break;
            cur = lbl.section;
        }
        return cur;
    };

    static const std::regex kMethodCallRe(
        R"(\b([A-Za-z_]\w*)\s*\()",
        std::regex::optimize);

    std::set<std::string> seen;

    auto it  = std::sregex_iterator(body.begin(), body.end(), kMethodCallRe);
    auto end = std::sregex_iterator();

    for (; it != end; ++it) {
        const std::smatch &m      = *it;
        std::string        name   = m[1].str();
        size_t             matchPos = static_cast<size_t>(m.position());

        // Skip declaration keywords.
        if (kDeclKeywords.count(name))
            continue;

        // Skip C++ keywords.
        if (kCppKeywords.count(name))
            continue;

        // Must be in public or public Q_SLOTS section.
        Section sec = sectionAt(matchPos);
        if (sec != Section::Public && sec != Section::Slots)
            continue;

        // Skip constructor and destructor.
        if (name == className)
            continue;

        // Skip Q_* macros.
        if (name.size() >= 2 && name.substr(0, 2) == "Q_")
            continue;

        // Skip QT_* macros (QT_DEPRECATED_VERSION_X_*, QT7_ONLY, QT6_ONLY, …).
        // The QT_ prefix check handles the common case; the underscore check
        // catches variants like QT7_ONLY that start with QT<digit>_.
        if (name.size() >= 3 && name.substr(0, 3) == "QT_")
            continue;

        // Skip any name containing '_': Qt public API method names never
        // contain underscores — underscored identifiers are always macros.
        if (name.find('_') != std::string::npos)
            continue;

        // Skip known problematic method names.
        if (kSkippedMethodNames.count(name))
            continue;
        if (name == "emit" || name == "connect" || name == "disconnect")
            continue;

        // Skip Qt property binding accessors.
        if (name.size() >= 8 && name.substr(0, 8) == "bindable")
            continue;

        // Determine context by examining what immediately precedes this word.
        {
            size_t i = matchPos;
            while (i > 0 && std::isspace(static_cast<unsigned char>(body[i-1])))
                --i;

            if (i > 0) {
                char prev = body[i-1];

                if (prev == '(' || prev == '=' || prev == ','
                 || prev == '!' || prev == '+' || prev == '-'
                 || prev == '|' || prev == '<' || prev == '~'
                 || prev == '^' || prev == '%' || prev == ':')
                    continue;

                if (std::isalnum(static_cast<unsigned char>(prev)) || prev == '_') {
                    size_t wordEnd = i;
                    while (i > 0 && (std::isalnum(static_cast<unsigned char>(body[i-1]))
                                     || body[i-1] == '_'))
                        --i;
                    std::string preceding = body.substr(i, wordEnd - i);

                    static const std::unordered_set<std::string> kExprKeywords = {
                        "return", "new", "delete", "throw", "emit",
                        "case", "sizeof", "alignof", "decltype", "typeof",
                        "co_return", "co_yield",
                    };
                    if (kExprKeywords.count(preceding))
                        continue;

                    // If the preceding word is a C++ type qualifier, the
                    // matched identifier is a TYPE NAME, not a method name.
                    // e.g. "const Byte (&data)[]" — Byte is a type, not a
                    // method; the '(' belongs to the reference declarator.
                    static const std::unordered_set<std::string> kTypeQualifiers = {
                        "const", "volatile", "unsigned", "signed",
                    };
                    if (kTypeQualifiers.count(preceding))
                        continue;

                    // If the preceding word is itself preceded by '::',
                    // the full context is a scoped type used as an expression
                    // (e.g. std::chrono::milliseconds(...)) — not a declaration.
                    if (i >= 2) {
                        size_t j = i;
                        while (j > 0 && std::isspace(static_cast<unsigned char>(body[j-1])))
                            --j;
                        if (j >= 2 && body[j-1] == ':' && body[j-2] == ':')
                            continue;
                    }
                }
            }
        }

        // Skip operator overloads.
        {
            size_t i = matchPos;
            while (i > 0 && std::isspace(static_cast<unsigned char>(body[i-1])))
                --i;
            if (i >= 8 && body.substr(i - 8, 8) == "operator")
                continue;
        }

        // Skip template and friend declarations: scan backward from matchPos
        // to the previous statement boundary (';', '{', '}', lone ':').
        // If the preceding text contains "template" → template method (skip:
        // we cannot construct its arguments from raw bytes).
        // If it contains "friend" → friend function declared in class body
        // (skip: it is NOT a member method, e.g. friend size_t qHash(...)).
        {
            size_t scanPos = matchPos;
            while (scanPos > 0) {
                char c2 = body[scanPos - 1];
                if (c2 == ';' || c2 == '{' || c2 == '}')
                    break;
                if (c2 == ':') {
                    // '::' — scope resolution, skip both colons and continue.
                    if (scanPos >= 2 && body[scanPos - 2] == ':')
                        { scanPos -= 2; continue; }
                    break; // lone ':' — access label
                }
                --scanPos;
            }
            static const std::regex kTplRe(R"(\btemplate\s*<)", std::regex::optimize);
            static const std::regex kFriendRe(R"(\bfriend\b)", std::regex::optimize);
            std::string before = body.substr(scanPos, matchPos - scanPos);
            if (std::regex_search(before, kTplRe) || std::regex_search(before, kFriendRe))
                continue;
        }

        // Find the full parameter list.
        size_t parenOpen  = matchPos + m[0].length() - 1;
        size_t parenClose = std::string::npos;
        {
            int depth = 1;
            for (size_t i = parenOpen + 1; i < body.size(); ++i) {
                if (body[i] == '(') {
                    ++depth;
                } else if (body[i] == ')') {
                    --depth;
                    if (depth == 0) {
                        parenClose = i;
                        break;
                    }
                }
            }
        }
        if (parenClose == std::string::npos)
            continue;

        std::string paramList = trim(body.substr(parenOpen + 1,
                                                  parenClose - parenOpen - 1));

        // Raw check for QPrivateSignal BEFORE parsing — signals have it as
        // the last param and it must be skipped at the raw string level
        // because parseParam may not see it clearly after stripping defaults.
        if (paramList.find("QPrivateSignal") != std::string::npos)
            continue;

        // Skip variadic template methods (Args&&..., typename... etc.)
        if (paramList.find("...") != std::string::npos)
            continue;

        // Skip pure virtuals.
        {
            size_t after = parenClose + 1;
            while (after < body.size() && std::isspace(static_cast<unsigned char>(body[after])))
                ++after;
            static const std::regex kTrailRe(
                R"(^(?:(?:const|noexcept|override|final|Q_DECL_\w+)\s*)*(=\s*0))",
                std::regex::optimize);
            std::string afterStr = body.substr(after, std::min<size_t>(64, body.size() - after));
            if (std::regex_search(afterStr, kTrailRe))
                continue;
        }

        // Check if const method.
        bool isConst = false;
        {
            size_t after = parenClose + 1;
            while (after < body.size() && std::isspace(static_cast<unsigned char>(body[after])))
                ++after;
            static const std::regex kConstRe(R"(^const\b)", std::regex::optimize);
            std::string afterStr = body.substr(after, std::min<size_t>(8, body.size() - after));
            isConst = std::regex_search(afterStr, kConstRe);
        }

        // Parse parameter list.
        std::vector<MethodParam> params;
        bool anyDefault = false;
        bool skipMethod = false;

        if (!paramList.empty() && paramList != "void") {
            for (const auto &rawParam : splitParams(paramList)) {
                if (rawParam.empty())
                    continue;

                // Raw string checks on each param before parsing.
                if (rawParam.find("QPrivateSignal") != std::string::npos) {
                    skipMethod = true; break;
                }
                // Skip function pointer params.
                if (rawParam.find("(*") != std::string::npos) {
                    skipMethod = true; break;
                }
                // Skip initializer_list params — cannot be cast from a byte.
                if (rawParam.find("initializer_list") != std::string::npos) {
                    skipMethod = true; break;
                }
                // Skip params containing 'Func' or 'Callback' (function pointer typedefs).
                {
                    bool hasEq = rawParam.find('=') != std::string::npos;
                    std::string declPart = hasEq
                        ? trim(rawParam.substr(0, rawParam.find('=')))
                        : rawParam;
                    if (declPart.find("Func") != std::string::npos
                     || declPart.find("func") != std::string::npos
                     || declPart.find("Callback") != std::string::npos) {
                        skipMethod = true; break;
                    }
                }

                bool hasEq = rawParam.find('=') != std::string::npos;
                if (hasEq)
                    anyDefault = true;
                MethodParam mp = parseParam(rawParam);

                // If the parsed type contains '(' or ')' it means a complex
                // expression (template instantiation, function call in default
                // arg, etc.) leaked into the type — skip the whole method.
                if (mp.type.find('(') != std::string::npos
                 || mp.type.find(')') != std::string::npos) {
                    skipMethod = true;
                    break;
                }

                // Skip template methods: if the base type (stripped of
                // const/&/*/whitespace) is a single uppercase letter it is a
                // template type parameter (T, U, V …) — not a real type.
                // Such overloads cannot be called from generated code.
                {
                    std::string base = mp.type;
                    while (!base.empty()
                           && (base.back() == '&' || base.back() == '*'
                               || base.back() == ' '))
                        base.pop_back();
                    if (base.size() >= 6 && base.substr(0, 6) == "const ")
                        base = base.substr(6);
                    while (!base.empty() && base.back() == ' ')
                        base.pop_back();
                    if (base.size() == 1
                            && std::isupper(static_cast<unsigned char>(base[0]))) {
                        skipMethod = true;
                        break;
                    }
                }

                // If the raw param had no '=' (not a default arg) but the
                // parsed type equals the full raw param (no name extracted),
                // and the type looks like "Namespace::EnumValue" (scoped but
                // no known type suffix), this is likely a leaked enum value
                // from a macro-stripped default arg. Skip the method.
                if (!hasEq && mp.name.empty() && mp.type.find("::") != std::string::npos
                    && mp.type.find('<') == std::string::npos) {
                    // A real type like Qt::FocusReason would have a param name.
                    // A leaked value like "Qt::OtherFocusReason" has no name.
                    skipMethod = true;
                    break;
                }

                // Detect non-const reference params — these require a named
                // local variable in the generated code (can't bind rvalue).
                {
                    std::string t = mp.type;
                    while (!t.empty() && t.back() == ' ')
                        t.pop_back();
                    bool isRef   = !t.empty() && t.back() == '&';
                    bool isConst = t.find("const ") != std::string::npos
                                || t.find(" const") != std::string::npos;
                    mp.isNonConstRef = isRef && !isConst;

                    // Skip methods that take a reference to a likely
                    // forward-declared type — we cannot construct it.
                    if (isRef && isLikelyForwardDeclared(t)) {
                        skipMethod = true;
                        break;
                    }
                }

                // Qualify nested types: if the base type name (stripped of
                // const/&/*/whitespace) matches a type declared inside this
                // class body (e.g. YearMonthDay in QCalendar), prepend
                // "ClassName::" so the generated code compiles.
                // Only qualify if the type doesn't already have a '::'.
                if (mp.type.find("::") == std::string::npos) {
                    std::string base = mp.type;
                    while (!base.empty()
                           && (base.back() == '&' || base.back() == '*'
                               || base.back() == ' '))
                        base.pop_back();
                    const std::string constPfx = "const ";
                    if (base.size() >= constPfx.size()
                            && base.substr(0, constPfx.size()) == constPfx)
                        base = base.substr(constPfx.size());
                    while (!base.empty() && base.back() == ' ')
                        base.pop_back();
                    // Nested class types (iterators, handles …) cannot be
                    // trivially constructed from raw bytes — skip the method.
                    if (!base.empty() && nestedClasses.count(base)) {
                        skipMethod = true;
                        break;
                    }
                    // Nested struct types are simple value types — qualify
                    // them so the generated code compiles:
                    // e.g. YearMonthDay → QCalendar::YearMonthDay
                    if (!base.empty() && nestedStructs.count(base)) {
                        // Replace bare 'base' with 'ClassName::base' in the type.
                        size_t p = mp.type.find(base);
                        while (p != std::string::npos) {
                            // Only replace whole-word occurrences.
                            bool leftOk  = (p == 0 || !std::isalnum(static_cast<unsigned char>(mp.type[p-1])));
                            bool rightOk = (p + base.size() >= mp.type.size()
                                            || !std::isalnum(static_cast<unsigned char>(mp.type[p+base.size()])));
                            if (leftOk && rightOk) {
                                mp.type.replace(p, base.size(), className + "::" + base);
                                break; // type name appears at most once
                            }
                            p = mp.type.find(base, p + 1);
                        }
                    }
                }

                params.push_back(mp);
            }
        }

        if (skipMethod)
            continue;

        // If the param list was non-empty but we ended up with zero params,
        // all params were individually rejected (e.g. all were forward-declared
        // refs). The method cannot be called with zero args — skip it.
        if (params.empty() && !paramList.empty() && paramList != "void")
            continue;

        // Build unique key.
        std::string key = name + "(";
        for (const auto &p : params)
            key += p.type + ",";
        key += ")";
        if (!seen.insert(key).second)
            continue;

        // Extract the raw return type by scanning backward from matchPos.
        // Stop at ';', '{', '}', or a lone ':' (not part of '::').
        // This gives us the text between the previous statement boundary
        // and the method name, from which we strip modifier keywords to
        // recover the return type.
        std::string rawReturnType;
        {
            size_t scanPos = matchPos;
            while (scanPos > 0) {
                char c = body[scanPos - 1];
                if (c == ';' || c == '{' || c == '}')
                    break;
                if (c == ':') {
                    // '::' (scope resolution) — skip both colons and continue.
                    if (scanPos >= 2 && body[scanPos - 2] == ':') {
                        scanPos -= 2;
                        continue;
                    }
                    // Lone ':' — access label boundary.
                    break;
                }
                --scanPos;
            }

            if (scanPos < matchPos) {
                std::string decl = body.substr(scanPos, matchPos - scanPos);

                // Trim leading/trailing whitespace.
                size_t first = decl.find_first_not_of(" \t\n\r");
                if (first != std::string::npos) {
                    size_t last = decl.find_last_not_of(" \t\n\r");
                    decl = decl.substr(first, last - first + 1);

                    // Strip modifier keywords that precede the return type.
                    static const std::vector<std::string> kReturnMods = {
                        "[[nodiscard]]", "Q_REQUIRED_RESULT", "Q_INVOKABLE",
                        "Q_SLOT", "Q_SIGNAL", "Q_SCRIPTABLE", "QT6_ONLY",
                        "virtual", "static", "inline", "explicit",
                        "constexpr", "consteval", "constinit",
                    };
                    for (const auto &mod : kReturnMods) {
                        size_t p;
                        while ((p = decl.find(mod)) != std::string::npos)
                            decl.replace(p, mod.size(), " ");
                    }

                    // Normalise whitespace.
                    std::string norm;
                    bool lastWasSpace = true;
                    for (char ch : decl) {
                        if (std::isspace(static_cast<unsigned char>(ch))) {
                            if (!lastWasSpace) {
                                norm += ' ';
                                lastWasSpace = true;
                            }
                        } else {
                            norm += ch;
                            lastWasSpace = false;
                        }
                    }
                    while (!norm.empty() && norm.back() == ' ')
                        norm.pop_back();
                    rawReturnType = norm;
                }
            }
        }

        MethodSignature sig;
        sig.name       = name;
        sig.returnType = rawReturnType;
        sig.params     = std::move(params);
        sig.isConst    = isConst;
        sig.hasDefault = anyDefault;
        result.push_back(std::move(sig));
    }

    // Post-process: remove 0-param entries when a same-named entry with
    // params also exists. These are false 0-param matches from macro-stripped
    // headers that coexist with the real signature.
    {
        std::unordered_set<std::string> namesWithParams;
        for (const auto &s : result) {
            if (!s.params.empty())
                namesWithParams.insert(s.name);
        }

        result.erase(
            std::remove_if(result.begin(), result.end(),
                [&](const MethodSignature &s) {
                    return s.params.empty() && namesWithParams.count(s.name);
                }),
            result.end());
    }

    return result;
}

// ---------------------------------------------------------------------------
// Constructor detection
// ---------------------------------------------------------------------------

bool isNotAConstructor(const std::string &body, size_t matchStart)
{
    if (matchStart == 0)
        return false;

    size_t i = matchStart;
    while (i > 0 && std::isspace(static_cast<unsigned char>(body[i - 1])))
        --i;

    if (i == 0)
        return false;

    if (std::isalnum(static_cast<unsigned char>(body[i - 1])) || body[i - 1] == '_') {
        size_t wordEnd = i;
        while (i > 0 && (std::isalnum(static_cast<unsigned char>(body[i - 1]))
                         || body[i - 1] == '_'))
            --i;
        std::string word = body.substr(i, wordEnd - i);
        if (word == "explicit" || word == "virtual" || word == "inline"
            || word == "constexpr" || word == "Q_INVOKABLE")
            return false;
        return true;
    }

    const char prev = body[i - 1];
    return prev == '(' || prev == '~';
}

bool bodyHasDefaultConstructor(const std::string &source,
                                size_t classPos,
                                const std::string &className)
{
    size_t pos = source.find('{', classPos);
    if (pos == std::string::npos)
        return true;

    std::string body;
    int depth = 0;
    size_t i = pos;
    while (i < source.size()) {
        const char c = source[i];
        if (c == '{') {
            ++depth;
            body += (depth > 1) ? ' ' : '{';
        } else if (c == '}') {
            if (depth == 0)
                break;
            --depth;
            if (depth == 0)
                break;
            body += (depth == 1) ? ';' : ' ';
        } else if (depth == 1) {
            // Strip // line comments — text like "// prevent construction"
            // before "ClassName()" must not confuse isNotAConstructor() into
            // thinking the word immediately before the ctor name is a regular
            // identifier (which would make it look like a non-constructor call).
            if (c == '/' && i + 1 < source.size() && source[i + 1] == '/') {
                while (i < source.size() && source[i] != '\n') {
                    body += ' ';
                    ++i;
                }
                continue;
            }
            // Strip preprocessor directives (#ifdef, #else, #endif, etc.).
            // Without this, a constructor preceded by e.g. "#ifdef Q_QDOC"
            // causes isNotAConstructor() to see "Q_QDOC" as the word before
            // the constructor name and incorrectly reject it as non-constructor,
            // leading to the class being marked as default-constructible when
            // it is not (e.g. QApplication).
            if (c == '#') {
                while (i < source.size() && source[i] != '\n') {
                    body += ' ';
                    ++i;
                }
                continue;
            }
            body += c;
        } else {
            body += ' ';
        }
        ++i;
    }

    static const std::regex kAccessRe(
        R"(\b(public|protected|private)\s*(?:Q_SLOTS|Q_SIGNALS|signals|slots)?\s*:)",
        std::regex::optimize);

    struct AccessLabel { size_t pos; bool isPublic; };
    std::vector<AccessLabel> labels;
    {
        auto it  = std::sregex_iterator(body.begin(), body.end(), kAccessRe);
        auto end = std::sregex_iterator();
        for (; it != end; ++it) {
            labels.push_back({ static_cast<size_t>((*it).position()),
                                (*it)[1].str() == "public" });
        }
    }

    const auto isPublicAt = [&](size_t p) -> bool {
        bool cur = false;
        for (const auto &lbl : labels) {
            if (lbl.pos >= p)
                break;
            cur = lbl.isPublic;
        }
        return cur;
    };

    const std::regex ctorRe(
            "\\b" + className + R"(\s*\(([^;{]*))",
            std::regex::optimize);

    bool foundPublicCtor      = false;
    bool foundAnyExplicitCtor = false;

    auto it  = std::sregex_iterator(body.begin(), body.end(), ctorRe);
    auto end = std::sregex_iterator();

    for (; it != end; ++it) {
        auto matchStart = static_cast<size_t>((*it).position());

        if (isNotAConstructor(body, matchStart))
            continue;

        foundAnyExplicitCtor = true;

        if (!isPublicAt(matchStart))
            continue;

        foundPublicCtor = true;
        std::string args = (*it)[1].str();

        auto last = args.find_last_not_of(" \t\n\r");
        if (last == std::string::npos)
            return true;
        args = args.substr(0, last + 1);

        // Strip trailing "= default" / "= delete" specifiers that follow the
        // closing ')' (e.g. "Foo(const Foo &) = default" → capture includes
        // "const Foo &) = default"; we must remove the trailer before parsing).
        // A deleted constructor (= delete) is never callable, so skip it entirely.
        bool isDeleted = false;
        for (const char *trailer : { "= delete", "= default" }) {
            const size_t tlen = std::strlen(trailer);
            if (args.size() >= tlen && args.compare(args.size() - tlen, tlen, trailer) == 0) {
                isDeleted = (std::strcmp(trailer, "= delete") == 0);
                args.resize(args.size() - tlen);
                last = args.find_last_not_of(" \t\n\r");
                if (last == std::string::npos) {
                    args.clear();
                    break;
                }
                args = args.substr(0, last + 1);
                break;
            }
        }
        if (isDeleted)
            continue; // deleted ctor cannot be default-constructed

        if (!args.empty() && args.back() == ')')
            args.pop_back();

        last = args.find_last_not_of(" \t\n\r");
        if (last == std::string::npos)
            return true;

        args = args.substr(0, last + 1);
        if (args.empty())
            return true;

        bool allDefaulted = true;
        std::istringstream ss(args);
        std::string param;
        while (std::getline(ss, param, ',')) {
            if (param.find('=') == std::string::npos) {
                allDefaulted = false;
                break;
            }
        }
        if (allDefaulted)
            return true;
    }

    if (foundPublicCtor)
        return false;

    return !foundAnyExplicitCtor;
}

// ---------------------------------------------------------------------------
// Platform flag detection
// ---------------------------------------------------------------------------

static const std::unordered_map<std::string, Platform> kPlatformMacros = {
    { "Q_OS_LINUX", Platform::Linux },     { "Q_OS_UNIX", Platform::Linux },
    { "Q_OS_WIN", Platform::Windows },     { "Q_OS_WIN32", Platform::Windows },
    { "Q_OS_WIN64", Platform::Windows },   { "Q_OS_WINRT", Platform::Windows },
    { "Q_OS_MACOS", Platform::macOS },     { "Q_OS_IOS", Platform::iOS },
    { "Q_OS_TVOS", Platform::iOS },        { "Q_OS_WATCHOS", Platform::iOS },
    { "Q_OS_ANDROID", Platform::Android }, { "Q_OS_WASM", Platform::WASM },
};

Platform platformsInCondition(const std::string &condition)
{
    Platform result = Platform::None;
    for (const auto &[macro, flag] : kPlatformMacros) {
        if (condition.find(macro) != std::string::npos)
            result = result | flag;
    }
    return result;
}

Platform detectAvailablePlatforms(const std::string &stripped, size_t classPos)
{
    std::vector<std::string> lines;
    {
        std::istringstream ss(stripped.substr(0, classPos));
        std::string line;
        while (std::getline(ss, line))
            lines.push_back(line);
    }

    static const std::regex kIfRe(
            R"(#\s*ifdef\b(.*))",    std::regex::optimize);
    static const std::regex kIfDefinedRe(
            R"(#\s*if\b(.*))",       std::regex::optimize);
    static const std::regex kIfndefRe(
            R"(#\s*ifndef\b(.*))",   std::regex::optimize);
    static const std::regex kEndifRe(
            R"(#\s*endif\b)",        std::regex::optimize);

    int pendingEndifs = 0;
    Platform accumulated = Platform::None;
    bool foundAny = false;

    for (auto it = lines.rbegin(); it != lines.rend(); ++it) {
        size_t first = it->find_first_not_of(" \t");
        if (first == std::string::npos)
            continue;
        const std::string trimmed = it->substr(first);

        if (std::regex_search(trimmed, kEndifRe)) {
            ++pendingEndifs;
            continue;
        }
        if (std::regex_search(trimmed, kIfndefRe)) {
            if (pendingEndifs > 0)
                --pendingEndifs;
            continue;
        }

        std::smatch m;
        const bool isIfdef = std::regex_search(trimmed, m, kIfRe);
        const bool isIf = !isIfdef && std::regex_search(trimmed, m, kIfDefinedRe);
        if (!isIfdef && !isIf)
            continue;

        if (pendingEndifs > 0) {
            --pendingEndifs;
            continue;
        }

        Platform flags = platformsInCondition(m[1].str());
        if (flags != Platform::None) {
            accumulated = accumulated | flags;
            foundAny = true;
        }
    }

    return foundAny ? accumulated : Platform::All;
}

// ---------------------------------------------------------------------------
// Class match extraction
// ---------------------------------------------------------------------------

struct ClassMatch {
    std::string name;
    std::vector<std::string> baseNames; // Q-prefixed bases only (may be empty)
    size_t pos;
};

bool isTemplateClass(const std::string &source, size_t classPos)
{
    if (classPos == 0)
        return false;

    size_t i = classPos - 1;
    while (i > 0 && std::isspace(static_cast<unsigned char>(source[i])))
        --i;

    if (source[i] != '>')
        return false;

    int depth = 0;
    while (i > 0) {
        const char c = source[i];
        if (c == '>') {
            ++depth;
        } else if (c == '<') {
            --depth;
            if (depth == 0)
                break;
        }
        --i;
    }
    if (depth != 0)
        return false;

    size_t anglePos = i;
    while (anglePos > 0 && std::isspace(static_cast<unsigned char>(source[anglePos - 1])))
        --anglePos;

    if (anglePos < 8)
        return false;
    return source.substr(anglePos - 8, 8) == "template";
}

std::vector<std::string> extractBaseNames(const std::string &baseListText)
{
    static const std::regex kBaseRe(R"(\bQ[A-Z]\w*\b)", std::regex::optimize);

    std::vector<std::string> result;
    auto it  = std::sregex_iterator(baseListText.begin(), baseListText.end(), kBaseRe);
    auto end = std::sregex_iterator();
    for (; it != end; ++it)
        result.push_back((*it)[0].str());
    return result;
}

// Extracts all Q-prefixed class declarations from a stripped header source.
// Unlike the former extractQObjectSubclassMatches, this function accepts
// classes with any inheritance (including none) — there is no requirement
// for a QObject ancestor.
std::vector<ClassMatch> extractClassMatches(const std::string &stripped)
{
    // Match classes with optional inheritance:
    //   class [EXPORT_MACRO] ClassName [: bases] {
    // Group 1: ClassName  (required, must start with uppercase)
    // Group 2: base list  (optional, captured after ':')
    static const std::regex kClassRe(
            // (?!::) rejects scoped definitions like "class QMetaObject::Connection {"
            // — those would capture "QMetaObject" as the name but refer to a nested
            // class body, not the QMetaObject struct itself.
            R"(\bclass\s+(?:Q_\w+_EXPORT\s+)?([A-Z]\w*)(?!::)\s*(?::([^{;]*))?(?=\{))",
            std::regex::optimize);

    std::vector<ClassMatch> result;
    std::set<std::string>   seen;

    auto it  = std::sregex_iterator(stripped.begin(), stripped.end(), kClassRe);
    auto end = std::sregex_iterator();

    for (; it != end; ++it) {
        const std::smatch &m    = *it;
        std::string        name = m[1].str();

        if (name.empty() || name[0] != 'Q')
            continue;
        if (name.size() > 7 && name.substr(name.size() - 7) == "Private")
            continue;
        if (name.size() > 4 && name.substr(name.size() - 4) == "Impl")
            continue;
        if (name.find("_p") != std::string::npos)
            continue;

        size_t pos = static_cast<size_t>(m.position());
        if (isTemplateClass(stripped, pos))
            continue;
        if (!seen.insert(name).second)
            continue;

        // Extract Q-prefixed base names for abstract propagation.
        // The base list may be empty for standalone classes (e.g. QPoint).
        std::vector<std::string> bases;
        if (m[2].matched)
            bases = extractBaseNames(m[2].str());

        result.push_back({ name, bases, pos });
    }
    return result;
}

std::string firstComponent(const fs::path &rel)
{
    if (rel.empty())
        return { };
    return rel.begin()->string();
}

// ---------------------------------------------------------------------------
// Universe construction — all Q-prefixed classes
// ---------------------------------------------------------------------------

struct UniverseEntry {
    std::vector<std::string> baseNames;
    bool isAbstract = false;
    bool isDefaultConstructible = true;
    bool hasQObject = false;
    Platform availableOn = Platform::All;
    std::unordered_set<std::string> ownPureVirtualNames;
    std::unordered_set<std::string> ownDeclaredNames;
    std::vector<MethodSignature> publicMethods;
};

// Scans all public headers under srcRoot and builds a map of every
// Q-prefixed class encountered. No ancestry filter is applied — all
// Q-prefixed classes, regardless of their base classes, are admitted.
std::unordered_map<std::string, UniverseEntry>
buildUniverseMap(const fs::path &srcRoot, bool verbose)
{
    std::unordered_map<std::string, UniverseEntry> universe;
    std::set<std::string> seen;

    std::error_code ec;
    for (const auto &entry : fs::recursive_directory_iterator(srcRoot, ec)) {
        if (ec) {
            ec.clear();
            continue;
        }
        if (!entry.is_regular_file())
            continue;

        const fs::path &p = entry.path();
        if (p.extension() != ".h")
            continue;

        {
            std::string pathStr = p.string();
            if (pathStr.find("/private/") != std::string::npos)
                continue;
            if (pathStr.find("_p.h") != std::string::npos)
                continue;
            if (pathStr.find("private.h") != std::string::npos)
                continue;
        }

        std::string source = readFile(p);
        if (source.empty())
            continue;

        const std::string stripped = stripBlockComments(source);

        for (const auto &[name, baseNames, matchPos] : extractClassMatches(stripped)) {
            if (!seen.insert(name).second)
                continue;

            const auto pvNames = collectPureVirtualNames(source, matchPos);
            const auto declNames = collectDeclaredMethodNames(stripped, matchPos);
            const auto pubMethods = collectPublicMethods(stripped, matchPos, name);
            const bool isAbstract = !pvNames.empty();
            const bool isDefaultConstructible = bodyHasDefaultConstructor(stripped, matchPos, name);
            const bool hasQObject = bodyHasQObjectMacro(stripped, matchPos);
            Platform availableOn = detectAvailablePlatforms(stripped, matchPos);

            if (verbose) {
                if (isAbstract) {
                    std::cout << "[Scanner/universe]   " << name
                              << " has own pure virtuals:";
                    for (const auto &pv : pvNames)
                        std::cout << " " << pv;
                    std::cout << "\n";
                }
                if (!isDefaultConstructible) {
                    std::cout << "[Scanner/universe]   " << name
                              << " not default-constructible\n";
                }
                if (availableOn != Platform::All) {
                    std::cout << "[Scanner/universe]   " << name
                              << " platform restricted (mask=0x"
                              << std::hex << static_cast<uint32_t>(availableOn)
                              << std::dec << ")\n";
                }
                if (hasQObject) {
                    std::cout << "[Scanner/universe]   " << name
                              << " has Q_OBJECT\n";
                }
                if (!pubMethods.empty()) {
                    std::cout << "[Scanner/universe]   " << name
                              << " has " << pubMethods.size()
                              << " public method(s)\n";
                }
            }

            universe[name] = UniverseEntry{ baseNames,
                                            isAbstract,
                                            isDefaultConstructible,
                                            hasQObject,
                                            availableOn,
                                            std::move(pvNames),
                                            std::move(declNames),
                                            std::move(pubMethods) };
        }
    }

    if (verbose) {
        std::cout << "[Scanner/universe] Universe size: " << universe.size()
                  << " Q-prefixed classes.\n";
    }

    return universe;
}

std::unordered_set<std::string>
collectUnresolvedPureVirtuals(
        const std::string &className,
        const std::unordered_map<std::string, UniverseEntry> &universe,
        std::unordered_map<std::string, std::unordered_set<std::string>> &cache)
{
    auto cit = cache.find(className);
    if (cit != cache.end())
        return cit->second;

    cache[className] = {};

    auto uit = universe.find(className);
    if (uit == universe.end())
        return {};

    const UniverseEntry &entry = uit->second;
    std::unordered_set<std::string> unresolved = entry.ownPureVirtualNames;

    for (const auto &base : entry.baseNames) {
        auto baseUnresolved = collectUnresolvedPureVirtuals(
                base, universe, cache);
        for (const auto &pvName : baseUnresolved) {
            if (!entry.ownDeclaredNames.count(pvName))
                unresolved.insert(pvName);
        }
    }

    cache[className] = unresolved;
    return unresolved;
}

void propagateAbstract(
        std::unordered_map<std::string, UniverseEntry> &universe,
        bool verbose)
{
    std::unordered_map<std::string, std::unordered_set<std::string>> cache;

    for (auto &[name, entry] : universe) {
        if (entry.isAbstract)
            continue;

        const auto unresolved = collectUnresolvedPureVirtuals(name, universe, cache);

        if (!unresolved.empty()) {
            entry.isAbstract = true;
            if (verbose) {
                std::cout << "[Scanner/propagate]  " << name
                          << " marked abstract (unresolved:";
                for (const auto &pv : unresolved)
                    std::cout << " " << pv;
                std::cout << ")\n";
            }
        }
    }
}

} // anonymous namespace

// ---------------------------------------------------------------------------

bool classIsAbstract(const std::string &source, const std::string &className)
{
    static const std::regex kDeclRe(
            R"(\bclass\s+(?:Q_\w+_EXPORT\s+)?([A-Z]\w*)\s*:)",
            std::regex::optimize);

    size_t searchFrom = 0;
    while (true) {
        size_t pos = source.find("class ", searchFrom);
        if (pos == std::string::npos)
            return false;

        std::smatch m;
        auto sub = source.substr(pos, std::min<size_t>(256, source.size() - pos));
        if (std::regex_search(sub, m, kDeclRe) && m[1].str() == className)
            return bodyHasPureVirtual(source, pos);

        searchFrom = pos + 1;
    }
}

bool classHasQObjectMacro(const std::string &source, const std::string &className)
{
    const std::string stripped = stripBlockComments(source);

    static const std::regex kDeclRe(
            R"(\bclass\s+(?:Q_\w+_EXPORT\s+)?([A-Z]\w*)\s*(?:[:{]))",
            std::regex::optimize);

    size_t searchFrom = 0;
    while (true) {
        size_t pos = stripped.find("class ", searchFrom);
        if (pos == std::string::npos)
            return false;

        std::smatch m;
        auto sub = stripped.substr(pos, std::min<size_t>(256, stripped.size() - pos));
        if (std::regex_search(sub, m, kDeclRe) && m[1].str() == className)
            return bodyHasQObjectMacro(stripped, pos);

        searchFrom = pos + 1;
    }
}

// ---------------------------------------------------------------------------

std::optional<std::pair<std::string, ModuleInfo>>
moduleForHeader(const fs::path &headerPath, const fs::path &submoduleRoot)
{
    std::error_code ec;
    fs::path rel = fs::relative(headerPath, submoduleRoot / "src", ec);
    if (ec || rel.empty())
        return std::nullopt;

    std::string dirName = firstComponent(rel);
    if (dirName.empty())
        return std::nullopt;

    std::string lower = dirName;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);

    const ModuleInfo *mi = findModuleByDir(lower);
    if (mi)
        return std::make_pair(lower, *mi);

    std::string comp = dirName;
    if (!comp.empty())
        comp[0] = static_cast<char>(std::toupper(comp[0]));
    ModuleInfo fallback{ comp, "Qt6::" + comp, { "Core" }, AppType::Core };
    return std::make_pair(lower, fallback);
}

std::optional<fs::path> findHeader(const std::string &className,
                                   const fs::path &submoduleRoot)
{
    std::string lower = className;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    const std::string filename = lower + ".h";

    std::error_code ec;
    for (const auto &entry : fs::recursive_directory_iterator(submoduleRoot, ec)) {
        if (ec) {
            ec.clear();
            continue;
        }
        if (!entry.is_regular_file())
            continue;
        if (entry.path().filename().string() == filename)
            return entry.path();
    }
    return std::nullopt;
}

std::vector<DiscoveredClass> scanClasses(const fs::path &submoduleRoot,
                                         const std::vector<std::string> &moduleFilter, bool verbose,
                                         const SkipList &skipList)
{
    const fs::path srcRoot = submoduleRoot / "src";

    if (!fs::exists(srcRoot)) {
        std::cerr << "[Scanner] ERROR: " << srcRoot << " does not exist.\n";
        return {};
    }

    if (verbose)
        std::cout << "[Scanner] Phase 1: scanning all headers for Q-prefixed classes...\n";

    auto universe = buildUniverseMap(srcRoot, verbose);

    if (verbose)
        std::cout << "[Scanner] Propagating abstract flags...\n";

    propagateAbstract(universe, verbose);

    if (verbose)
        std::cout << "[Scanner] Phase 3: collecting results for requested modules...\n";

    std::set<std::string> filterSet(moduleFilter.begin(), moduleFilter.end());

    std::vector<DiscoveredClass> result;
    std::set<std::string>        seen;

    std::error_code ec;
    size_t filesScanned = 0;
    size_t abstractCount = 0;
    size_t notConstructibleCount = 0;
    size_t platformCount = 0;
    size_t withQObjectCount = 0;
    size_t directOnlyCount = 0;
    size_t skippedCount = 0;

    for (const auto &entry : fs::recursive_directory_iterator(srcRoot, ec)) {
        if (ec) {
            ec.clear();
            continue;
        }
        if (!entry.is_regular_file())
            continue;

        const fs::path &p = entry.path();
        if (p.extension() != ".h")
            continue;

        auto modOpt = moduleForHeader(p, submoduleRoot);
        if (!modOpt)
            continue;

        auto &[srcDir, mod] = *modOpt;

        if (!filterSet.empty() && filterSet.find(srcDir) == filterSet.end())
            continue;

        {
            std::string pathStr = p.string();
            if (pathStr.find("/private/") != std::string::npos)
                continue;
            if (pathStr.find("_p.h") != std::string::npos)
                continue;
            if (pathStr.find("private.h") != std::string::npos)
                continue;
        }

        std::string source = readFile(p);
        if (source.empty())
            continue;

        ++filesScanned;

        const std::string stripped = stripBlockComments(source);

        // Compute the lowercase stem of this header file once per file.
        // Qt's public API convention: class QFooBar lives in qfoobar.h or
        // qfoo.h (the header stem is a prefix of the lowercased class name).
        // Any class whose header stem is NOT such a prefix is an internal
        // helper that has no corresponding public <ClassName> module header;
        // including it would produce an unresolvable #include.
        std::string stemLower = p.stem().string();
        for (char &c : stemLower)
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

        for (const auto &[name, baseNames, matchPos] : extractClassMatches(stripped)) {
            // Check header-stem prefix rule.
            {
                std::string cnameLower = name;
                for (char &c : cnameLower)
                    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
                // stemLower must be a prefix of cnameLower, otherwise this class
                // is defined in an unrelated header (e.g. QXmlString in qxmlutils.h)
                // and has no public <ClassName> module header.
                if (cnameLower.size() < stemLower.size()
                    || cnameLower.substr(0, stemLower.size()) != stemLower) {
                    continue;
                }
            }

            if (!seen.insert(name).second)
                continue;

            const auto it = universe.find(name);
            if (it == universe.end())
                continue;

            bool isAbstract = it->second.isAbstract;
            bool isDefaultConstructible = it->second.isDefaultConstructible;
            bool hasQObject = it->second.hasQObject;
            Platform availableOn = it->second.availableOn;

            if (isAbstract)
                ++abstractCount;
            if (!isDefaultConstructible)
                ++notConstructibleCount;
            if (availableOn != Platform::All)
                ++platformCount;
            if (hasQObject)
                ++withQObjectCount;
            else
                ++directOnlyCount;

            if (verbose) {
                std::cout << "[Scanner]   " << name
                          << "  (" << srcDir << ")  " << p.filename();
                if (isAbstract)
                    std::cout << "  [abstract]";
                if (!isDefaultConstructible)
                    std::cout << "  [not-default-constructible]";
                if (availableOn != Platform::All) {
                    std::cout << "  [platform-restricted 0x"
                              << std::hex << static_cast<uint32_t>(availableOn)
                              << std::dec << "]";
                }
                std::cout << (hasQObject ? "  [Q_OBJECT]" : "  [direct-only]")
                          << "\n";
            }

            // Skip classes that appear in the skip list.
            if (skipList.isClassSkipped(name)) {
                ++skippedCount;
                if (verbose)
                    std::cout << "[Scanner] Skipping (skiplist): " << name << "\n";
                continue;
            }

            // Remove individually skipped methods.
            // Copy name to a plain local to avoid capturing a structured binding
            // (C++17 limitation; structured bindings are not variables).
            const std::string className = name;
            std::vector<MethodSignature> methods = it->second.publicMethods;
            {
                auto end =
                        std::remove_if(methods.begin(), methods.end(),
                                       [&className, &skipList](const MethodSignature &sig) {
                                           return skipList.isFunctionSkipped(className, sig.name);
                                       });
                methods.erase(end, methods.end());
            }

            std::string primaryBase = baseNames.empty() ? "" : baseNames.front();

            result.push_back(DiscoveredClass{ name, primaryBase, p, srcDir, mod, isAbstract,
                                              isDefaultConstructible, hasQObject, availableOn,
                                              std::move(methods) });
        }
    }

    if (verbose) {
        std::cout << "[Scanner] Scanned " << filesScanned << " headers, found " << result.size()
                  << " classes (" << abstractCount << " abstract, " << notConstructibleCount
                  << " not default-constructible, " << platformCount << " platform-restricted, "
                  << withQObjectCount << " with Q_OBJECT, " << directOnlyCount
                  << " direct-call only, " << skippedCount << " in skip list).\n";
    }

    std::sort(result.begin(), result.end(),
              [](const DiscoveredClass &a, const DiscoveredClass &b) {
                  if (a.moduleSrcDir != b.moduleSrcDir)
                      return a.moduleSrcDir < b.moduleSrcDir;
                  return a.className < b.className;
              });

    return result;
}

std::optional<DiscoveredClass> scanSingleClass(const std::string &className,
                                               const fs::path &submoduleRoot)
{
    // Fast path: filename == <lowercase(class)>.h (works for QDir → qdir.h, etc.)
    fs::path headerPath;
    if (auto h = findHeader(className, submoduleRoot))
        headerPath = *h;

    // Slow path: multiple classes can share one header (e.g. QDomDocument,
    // QDomElement, … all live in qdom.h).  Apply the same stem-prefix rule
    // that scanClasses() uses: a header whose lowercase stem is a prefix of
    // the lowercased class name is a candidate.
    if (headerPath.empty()) {
        std::string cnameLower = className;
        for (char &c : cnameLower)
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

        std::error_code ec;
        for (const auto &entry : fs::recursive_directory_iterator(submoduleRoot / "src", ec)) {
            if (ec) {
                ec.clear();
                continue;
            }
            if (!entry.is_regular_file())
                continue;
            const fs::path &p = entry.path();
            if (p.extension() != ".h")
                continue;

            const std::string ps = p.string();
            if (ps.find("/private/") != std::string::npos)
                continue;
            if (ps.find("_p.h") != std::string::npos)
                continue;
            if (ps.find("private.h") != std::string::npos)
                continue;

            std::string stemLower = p.stem().string();
            for (char &c : stemLower)
                c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

            // stemLower must be a non-empty prefix of cnameLower
            if (stemLower.empty() || cnameLower.size() < stemLower.size()
                || cnameLower.substr(0, stemLower.size()) != stemLower)
                continue;

            const std::string src = readFile(p);
            if (src.empty())
                continue;
            const std::string stripped2 = stripBlockComments(src);
            for (const auto &[name, bases, matchPos] : extractClassMatches(stripped2)) {
                if (name == className) {
                    headerPath = p;
                    break;
                }
            }
            if (!headerPath.empty())
                break;
        }
    }

    if (headerPath.empty())
        return std::nullopt;

    const std::string source   = readFile(headerPath);
    if (source.empty())
        return std::nullopt;

    const std::string stripped = stripBlockComments(source);

    // Locate the class declaration inside the header.
    size_t classPos = std::string::npos;
    std::vector<std::string> baseNames;
    for (const auto &[name, bases, matchPos] : extractClassMatches(stripped)) {
        if (name == className) {
            classPos = matchPos;
            baseNames = bases;
            break;
        }
    }
    if (classPos == std::string::npos)
        return std::nullopt;

    auto modOpt = moduleForHeader(headerPath, submoduleRoot);
    if (!modOpt)
        return std::nullopt;
    const auto &[srcDir, mod] = *modOpt;

    const bool hasQObject = bodyHasQObjectMacro(stripped, classPos);
    const bool isAbstract = bodyHasPureVirtual(source, classPos);
    const bool isDefaultConstructible = bodyHasDefaultConstructor(stripped, classPos, className);
    const Platform availableOn = detectAvailablePlatforms(stripped, classPos);
    auto publicMethods = collectPublicMethods(stripped, classPos, className);

    const std::string primaryBase = baseNames.empty() ? "" : baseNames.front();

    return DiscoveredClass{ className, primaryBase, headerPath, srcDir, mod,
                            isAbstract, isDefaultConstructible, hasQObject,
                            availableOn, std::move(publicMethods) };
}

} // namespace QtFuzz
