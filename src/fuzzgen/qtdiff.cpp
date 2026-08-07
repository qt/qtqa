// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// qtdiff — lists the Qt classes whose header or source files differ between
// local HEAD and remote HEAD.
//
// Usage:
//   qtdiff [--repo <path>] [--branch <name>]
//
// Options:
//   --repo <path>     Directory inside the git repository to operate on
//                      (default: current working directory).
//   --branch <name>   Diff against origin/<name> instead of the
//                      auto-detected remote HEAD (e.g. "--branch 6.12" to
//                      diff against a release branch). Applied uniformly to
//                      --repo and every submodule.
//
// By default, "remote HEAD" is the current branch's configured upstream
// (@{upstream}) when on a named branch, or the remote's default branch
// (origin/HEAD) when HEAD is detached — the normal state for a submodule
// pinned to a fixed commit by its superproject. --branch overrides this
// entirely with a fixed origin/<name> ref for every repository scanned.
//
// --repo (or the current directory) is always diffed directly first. If it
// also declares submodules (has a .gitmodules — e.g. a qt5 superproject
// checkout, or a module like qtdeclarative/qtwebengine that bundles its own
// test-data/vendored submodule), every initialized submodule is diffed too
// — one is never a substitute for the other, since a module can have real
// Qt sources of its own *and* an incidental nested submodule. Submodule
// nesting is followed exactly one level deep: a submodule's own further
// submodules (e.g. qtwebengine's vendored Chromium tree) are never
// expanded, since they are not Qt sources. The repo's own classes are
// printed unprefixed; a submodule's are printed as "<submodule>: <ClassName>".
//
// Exits non-zero (with a message on stderr) when: not inside a git
// repository, or (for a repo with no submodules) HEAD is detached with no
// origin/HEAD, or the current branch has no upstream configured. Otherwise
// prints the sorted, de-duplicated list of Qt class names touched by the
// diff, one per line, or "No Qt classes changed." if no repository in scope
// had any qualifying result. A file whose scan crashes or exceeds the
// per-file timeout (see kScanTimeoutMs) is skipped with a warning on
// stderr rather than aborting the run — real-world diffs can include
// adversarial-scale vendored code (e.g. Chromium sources reachable through
// qtwebengine) that can defeat libstdc++'s std::regex.

#include "scanner.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
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
#  include <fcntl.h>
#  include <poll.h>
#  include <signal.h>
#  include <spawn.h>
#  include <sys/wait.h>
#  include <unistd.h>
extern char **environ;
#endif

// Per-file wall-clock budget for the out-of-process class-name scan (see
// scanFileInSubprocess below). Real Qt/Chromium source files scan in low
// single-digit milliseconds; this only ever engages for the rare
// pathological file that trips libstdc++'s std::regex into extreme
// slowness or (observed in practice, on ordinary qtdeclarative sources)
// a stack-overflow crash — both are handled the same way: the scan runs in
// a disposable child process, so a crash or a timed-out kill only costs us
// that one file's classes, never the rest of the run.
static constexpr int kScanTimeoutMs = 5000;

namespace fs = std::filesystem;

namespace {

struct CommandResult {
    int exitCode = -1;
    std::string output;
};

// Runs `git <args...>` with cwd set to workDir, via posix_spawn/CreateProcess
// with an explicit argv array — never a shell string — so that ref/branch
// names (which are effectively attacker-influenceable: anyone who can push
// a branch controls their text) cannot inject shell metacharacters.
// git's own stderr chatter (e.g. "fatal: no upstream configured for branch")
// is discarded — callers report their own, more specific messages.
#ifdef _WIN32

CommandResult runGit(const std::vector<std::string> &args, const fs::path &workDir)
{
    SECURITY_ATTRIBUTES sa = { };
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE readPipe = nullptr, writePipe = nullptr;
    if (!CreatePipe(&readPipe, &writePipe, &sa, 0))
        return { -1, { } };
    SetHandleInformation(readPipe, HANDLE_FLAG_INHERIT, 0);

    HANDLE nulHandle = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa,
                                   OPEN_EXISTING, 0, nullptr);

    std::string cmd = "git -C \"" + workDir.string() + "\"";
    for (const auto &a : args)
        cmd += " \"" + a + "\"";

