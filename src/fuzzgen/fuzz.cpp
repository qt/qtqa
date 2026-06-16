// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// fuzz — targeted single-function fuzzer runner for Qt classes.
//
// Generates a specialized single-function fuzzer, compiles and caches it in
// a temporary directory, then runs it against specific or random input.
//
// Usage:
//   fuzz -c <ClassName> -f <functionName> [options]
//   fuzz --cleanup
//
// Options:
//   -c <ClassName>       Qt class to fuzz (required)
//   -f <functionName>    Function to fuzz (required)
//   -t <seconds>         Fuzz duration for random mode (default: 30)
//   -d <data>            Inline input: one argument value per line
//   -i <file>            File with input data (same format as -d)
//   -b <file>            Raw binary corpus file (may be repeated; no serialization)
//   --submodule <path>   Qt submodule root for class/function discovery
//   --qt-prefix <path>   Qt install prefix (auto-detected if omitted)
//   --list-cached        List all cached fuzzers and their build status
//   --cleanup            Remove all cached fuzzers from the temp directory
//
// -d and -i are mutually exclusive.
// Input format: one argument value per line, with exactly
//   (numParams × N) lines for N function calls.
//   Example: a 2-param function called twice uses 4 lines.
// -b may be repeated and combined with -d / -i.
//
// Return codes:
//   0  Generated fuzzer ran for full -t seconds without crash.
//   1  Generated fuzzer processed specific -d/-i input without crash.
//   2  Generated fuzzer crashed.
//   3  Error (class/function not found, build failure, etc.; see stderr).

#include "codegen.h"
#include "modulemap.h"
#include "qtdetect.h"
#include "scanner.h"

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  define NOMINMAX
#  include <windows.h>
#else
#  include <csignal>
#  include <sys/wait.h>
#  include <unistd.h>
#endif

namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
// Exit codes (match what callers expect)
// ---------------------------------------------------------------------------
static constexpr int EC_TIMEOUT = 0; // ran to timeout without crash
static constexpr int EC_GRACEFUL = 1; // corpus processed without crash
static constexpr int EC_CRASH = 2; // crash
static constexpr int EC_ERROR = 3; // configuration / build error

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static fs::path cacheRoot()
{
#ifdef _WIN32
    const char *tmp = std::getenv("TEMP");
    if (!tmp || !tmp[0])
        tmp = std::getenv("TMP");
    return fs::path(tmp ? tmp : "C:\\Temp") / "qtfuzz";
#else
    const char *tmp = std::getenv("TMPDIR");
    return fs::path(tmp ? tmp : "/tmp") / "qtfuzz";
#endif
}

// Convert MinGW/MSYS2 Unix-style paths (/c/Users/...) to Windows-style
// (C:/Users/...) so cmd.exe and cmake.exe can resolve them.
// On non-Windows or paths that don't match the pattern, returns the input unchanged.
static std::string nativePath(const std::string &p)
{
#ifdef _WIN32
    if (p.size() >= 2 && p[0] == '/' && std::isalpha(static_cast<unsigned char>(p[1]))
        && (p.size() == 2 || p[2] == '/')) {
        std::string r;
        r += static_cast<char>(std::toupper(static_cast<unsigned char>(p[1])));
        r += ':';
        r += (p.size() > 2 ? p.substr(2) : "/");
        return r;
    }
#endif
    return p;
}

// Resolve the actual cmake prefix that contains Qt6Config.cmake.
// Handles both installed Qt (<prefix>/lib/cmake/Qt6/) and supermodule builds
// (<prefix>/qtbase/lib/cmake/Qt6/).  Returns the prefix unchanged when
// Qt6Config.cmake cannot be found — cmake will then emit the usual error.
static std::string resolveQtPrefix(const std::string &prefix)
{
    if (prefix.empty())
        return prefix;
    const fs::path qt6cmake = fs::path("lib") / "cmake" / "Qt6" / "Qt6Config.cmake";
    if (fs::exists(fs::path(prefix) / qt6cmake))
        return prefix;
    const fs::path qtbaseSub = fs::path(prefix) / "qtbase";
    if (fs::exists(qtbaseSub / qt6cmake))
        return qtbaseSub.string();
    return prefix;
}

// Replace any character that is not alphanumeric with '_'.
static std::string sanitize(const std::string &s)
{
    std::string r;
    r.reserve(s.size());
    for (char c : s)
        r += std::isalnum(static_cast<unsigned char>(c)) ? c : '_';
    return r;
}

// Wrap a path in quotes for shell commands.
static std::string shellQuote(const std::string &s)
{
#ifdef _WIN32
    return "\"" + s + "\"";
#else
    std::string r = "'";
    for (char c : s) {
        if (c == '\'')
            r += "'\\''";
        else
            r += c;
    }
    r += "'";
    return r;
#endif
}

