#pragma once
// Copyright (C) 2024 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
//
// QtFuzz/modulemap.h
// Mapping from qtbase/src sub-directory names to Qt6 CMake component metadata.

#include <map>
#include <string>
#include <vector>

namespace QtFuzz {

// ---------------------------------------------------------------------------
// AppType
//
// The Qt application object required to safely instantiate classes from a
// given module.
//
//   Core     -> QCoreApplication   (no display connection needed)
//   Gui      -> QGuiApplication    (needs a display / platform plugin)
//   Widgets  -> QApplication       (needs a display + widget subsystem)
//
// The enum is ordered: Widgets > Gui > Core, so the maximum of two modules'
// AppType is always the safe choice for both.
// ---------------------------------------------------------------------------
enum class AppType {
    Core = 0, // QCoreApplication  — QtCore, QtNetwork, QtSql, …
    Gui = 1, // QGuiApplication   — QtGui, QtDBus, QtOpenGL, …
    Widgets = 2, // QApplication      — QtWidgets, QtPrintSupport, …
    Quick = 3, // unused for now; QtQuick and QtQuickControls
};

// Human-readable include and class name for each AppType.
struct AppTypeInfo {
    const char *includeHeader; // e.g. "<QApplication>"
    const char *className;     // e.g. "QApplication"
};

// Returns the header/classname pair for t.
AppTypeInfo appTypeInfo(AppType t);

struct ModuleInfo {
    std::string component; // find_package component, e.g. "Widgets"
    std::string target; // CMake target, e.g. "Qt6::Widgets"
    std::vector<std::string> dependencies; // transitive component deps
    AppType appType; // minimum application object required
};

// Returns the canonical module map: src-dir-name -> ModuleInfo.
// The directory structure under qtbase/src/ is authoritative.
const std::map<std::string, ModuleInfo> &moduleMap();

// Look up module info by lower-cased src directory name.
// Returns nullptr if the directory is not in the map.
const ModuleInfo *findModuleByDir(const std::string &srcDirName);

// Look up module info by component name (case-insensitive).
// Returns nullptr if not found.
const ModuleInfo *findModuleByComponent(const std::string &componentName);

// Returns all components needed to link against mod (including its
// transitive dependencies), in dependency-first order.
std::vector<std::string> resolveComponents(const ModuleInfo &mod);

} // namespace QtFuzz
