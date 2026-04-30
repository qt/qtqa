# Qt Doc-Snapshots Product Inventory

Verified 2026-04-14 against doc-snapshots.qt.io.

## Reading This Table

- **Snapshot path**: URL suffix at `https://doc-snapshots.qt.io/{path}/`
- **Index file**: `{filename}.index` at the snapshot root. ✓ = confirmed 200, ✗ = 404
- **Link mechanism**: How this product links to Qt Reference docs
- **Repo**: For shallow-clone verification

---

## Qt Framework

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Qt 6 dev | `qt6-dev/` | `qtdoc.index`, `qtbase.index`, etc. | Source of truth | qt/qt5 |
| Qt 6.11 | `qt6-6.11/` | same | Source | qt/qt5 |
| Qt 6.10 | `qt6-6.10/` | same | Source | qt/qt5 |
| Qt 6.8 (LTS) | `qt6-6.8/` | same | Source | qt/qt5 |
| Qt 6.5 (LTS) | `qt6-6.5/` | same | Source | qt/qt5 |

---

## Design & Development Tools

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Qt Creator (master) | `qtcreator-master/` | ✓ `qtcreator.index` | QDoc `depends` → index | qt-creator/qt-creator |
| Qt Creator 19.0 | `qtcreator-19.0/` | ✓ `qtcreator.index` | QDoc `depends` → index | qt-creator/qt-creator |
| Qt Creator 18.0 | `qtcreator-18.0/` | ✓ `qtcreator.index` | QDoc `depends` → index | qt-creator/qt-creator |
| Extending Qt Creator | `qtcreator-extending/` | check | QDoc `depends` → index | qt-creator/qt-creator |
| Qt Design Studio | `qtdesignstudio/` | ✓ `qtdesignstudio.index` | QDoc `depends` → index | qt-design-studio |
| Figma to Qt | `figmatoqt/` | check | QDoc | qt-design-studio |
| VS Tools | `vstools-dev/` | check | QDoc | qt-vstools |
| VS Code Extension | `vscodeext-dev/` | check | QDoc | qt-labs/qt-vscode-extension |

**Key pages to HTML-search in Creator:**
- `qtcreator-index.html`, `qtcreator-toc.html`, `creator-overview.html`
- `creator-supported-platforms.html`, `creator-getting-started.html`

**Key pages to HTML-search in Design Studio:**
- `studio-toc.html`, `studio-overview.html`, `studio-supported-platforms.html`

---

## Qt for Python

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Qt for Python (dev) | `qtforpython-dev/` | ✗ none published | Sphinx + HTML URLs | pyside/pyside-setup |
| Qt for Python 6.10 | `qtforpython-6.10/` | ✗ none | Sphinx + HTML URLs | pyside/pyside-setup |
| Qt for Python 6.8 | `qtforpython-6.8/` | ✗ none | Sphinx + HTML URLs | pyside/pyside-setup |
| Qt for Python 6.5 | `qtforpython-6.5/` | ✗ none | Sphinx + HTML URLs | pyside/pyside-setup |

**Important:** Qt for Python auto-generates overview pages from qtdoc source. The page
`qtforpython-6/overviews/qtdoc-{filename}.html` mirrors the qtdoc `\page` filename.
A filename rename in qtdoc (`\page topics-foo.html` → `\page bar.html`) renames the
corresponding PySide page from `qtdoc-topics-foo.html` to `qtdoc-bar.html`.

To check: search `doc-snapshots.qt.io/qtforpython-dev/` for links to the old filename,
or clone `pyside-setup` and grep `sources/pyside6/doc/`.

---

## Embedded / Device Creation

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Boot to Qt (dev) | `boot2qt-dev/` | ✗ none published | QDoc `depends` → index | qt/qtdevicecreation |
| Boot to Qt 6.11 | `boot2qt-6.11/` | check | QDoc `depends` → index | qt/qtdevicecreation |
| Boot to Qt 6.10 | `boot2qt-6.10/` | check | QDoc `depends` → index | qt/qtdevicecreation |
| Boot to Qt 6.8 | `boot2qt-6.8/` | check | QDoc `depends` → index | qt/qtdevicecreation |
| Boot to Qt 6.5 | `boot2qt-6.5/` | check | QDoc `depends` → index | qt/qtdevicecreation |
| Qt for MCUs (dev) | `qtformcus-dev/` | ✗ none published | QDoc `depends` → index | qt/qtquickultralite |
| Qt for MCUs 2.12 | `qtformcus-2.12/` | check | QDoc `depends` → index | qt/qtquickultralite |
| Qt for MCUs 2.11 | `qtformcus-2.11/` | check | QDoc `depends` → index | qt/qtquickultralite |
| Qt VNC Server | `qtvncserver/` | check | QDoc | qt/qtvncserver |
| Qt Onboard | `qtonboard-dev/` | check | QDoc | — |

