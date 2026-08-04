// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// run_and_check — spawns a child process expected to crash, captures its
// combined stdout+stderr, and checks that a regex matches somewhere in it.
//
// CTest treats a subprocess that dies from a signal / structured exception
// as an automatic failure — PASS_REGULAR_EXPRESSION does not override that
// (confirmed empirically: it only overrides an ordinary nonzero exit code).
// Since crashdiag_test and the Tier-3 fixture deliberately crash by design,
// they can't be wired to CTest directly; this wrapper runs them, prints
// whatever they printed before dying, and itself always exits cleanly (0 if
// the expected text was found, 1 otherwise) — so CTest sees a normal
// process and PASS_REGULAR_EXPRESSION / a plain zero exit code works as
// expected.
//
// Usage: run_and_check <expected-regex> <program> [args...]

#include <cstdio>
#include <cstring>
#include <iostream>
#include <regex>
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

#ifdef _WIN32

static std::string runAndCapture(const std::string &exe, const std::vector<std::string> &args)
{
    SECURITY_ATTRIBUTES sa = { };
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE readPipe = nullptr, writePipe = nullptr;
    if (!CreatePipe(&readPipe, &writePipe, &sa, 0)) {
        std::cerr << "run_and_check: CreatePipe failed\n";
        return { };
    }
    SetHandleInformation(readPipe, HANDLE_FLAG_INHERIT, 0);

    std::string cmdLine = "\"" + exe + "\"";
    for (const auto &a : args)
        cmdLine += " \"" + a + "\"";

    STARTUPINFOA si = { };
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = writePipe;
    si.hStdError = writePipe;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    PROCESS_INFORMATION pi = { };
    const BOOL ok = CreateProcessA(nullptr, cmdLine.data(), nullptr, nullptr, TRUE, 0, nullptr,
                                   nullptr, &si, &pi);
    CloseHandle(writePipe);
    if (!ok) {
        std::cerr << "run_and_check: CreateProcess failed (error " << GetLastError() << ")\n";
        CloseHandle(readPipe);
        return { };
    }

    std::string output;
    char buf[4096];
    DWORD n = 0;
    while (ReadFile(readPipe, buf, sizeof(buf), &n, nullptr) && n > 0)
        output.append(buf, n);

    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(readPipe);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return output;
}

#else

static std::string runAndCapture(const std::string &exe, const std::vector<std::string> &args)
{
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        std::cerr << "run_and_check: pipe() failed\n";
        return { };
    }

    const pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "run_and_check: fork() failed\n";
        return { };
    }

    if (pid == 0) {
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[0]);
        close(pipefd[1]);

        std::vector<const char *> argv;
        argv.push_back(exe.c_str());
        for (const auto &a : args)
            argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execv(exe.c_str(), const_cast<char **>(argv.data()));
        _exit(127);
    }

    close(pipefd[1]);
    std::string output;
    char buf[4096];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf))) > 0)
        output.append(buf, static_cast<size_t>(n));
    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);
    return output;
}

#endif

int main(int argc, char *argv[])
{
    if (argc < 3) {
        std::cerr << "Usage: run_and_check <expected-regex> <program> [args...]\n";
        return 2;
    }

    const std::string pattern = argv[1];
    const std::string exe = argv[2];
    std::vector<std::string> args;
    for (int i = 3; i < argc; i++)
        args.push_back(argv[i]);

    const std::string output = runAndCapture(exe, args);
    std::cout << output;

    const std::regex re(pattern);
    if (std::regex_search(output, re)) {
        std::cout << "run_and_check: output matched: " << pattern << "\n";
        return 0;
    }

    std::cerr << "run_and_check: output did NOT match: " << pattern << "\n";
    return 1;
}
