# Qt Help Files and HTML Output

## Qt Help Files (.qhp and .qch)

### File Formats

| Format | Purpose |
|--------|---------|
| **.qhp** | Qt Help Project - XML defining structure, TOC, keywords |
| **.qch** | Qt Compressed Help - Compiled binary with HTML + index |
| **.qhc** | Qt Help Collection - Container for multiple .qch files |

### Workflow

```
Source Files → QDoc → HTML + .qhp
                         ↓
                   qhelpgenerator
                         ↓
                       .qch
                         ↓
              Qt Assistant / QHelpEngine
```

### QHP Configuration

```qdocconf
qhp.projects = QtCore

qhp.QtCore.file = qtcore.qhp
qhp.QtCore.namespace = org.qt-project.qtcore.$QT_VERSION_TAG
qhp.QtCore.virtualFolder = qtcore
qhp.QtCore.indexTitle = Qt Core
qhp.QtCore.indexRoot =

# Subprojects (TOC sections)
qhp.QtCore.subprojects = classes qmltypes examples

qhp.QtCore.subprojects.classes.title = C++ Classes
qhp.QtCore.subprojects.classes.indexTitle = Qt Core C++ Classes
qhp.QtCore.subprojects.classes.selectors = class headerfile
qhp.QtCore.subprojects.classes.sortPages = true
```

### Selector Types

| Selector | Matches |
|----------|---------|
| `class` | C++ classes |
| `namespace` | Namespaces |
| `qmltype` | QML types |
| `module` | Module pages |
| `module:QtCore` | Specific module |
| `doc:example` | Example pages |
| `doc:page` | Documentation pages |
| `group:painting` | Specific group |

### Compilation

```bash
qhelpgenerator qtcore.qhp -o qtcore.qch
qhelpgenerator qt.qhcp -o qt.qhc
```

---

## HTML Output Configuration

### Core Variables

```qdocconf
outputdir = ./html
outputformats = HTML
HTML.outputsubdir = qtcore
HTML.nosubdirs = false
```

### Styling

```qdocconf
HTML.stylesheets = style/style.css \
                   style/custom.css
HTML.style = "h1 { color: #333; }"
```

### Page Structure

```qdocconf
HTML.postheader = "<div class=\"header\">...</div>"
HTML.footer = "<div class=\"footer\">Copyright Qt Company</div>"
HTML.tocdepth = 3
```

### File Naming

```qdocconf
outputprefixes = QML
outputprefixes.QML = qml-
outputsuffixes.QML = -qmltype
```

Result: `Rectangle` QML type → `qml-rectangle-qmltype.html`