**Note:** Boot to Qt and Qt for MCUs do not publish `.index` files to doc-snapshots.
Verification requires HTML search or repo clone.

---

## Automotive

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Qt Android Automotive | `qtandroidautomotive/` | ✓ `qtandroidautomotive.index` | QDoc `depends` → index | qt/qtandroidautomotive |
| Qt Android Automotive 6.11 | `qtandroidautomotive-6.11/` | check | QDoc `depends` → index | — |
| Qt Android Automotive 6.10 | `qtandroidautomotive-6.10/` | check | QDoc `depends` → index | — |
| Qt Android Automotive 6.8 | `qtandroidautomotive-6.8/` | check | QDoc `depends` → index | — |

**Note:** Qt Automotive Suite (`qtautomotive-dev`) is not currently listed on doc-snapshots
landing page. Check for new paths or use repo clone for verification.

---

## Safety-Critical

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Qt Safe Renderer (dev) | `qtsaferenderer-dev/` | check | QDoc | qt/qtsaferenderer |
| Qt Safe Renderer 2.2 | `qtsaferenderer-2.2/` | check | QDoc | qt/qtsaferenderer |

---

## Installer & Build Tools

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Qt Installer Framework | `qtifw-dev/` | check | QDoc | qt-installer-framework |
| Qt Gradle Plugin | `qtgradleplugin-dev/` | check | QDoc | qt-labs/qtgradleplugin |
| Qt Gradle Plugin 1.4 | `qtgradleplugin-1.4/` | check | QDoc | — |
| Qt Tools for Android | `qttoolsforandroid-dev/` | check | QDoc | — |
| Qt Tools for Android 4.1 | `qttoolsforandroid-4.1/` | check | QDoc | — |

---

## Integrations & Bridges

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Qt Bridges | `qtbridges-dev/` | check | QDoc | — |

---

## Quality Assurance (Froglogic)

| Product | Snapshot path | Index file | Link mechanism | Repo |
|---------|--------------|-----------|----------------|------|
| Squish | `squish-master/` | check | Custom (not QDoc) | froglogic/squish |

**Note:** Squish, Coco, and GammaRay use Froglogic's own doc system, not QDoc.
They do not cross-link into Qt Reference docs. Safe to mark as Not affected for
any Qt Reference change.

---

## Products NOT on doc-snapshots (check doc.qt.io instead)

These are published directly to production and have no snapshot equivalent:

| Product | URL | Notes |
|---------|-----|-------|
| Qt Insight | `doc.qt.io/qtinsight/` | Analytics product |
| Qt Application Manager | `doc.qt.io/QtApplicationManager/` | — |
| Qt Interface Framework | `doc.qt.io/QtInterfaceFramework/` | — |

---

## Index File Check Command

To bulk-check whether index files exist for any product:

```bash
for path in qtcreator-master/qtcreator qtdesignstudio/qtdesignstudio \
            boot2qt-dev/boot2qt qtformcus-dev/qtformcus \
            qtandroidautomotive/qtandroidautomotive qtsaferenderer-dev/qtsaferenderer \
            qtifw-dev/installerfw qtbridges-dev/qtbridges; do
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://doc-snapshots.qt.io/${path}.index")
  echo "$status  $path"
done
```

## Grep Command Template

Once an index file is confirmed to exist:

```bash
# Search for old title or filename in a product's index
curl -s "https://doc-snapshots.qt.io/{path}/{module}.index" \
  | grep -i "Old Title\|old-filename\|old-anchor"

# Search published HTML (outgoing links)
curl -s "https://doc-snapshots.qt.io/{path}/index.html" \
  | grep -i "Old Title\|old-filename"
```
