# Group and Organization Reference

**Verified against:** QDoc manual (doc.qt.io/qt-6), 145 `\group`
definitions across 108 files in qt5 super-repo.

## `\group` — Named Collection of Types

Creates a page listing entities that belong to the group.
Entities join via `\ingroup` in their doc comments.

### Syntax

```qdoc
/*!
    \group group-name
    \title Group Title
    \ingroup parent-group
    \brief One-line description.

    Optional body paragraph.

    \generatelist{related}
*/
```

### Mandatory companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\title` | Page heading | `Dialog Examples` |
| `\brief` | Summary for listings | `Examples of dialog usage.` |

### Common companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\ingroup` | Nest in parent group | `\ingroup all-examples` |
| `\generatelist{related}` | Auto-list group members | Usually at end |
| `\image` | Thumbnail for example groups | Common in example groups |

### Command ordering

The official example puts `\group` before `\title`. In the
codebase, some files reverse this (`\title` before `\group`).
QDoc accepts either order. Be consistent within a module.

---

## Group Patterns

### Example groups

Every module with examples defines a group:

```qdoc
/*!
    \group examples-dialogs
    \ingroup all-examples
    \title Dialog Examples
    \brief Using Qt's standard dialogs and building custom
           dialogs.
*/
```

Convention: `\ingroup all-examples` for top-level example groups.

### Hierarchical groups

Groups can nest via `\ingroup`:

```qdoc
/*!
    \group graphs_2D
    \title Qt Graphs C++ Classes for 2D
    \ingroup graphs
    \brief C++ classes for the Qt Graphs for 2D API.
*/
```

Here `graphs_2D` is a child of the `graphs` group.

### Functional groups

Group classes by function:

```qdoc
/*!
    \group network
    \title Network Programming API
    \brief Classes for network programming.
*/
```

Types join with `\ingroup network` in their `\class` docs.

---

## `\ingroup` — Group Membership

Adds the current entity to a named group.

### Syntax

```qdoc
\ingroup group-name
```

Can appear in any doc block (`\class`, `\qmltype`, `\page`,
`\module`, `\example`, etc.). An entity can belong to multiple
groups:

```qdoc
\ingroup modules
\ingroup frameworks-technologies
```

### Standard group names

| Group | Used by | Purpose |
|-------|---------|---------|
| `modules` | `\module` declarations | C++ module listing |
| `qmlmodules` | `\qmlmodule` declarations | QML module listing |
| `all-examples` | Example groups | Master example listing |
| `frameworks-technologies` | Module overviews | Technology listing |
| `funclists` | `\headerfile` docs | Function reference listing |

---

## `\generatelist` — Auto-Generated Lists

Generates a list of group members on the page.

### Syntax

```qdoc
\generatelist{related}
```

Other variants:
- `\generatelist{annotatedclasses}` — classes with briefs
- `\generatelist{classes}` — alphabetical class list
- `\generatelist{qmltypes}` — QML types
- `\generatelist{examples}` — examples

### With `\noautolist`

By default, `\module` and `\qmlmodule` pages auto-generate a
member list. Use `\noautolist` to suppress and control placement
with `\generatelist`:

```qdoc
/*!
    \module QtMultimedia
    \noautolist
    ...

    \section1 Namespaces
    \generatelist{classesbymodule QtMultimedia}
*/
```

---

## Output Filenames

| Command | Filename Pattern | Example |
|---------|-----------------|---------|
| `\group` | `{groupname}.html` (lowercase) | `animation.html` |
| `\module` | `{module}-module.html` | `qtcore-module.html` |
| `\qmlmodule` | `{module}-qmlmodule.html` | `qtquick-qmlmodule.html` |

---

## Version History

- **v1.0** (2026-03-26): Initial version from audit of 145
  `\group` definitions
