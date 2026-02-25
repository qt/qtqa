# Qt Repository Structure

## qt5.git Super-Repo

```
qt5/                          # Super-repo root
├── cmake/                    # Build system configuration
├── coin/                     # CI/CD configuration
├── configure                 # Build configuration script
├── init-repository           # Submodule initialization
├── qtbase/                   # Core module (submodule)
├── qtdeclarative/            # QML/Quick module (submodule)
├── qttools/                  # Dev tools including QDoc (submodule)
├── qtdoc/                    # Cross-module documentation (submodule)
└── ... (50+ qt* submodules)
```

---

## Module Categories

| Category | Repositories |
|----------|--------------|
| **Core** | qtbase, qtdeclarative, qttools, qtdoc |
| **Graphics** | qt3d, qtquick3d, qtquick3dphysics, qtcharts, qtgraphs, qtdatavis3d, qtsvg, qtlottie |
| **Connectivity** | qtconnectivity, qtwebsockets, qtwebchannel, qtwebengine, qtwebview, qtnetworkauth |
| **Hardware** | qtsensors, qtserialport, qtserialbus, qtpositioning, qtlocation |
| **Protocols** | qtcoap, qtmqtt, qtopcua, qtopenapi, qtgrpc |
| **Multimedia** | qtmultimedia, qtspeech |
| **Platform** | qtwayland, qtvirtualkeyboard, qtshadertools |
| **Utilities** | qt5compat, qtimageformats, qttranslations, qtlanguageserver |
| **State/Logic** | qtscxml, qtremoteobjects, qttasktree, qtquicktimeline |
| **Internal** | qtqa, qtrepotools |

---

## Module Internal Structure

Example using qtbase:

```
qtbase/
├── src/                      # Source code
│   ├── corelib/              # Qt Core
│   ├── gui/                  # Qt GUI
│   ├── widgets/              # Qt Widgets
│   ├── network/              # Qt Network
│   ├── sql/                  # Qt SQL
│   ├── concurrent/           # Qt Concurrent
│   ├── dbus/                 # Qt D-Bus
│   ├── xml/                  # Qt XML
│   └── testlib/              # Qt Test
├── doc/                      # Generated docs output
├── examples/                 # Code examples
└── tests/                    # Unit tests
```

---

## Documentation Paths

| Path | Purpose |
|------|---------|
| `qttools/src/qdoc/` | QDoc tool source code |
| `qtbase/doc/` | Built documentation output (HTML + .qch) |
| `qtdoc/doc/` | Cross-module docs (getting started, overviews) |
| `<module>/src/**/*.qdoc` | Standalone doc files |
| `<module>/src/**/*.cpp` | Inline API documentation |

---

## Deprecated/Empty Modules

Placeholders from Qt 5 (no longer active):
- qtcanvas3d
- qtfeedback
- qtgamepad
- qtpim
- qtsystems
- qtwebglplugin
- qtxmlpatterns
