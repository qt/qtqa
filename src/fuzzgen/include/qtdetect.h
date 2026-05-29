#pragma once
// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// QtFuzz/qtdetect.h
// Helpers for locating an installed Qt6 instance.

#include <string>

namespace QtFuzz {

// Returns the Qt6 installation prefix, or an empty string if it cannot
// be determined.
//
// Detection order:
//   1. Qt6_DIR environment variable
//   2. `qmake -query QT_INSTALL_PREFIX`
//   3. Empty string (let CMake find it)
std::string detectQtPrefix();

} // namespace QtFuzz
