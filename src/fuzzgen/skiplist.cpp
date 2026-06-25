// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include "include/skiplist.h"

#include <fstream>
#include <sstream>

namespace QtFuzz {

static bool tagMatchesCurrentPlatform(const std::string &tag)
{
    if (tag == "All")
        return true;
#if defined(_WIN32) || defined(_WIN64)
    return tag == "Windows" || tag == "Windows11";
#elif defined(__APPLE__)
    return tag == "macOS" || tag == "mac";
#elif defined(__ANDROID__)
    return tag == "Android";
#elif defined(__EMSCRIPTEN__)
    return tag == "WASM";
#elif defined(__linux__)
    return tag == "Linux";
#else
    return false;
#endif
}

static void parseInto(const fs::path &path, std::unordered_set<std::string> &skippedClasses,
                      std::unordered_set<std::string> &skippedFunctions,
                      std::unordered_set<std::string> &crashFunctions)
{
    if (path.empty())
        return;

    std::ifstream file(path);
    if (!file)
        return;

    bool sectionSeen = false;
    bool applies = false;

    std::string line;
    while (std::getline(file, line)) {
        const auto commentPos = line.find('#');
        if (commentPos != std::string::npos)
            line.resize(commentPos);

        const auto first = line.find_first_not_of(" \t\r\n");
        if (first == std::string::npos)
            continue;
        const auto last = line.find_last_not_of(" \t\r\n");
        line = line.substr(first, last - first + 1);

        if (line.empty())
            continue;

        if (line.front() == '[' && line.back() == ']') {
            std::string tag = line.substr(1, line.size() - 2);
            const auto tf = tag.find_first_not_of(" \t");
            if (tf == std::string::npos) {
                sectionSeen = false;
                applies = false;
            } else {
                const auto tl = tag.find_last_not_of(" \t");
                tag = tag.substr(tf, tl - tf + 1);
                sectionSeen = true;
                applies = tagMatchesCurrentPlatform(tag);
            }
            continue;
        }

        if (!sectionSeen || !applies)
            continue;

        std::string target, action;
        std::istringstream ss(line);
        if (!(ss >> target >> action))
            continue;

        const bool isFunction = target.find("::") != std::string::npos;

        if (action == "skip") {
            if (isFunction)
                skippedFunctions.insert(target);
            else
                skippedClasses.insert(target);
        } else if (action == "expectCrash") {
            if (isFunction)
                crashFunctions.insert(target);
        }
    }
}

SkipList::SkipList(const fs::path &path)
{
    parseInto(path, m_skippedClasses, m_skippedFunctions, m_crashFunctions);
}

void SkipList::load(const fs::path &path)
{
    parseInto(path, m_skippedClasses, m_skippedFunctions, m_crashFunctions);
}

bool SkipList::isClassSkipped(const std::string &className) const
{
    return m_skippedClasses.count(className) > 0;
}

bool SkipList::isFunctionSkipped(const std::string &className,
                                 const std::string &functionName) const
{
    return m_skippedFunctions.count(className + "::" + functionName) > 0;
}

bool SkipList::expectsCrash(const std::string &className, const std::string &functionName) const
{
    return m_crashFunctions.count(className + "::" + functionName) > 0;
}

} // namespace QtFuzz