    STARTUPINFOA si = { };
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = writePipe;
    si.hStdError = nulHandle ? nulHandle : writePipe;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    PROCESS_INFORMATION pi = { };

    BOOL ok = CreateProcessA(nullptr, const_cast<char *>(cmd.c_str()), nullptr, nullptr, TRUE, 0,
                             nullptr, nullptr, &si, &pi);
    CloseHandle(writePipe);
    if (nulHandle)
        CloseHandle(nulHandle);

    if (!ok) {
        CloseHandle(readPipe);
        return { -1, { } };
    }
    CloseHandle(pi.hThread);

    std::string output;
    char buf[4096];
    DWORD n = 0;
    while (ReadFile(readPipe, buf, sizeof(buf), &n, nullptr) && n > 0)
        output.append(buf, n);
    CloseHandle(readPipe);

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);

    return { static_cast<int>(code), output };
}

#else // POSIX

CommandResult runGit(const std::vector<std::string> &args, const fs::path &workDir)
{
    int outPipe[2];
    if (pipe(outPipe) != 0)
        return { -1, { } };

    std::vector<std::string> argv = { "git", "-C", workDir.string() };
    argv.insert(argv.end(), args.begin(), args.end());

    std::vector<char *> cArgv;
    cArgv.reserve(argv.size() + 1);
    for (auto &a : argv)
        cArgv.push_back(const_cast<char *>(a.c_str()));
    cArgv.push_back(nullptr);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    pid_t pid = -1;
    int rc = posix_spawnp(&pid, "git", &actions, nullptr, cArgv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    close(outPipe[1]);

    if (rc != 0) {
        close(outPipe[0]);
        return { -1, { } };
    }

    std::string output;
    char buf[4096];
    ssize_t n;
    while ((n = read(outPipe[0], buf, sizeof(buf))) > 0)
        output.append(buf, static_cast<size_t>(n));
    close(outPipe[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    CommandResult result;
    result.exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    result.output = output;
    return result;
}

#endif

struct ScanResult {
    bool ok = false;
    bool timedOut = false;
    bool crashed = false;
    std::string output;
};

// Runs argv[0] (an absolute path to this same qtdiff binary) with the given
// arguments, capturing stdout, and hard-kills it if it hasn't exited within
// timeoutMs. Used exclusively to run the class-name scan for one file in a
// disposable child process — see the kScanTimeoutMs comment above main().
#ifdef _WIN32

ScanResult spawnCapture(const std::vector<std::string> &argv, int timeoutMs)
{
    ScanResult result;

    SECURITY_ATTRIBUTES sa = { };
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE readPipe = nullptr, writePipe = nullptr;
    if (!CreatePipe(&readPipe, &writePipe, &sa, 0))
        return result;
    SetHandleInformation(readPipe, HANDLE_FLAG_INHERIT, 0);

    HANDLE nulHandle = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa,
                                   OPEN_EXISTING, 0, nullptr);

    std::string cmd;
    for (const auto &a : argv)
        cmd += (cmd.empty() ? "" : " ") + ("\"" + a + "\"");

    STARTUPINFOA si = { };
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = writePipe;
    si.hStdError = nulHandle ? nulHandle : writePipe;
    si.hStdInput = nullptr;
    PROCESS_INFORMATION pi = { };

    BOOL ok = CreateProcessA(nullptr, const_cast<char *>(cmd.c_str()), nullptr, nullptr, TRUE, 0,
                             nullptr, nullptr, &si, &pi);
    CloseHandle(writePipe);
    if (nulHandle)
        CloseHandle(nulHandle);

    if (!ok) {
        CloseHandle(readPipe);
        return result;
    }
    CloseHandle(pi.hThread);

    // Drain the pipe while waiting so a chatty child can never fill the
    // pipe buffer and deadlock against our own wait loop, then enforce the
    // timeout with a bounded WaitForSingleObject poll.
    std::string output;
    char buf[4096];
    bool exited = false;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);

    while (true) {
        DWORD avail = 0;
        if (PeekNamedPipe(readPipe, nullptr, 0, nullptr, &avail, nullptr) && avail > 0) {
            DWORD n = 0;
            if (ReadFile(readPipe, buf, sizeof(buf), &n, nullptr) && n > 0)
                output.append(buf, n);
        }
        DWORD waitRc = WaitForSingleObject(pi.hProcess, 20);
        if (waitRc == WAIT_OBJECT_0) {
            exited = true;
            break;
        }
        if (std::chrono::steady_clock::now() >= deadline) {
            TerminateProcess(pi.hProcess, 124);
            WaitForSingleObject(pi.hProcess, INFINITE);
            result.timedOut = true;
            break;
        }
    }

    if (exited) {
        DWORD n = 0;
        while (ReadFile(readPipe, buf, sizeof(buf), &n, nullptr) && n > 0)
            output.append(buf, n);
    }
    CloseHandle(readPipe);

    if (result.timedOut) {
        CloseHandle(pi.hProcess);
        return result;
    }

    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);

    result.crashed = (code != 0);
    result.ok = !result.crashed;
    result.output = output;
    return result;
}

