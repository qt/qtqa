# Framework Tree Configuration Reference

**Verified against:** `qtdoc/doc/config/style/tree_config.xml` (dev,
2026-08) and its qtdoc git history.

## Scope

`qtdoc/doc/config/style/tree_config.xml` holds the root structure of
the **Qt Framework** documentation — not Qt Creator, Qt Design Studio,
or other doc projects, which have their own trees. It specifies how
each module's tree (see `references/qhp-subprojects.md`) is merged into
the single tree visible on the website. It is shipped to the output via
`HTML.stylesheets += style/tree_config.xml` in
`qtdoc/doc/config/qtdoc.qdocconf`.

**The file's trailing comment block is the authoritative format
documentation** — read it when in doubt; the summary below mirrors it.

## Node Format

Two node kinds:

**Folder node** — a collapsible entry, optionally with its own page:

| Attribute | Meaning |
|-----------|---------|
| `title` | Name of a virtual folder. Alone, gives a collapsible node that stores other nodes |
| `href` | Topic assigned to the folder; opens when the node opens. The topic **must already be in the tree** — its module must be included before this node |

**Module attachment** — inserts a module's tree:

| Attribute | Meaning |
|-----------|---------|
| `toc` (required) | Module name (e.g. `qtdoc`, `qtquick`) whose TOC is inserted; the module's TOC is defined in its `<projectname>-toc.qdoc` file |
| `childrenonly` (optional) | `false` (default): insert the whole TOC, root topic and children. `true`: insert only the children, no root node |
| `parent_url` (optional) | Append the TOC as a child of the node with the specified topic |

The topmost `<node title="Docs">` is a folder that is not displayed
anywhere — never change it.

## Live Structure (excerpt)

```xml
<node title="Docs">
    <node toc="qtdoc" childrenonly="true"/>
    <node toc="qtcore"/>
    <node toc="qtdbus" parent_url="ipc-overview.html"/>
    <node toc="qtqml"/>
    <node toc="qtqmlmodels" parent_url="qtqml-index.html"/>
    <node toc="qtquick"/>
    <node toc="qtquickcontrols" parent_url="qtquick-index.html"/>
    <node title="Modules" href="qt-additional-modules.html">
        <node toc="qtbluetooth"/>
        <node toc="qtspatialaudio"/>
        ...
    </node>
    <node title="Tools and utilities" href="qt-tools-utilities.html">
        <node toc="qdoc"/>
        ...
    </node>
</node>
```

Patterns to copy:

- `toc="qtdoc" childrenonly="true"` — the framework root topics appear
  at the top level without a wrapping "QtDoc" node.
- `parent_url="qtqml-index.html"` — satellite modules (Qt QML Models,
  Qt Quick Controls, …) are grafted under their parent module's landing
  page instead of the top level.
- Essential modules sit directly under the root; add-ons go inside the
  `Modules` folder node; tools inside `Tools and utilities`.

## Adding a New Module

Adding a module's docs requires edits in **two repositories**:

1. The module's own repo: qdocconf + landing/TOC pages (see SKILL.md
   Procedure B).
2. **qtdoc**: a `<node toc="<module>"/>` entry in `tree_config.xml`,
   placed in the right folder or grafted with `parent_url`.

There is no warning if step 2 is skipped — the module's tree simply
never appears on the website. Precedent commits in qtdoc:

- `c9624e14d` Doc: Add Qt Qml Design Support module to the TOC and the
  module list
- `cf4be71a2` Doc: Add the Qt Platform Integration module to the TOC
  tree
- `b7fc146ce` Doc: Add OpenAPI and CanvasPainter modules to the TOC
  tree

Such commits typically also add the module to the module lists in
`qtdoc/doc/src/qtmodules.qdoc`.

## Version History

- **v1.0** (2026-08-14): Initial version
