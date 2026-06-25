#pragma once
// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// Parses a SKIPLIST file and answers queries about whether a class or
// function should be excluded from fuzz test generation.
//
// File format:
//   # comment
//   [Platform]                  -- section tag (All, Linux, Windows, MacOS, …)
//   ClassName skip              -- skip this class entirely
//   ClassName::method skip      -- skip this method
//   ClassName::method expectCrash -- known-crashing method; exclude from generation

#include <filesystem>
#include <string>
#include <unordered_set>

namespace fs = std::filesystem;

namespace QtFuzz {

class SkipList
{
public:
    SkipList() = default;
    explicit SkipList(const fs::path &path);

    // Load an additional skiplist file, merging its entries into this list.
    void load(const fs::path &path);

    // Returns true if no fuzzer should be generated for className.
    bool isClassSkipped(const std::string &className) const;

    // Returns true if functionName on className should be excluded from fuzzing.
    bool isFunctionSkipped(const std::string &className, const std::string &functionName) const;

    // Returns true if calling functionName on className is expected to crash.
    bool expectsCrash(const std::string &className, const std::string &functionName) const;

private:
    std::unordered_set<std::string> m_skippedClasses;
    std::unordered_set<std::string> m_skippedFunctions; // "Class::func"
    std::unordered_set<std::string> m_crashFunctions; // "Class::func"
};

} // namespace QtFuzz
