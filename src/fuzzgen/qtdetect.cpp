// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include "qtdetect.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>

namespace QtFuzz {

std::string detectQtPrefix()
{
    // 1. Check Qt6_DIR env var
    const char *qt6dir = std::getenv("Qt6_DIR");
    if (qt6dir && qt6dir[0] != '\0')
        return qt6dir;

    // 2. Ask qmake
#ifdef _WIN32
    FILE *p = _popen("qmake -query QT_INSTALL_PREFIX 2>nul", "r");
#else
    FILE *p = popen("qmake -query QT_INSTALL_PREFIX 2>/dev/null", "r");
#endif
    if (p) {
        char buf[512] = {};
        const bool gotData = (fgets(buf, sizeof(buf), p) != nullptr);
#ifdef _WIN32
        _pclose(p);
#else
        pclose(p);
#endif
        if (gotData) {
            std::string s(buf);
            // Trim trailing whitespace / newlines
            s.erase(std::find_if(s.rbegin(), s.rend(), [](unsigned char c) {
                        return !std::isspace(c);
                    }).base(),
                    s.end());
            if (!s.empty() && s != "**Unknown**")
                return s;
        }
    }

    return {}; // Let CMake find Qt itself
}

} // namespace QtFuzz