#else // POSIX

ScanResult spawnCapture(const std::vector<std::string> &argv, int timeoutMs)
{
    ScanResult result;

    int outPipe[2];
    if (pipe(outPipe) != 0)
        return result;

    std::vector<char *> cArgv;
    cArgv.reserve(argv.size() + 1);
    for (auto &a : argv)
        cArgv.push_back(const_cast<char *>(a.c_str()));
    cArgv.push_back(nullptr);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outPipe[1]);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    pid_t pid = -1;
    int rc = posix_spawn(&pid, argv[0].c_str(), &actions, nullptr, cArgv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    close(outPipe[1]);

    if (rc != 0) {
        close(outPipe[0]);
        return result;
    }

    // Drain the pipe while waiting (via poll's own timeout as the tick) so
    // a chatty child can never fill the pipe buffer and deadlock against
    // our own wait loop, then enforce the overall timeout across ticks.
    std::string output;
    char buf[4096];
    bool exited = false;
    int status = 0;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);

    while (true) {
        struct pollfd pfd = { outPipe[0], POLLIN, 0 };
        if (poll(&pfd, 1, 20) > 0 && (pfd.revents & (POLLIN | POLLHUP))) {
            ssize_t n = read(outPipe[0], buf, sizeof(buf));
            if (n > 0)
                output.append(buf, static_cast<size_t>(n));
        }

        if (waitpid(pid, &status, WNOHANG) == pid) {
            exited = true;
            break;
        }
        if (std::chrono::steady_clock::now() >= deadline) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            result.timedOut = true;
            break;
        }
    }

    if (exited) {
        ssize_t n;
        while ((n = read(outPipe[0], buf, sizeof(buf))) > 0)
            output.append(buf, static_cast<size_t>(n));
    }
    close(outPipe[0]);

    if (result.timedOut)
        return result;

    result.crashed = !WIFEXITED(status) || WEXITSTATUS(status) != 0;
    result.ok = !result.crashed;
    result.output = output;
    return result;
}

#endif

std::string trim(const std::string &s)
{
    size_t a = s.find_first_not_of(" \t\n\r");
    if (a == std::string::npos)
        return { };
    size_t b = s.find_last_not_of(" \t\n\r");
    return s.substr(a, b - a + 1);
}

std::vector<std::string> splitLines(const std::string &s)
{
    std::vector<std::string> lines;
    std::istringstream iss(s);
    std::string line;
    while (std::getline(iss, line)) {
        line = trim(line);
        if (!line.empty())
            lines.push_back(line);
    }
    return lines;
}

void usage(const char *prog)
{
    std::cerr << "Usage: " << prog << " [--repo <path>] [--branch <name>]\n"
              << "Lists the Qt classes whose header/source files differ between\n"
              << "the current branch's local HEAD and its remote HEAD.\n"
              << "\n"
              << "\"Remote HEAD\" is, by default, the current branch's configured\n"
              << "upstream (@{upstream}) when on a named branch, or the remote's\n"
              << "default branch (origin/HEAD) when HEAD is detached — e.g. a\n"
              << "submodule pinned to a fixed commit by its superproject.\n"
              << "\n"
              << "--branch <name>   Diff against origin/<name> instead (e.g.\n"
              << "                   '--branch 6.12' to diff against a release\n"
              << "                   branch rather than the default branch). Applied\n"
              << "                   uniformly to --repo and every submodule; a\n"
              << "                   submodule where that branch doesn't exist\n"
              << "                   remotely is skipped with a warning.\n"
              << "\n"
              << "--repo is always diffed directly. If it also declares submodules\n"
              << "(has .gitmodules), every initialized submodule is diffed too, one\n"
              << "level deep; each submodule's results are printed as\n"
              << "\"<submodule>: <ClassName>\".\n";
}

