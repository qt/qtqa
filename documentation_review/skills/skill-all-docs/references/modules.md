# Qt Modules Reference

## Qt Essentials

Core modules required on all platforms:

| Module | `\inmodule` | Purpose |
|--------|-------------|---------|
| Qt Core | QtCore | Non-graphical classes used by other modules |
| Qt D-Bus | QtDBus | Inter-process communication (D-Bus protocol) |
| Qt GUI | QtGui | Base classes for graphical UI components |
| Qt Network | QtNetwork | Network programming utilities |
| Qt Qml | QtQml | QML and JavaScript language support |
| Qt Quick | QtQuick | Framework for dynamic custom UIs |
| Qt Quick Controls | QtQuickControls | Lightweight QML UI types |
| Qt Quick Dialogs | QtQuickDialogs | System dialog interaction |
| Qt Quick Layouts | QtQuickLayouts | Layout items for Qt Quick |
| Qt Quick Test | QtQuickTest | Unit testing for QML apps |
| Qt Test | QtTest | Unit testing for Qt C++ apps |
| Qt Widgets | QtWidgets | C++ widget classes extending Qt GUI |

---

## Qt Add-Ons

Specialized functionality modules:

| Module | `\inmodule` | Purpose |
|--------|-------------|---------|
| Qt 3D | Qt3D | 3D rendering framework |
| Qt Bluetooth | QtBluetooth | Bluetooth hardware access |
| Qt Charts | QtCharts | Chart/graph visualization |
| Qt Concurrent | QtConcurrent | Multi-threaded programming |
| Qt Graphs | QtGraphs | Modern graphing (replaces Charts) |
| Qt GRPC | QtGrpc | gRPC protocol support |
| Qt HTTP Server | QtHttpServer | HTTP server implementation |
| Qt Multimedia | QtMultimedia | Audio, video, camera support |
| Qt NFC | QtNfc | Near-field communication |
| Qt Network Auth | QtNetworkAuth | OAuth support |
| Qt OPC UA | QtOpcUa | OPC UA protocol |
| Qt OpenAPI | QtOpenAPI | OpenAPI client generation |
| Qt PDF | QtPdf | PDF document rendering |
| Qt Positioning | QtPositioning | Location/GPS data |
| Qt Remote Objects | QtRemoteObjects | IPC with replica objects |
| Qt SCXML | QtScxml | State machine support |
| Qt Sensors | QtSensors | Device sensor access |
| Qt Serial Bus | QtSerialBus | Serial bus protocols (CAN, Modbus) |
| Qt Serial Port | QtSerialPort | Serial port access |
| Qt Shader Tools | QtShaderTools | Shader compilation |
| Qt Speech | QtTextToSpeech | Text-to-speech |
| Qt SQL | QtSql | Database integration |
| Qt SVG | QtSvg | SVG rendering |
| Qt Web Channel | QtWebChannel | Qt to HTML/JavaScript bridge |
| Qt Web Engine | QtWebEngine | Chromium-based web embedding |
| Qt Web Sockets | QtWebSockets | WebSocket communication (RFC 6455) |
| Qt Web View | QtWebView | Native web view integration |

---

## Module Name Lookup

To find the correct `\inmodule` value:

1. Check the module's documentation page title
2. Remove spaces and "Qt" prefix variations
3. Use CamelCase: `Qt Widgets` → `QtWidgets`

**Common patterns:**
- Single word: `QtCore`, `QtGui`, `QtWidgets`
- Multi-word: `QtQuickControls`, `QtWebEngine`
- Protocols: `QtGrpc`, `QtOpcUa`, `QtMqtt`
