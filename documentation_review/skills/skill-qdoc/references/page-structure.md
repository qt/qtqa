# Page Structure Reference

**Verified against:** QDoc manual (doc.qt.io/qt-6), 991 `\page`,
532 `\example`, 1,236 `\externalpage`, and 393 navigation command
usages in qt5 super-repo.

## `\page` — Standalone Documentation Page

Creates a documentation page not tied to a C++ class or QML type.
Used for module overviews, guides, tutorials, and reference pages.

### Syntax

```qdoc
/*!
    \page filename.html
    \title Page Title
    \ingroup group-name
    \brief One-line description.

    Page content...
*/
```

**The `.html` extension is mandatory.** Every `\page` in the
codebase (991 files) includes `.html`. QDoc normalizes the
filename: non-alphanumeric sequences become hyphens, uppercase
becomes lowercase.

### Naming conventions (from codebase)

| Page Type | Pattern | Example |
|-----------|---------|---------|
| Module index | `{module}-index.html` | `qtgrpc-index.html` |
| TOC page | `{module}-toc.html` | `qtprotobuf-toc.html` |
| Migration guide | `{module}-changes-qt6.html` | `qtwebsockets-changes-qt6.html` |
| CMake command | `qt-{command}.html` | `qt-add-protobuf.html` |
| Feature page | `{module}-{feature}.html` | `activeqt-server.html` |

---

## Module Overview Page Template

The following is a guideline — actual modules vary. Some use
topic-specific sections; others follow this structure closely.
The only near-universal sections are "Using the Module" and
"Licenses and Attributions".

```qdoc
/*!
    \page modulename-index.html
    \title Module Name
    \ingroup frameworks-technologies

    \brief One-line module description.

    Introductory paragraph (2-4 sentences).

    \section1 Using the Module

    \section2 QML API

    The QML types of the module are available through the
    \c QML option in the \l{qt_add_protobuf} macro.

    To use the types, add the following import statement:
    \qml
    import ModuleName
    \endqml

    \section2 C++ API

    \include {module-use.qdocinc} {using the c++ api}

    \section3 Building with CMake

    \include {module-use.qdocinc} {building with cmake}
        {ComponentName}

    \section1 Reference
    \list
    \li \l{Module Name C++ Classes}
    \li \l{Module Name QML Types}
    \endlist

    \section1 Licenses and Attributions

    The Module Name module is available under commercial
    licenses from \l{The Qt Company}. In addition, it is
    available under free software licenses:
    ...
*/
```

**Variations seen in the codebase:**
- Qt Core uses topic-specific sections ("Threading and
  Concurrent Programming", "Input/Output") instead of
  "Articles and Guides"
- Some modules omit "Examples" as a separate section
- "Reference" is singular (not "References")
- Smaller modules may combine sections

---

## `\example` — Example Documentation

Documents a Qt example project.

### Syntax

```qdoc
/*!
    \example path/to/example
    \examplecategory {Category Name}
    \ingroup modulename-examples
    \title Example Title
    \brief Demonstrates how to use X with Y.
    \meta {tag} {tag1,tag2,tag3}

    Description of what the example shows.

    \include examples-run.qdocinc

    \section1 Implementation Details

    Walkthrough using \quotefromfile or \snippet...

    \section1 Source files

    \sa {Related Examples}, {Related Types}
*/
```

### Metadata commands

| Command | Purpose | Example |
|---------|---------|---------|
| `\examplecategory` | Category for filtering | `{Networking}`, `{Graphics}` |
| `\meta {tag}` | Search tags (braced key) | `\meta {tag} {widgets}` |
| `\meta tag` | Search tags (bare key) | `\meta tag {network,grpc}` |
| `\ingroup` | Group membership | `\ingroup qtgrpc-examples` |

### Discrepancy: `\meta tag` variations

Three formats coexist in the codebase:
- `\meta tag {network,protobuf,grpc}` — comma-separated, singular
- `\meta tags {quick, network, http}` — space-separated, plural
- `\meta {tag} {widgets}` — braced key

All three work. No single convention is universal. When writing
new examples, follow the pattern used by other examples in the
same module.

### Output filename

Generated from `\example` path:
`{module}-{path-with-hyphens}-example.html`

Example: `\example demos/thermostat` in qtdoc produces
`qtdoc-demos-thermostat-example.html`

---

## `\externalpage` — Named External URL

Assigns a title to an external URL for easy linking.

### Syntax

```qdoc
/*!
    \externalpage https://example.com/resource
    \title Resource Name
*/
```

Link to it with: `\l{Resource Name}`

### Convention

Most modules maintain a dedicated `external-resources.qdoc` file.
Global external sites live in
`qtbase/doc/global/externalsites/` (split by category).

### Anti-autolink pattern (undocumented officially)

```qdoc
/*!
    \externalpage nolink
    \title WebChannel
    \internal
*/
```

Prevents QDoc from auto-linking the word "WebChannel" to a
QML type. The `nolink` URL and `\internal` tag suppress the
link without generating a visible page.

---

## Page Order and Navigation

Page order (previous/next links, tree placement) comes from the
module's TOC page (`<module>-toc.qdoc`, named in
`navigation.toctitles`) — see `skill-toc-tree`. The legacy
`\previouspage`/`\nextpage`/`\startpage` commands are superseded:
the TOC mechanism overwrites their links on listed pages. Do not
add them to new documentation.

---

## Version History

- **v1.1** (2026-08-14): Navigation Commands section replaced by a
  pointer to skill-toc-tree; `\previouspage`/`\nextpage`/`\startpage`
  documented as legacy
- **v1.0** (2026-03-26): Initial version from audit of 991
  `\page`, 532 `\example`, 1,236 `\externalpage`, and 393
  navigation command usages