static void usage(const char *prog)
{
    std::cerr << "Usage: " << prog << " -c <ClassName> -f <functionName> [options]\n"
              << "       " << prog << " --cleanup\n\n"
              << "Options:\n"
              << "  -c <ClassName>       Qt class to fuzz (required)\n"
              << "  -f <functionName>    Function to fuzz (required)\n"
              << "  -t <seconds>         Fuzz duration — random mode (default: 30)\n"
              << "  -d <data>            Inline input: one argument value per line\n"
              << "  -i <file>            File with input data (same format as -d)\n"
              << "  -b <file>            Raw binary corpus (may repeat; bypasses serialization)\n"
              << "  --submodule <path>   Qt submodule root for class/function discovery\n"
              << "  --qt-prefix <path>   Qt install prefix (auto-detected if omitted)\n"
              << "  --list-cached        List all cached fuzzers and their build status\n"
              << "  --cleanup            Remove all cached fuzzers\n\n"
              << "Return codes:\n"
              << "  0  Fuzzer ran full -t seconds without crash.\n"
              << "  1  Fuzzer processed specific -d/-i input without crash.\n"
              << "  2  Fuzzer crashed.\n"
              << "  3  Error (class/function not found, build failure, etc.).\n";
}

// ---------------------------------------------------------------------------
// Type-to-FuzzData-expression mapper  (mirrors fuzzExprForType in codegen.cpp)
// ---------------------------------------------------------------------------
static std::string normType(const std::string &raw)
{
    std::string t;
    bool lastSpace = true;
    for (char c : raw) {
        if (std::isspace(static_cast<unsigned char>(c))) {
            if (!lastSpace) {
                t += ' ';
                lastSpace = true;
            }
        } else {
            t += c;
            lastSpace = false;
        }
    }
    while (!t.empty() && t.back() == ' ')
        t.pop_back();
    return t;
}

static std::string fuzzExpr(const std::string &rawType, const std::string &className)
{
    const std::string type = normType(rawType);

    if (type == "bool")
        return "static_cast<bool>(fd.nextBool())";
    if (type == "int" || type == "qint32")
        return "static_cast<int>(fd.nextInt())";
    if (type == "uint" || type == "quint32" || type == "unsigned int")
        return "static_cast<uint>(fd.nextUInt())";
    if (type == "qint64" || type == "qlonglong" || type == "long long")
        return "static_cast<" + type + ">(fd.nextInt64())";
    if (type == "quint64" || type == "qulonglong" || type == "unsigned long long")
        return "static_cast<" + type + ">(fd.nextUInt64())";
    if (type == "double")
        return "static_cast<double>(fd.nextDouble())";
    if (type == "float")
        return "static_cast<float>(fd.nextFloat())";
    if (type == "qreal")
        return "static_cast<qreal>(fd.nextDouble())";
    if (type == "char")
        return "static_cast<char>(fd.nextByte())";
    if (type == "uchar" || type == "unsigned char")
        return "static_cast<uchar>(fd.nextByte())";
    if (type == "char32_t")
        return "static_cast<char32_t>(fd.nextInt())";
    if (type == "short" || type == "qint16")
        return "static_cast<short>(fd.nextInt<short>())";
    if (type == "ushort" || type == "quint16")
        return "static_cast<ushort>(fd.nextInt<ushort>())";
    if (type == "qsizetype")
        return "static_cast<qsizetype>(fd.nextInt64())";
    if (type == "qptrdiff")
        return "static_cast<qptrdiff>(fd.nextInt64())";

    if (type == "QString" || type == "const QString &" || type == "const QString&")
        return "fd.nextQString()";
    if (type == "QByteArray" || type == "const QByteArray &" || type == "const QByteArray&")
        return "fd.nextQByteArray()";

    if (type.find("std::chrono::") == 0)
        return type + "(fd.nextInt64())";

    if (type == "QChar")
        return "QChar(fd.nextInt<ushort>())";
    if (type == "QPoint")
        return "QPoint(fd.nextInt(), fd.nextInt())";
    if (type == "QPointF")
        return "QPointF(fd.nextDouble(), fd.nextDouble())";
    if (type == "QSize")
        return "QSize(fd.nextInt(), fd.nextInt())";
    if (type == "QSizeF")
        return "QSizeF(fd.nextDouble(), fd.nextDouble())";
    if (type == "QRect")
        return "QRect(fd.nextInt(), fd.nextInt(), fd.nextInt(), fd.nextInt())";
    if (type == "QRectF")
        return "QRectF(fd.nextDouble(), fd.nextDouble(), fd.nextDouble(), fd.nextDouble())";
    if (type == "QUrl" || type == "const QUrl &" || type == "const QUrl&")
        return "QUrl(fd.nextQString())";
    if (type == "QColor" || type == "const QColor &" || type == "const QColor&")
        return "QColor(fd.nextByte(), fd.nextByte(), fd.nextByte(), fd.nextByte())";
    if (type == "QDeadlineTimer")
        return "QDeadlineTimer(fd.nextInt64())";
    if (type == "QAnyStringView" || type == "const QAnyStringView &")
        return "QAnyStringView(fd.nextQString())";

    // Pointer → nullptr
    if (!type.empty() && type.back() == '*')
        return "static_cast<" + type + ">(nullptr)";

    // Reference → strip and default-construct a local (const refs bind to temporaries)
    if (!type.empty() && type.back() == '&') {
        std::string base = type;
        while (!base.empty() && (base.back() == '&' || base.back() == ' '))
            base.pop_back();
        if (base.size() >= 6 && base.substr(0, 6) == "const ")
            base = base.substr(6);
        while (!base.empty() && base.back() == ' ')
            base.pop_back();
        return "/* ref */ " + base + "{}";
    }

    // Qt:: scoped enums / flags
    if (type.size() >= 4 && type.substr(0, 4) == "Qt::")
        return "static_cast<" + type + ">(fd.nextByte())";

    // Fully qualified with :: (not std::) → enum cast
    if (type.find("::") != std::string::npos && !(type.size() >= 5 && type.substr(0, 5) == "std::"))
        return "static_cast<" + type + ">(fd.nextByte())";

    // Single-word uppercase Qt types
    if (!type.empty() && std::isupper(static_cast<unsigned char>(type[0]))
        && type.find('<') == std::string::npos) {
        if (type.size() >= 2 && type[0] == 'Q' && std::isupper(static_cast<unsigned char>(type[1])))
            return type + "{}";
        // Nested enum / typedef inside the fuzzed class
        return "static_cast<" + className + "::" + type + ">(fd.nextByte())";
    }

    if (type.find("std::optional") != std::string::npos)
        return "std::nullopt";
    if (type.size() >= 5 && type.substr(0, 5) == "std::")
        return type + "{}";

    return "fd.nextInt()"; // fallback
}

