---
name: skill-toc-tree
description: >
  Qt documentation topic tree (TOC, navigation sidebar) — how a module's
  tree is declared via qhp subprojects, how manually written pages attach
  to it through the module's *-toc.qdoc page, and how module trees merge
  into the Qt Framework website tree via tree_config.xml. Load this skill
  when adding a manually written page, creating module docs from scratch,
  diagnosing a page missing from the sidebar or QCH contents, fixing page
  order, a wrong breadcrumb parent, or missing previous/next links, adding
  a whole group of pages to the tree via \generatelist, resolving
  toctitles/indexTitle warnings, or auditing a module for orphan pages.
metadata:
  version: "1.0.0"
---

# Qt Documentation Topic Tree Reference

How Qt documentation pages become visible — and ordered — in the
navigation tree: the QCH contents in Qt Assistant/Qt Creator and the
sidebar on doc.qt.io.

## When to Use

- A new manually written page must appear in the tree
- Creating module documentation from scratch (new module)
- A page builds fine but is missing from the sidebar or QCH contents
- Pages appear in the wrong order or at the wrong nesting level
- Build log shows `Failed to find table of contents with title` or
  `Failed to find <P>.indexTitle`
- Auditing a module for orphan pages

## The Module Tree

A module's tree is declared by `qhp.<Module>.subprojects`. **Item order
is significant** — it is the order of the branches in the tree:

```
qhp.QtQuick.subprojects = manual examples qmltypes classes
```

puts the manually combined nodes first, then selector-generated
examples, then QML types, then the C++ API. Conventional branches —
modules use whichever subset applies:

| Branch | Subproject | Source of entries | Populated |
|--------|-----------|-------------------|-----------|
| Manual docs | `manual`, `type = manual` | `\list` on `<module>-toc.qdoc` | **by hand** |
| Examples | `examples`, `selectors = example` | `\example` nodes | automatic |
| C++ reference | `classes`, `selectors = class …` | `\class`/`\headerfile` | automatic |
| QML reference | `qmltypes`, `selectors = qmlclass` | `\qmltype` nodes | automatic |

**The rule this skill enforces:** selector-based branches are collected
automatically; manually written pages are not. A manually written page
is in the tree only if it is listed on `<module>-toc.qdoc`.

The tree visible in the QCH is the same tree that appears on the
website. Preview it locally by opening the compiled `.qch` in
Qt Creator's help viewer or in Qt Assistant.

**Small-module variant:** a module with one or two doc topics can skip
the `manual` branch and TOC page. A subproject whose `indexTitle` is
the one topic and whose selectors match nothing yields a single tree
entry (QtSpatialAudio: `subprojects.overview.indexTitle = Spatial Audio
Overview`, `selectors = group:none`; since QDoc 6.9 the documented form
is `selectors = none`).

For subproject properties and selectors, read
`references/qhp-subprojects.md`.

## Groups Are Lists, Not Navigation

`\group`, `\ingroup`, `\annotatedlist`, and `\generatelist` create
topic *listings* on pages. Group membership does **not** place a page
in the tree. The `\group` page itself, however, should be listed on the
module's TOC page like any other manually written page.

For group and list command syntax, read
`skill-qdoc/references/group-and-organization.md`.

## The Module Contract

Five qdocconf values must each match a `\title` exactly. Qt Quick
(`qtdeclarative/src/quick/doc/qtquick.qdocconf`) exercises all of them:

| qdocconf variable | Value (Qt Quick) | Must equal `\title` of |
|-------------------|------------------|------------------------|
| `navigation.landingpage` | `Qt Quick` | the landing page (`qtquick.qdoc`, `\page qtquick-index.html`) |
| `navigation.cppclassespage` | `Qt Quick C++ Classes` | the C++ classes page — usually the `\module` page, sometimes a plain `\page` |
| `navigation.qmltypespage` | `Qt Quick QML Types` | the `\qmlmodule` page |
| `navigation.toctitles` | `Qt Quick module topics` | the TOC page |
| `qhp.QtQuick.subprojects.manual.indexTitle` | `Qt Quick module topics` | the same TOC page |

The last two name the **same page**: one `\list` on `qtquick-toc.qdoc`
drives both the previous/next page order (`navigation.toctitles`) and
the `manual` branch of the tree (`indexTitle` + `type = manual`).

## The `<module>-toc.qdoc` Page

```qdoc
/*!
    \page qtquick-toc.html
    \title Qt Quick module topics

    \list
    \li \l {Getting started with Qt Quick applications}{Getting Started}
        \list
            \li \l {First Steps with QML}
        \endlist
    \li \l {Important Concepts In Qt Quick - The Visual Canvas}{Visual Canvas}
    \endlist
*/
```

- Nesting depth = tree depth; list order = page order (previous/next).
- Link by page `\title`; an optional second argument sets the visible
  tree label.
- **Tree items must be `\l` links (or a `\generatelist`).** A
  plain-text `\li` item is not displayed in the tree.
- Use `\generatelist [descending] <group>` (QDoc 6.11+) to add
  numerous homogeneous topics that need no subitems — linter
  diagnostics, what's new items. See `references/toc-page.md`.

For `navigation.toctitles` semantics and worked examples, read
`references/toc-page.md`.

## The Framework Tree