// Result of diffing a single git repository (not a superproject traversal).
struct RepoResult {
    bool ok = false;
    std::string error; // set when !ok
    std::set<std::string> classes;
};

// Resolves "remote HEAD" for repoRoot: origin/<branchOverride> when one is
// given (e.g. "6.12" for a release branch); otherwise the current branch's
// upstream when on a named branch, or origin/HEAD when detached
// (submodule-pinned checkouts have no current branch at all — origin/HEAD
// is the most literal reading of "remote HEAD" available in that state).
// Returns {ok, ref, error}.
struct RemoteHeadResult {
    bool ok = false;
    std::string ref;
    std::string error;
};

RemoteHeadResult resolveRemoteHead(const fs::path &repoRoot, const std::string &branchOverride)
{
    if (!branchOverride.empty()) {
        const std::string ref = "origin/" + branchOverride;
        if (runGit({ "rev-parse", "--verify", "--quiet", ref }, repoRoot).exitCode != 0) {
            return { false, { }, "remote branch '" + ref + "' not found" };
        }
        return { true, ref, { } };
    }

    auto branchResult = runGit({ "rev-parse", "--abbrev-ref", "HEAD" }, repoRoot);
    const std::string branch = trim(branchResult.output);

    if (branchResult.exitCode == 0 && !branch.empty() && branch != "HEAD") {
        auto upstreamResult = runGit(
                { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" }, repoRoot);
        const std::string upstream = trim(upstreamResult.output);
        if (upstreamResult.exitCode != 0 || upstream.empty()) {
            return { false, { },
                     "branch '" + branch + "' has no upstream — nothing to diff against" };
        }
        return { true, upstream, { } };
    }

    // Detached HEAD: fall back to the remote's default branch pointer.
    auto symrefResult = runGit({ "symbolic-ref", "refs/remotes/origin/HEAD" }, repoRoot);
    const std::string symref = trim(symrefResult.output);
    static const std::string kRemotesPrefix = "refs/remotes/";
    if (symrefResult.exitCode != 0 || symref.rfind(kRemotesPrefix, 0) != 0) {
        return { false, { },
                 "detached HEAD and no origin/HEAD to diff against" };
    }
    return { true, symref.substr(kRemotesPrefix.size()), { } };
}

// Maps relative path -> list of (startLine, lineCount) ranges on the HEAD
// (old) side that differ from remoteRef, parsed from a single
// `git diff --unified=0 HEAD remoteRef` invocation (one call for the whole
// repo, rather than one per changed file). Zero-context unified diff hunk
// headers look like "@@ -START[,COUNT] +newStart[,newCount] @@"; COUNT
// defaults to 1 when omitted, and a COUNT of 0 (pure insertion, nothing
// removed from the HEAD side at that point) contributes no HEAD-side range.
//
// This is what lets qtdiff attribute a changed file to only the specific
// classes whose own declaration/definition lines actually differ, instead
// of every class merely *present* in that file — otherwise a file like
// qdom.cpp, which defines methods for a few dozen QDom* classes, would
// attribute all of them to a single one-line change anywhere in the file.
std::map<std::string, std::vector<std::pair<int, int>>>
changedLineRanges(const fs::path &repoRoot, const std::string &remoteRef)
{
    std::map<std::string, std::vector<std::pair<int, int>>> result;

    auto diffResult = runGit({ "diff", "--unified=0", "HEAD", remoteRef }, repoRoot);
    if (diffResult.exitCode != 0)
        return result;

    static const std::string kFilePrefix = "diff --git a/";
    static const std::regex kHunkRe(R"(^@@ -(\d+)(?:,(\d+))? \+)");

    std::string currentFile;
    for (const auto &line : splitLines(diffResult.output)) {
        if (line.rfind(kFilePrefix, 0) == 0) {
            const std::string rest = line.substr(kFilePrefix.size());
            const size_t sep = rest.find(" b/");
            currentFile = (sep != std::string::npos) ? rest.substr(0, sep) : std::string();
            continue;
        }
        std::smatch m;
        if (!currentFile.empty() && std::regex_search(line, m, kHunkRe)) {
            const int start = std::stoi(m[1].str());
            const int count = m[2].matched ? std::stoi(m[2].str()) : 1;
            if (count > 0)
                result[currentFile].push_back({ start, count });
        }
    }
    return result;
}

// Scans one file's already-fetched content for Qt class names, restricted
// to classes whose declaration/definition overlaps changedRanges, out of
// process (see kScanTimeoutMs): writes content to a throwaway temp file,
// re-invokes this same qtdiff binary with a hidden internal flag that
// reads that file, filters by the given line ranges, and prints the
// result, hard-killing it if it doesn't finish in time. A crash or timeout
// is reported to stderr and treated as "no classes found for this file"
// rather than aborting the run.
std::vector<std::string> scanFileInSubprocess(const std::string &selfExe,
                                              const std::string &relPath,
                                              const std::string &content,
                                              bool isHeader,
                                              const std::vector<std::pair<int, int>> &changedRanges)
{
    static int counter = 0;
    const auto nowNs = std::chrono::steady_clock::now().time_since_epoch().count();
    std::error_code ec;
    const fs::path tmpFile = fs::temp_directory_path(ec)
            / ("qtdiff-scan-" + std::to_string(nowNs)
               + "-" + std::to_string(counter++)
               + (isHeader ? ".h" : ".cpp"));

    {
        std::ofstream out(tmpFile, std::ios::binary);
        out << content;
    }

    std::vector<std::string> argv = { selfExe,
                                      isHeader ? "--internal-scan-header" : "--internal-scan-source",
                                      tmpFile.string() };
    for (const auto &range : changedRanges)
        argv.push_back(std::to_string(range.first) + "," + std::to_string(range.second));

    ScanResult scan = spawnCapture(argv, kScanTimeoutMs);

    fs::remove(tmpFile, ec);

    if (!scan.ok) {
        std::cerr << "qtdiff: " << relPath
                  << (scan.timedOut ? ": scan timed out — skipping" : ": scan crashed — skipping")
                  << "\n";
        return { };
    }
    return splitLines(scan.output);
}

// Diffs a single git repository's local HEAD against its resolved remote
// HEAD and returns the Qt classes touched by that diff.
RepoResult processRepo(const fs::path &repo, const std::string &selfExe,
                        const std::string &branchOverride)
{
    RepoResult result;

    if (runGit({ "rev-parse", "--is-inside-work-tree" }, repo).exitCode != 0) {
        result.error = "not inside a git repository";
        return result;
    }

    const std::string topLevel = trim(runGit({ "rev-parse", "--show-toplevel" }, repo).output);
    if (topLevel.empty()) {
        result.error = "could not determine repository root";
        return result;
    }
    const fs::path repoRoot = topLevel;

    RemoteHeadResult remoteHead = resolveRemoteHead(repoRoot, branchOverride);
    if (!remoteHead.ok) {
        result.error = remoteHead.error;
        return result;
    }

    auto diffResult = runGit({ "diff", "--name-only", "HEAD", remoteHead.ref }, repoRoot);
    if (diffResult.exitCode != 0) {
        result.error = "'git diff' against " + remoteHead.ref + " failed";
        return result;
    }

    const auto lineRanges = changedLineRanges(repoRoot, remoteHead.ref);

    for (const auto &relPath : splitLines(diffResult.output)) {
        const fs::path ext = fs::path(relPath).extension();
        const bool isHeader = (ext == ".h" || ext == ".hpp");
        const bool isSource = (ext == ".cpp" || ext == ".cc" || ext == ".cxx");
        if (!isHeader && !isSource)
            continue;

        auto showResult = runGit({ "show", "HEAD:" + relPath }, repoRoot);
        if (showResult.exitCode != 0)
            continue; // deleted at HEAD relative to remote HEAD — nothing to attribute

        static const std::vector<std::pair<int, int>> kNoRanges;
        const auto rangesIt = lineRanges.find(relPath);
        const auto &ranges = (rangesIt != lineRanges.end()) ? rangesIt->second : kNoRanges;

        for (auto &name : scanFileInSubprocess(selfExe, relPath, showResult.output, isHeader,
                                                ranges))
            result.classes.insert(std::move(name));
    }

    result.ok = true;
    return result;
}

// Returns the submodule paths declared in repoRoot/.gitmodules (relative to
// repoRoot), via git's own config parser — not text scraping — so quoting
// and formatting edge cases in .gitmodules are handled correctly.
std::vector<std::string> submodulePaths(const fs::path &repoRoot)
{
    std::vector<std::string> paths;
    if (!fs::exists(repoRoot / ".gitmodules"))
        return paths;

    auto listResult = runGit({ "config", "-f", ".gitmodules", "--get-regexp", "\\.path$" },
                              repoRoot);
    for (const auto &line : splitLines(listResult.output)) {
        const size_t sp = line.find(' ');
        if (sp != std::string::npos)
            paths.push_back(line.substr(sp + 1));
    }
    return paths;
}

// Resolves the absolute path to this same running qtdiff binary, so
// scanFileInSubprocess() can re-invoke the exact program that is currently
// running rather than guessing. argv[0] alone is not reliable for this: for
// the common case of an installed CLI tool invoked by bare name (just
// "qtdiff", found via $PATH by the shell), fs::absolute(argv[0]) silently
// resolves it against the *current working directory* instead — producing
// a path that doesn't exist, so every re-exec fails and every file's scan
// is misreported as crashed.
std::string resolveSelfExe(const char *argv0)
{
#ifdef _WIN32
    char buf[MAX_PATH];
    DWORD n = GetModuleFileNameA(nullptr, buf, sizeof(buf));
    if (n > 0 && n < sizeof(buf))
        return std::string(buf, n);
#elif defined(__linux__)
    std::error_code ec;
    fs::path self = fs::read_symlink("/proc/self/exe", ec);
    if (!ec && !self.empty())
        return self.string();
#endif

    // Fallback (macOS, or if the platform-specific lookup above failed): if
    // argv0 contains a path separator, exec() semantics already resolved it
    // relative to cwd or as an absolute path — fs::absolute() is correct.
    // Otherwise it was found via a $PATH search when this process was
    // launched; search PATH ourselves so the re-exec uses that same binary.
    const std::string argv0Str(argv0);
    if (argv0Str.find('/') != std::string::npos || argv0Str.find('\\') != std::string::npos) {
        std::error_code ec;
        return fs::absolute(argv0Str, ec).string();
    }

    if (const char *pathEnv = std::getenv("PATH")) {
        std::istringstream iss(pathEnv);
        std::string dir;
        while (std::getline(iss, dir, ':')) {
            std::error_code ec;
            fs::path candidate = fs::path(dir) / argv0Str;
            if (fs::exists(candidate, ec))
                return candidate.string();
        }
    }
    return argv0Str; // last resort — spawnCapture will just fail cleanly
}

} // namespace

int main(int argc, char *argv[])
{
    // Hidden internal mode: re-invoked by scanFileInSubprocess() on this
    // same binary to run the class-name scan for one file out of process
    // (see kScanTimeoutMs) — never invoked directly by a user. Reads the
    // given file, computes each class's declaration/definition span, keeps
    // only the ones overlapping at least one "start,count" changed-line
    // range given as the remaining arguments, and prints the resulting
    // distinct class names, one per line. No range arguments at all means
    // no class in this file has any of its own lines different from
    // HEAD (see the note on overlapsAnyRange below) — correctly prints
    // nothing, not "everything".
    if (argc >= 3
        && (std::string(argv[1]) == "--internal-scan-header"
            || std::string(argv[1]) == "--internal-scan-source")) {
        const bool isHeader = std::string(argv[1]) == "--internal-scan-header";
        std::ifstream f(argv[2], std::ios::binary);
        std::ostringstream ss;
        ss << f.rdbuf();
        const std::string content = ss.str();

        std::vector<std::pair<int, int>> ranges;
        for (int i = 3; i < argc; ++i) {
            const std::string tok = argv[i];
            const size_t comma = tok.find(',');
            if (comma != std::string::npos)
                ranges.push_back({ std::atoi(tok.substr(0, comma).c_str()),
                                    std::atoi(tok.substr(comma + 1).c_str()) });
        }

        // Note: an empty ranges list is not "no filtering requested" — it
        // means the diff for this file consisted entirely of hunks with
        // zero HEAD-side lines (e.g. the remote side merely *added* an
        // #ifdef guard around code that already exists, unchanged, in
        // HEAD — see qlabel.cpp's "@@ -193,0 +194 @@" style hunks). In
        // that case correctly no class in this file has any of its own
        // lines different from HEAD, so nothing should match.
        const auto overlapsAnyRange = [&](int startLine, int endLine) {
            for (const auto &r : ranges) {
                const int rangeStart = r.first;
                const int rangeEnd = r.first + r.second - 1;
                if (startLine <= rangeEnd && endLine >= rangeStart)
                    return true;
            }
            return false;
        };

        const std::vector<QtFuzz::ClassSpan> spans = isHeader
                ? QtFuzz::classDeclarationSpansIn(content)
                : QtFuzz::classDefinitionSpansIn(content);

        std::set<std::string> matched;
        for (const auto &span : spans) {
            if (overlapsAnyRange(span.startLine, span.endLine))
                matched.insert(span.className);
        }
        for (const auto &name : matched)
            std::cout << name << "\n";
        return 0;
    }

    fs::path repo = fs::current_path();
    std::string branchOverride;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--help" || a == "-h") {
            usage(argv[0]);
            return 0;
        } else if (a == "--repo" && i + 1 < argc) {
            repo = argv[++i];
        } else if (a == "--branch" && i + 1 < argc) {
            branchOverride = argv[++i];
        } else {
            std::cerr << "qtdiff: unknown argument: " << a << "\n";
            usage(argv[0]);
            return 1;
        }
    }

    const std::string selfExe = resolveSelfExe(argv[0]);

    if (runGit({ "rev-parse", "--is-inside-work-tree" }, repo).exitCode != 0) {
        std::cerr << "qtdiff: not inside a git repository\n";
        return 1;
    }

    const std::string topLevel = trim(runGit({ "rev-parse", "--show-toplevel" }, repo).output);
    if (topLevel.empty()) {
        std::cerr << "qtdiff: could not determine repository root\n";
        return 1;
    }
    const fs::path repoRoot = topLevel;

    const std::vector<std::string> submodules = submodulePaths(repoRoot);

    bool anySucceeded = false;
    bool printedAny = false;

    // Always scan the target's own diff — a repo can have real Qt sources
    // of its own *and* an incidental submodule (e.g. qtdeclarative has its
    // own huge QML/Quick source tree plus a nested ecmascript test-data
    // submodule; qtwebengine has its own Qt-facing API plus the vendored
    // Chromium submodule) — one is never a substitute for the other.
    RepoResult own = processRepo(repoRoot, selfExe, branchOverride);
    if (own.ok) {
        anySucceeded = true;
        for (const auto &name : own.classes) {
            std::cout << name << "\n";
            printedAny = true;
        }
    } else if (submodules.empty()) {
        std::cerr << "qtdiff: " << own.error << "\n";
        return 1;
    }
    // else: the target itself isn't cleanly diffable as a whole (e.g. a
    // pure gitlink superproject with no meaningful branch of its own), but
    // it may still have real submodules worth diffing below.

    for (const auto &sub : submodules) {
        const fs::path subPath = repoRoot / sub;
        if (!fs::exists(subPath / ".git")) {
            std::cerr << "qtdiff: " << sub << ": submodule not initialized — skipping\n";
            continue;
        }
        RepoResult result = processRepo(subPath, selfExe, branchOverride);
        if (!result.ok) {
            std::cerr << "qtdiff: " << sub << ": " << result.error << "\n";
            continue;
        }
        anySucceeded = true;
        for (const auto &name : result.classes) {
            std::cout << sub << ": " << name << "\n";
            printedAny = true;
        }
    }

    if (!anySucceeded) {
        std::cerr << "qtdiff: no repositories could be diffed\n";
        return 1;
    }
    if (!printedAny)
        std::cout << "No Qt classes changed.\n";

    return 0;
}