// ---------------------------------------------------------------------------
// Binary serialization: text line → FuzzData byte sequence
//
// Must match exactly what the FuzzData methods read:
//   nextBool / nextByte  → 1 byte
//   nextInt<T>           → sizeof(T) bytes, big-endian
//   nextQString          → uint16_t(len) + len bytes  (len = uint16 % 257, max 256)
//   nextQByteArray       → uint16_t(len) + len bytes  (len = uint16 % 513, max 512)
//   nextDouble           → uint64 big-endian reinterpreted as IEEE 754 double
//   nextFloat            → uint32 big-endian reinterpreted as IEEE 754 float
// ---------------------------------------------------------------------------
static void writeU64Be(uint64_t v, std::vector<uint8_t> &out)
{
    for (int i = 7; i >= 0; --i)
        out.push_back(static_cast<uint8_t>((v >> (i * 8)) & 0xFF));
}

static void writeU32Be(uint32_t v, std::vector<uint8_t> &out)
{
    out.push_back((v >> 24) & 0xFF);
    out.push_back((v >> 16) & 0xFF);
    out.push_back((v >> 8) & 0xFF);
    out.push_back(v & 0xFF);
}

// Returns false and emits a warning if the type cannot be serialized precisely.
static bool serializeParam(const std::string &rawType, const std::string &text,
                           std::vector<uint8_t> &out)
{
    const std::string type = normType(rawType);

    if (type == "bool") {
        out.push_back((text == "true" || text == "1" || text == "yes") ? 1u : 0u);
        return true;
    }
    if (type == "int" || type == "qint32") {
        int32_t v = 0;
        try {
                v = static_cast<int32_t>(std::stol(text));
            } catch (...) { }
        writeU32Be(static_cast<uint32_t>(v), out);
        return true;
    }
    if (type == "uint" || type == "quint32" || type == "unsigned int") {
        uint32_t v = 0;
        try {
                v = static_cast<uint32_t>(std::stoul(text));
            } catch (...) { }
        writeU32Be(v, out);
        return true;
    }
    if (type == "qint64" || type == "qlonglong" || type == "long long") {
        int64_t v = 0;
        try {
                v = std::stoll(text);
            } catch (...) { }
        writeU64Be(static_cast<uint64_t>(v), out);
        return true;
    }
    if (type == "quint64" || type == "qulonglong" || type == "unsigned long long") {
        uint64_t v = 0;
        try {
                v = std::stoull(text);
            } catch (...) { }
        writeU64Be(v, out);
        return true;
    }
    if (type == "double" || type == "qreal") {
        double d = 0.0;
        try {
                d = std::stod(text);
            } catch (...) { }
        uint64_t bits = 0;
        std::memcpy(&bits, &d, 8);
        writeU64Be(bits, out);
        return true;
    }
    if (type == "float") {
        float f = 0.0f;
        try {
                f = std::stof(text);
            } catch (...) { }
        uint32_t bits = 0;
        std::memcpy(&bits, &f, 4);
        writeU32Be(bits, out);
        return true;
    }
    if (type == "char" || type == "uchar" || type == "unsigned char") {
        out.push_back(text.empty() ? 0u : static_cast<uint8_t>(text[0]));
        return true;
    }
    if (type == "short" || type == "qint16") {
        int16_t v = 0;
        try {
                v = static_cast<int16_t>(std::stoi(text));
            } catch (...) { }
        out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
        out.push_back(static_cast<uint8_t>(v & 0xFF));
        return true;
    }
    if (type == "ushort" || type == "quint16") {
        uint16_t v = 0;
        try {
                v = static_cast<uint16_t>(std::stoul(text));
            } catch (...) { }
        out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
        out.push_back(static_cast<uint8_t>(v & 0xFF));
        return true;
    }
    // QString-like: nextQString reads uint16_t len then len bytes.
    // With maxLen=256: len = uint16_val % 257, so len ≤ 256.
    if (type == "QString" || type == "const QString &" || type == "const QString&" || type == "QUrl"
        || type == "const QUrl &" || type == "const QUrl&" || type == "QAnyStringView"
        || type == "const QAnyStringView &") {
        size_t len = std::min(text.size(), size_t(256));
        auto ul = static_cast<uint16_t>(len);
        out.push_back(static_cast<uint8_t>((ul >> 8) & 0xFF));
        out.push_back(static_cast<uint8_t>(ul & 0xFF));
        out.insert(out.end(), text.begin(), text.begin() + static_cast<ptrdiff_t>(len));
        return true;
    }
    // QByteArray: nextQByteArray reads uint16_t len then len bytes, maxLen=512.
    if (type == "QByteArray" || type == "const QByteArray &" || type == "const QByteArray&") {
        size_t len = std::min(text.size(), size_t(512));
        auto ul = static_cast<uint16_t>(len);
        out.push_back(static_cast<uint8_t>((ul >> 8) & 0xFF));
        out.push_back(static_cast<uint8_t>(ul & 0xFF));
        out.insert(out.end(), text.begin(), text.begin() + static_cast<ptrdiff_t>(len));
        return true;
    }
    // QChar: nextInt<ushort>() → 2 bytes
    if (type == "QChar") {
        uint16_t v = text.empty() ? 0u : static_cast<uint16_t>(static_cast<unsigned char>(text[0]));
        if (text.size() > 1 && std::isdigit(static_cast<unsigned char>(text[0])))
            try {
                    v = static_cast<uint16_t>(std::stoul(text));
            } catch (...) { }
        out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
        out.push_back(static_cast<uint8_t>(v & 0xFF));
        return true;
    }

    // Unknown / complex type — write 4 zero bytes as best-effort nextInt() fallback.
    std::cerr << "[fuzz] WARNING: no precise serializer for type '" << rawType
              << "'; using 4 zero bytes.\n";
    out.push_back(0);
    out.push_back(0);
    out.push_back(0);
    out.push_back(0);
    return false;
}