`qtdoc/doc/config/style/tree_config.xml` holds the root structure of
the **Qt Framework** documentation (not Qt Creator or other projects).
It specifies how the module trees are merged into the single tree on
the website: `<node toc="qtcore"/>` inserts a module's tree,
`parent_url` grafts it under another module's page, and
`<node title= href=>` creates folder nodes. The file carries a
comprehensive doc comment on its own format.

A module without a `manual` branch or TOC page still appears here —
its tree is just the selector-generated branches (many `<node toc=>`
entries have no matching `*-toc.qdoc`).

For the node format and the new-module procedure, read
`references/tree-config-xml.md`.

## Procedure A — Add a Manually Written Page

1. Locate the module's TOC page: the file whose `\title` matches
   `navigation.toctitles` (conventionally `<module>-toc.qdoc`).
2. Add an `\li \l {Page Title}` entry at the intended depth and
   position. Position sets previous/next order; depth sets nesting.
3. API and example pages need nothing — selectors collect them.
4. Rebuild; confirm no `Failed to find table of contents` warning and
   that the page appears in the `.qch` contents.

## Procedure B — Create Module Docs from Scratch

For **new modules only**. Two sides, two repositories:

1. Module side: landing page (`<module>-index.qdoc`), `\module` and/or
   `\qmlmodule` pages, the TOC page, the five matching qdocconf values
   (see The Module Contract), and `qhp.<Module>.subprojects` in tree
   order. Small modules may use the single-topic subproject instead.
2. qtdoc side: add a `<node toc="<module>"/>` entry to
   `qtdoc/doc/config/style/tree_config.xml`, with `parent_url` if the
   module belongs under another module's node.

Skipping step 2 produces no warning — the module simply never appears
in the website tree.

## Procedure C — Orphan Audit

A manually written page is in the tree **iff** it is reachable from the
module's TOC page. Group membership does not count.

1. Enumerate manually written pages:
   ```bash
   grep -rh "^[[:space:]]*\\\\page " src/<mod>/doc/src \
     --include="*.qdoc" | awk '{print $2}' | sort > /tmp/pages.txt
   ```
2. Collect their titles (a second grep for `\title` in the same
   files). Subtract auto-collected node types (`\example`, `\class`,
   `\qmltype` pages need no TOC entry) and every branch root: the
   landing page (`navigation.landingpage`), the TOC page itself, and
   **every `qhp.<P>.subprojects.*.indexTitle` value** — those pages
   are the roots of the selector branches, already in the tree.
3. Extract every `\l {Title}` from `<module>-toc.qdoc` (including
   nested lists) and compare.
4. Report each unlisted page as ORPHAN. Flag `\group` pages missing
   from the TOC page. QDoc itself never warns about orphans.

## Warning Catalogue

Exact strings to grep in build logs:

| Warning | Cause | Fix |
|---------|-------|-----|
| `Failed to find table of contents with title '<T>'` | `navigation.toctitles` names no page `\title` | Match the value to the TOC page title |
| `Failed to find <prefix>.indexTitle '<T>'` (`<prefix>` = full qdocconf path, e.g. `qhp.QtCore.subprojects.manual`) | Subproject `indexTitle` names no page | Match `indexTitle` to the page title |
| `'\generatelist <G>' no such group` | No entity has `\ingroup <G>` | Fix group name or add members |
| `'\generatelist <G>' group is empty` | Group exists, no matching items | Add members or drop the list |

## Silent Failures

No warning is emitted for any of these:

- Manually written page never added to the TOC page — builds clean,
  absent from every tree.
- A plain-text `\li` item (no `\l`) in the TOC list — silently
  omitted from the tree.
- Module missing from `tree_config.xml` — invisible on the website.
- A subproject defined but not listed in `qhp.<P>.subprojects` — the
  block is ignored (live example: qtdoc's `examples` block).
- `\generatelist` inside a TOC list on QDoc < 6.11 — no navigation
  links are generated for the group members.
- `\ingroup` consumes the rest of the line — a trailing comment
  silently becomes part of the group name.

## Reference Materials

| File | Content |
|------|---------|
| `references/toc-page.md` | TOC page anatomy, `navigation.toctitles`, `\generatelist` caveat, legacy nav commands |
| `references/qhp-subprojects.md` | `qhp.*` properties, selectors, branch order, single-topic pattern |
| `references/tree-config-xml.md` | Framework tree node format, merge order, new-module procedure |

## Owned Elsewhere — Do Not Duplicate

| Topic | Owner |
|-------|-------|
| `\group`/`\ingroup`/`\generatelist` syntax | `skill-qdoc/references/group-and-organization.md` |
| Landing page structure (R58), qdocconf (R61) | `skill-language-style/references/page-templates.md` |
| HTML output filename patterns | `skill-qdoc-output` |
| General qdocconf variables (`project`, `depends`, `imagedirs`, `warninglimit`) | `skill-qdoc/references/advanced-qdocconf.md` |

## External References

- [QDoc Manual: navigation](https://doc.qt.io/qt-6/22-qdoc-configuration-generalvariables.html#navigation-variable)
- [QDoc Manual: Creating Help Project Files](https://doc.qt.io/qt-6/22-creating-help-project-files.html)

## Version History

- **1.0.0** (2026-08-14): Initial version — module tree subprojects,
  TOC page, framework tree, orphan audit
