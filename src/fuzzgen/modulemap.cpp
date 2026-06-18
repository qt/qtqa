// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include "modulemap.h"

#include <algorithm>
#include <functional>
#include <set>

namespace QtFuzz {

AppTypeInfo appTypeInfo(AppType t)
{
    switch (t) {
    case AppType::Core:
        return { "<QCoreApplication>", "QCoreApplication" };
    case AppType::Gui:
        return { "<QGuiApplication>", "QGuiApplication" };
    case AppType::Widgets:
        return { "<QApplication>", "QApplication" };
    case AppType::Quick:   return {}; // unused
    }
    return { "<QCoreApplication>", "QCoreApplication" }; // unreachable
}

const std::map<std::string, ModuleInfo> &moduleMap()
{
    // clang-format off
    //
    // Keys are the src/ sub-directory name inside the submodule repo.
    // The same map covers every Qt submodule: point --submodule at any
    // submodule root and the directory names found under its src/ tree
    // will be resolved here.
    //
    // Columns:
    //   key (src dir)  | component        | CMake target              | dependencies                                         | AppType
    //
    static const std::map<std::string, ModuleInfo> kMap = {

        // -----------------------------------------------------------------------
        // qtbase
        // -----------------------------------------------------------------------

        // Core-tier (QCoreApplication sufficient)
        { "corelib",           { "Core",              "Qt6::Core",              {},                                                       AppType::Core    } },
        { "network",           { "Network",           "Qt6::Network",           {"Core"},                                                 AppType::Core    } },
        { "sql",               { "Sql",               "Qt6::Sql",               {"Core"},                                                 AppType::Core    } },
        { "xml",               { "Xml",               "Qt6::Xml",               {"Core"},                                                 AppType::Core    } },
        { "concurrent",        { "Concurrent",        "Qt6::Concurrent",        {"Core"},                                                 AppType::Core    } },
        { "testlib",           { "Test",              "Qt6::Test",              {"Core"},                                                 AppType::Core    } },
        { "statemachine",      { "StateMachine",      "Qt6::StateMachine",      {"Core"},                                                 AppType::Core    } },
        { "scxml",             { "Scxml",             "Qt6::Scxml",             {"Core"},                                                 AppType::Core    } },
        { "remoteobjects",     { "RemoteObjects",     "Qt6::RemoteObjects",     {"Core", "Network"},                                      AppType::Core    } },
        { "serialport",        { "SerialPort",        "Qt6::SerialPort",        {"Core"},                                                 AppType::Core    } },
        { "serialbus",         { "SerialBus",         "Qt6::SerialBus",         {"Core"},                                                 AppType::Core    } },
        { "bluetooth",         { "Bluetooth",         "Qt6::Bluetooth",         {"Core"},                                                 AppType::Core    } },
        { "nfc",               { "Nfc",               "Qt6::Nfc",               {"Core"},                                                 AppType::Core    } },

        // Gui-tier (QGuiApplication required)
        { "dbus",              { "DBus",              "Qt6::DBus",              {"Core"},                                                 AppType::Core    } },
        { "gui",               { "Gui",               "Qt6::Gui",               {"Core"},                                                 AppType::Gui     } },
        { "opengl",            { "OpenGL",            "Qt6::OpenGL",            {"Core", "Gui"},                                          AppType::Gui     } },

        // Widgets-tier (QApplication required)
        { "widgets",           { "Widgets",           "Qt6::Widgets",           {"Core", "Gui"},                                          AppType::Widgets } },
        { "openglwidgets",     { "OpenGLWidgets",     "Qt6::OpenGLWidgets",     {"Core", "Gui", "Widgets", "OpenGL"},                     AppType::Widgets } },
        { "printsupport",      { "PrintSupport",      "Qt6::PrintSupport",      {"Core", "Gui", "Widgets"},                               AppType::Widgets } },

        // -----------------------------------------------------------------------
        // qtdeclarative  (src/qml, src/quick, src/quickcontrols, …)
        // -----------------------------------------------------------------------
        { "qml",               { "Qml",               "Qt6::Qml",               {"Core", "Network"},                                      AppType::Core    } },
        { "quick",             { "Quick",             "Qt6::Quick",             {"Core", "Gui", "Qml"},                                   AppType::Gui     } },
        { "quickcontrols",     { "QuickControls2",    "Qt6::QuickControls2",    {"Core", "Gui", "Quick"},                                 AppType::Gui     } },
        { "quickdialogs",      { "QuickDialogs2",     "Qt6::QuickDialogs2",     {"Core", "Gui", "Quick", "QuickControls2"},               AppType::Gui     } },
        { "quicklayouts",      { "QuickLayouts",      "Qt6::QuickLayouts",      {"Core", "Gui", "Quick"},                                 AppType::Gui     } },
        { "quickwidgets",      { "QuickWidgets",      "Qt6::QuickWidgets",      {"Core", "Gui", "Widgets", "Quick"},                      AppType::Widgets } },
        { "quickshapes",       { "QuickShapes",       "Qt6::QuickShapes",       {"Core", "Gui", "Quick"},                                 AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtsvg
        // -----------------------------------------------------------------------
        { "svg",               { "Svg",               "Qt6::Svg",               {"Core", "Gui"},                                          AppType::Gui     } },
        { "svgwidgets",        { "SvgWidgets",        "Qt6::SvgWidgets",        {"Core", "Gui", "Widgets", "Svg"},                        AppType::Widgets } },

        // -----------------------------------------------------------------------
        // qtmultimedia  (src/multimedia, src/multimediawidgets, src/spatialaudio)
        // -----------------------------------------------------------------------
        { "multimedia",        { "Multimedia",        "Qt6::Multimedia",        {"Core", "Gui"},                                          AppType::Gui     } },
        { "multimediawidgets", { "MultimediaWidgets", "Qt6::MultimediaWidgets", {"Core", "Gui", "Widgets", "Multimedia"},                 AppType::Widgets } },
        { "spatialaudio",      { "SpatialAudio",      "Qt6::SpatialAudio",      {"Core", "Gui", "Multimedia"},                            AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtsensors  (src/sensors, src/sensorsquick)
        // -----------------------------------------------------------------------
        { "sensors",           { "Sensors",           "Qt6::Sensors",           {"Core"},                                                 AppType::Gui     } },
        { "sensorsquick",      { "SensorsQuick",      "Qt6::SensorsQuick",      {"Core", "Qml", "Sensors"},                              AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtpositioning  (src/positioning, src/positioningquick)
        // -----------------------------------------------------------------------
        { "positioning",       { "Positioning",       "Qt6::Positioning",       {"Core"},                                                 AppType::Gui     } },
        { "positioningquick",  { "PositioningQuick",  "Qt6::PositioningQuick",  {"Core", "Qml", "Positioning"},                          AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtlocation  (Technical Preview — not deprecated in Qt 6)
        // -----------------------------------------------------------------------
        { "location",          { "Location",          "Qt6::Location",          {"Core", "Gui"},                                          AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtcharts
        // -----------------------------------------------------------------------
        { "charts",            { "Charts",            "Qt6::Charts",            {"Core", "Gui", "Widgets"},                               AppType::Widgets } },

        // -----------------------------------------------------------------------
        // qtdatavis3d  (src/datavisualization)
        // -----------------------------------------------------------------------
        { "datavisualization", { "DataVisualization", "Qt6::DataVisualization", {"Core", "Gui"},                                          AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtgraphs  (Qt 6.6+; src/graphs, or src/graphs2d + src/graphs3d)
        // -----------------------------------------------------------------------
        { "graphs",            { "Graphs",            "Qt6::Graphs",            {"Core", "Gui", "Quick"},                                 AppType::Gui     } },
        { "graphs2d",          { "Graphs",            "Qt6::Graphs",            {"Core", "Gui", "Quick"},                                 AppType::Gui     } },
        { "graphs3d",          { "Graphs",            "Qt6::Graphs",            {"Core", "Gui", "Quick"},                                 AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qt3d  (src/3dcore, src/3drender, src/3dinput, etc.)
        // -----------------------------------------------------------------------
        { "3d",                { "3DCore",            "Qt6::3DCore",            {"Core", "Gui"},                                          AppType::Gui     } },
        { "3dcore",            { "3DCore",            "Qt6::3DCore",            {"Core", "Gui"},                                          AppType::Gui     } },
        { "3drender",          { "3DRender",          "Qt6::3DRender",          {"Core", "Gui", "3DCore"},                                AppType::Gui     } },
        { "3dinput",           { "3DInput",           "Qt6::3DInput",           {"Core", "Gui", "3DCore"},                                AppType::Gui     } },
        { "3dlogic",           { "3DLogic",           "Qt6::3DLogic",           {"Core", "3DCore"},                                       AppType::Gui     } },
        { "3danimation",       { "3DAnimation",       "Qt6::3DAnimation",       {"Core", "Gui", "3DCore", "3DRender"},                    AppType::Gui     } },
        { "3dextras",          { "3DExtras",          "Qt6::3DExtras",          {"Core", "Gui", "3DCore", "3DRender", "3DInput", "3DAnimation"}, AppType::Gui } },
        { "3dquick",           { "3DQuick",           "Qt6::3DQuick",           {"Core", "Gui", "Quick", "3DCore"},                       AppType::Gui     } },
        { "3dquickrender",     { "3DQuickRender",     "Qt6::3DQuickRender",     {"Core", "Gui", "Quick", "3DCore", "3DRender"},           AppType::Gui     } },
        { "3dquickinput",      { "3DQuickInput",      "Qt6::3DQuickInput",      {"Core", "Gui", "Quick", "3DCore", "3DInput"},            AppType::Gui     } },
        { "3dquickanimation",  { "3DQuickAnimation",  "Qt6::3DQuickAnimation",  {"Core", "Gui", "Quick", "3DCore", "3DAnimation"},        AppType::Gui     } },
        { "3dquickextras",     { "3DQuickExtras",     "Qt6::3DQuickExtras",     {"Core", "Gui", "Quick", "3DCore", "3DExtras"},           AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtquick3d  (src/quick3d)
        // -----------------------------------------------------------------------
        { "quick3d",           { "Quick3D",           "Qt6::Quick3D",           {"Core", "Gui", "Quick"},                                 AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtquick3dphysics  (src/quick3dphysics)
        // -----------------------------------------------------------------------
        { "quick3dphysics",    { "Quick3DPhysics",    "Qt6::Quick3DPhysics",    {"Core", "Gui", "Quick", "Quick3D"},                      AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtwebengine  (src/core, src/webenginequick, src/webenginewidgets)
        // "webengine" kept for legacy compatibility; "core" maps to WebEngineCore
        // when scanning the qtwebengine submodule.
        // -----------------------------------------------------------------------
        { "webengine",         { "WebEngineCore",     "Qt6::WebEngineCore",     {"Core", "Gui", "Network"},                               AppType::Gui     } },
        { "core",              { "WebEngineCore",     "Qt6::WebEngineCore",     {"Core", "Gui", "Network"},                               AppType::Gui     } },
        { "webenginequick",    { "WebEngineQuick",    "Qt6::WebEngineQuick",    {"Core", "Gui", "Quick", "WebEngineCore"},                AppType::Gui     } },
        { "webenginewidgets",  { "WebEngineWidgets",  "Qt6::WebEngineWidgets",  {"Core", "Gui", "Widgets", "WebEngineCore"},              AppType::Widgets } },

        // -----------------------------------------------------------------------
        // qtwebchannel  (src/webchannel)
        // -----------------------------------------------------------------------
        { "webchannel",        { "WebChannel",        "Qt6::WebChannel",        {"Core"},                                                 AppType::Core    } },

        // -----------------------------------------------------------------------
        // qtwebsockets  (src/websockets)
        // -----------------------------------------------------------------------
        { "websockets",        { "WebSockets",        "Qt6::WebSockets",        {"Core", "Network"},                                      AppType::Core    } },

        // -----------------------------------------------------------------------
        // qtwebview  (src/webview)
        // -----------------------------------------------------------------------
        { "webview",           { "WebView",           "Qt6::WebView",           {"Core", "Gui"},                                          AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtnetworkauth  (src/oauth2)
        // -----------------------------------------------------------------------
        { "oauth2",            { "NetworkAuth",       "Qt6::NetworkAuth",       {"Core", "Network"},                                      AppType::Core    } },

        // -----------------------------------------------------------------------
        // qthttpserver  (src/httpserver)
        // -----------------------------------------------------------------------
        { "httpserver",        { "HttpServer",        "Qt6::HttpServer",        {"Core", "Network"},                                      AppType::Core    } },

        // -----------------------------------------------------------------------
        // qtlottie  (src/bodymovin)
        // -----------------------------------------------------------------------
        { "bodymovin",         { "Lottie",            "Qt6::Lottie",            {"Core", "Gui", "Quick"},                                 AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtpdf  (src/pdf, src/pdfwidgets)
        // -----------------------------------------------------------------------
        { "pdf",               { "Pdf",               "Qt6::Pdf",               {"Core", "Gui", "Network"},                               AppType::Gui     } },
        { "pdfwidgets",        { "PdfWidgets",        "Qt6::PdfWidgets",        {"Core", "Gui", "Widgets", "Pdf"},                        AppType::Widgets } },

        // -----------------------------------------------------------------------
        // qttexttospeech  (src/texttospeech)
        // -----------------------------------------------------------------------
        { "texttospeech",      { "TextToSpeech",      "Qt6::TextToSpeech",      {"Core"},                                                 AppType::Core    } },

        // -----------------------------------------------------------------------
        // qtvirtualkeyboard  (src/virtualkeyboard)
        // -----------------------------------------------------------------------
        { "virtualkeyboard",   { "VirtualKeyboard",   "Qt6::VirtualKeyboard",   {"Core", "Gui", "Quick"},                                 AppType::Gui     } },

        // -----------------------------------------------------------------------
        // qtscxml  (also in qtbase/src/scxml — same key, same info)
        // -----------------------------------------------------------------------
        // Already covered by "scxml" above.

        // -----------------------------------------------------------------------
        // qtstatemachine  (also in qtbase/src/statemachine — same key, same info)
        // -----------------------------------------------------------------------
        // Already covered by "statemachine" above.

        // -----------------------------------------------------------------------
        // qtremoteobjects  (also in qtbase/src/remoteobjects — same key, same info)
        // -----------------------------------------------------------------------
        // Already covered by "remoteobjects" above.

        // -----------------------------------------------------------------------
        // qtgrpc  (src/grpc, src/protobuf)
        // -----------------------------------------------------------------------
        { "grpc",              { "Grpc",              "Qt6::Grpc",              {"Core", "Network"},                                      AppType::Core    } },
        { "protobuf",          { "Protobuf",          "Qt6::Protobuf",          {"Core"},                                                 AppType::Core    } },

        // -----------------------------------------------------------------------
        // qtmqtt  (src/mqtt)
        // -----------------------------------------------------------------------
        { "mqtt",              { "Mqtt",              "Qt6::Mqtt",              {"Core", "Network"},                                      AppType::Core    } },

        // -----------------------------------------------------------------------
        // qtcoap  (src/coap)
        // -----------------------------------------------------------------------
        { "coap",              { "Coap",              "Qt6::Coap",              {"Core", "Network"},                                      AppType::Core    } },

        // -----------------------------------------------------------------------
        // qtopcua  (src/opcua)
        // -----------------------------------------------------------------------
        { "opcua",             { "OpcUa",             "Qt6::OpcUa",             {"Core"},                                                 AppType::Core    } },
    };
    // clang-format on
    return kMap;
}

const ModuleInfo *findModuleByDir(const std::string &srcDirName)
{
    std::string lower = srcDirName;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    auto it = moduleMap().find(lower);
    return it != moduleMap().end() ? &it->second : nullptr;
}

std::vector<std::string> resolveComponents(const ModuleInfo &mod)
{
    std::vector<std::string> ordered;
    std::set<std::string>    visited;

    std::function<void(const std::string &)> visit = [&](const std::string &comp) {
        if (!visited.insert(comp).second)
            return;
        for (const auto &[dir, info] : moduleMap()) {
            if (info.component == comp) {
                for (const auto &dep : info.dependencies)
                    visit(dep);
                break;
            }
        }
        ordered.push_back(comp);
    };

    for (const auto &dep : mod.dependencies)
        visit(dep);
    visit(mod.component);
    return ordered;
}

} // namespace QtFuzz