// ---------------------------------------------------------------------------
// Specialized fuzzer source generation
// ---------------------------------------------------------------------------
static const char kFuzzerTemplate[] = R"FUZZ(
// GENERATED by fuzz tool — do not edit by hand.
// Targeted fuzzer: @@CLASS@@::@@FUNC@@

#include <@@CLASS@@>
#include @@APP_INCLUDE@@
#include <QString>
#include <QByteArray>
#include <QUrl>
#include <QPoint>
#include <QPointF>
#include <QSize>
#include <QSizeF>
#include <QRect>
#include <QRectF>
#if QT_GUI_LIB
#include <QColor>
#endif
#include <QChar>
#include <QDate>
#include <QTime>
#include <QDateTime>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

@@FUZZ_DATA_STRUCT@@

static void fuzz_target(@@CLASS@@ &obj, FuzzData &fd)
{
    @@FUNC_CALL@@
}

int main(int argc, char *argv[])
{
    @@APP_CLASS@@ app(argc, argv);

    int  timeLimitSec = 0;
    bool corpusOnly   = false;
    std::vector<std::string> corpusFiles;

    for (int i = 1; i < argc; i++) {
        std::string a(argv[i]);
        if ((a == "--time" || a == "-t") && i + 1 < argc)
            timeLimitSec = std::atoi(argv[++i]);
        else if (a == "--corpus-only")
            corpusOnly = true;
        else if (a.rfind("--", 0) != 0)
            corpusFiles.push_back(a);
    }

    @@CLASS@@ obj;

    for (const auto &path : corpusFiles) {
        std::ifstream f(path, std::ios::binary);
        if (!f) { std::cerr << "Cannot open corpus: " << path << "\n"; continue; }
        std::vector<uint8_t> buf(std::istreambuf_iterator<char>(f), {});
        FuzzData fd{ buf.data(), buf.size() };
        fuzz_target(obj, fd);
    }

    if (corpusOnly)
        return 1; // corpus processed without crash — exit code 1 = EC_GRACEFUL

    uint64_t         seed = 0xdeadbeefcafe1234ULL;
    constexpr size_t BUF_SIZE = 4096;
    std::vector<uint8_t> buf(BUF_SIZE);
    uint64_t             iterations = 0;
    auto startTime = std::chrono::steady_clock::now();

    for (;;) {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
        uint64_t s = seed;
        for (size_t i = 0; i < BUF_SIZE; i++) {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17;
            buf[i] = static_cast<uint8_t>(s & 0xff);
        }
        FuzzData fd{ buf.data(), BUF_SIZE };
        fuzz_target(obj, fd);
        ++iterations;
        if (timeLimitSec <= 0)
            break; // no time limit: one iteration only
        auto elapsed = std::chrono::steady_clock::now() - startTime;
        if (std::chrono::duration_cast<std::chrono::seconds>(elapsed).count() >= timeLimitSec)
            break;
    }

    std::cout << "[fuzz_@@CLASS@@_@@FUNC@@] " << iterations << " iterations\n";
    return 0; // timed out normally — exit code 0 = EC_TIMEOUT
}
)FUZZ";

// Build the call expression for fuzz_target(), handling non-const ref params
// by creating stack locals (can't bind a non-const ref to a temporary).
static std::string buildFuncCall(const std::string &funcName, const QtFuzz::MethodSignature &sig,
                                 const std::string &className)
{
    std::ostringstream o;

    // Declare stack locals for non-const ref params.
    for (size_t i = 0; i < sig.params.size(); ++i) {
        if (!sig.params[i].isNonConstRef)
            continue;
        std::string base = sig.params[i].type;
        while (!base.empty() && (base.back() == '&' || base.back() == ' '))
            base.pop_back();
        if (base.size() >= 6 && base.substr(0, 6) == "const ")
            base = base.substr(6);
        while (!base.empty() && base.back() == ' ')
            base.pop_back();
        o << base << " _p" << i << "{};\n    ";
    }

    o << "(void)obj." << funcName << "(";
    for (size_t i = 0; i < sig.params.size(); ++i) {
        if (i > 0)
            o << ", ";
        o << (sig.params[i].isNonConstRef ? "_p" + std::to_string(i)
                                          : fuzzExpr(sig.params[i].type, className));
    }
    o << ");";

    // Suppress unused-parameter warning for zero-arg functions.
    if (sig.params.empty())
        o << "\n    (void)fd;";

    return o.str();
}

static std::string generateFuzzerSource(const std::string &className, const std::string &funcName,
                                        const QtFuzz::MethodSignature &sig, QtFuzz::AppType appType)
{
    const QtFuzz::AppTypeInfo ati = QtFuzz::appTypeInfo(appType);
    const std::string funcCall = buildFuncCall(funcName, sig, className);

    std::string src(kFuzzerTemplate);

    auto replace = [](std::string &s, const std::string &from, const std::string &to) {
        size_t pos = 0;
        while ((pos = s.find(from, pos)) != std::string::npos) {
            s.replace(pos, from.size(), to);
            pos += to.size();
        }
    };

    replace(src, "@@CLASS@@", className);
    replace(src, "@@FUNC@@", funcName);
    replace(src, "@@APP_INCLUDE@@", ati.includeHeader);
    replace(src, "@@APP_CLASS@@", ati.className);
    replace(src, "@@FUNC_CALL@@", funcCall);
    replace(src, "@@FUZZ_DATA_STRUCT@@", QtFuzz::fuzzDataStructSource());

    return src;
}

// ---------------------------------------------------------------------------
// Build helpers
// ---------------------------------------------------------------------------

// Run cmd (via shell), capture combined stdout+stderr.
// Returns empty string on success, captured output on failure.
static std::string runCommandCheck(const std::string &cmd)
{
#ifdef _WIN32
    FILE *p = _popen((cmd + " 2>&1").c_str(), "r");
#else
    FILE *p = popen((cmd + " 2>&1").c_str(), "r");
#endif
    if (!p)
        return "popen() failed for: " + cmd;

    std::string out;
    char buf[4096];
    while (fgets(buf, sizeof(buf), p))
        out += buf;

#ifdef _WIN32
    const int code = _pclose(p);
    if (code != 0)
        return out.empty() ? "(no output)" : out;
#else
    const int code = pclose(p);
    if (code == -1 || WEXITSTATUS(code) != 0)
        return out.empty() ? "(no output)" : out;
#endif
    return { };
}

#ifdef _WIN32
// Locate vcvarsall.bat via vswhere.exe so cmake runs in the MSVC environment.
static std::string findVcVarsAll()
{
    const std::string vswhere =
            "C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe";
    if (!fs::exists(vswhere))
        return { };
    FILE *p = _popen(("\"" + vswhere + "\" -latest -property installationPath 2>nul").c_str(), "r");
    if (!p)
        return { };
    char buf[512] = { };
    const bool got = fgets(buf, sizeof(buf), p) != nullptr;
    _pclose(p);
    if (!got)
        return { };
    std::string path(buf);
    while (!path.empty() && (path.back() == '\n' || path.back() == '\r' || path.back() == ' '))
        path.pop_back();
    return path.empty() ? std::string{ } : path + "\\VC\\Auxiliary\\Build\\vcvarsall.bat";
}
#endif

static std::string buildFuzzer(const fs::path &srcDir, const fs::path &buildDir,
                               const std::string &qtPrefix)
{
    std::string configCmd =
            "cmake -B " + shellQuote(buildDir.string()) + " -S " + shellQuote(srcDir.string());
    if (!qtPrefix.empty())
        configCmd += " -DCMAKE_PREFIX_PATH=" + shellQuote(qtPrefix);

#ifdef _WIN32
    // Specify MSVC explicitly; without this cmake picks up whatever c++ is
    // first in PATH (e.g. MinGW from Strawberry Perl).
    configCmd += " -G Ninja -DCMAKE_CXX_COMPILER=cl -DCMAKE_C_COMPILER=cl";
    // cmake must run inside the MSVC developer environment.
    // Write a small batch file that initialises it then drives both cmake steps.
    const fs::path batchFile = srcDir / "_build.bat";
    {
        std::ofstream bat(batchFile);
        if (!bat)
            return "Cannot write build script: " + batchFile.string();
        const std::string vcvarsall = findVcVarsAll();
        if (!vcvarsall.empty())
            bat << "@call \"" << vcvarsall << "\" x64 >nul 2>&1\r\n";
        // Delete stale CMakeCache.txt so a compiler change never causes a mismatch error.
        bat << "@if exist " << shellQuote(buildDir.string() + "\\CMakeCache.txt") << " del /f /q "
            << shellQuote(buildDir.string() + "\\CMakeCache.txt") << "\r\n";
        bat << "@" << configCmd << "\r\n"
            << "@if errorlevel 1 exit /b 1\r\n"
            << "@cmake --build " << shellQuote(buildDir.string()) << "\r\n";
    }
    const std::string err = runCommandCheck("cmd /c " + shellQuote(batchFile.string()));
    if (!err.empty())
        return "build failed:\n" + err;
    return { };
#else
    std::string err = runCommandCheck(configCmd);
    if (!err.empty())
        return "cmake configure failed:\n" + err;

    err = runCommandCheck("cmake --build " + shellQuote(buildDir.string()));
    if (!err.empty())
        return "cmake build failed:\n" + err;

    return { };
#endif
}

// ---------------------------------------------------------------------------
// Subprocess runner
// ---------------------------------------------------------------------------
#ifdef _WIN32
static int runFuzzer(const fs::path &exe, const std::vector<std::string> &args, int timeoutSec,
                     const std::string &qtPrefix)
{
    std::string cmdLine = "\"" + exe.string() + "\"";
    for (const auto &a : args) {
        cmdLine += ' ';
        if (a.find(' ') != std::string::npos)
            cmdLine += "\"" + a + "\"";
        else
            cmdLine += a;
    }

    // Prepend Qt's bin directory to PATH so the generated fuzzer can load Qt DLLs.
    std::string envBlock;
    if (!qtPrefix.empty()) {
        const std::string qtBin = qtPrefix + "\\bin";
        char currentPath[32768] = { };
        GetEnvironmentVariableA("PATH", currentPath, sizeof(currentPath));
        const std::string newPath = "PATH=" + qtBin + ";" + currentPath;
        // Environment block: null-terminated strings, double-null at end.
        envBlock = newPath;
        envBlock.push_back('\0');
        // Copy remaining environment variables.
        const char *env = GetEnvironmentStringsA();
        if (env) {
            for (const char *p = env; *p; p += std::strlen(p) + 1) {
                if (std::strncmp(p, "PATH=", 5) != 0 && std::strncmp(p, "Path=", 5) != 0
                    && std::strncmp(p, "path=", 5) != 0) {
                    envBlock.append(p, std::strlen(p) + 1);
                }
            }
            FreeEnvironmentStringsA(const_cast<char *>(env));
        }
        envBlock.push_back('\0'); // double-null terminator
    }

    STARTUPINFOA si = { };
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = { };

    const char *envPtr = envBlock.empty() ? nullptr : envBlock.data();
    if (!CreateProcessA(nullptr, const_cast<char *>(cmdLine.c_str()), nullptr, nullptr, FALSE, 0,
                        const_cast<char *>(envPtr), nullptr, &si, &pi)) {
        std::cerr << "[fuzz] CreateProcess failed with error " << GetLastError() << "\n";
        return EC_ERROR;
    }

    const DWORD waitMs = static_cast<DWORD>((timeoutSec + 30) * 1000);
    const DWORD result = WaitForSingleObject(pi.hProcess, waitMs);

    int exitCode = EC_CRASH;
    if (result == WAIT_OBJECT_0) {
        DWORD code = 0;
        if (GetExitCodeProcess(pi.hProcess, &code)) {
            if (code == 0)
                exitCode = EC_TIMEOUT;
            else if (code == 1)
                exitCode = EC_GRACEFUL;
        }
    } else {
        std::cerr << "[fuzz] Fuzzer timed out (safety), terminating.\n";
        TerminateProcess(pi.hProcess, 1);
    }

    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return exitCode;
}
#else
static volatile sig_atomic_t g_parentKilled = 0;
static pid_t g_childPid = -1;

static void onParentAlarm(int)
{
    g_parentKilled = 1;
    if (g_childPid > 0)
        kill(g_childPid, SIGKILL);
}

static int runFuzzer(const fs::path &exe, const std::vector<std::string> &args, int timeoutSec)
{
    const pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "[fuzz] fork() failed: " << strerror(errno) << "\n";
        return EC_ERROR;
    }

    if (pid == 0) {
        // Child: exec the generated fuzzer.
        std::vector<const char *> argv;
        argv.push_back(exe.c_str());
        for (const auto &a : args)
            argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execv(exe.c_str(), const_cast<char **>(argv.data()));
        _exit(127);
    }

    // Parent: wait with a safety timeout so a hung child cannot block forever.
    g_childPid = pid;
    g_parentKilled = 0;
    std::signal(SIGALRM, onParentAlarm);
    alarm(static_cast<unsigned>(timeoutSec + 30));

    int wstatus = 0;
    waitpid(pid, &wstatus, 0);
    alarm(0); // cancel parent alarm

    if (WIFEXITED(wstatus)) {
        const int code = WEXITSTATUS(wstatus);
        if (code == 0)
            return EC_TIMEOUT;
        if (code == 1)
            return EC_GRACEFUL;
        return EC_CRASH;
    }

    if (WIFSIGNALED(wstatus)) {
        const int sig = WTERMSIG(wstatus);
        if (sig == SIGKILL && g_parentKilled)
            std::cerr << "[fuzz] Fuzzer killed by parent safety timeout (hung).\n";
        else
            std::cerr << "[fuzz] Fuzzer killed by signal " << sig << ".\n";
        return EC_CRASH;
    }

    return EC_CRASH;
}
#endif

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, char *argv[])
{
    std::string className;
    std::string funcName;
    std::string inlineData;
    std::string inputFile;
    std::string submodule;
    std::string qtPrefix;
    std::vector<std::string> rawCorpusFiles;
    int timeSec = 30;
    bool doCleanup = false;
    bool doListCached = false;

    for (int i = 1; i < argc; i++) {
        std::string a(argv[i]);
        if (a == "--help" || a == "-h") {
            usage(argv[0]);
            return 0;
        } else if (a == "--cleanup") {
            doCleanup = true;
        } else if (a == "--list-cached") {
            doListCached = true;
        } else if (a == "-c" && i + 1 < argc) {
            className = argv[++i];
        } else if (a == "-f" && i + 1 < argc) {
            funcName = argv[++i];
        } else if (a == "-t" && i + 1 < argc) {
            timeSec = std::atoi(argv[++i]);
        } else if (a == "-d" && i + 1 < argc) {
            inlineData = argv[++i];
        } else if (a == "-i" && i + 1 < argc) {
            inputFile = argv[++i];
        } else if (a == "-b" && i + 1 < argc) {
            rawCorpusFiles.push_back(argv[++i]);
        } else if (a == "--submodule" && i + 1 < argc) {
            submodule = argv[++i];
        } else if (a == "--qt-prefix" && i + 1 < argc) {
            qtPrefix = argv[++i];
        }
    }

    // ── --list-cached ────────────────────────────────────────────────────────
    if (doListCached) {
        const fs::path root = cacheRoot();
        std::error_code ec;
        if (!fs::exists(root, ec) || ec) {
            std::cout << "[fuzz] No cached fuzzers (cache dir does not exist).\n";
            return 0;
        }
        bool any = false;
        for (const auto &entry : fs::directory_iterator(root, ec)) {
            if (ec) {
                ec.clear();
                continue;
            }
            if (!entry.is_directory())
                continue;
            const std::string name = entry.path().filename().string();
#ifdef _WIN32
            const fs::path binary = entry.path() / "build" / ("fuzz_" + name + ".exe");
#else
            const fs::path binary = entry.path() / "build" / ("fuzz_" + name);
#endif
            std::error_code ec2;
            const bool built = fs::exists(binary, ec2);
            std::cout << name << (built ? "  [built]" : "  [source only]") << "\n";
            any = true;
        }
        if (!any)
            std::cout << "[fuzz] No cached fuzzers.\n";
        return 0;
    }

    // ── --cleanup ────────────────────────────────────────────────────────────
    if (doCleanup) {
        std::error_code ec;
        const auto n = fs::remove_all(cacheRoot(), ec);
        std::cout << "[fuzz] Removed " << n << " entries from " << cacheRoot() << "\n";
        return 0;
    }

    // ── Validate required args ───────────────────────────────────────────────
    if (className.empty() || funcName.empty()) {
        usage(argv[0]);
        return EC_ERROR;
    }
    if (!inlineData.empty() && !inputFile.empty()) {
        std::cerr << "[fuzz] ERROR: -d and -i are mutually exclusive.\n";
        return EC_ERROR;
    }
    for (const auto &bf : rawCorpusFiles) {
        if (!fs::exists(bf)) {
            std::cerr << "[fuzz] ERROR: -b file not found: " << bf << "\n";
            return EC_ERROR;
        }
    }
    if (submodule.empty()) {
        std::cerr << "[fuzz] ERROR: --submodule <path> is required.\n";
        return EC_ERROR;
    }

    // ── Read input text ──────────────────────────────────────────────────────
    std::string inputText;
    if (!inlineData.empty()) {
        inputText = inlineData;
    } else if (!inputFile.empty()) {
        std::ifstream f(inputFile);
        if (!f) {
            std::cerr << "[fuzz] ERROR: cannot open input file: " << inputFile << "\n";
            return EC_ERROR;
        }
        std::ostringstream ss;
        ss << f.rdbuf();
        inputText = ss.str();
    }

    // ── Normalize paths (MinGW /c/... → C:/... for cmd.exe / cmake) ──────────
    submodule = nativePath(submodule);
    qtPrefix = nativePath(qtPrefix);

    // ── Auto-detect Qt prefix ────────────────────────────────────────────────
    if (qtPrefix.empty())
        qtPrefix = QtFuzz::detectQtPrefix();
    qtPrefix = resolveQtPrefix(qtPrefix);

    // ── Look up class and function ───────────────────────────────────────────
    auto classOpt = QtFuzz::scanSingleClass(className, fs::path(submodule));
    if (!classOpt) {
        std::cerr << "[fuzz] ERROR: class '" << className << "' not found under " << submodule
                  << ".\n";
        return EC_ERROR;
    }
    const QtFuzz::DiscoveredClass &dc = *classOpt;

    std::vector<const QtFuzz::MethodSignature *> matches;
    for (const auto &sig : dc.publicMethods) {
        if (sig.name == funcName)
            matches.push_back(&sig);
    }

    if (matches.empty()) {
        std::cerr << "[fuzz] ERROR: function '" << funcName << "' not found in class '" << className
                  << "'.\n"
                  << "       Known public methods:\n";
        for (const auto &sig : dc.publicMethods)
            std::cerr << "         " << sig.name << "\n";
        return EC_ERROR;
    }
    if (matches.size() > 1) {
        std::cerr << "[fuzz] NOTE: " << matches.size() << " overloads of '" << funcName
                  << "'; using the first one.\n";
    }
    const QtFuzz::MethodSignature &sig = *matches.front();
    const size_t numParams = sig.params.size();

    // ── Parse input lines ────────────────────────────────────────────────────
    bool hasInput = !inputText.empty() || !rawCorpusFiles.empty();
    std::vector<std::string> lines;
    if (hasInput) {
        std::istringstream ss(inputText);
        std::string line;
        while (std::getline(ss, line)) {
            if (!line.empty() && line.back() == '\r')
                line.pop_back();
            lines.push_back(line);
        }
        while (!lines.empty() && lines.back().empty())
            lines.pop_back();

        if (numParams > 0 && lines.size() % numParams != 0) {
            std::cerr << "[fuzz] ERROR: " << lines.size() << " input lines not divisible by "
                      << numParams << " (param count).\n";
            return EC_ERROR;
        }
    }

    // ── Cache setup ──────────────────────────────────────────────────────────
    const std::string safeName = sanitize(className) + "_" + sanitize(funcName);
    const std::string targetName = "fuzz_" + safeName;
    const fs::path cDir = cacheRoot() / safeName;
    const fs::path srcFile = cDir / (targetName + ".cpp");
    const fs::path cmakeFile = cDir / "CMakeLists.txt";
    const fs::path buildDir = cDir / "build";
#ifdef _WIN32
    const fs::path binaryPath = buildDir / (targetName + ".exe");
#else
    const fs::path binaryPath = buildDir / targetName;
#endif

    // ── Generate and build (if not cached) ──────────────────────────────────
    if (!fs::exists(binaryPath)) {
        std::cerr << "[fuzz] Building cached fuzzer for " << className << "::" << funcName
                  << " ...\n";

        std::error_code ec;
        fs::create_directories(cDir, ec);
        if (ec) {
            std::cerr << "[fuzz] ERROR: cannot create cache dir: " << ec.message() << "\n";
            return EC_ERROR;
        }

        // Write generated .cpp
        {
            std::ofstream f(srcFile);
            if (!f) {
                std::cerr << "[fuzz] ERROR: cannot write " << srcFile << "\n";
                return EC_ERROR;
            }
            f << generateFuzzerSource(className, funcName, sig, dc.module.appType);
        }

        // Write CMakeLists.txt via existing CMakeGenerator.
        // Use safeName as the cmake "className" so the target is fuzz_QDir_mkdir etc.
        auto components = QtFuzz::resolveComponents(dc.module);
        QtFuzz::CMakeGenerator::Config cfg{ safeName, targetName + ".cpp",
                                            dc.module, components,
                                            qtPrefix, timeSec };
        QtFuzz::CMakeGenerator cmakeGen(std::move(cfg), cmakeFile);
        if (!cmakeGen.generate()) {
            std::cerr << "[fuzz] ERROR: cannot write CMakeLists.txt\n";
            return EC_ERROR;
        }

        // Build
        const std::string buildErr = buildFuzzer(cDir, buildDir, qtPrefix);
        if (!buildErr.empty()) {
            std::cerr << "[fuzz] ERROR: " << buildErr;
            return EC_ERROR;
        }
        std::cerr << "[fuzz] Build complete: " << binaryPath << "\n";
    } else {
        std::cerr << "[fuzz] Using cached fuzzer: " << binaryPath << "\n";
    }

    // ── Serialize input to binary corpus files ───────────────────────────────
    std::vector<std::string> corpusPaths;
    if (!inputText.empty()) {
        const size_t callCount = numParams > 0 ? lines.size() / numParams : 1;
        for (size_t c = 0; c < callCount; ++c) {
            std::vector<uint8_t> binary;
            for (size_t p = 0; p < numParams; ++p)
                serializeParam(sig.params[p].type, lines[c * numParams + p], binary);

            const fs::path corpusFile = cDir / ("corpus_" + std::to_string(c) + ".bin");
            std::ofstream f(corpusFile, std::ios::binary);
            if (!f) {
                std::cerr << "[fuzz] ERROR: cannot write corpus file " << corpusFile << "\n";
                return EC_ERROR;
            }
            f.write(reinterpret_cast<const char *>(binary.data()),
                    static_cast<std::streamsize>(binary.size()));
            corpusPaths.push_back(corpusFile.string());
        }
    }
    // Raw binary corpus files: pass directly, no serialization.
    for (const auto &bf : rawCorpusFiles)
        corpusPaths.push_back(bf);

    // ── Run ──────────────────────────────────────────────────────────────────
    std::vector<std::string> fuzzArgs;
    if (hasInput) {
        // Corpus-only mode: process the specific inputs and exit.
        fuzzArgs.push_back("--corpus-only");
        for (const auto &p : corpusPaths)
            fuzzArgs.push_back(p);
    } else {
        // Random fuzzing mode: run for -t seconds.
        fuzzArgs.push_back("--time");
        fuzzArgs.push_back(std::to_string(timeSec));
    }

#ifdef _WIN32
    return runFuzzer(binaryPath, fuzzArgs, timeSec, qtPrefix);
#else
    return runFuzzer(binaryPath, fuzzArgs, timeSec);
#endif
}
