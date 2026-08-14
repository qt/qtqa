# The Module TOC Page Reference

**Verified against:** QDoc sources at
`qttools/src/qdoc/qdoc` (dev, 2026-08), the QDoc manual
(`doc/qdoc-manual-qdocconf.qdoc:1268-1378`), and live TOC pages
`qtbase/src/corelib/doc/src/qtcore-toc.qdoc`,
`qtdeclarative/src/quick/doc/src/qtquick-toc.qdoc`,
`qtdoc/doc/src/qtdoc-toc.qdoc`.

## Purpose

One page per module — conventionally `<module>-toc.qdoc` with the
title `<Module> module topics` — holds a nested `\list` of links to
every manually written page in the module. This single `\list` drives:

1. **Previous/next page links and tree order** — via
   `navigation.toctitles` (QDoc walks the list at build time,
   `qdocdatabase.cpp: updateNavigation()`).
2. **The `manual` branch of the module tree** — via
   `qhp.<Module>.subprojects.manual.indexTitle` + `type = manual`
   (`helpprojectwriter.cpp` re-walks the same list).

The tree in the QCH is the tree on the website.

## `navigation.toctitles`

From the QDoc manual (`qdoc-manual-qdocconf.qdoc`):

> Page title(s) containing a `\list` structure that acts as a table of
> contents (TOC). QDoc generates navigation links for pages listed in
> the TOC, without the need for `\nextpage` and `\previouspage`
> commands, as well as a navigation hierarchy that's visible in the
> navigation bar (breadcrumbs) for HTML output. *(Since QDoc 6.0)*

> `navigation.toctitles.inclusive` — If set to `true`, page(s) listed
> in `navigation.toctitles` will also appear in the navigation bar as
> a root item. *(Since QDoc 6.3)*

Qt modules set `inclusive = false`:

```
# qtbase/src/corelib/doc/qtcore.qdocconf
navigation.toctitles = "Qt Core module topics"
navigation.toctitles.inclusive = false
```

Rules enforced by the implementation (`qdocdatabase.cpp:1767-1995`):

- Each `toctitles` entry must resolve to a **page node**; otherwise:
  `Failed to find table of contents with title '<T>'`.
- List order = previous/next order. Nesting depth = tree depth.
- Self-references are skipped.
- `\nextpage`/`\previouspage` links on listed pages are **overwritten**
  by the TOC-derived links (`qdocdatabase.cpp:1878-1923`).

## Anatomy

```qdoc
/*!
    \page qtquick-toc.html
    \title Qt Quick module topics

    The following list has links to all the individual topics
    (HTML files) in the Qt Quick module.

    \list
    \li \l {Getting started with Qt Quick applications}{Getting Started}
        \list
            \li \l {First Steps with QML}
            \li \l {Visual types}
        \endlist
    \li \l {Important Concepts In Qt Quick - The Visual Canvas}{Visual Canvas}
    \endlist
*/
```

- Link by page `\title`. The optional second argument sets the label
  shown in the tree — use it to shorten long titles.
- **Tree items must be `\l` links (or a `\generatelist`).** A
  plain-text `\li` item (no `\l`) is not displayed in the tree.
  The manual's own example shows an unlinked `\li What's new` with
  a sub-list — do not copy it. A broken `\l` link is reported as an
  ordinary link warning.

## `\generatelist` in a TOC list

`\generatelist` inside a TOC list pulls a whole group into the tree:

```qdoc
\list
    \li \l {Home}
    \li \l {What's new}
        \generatelist [descending] whatsnew
\endlist
```

**Recommended for numerous homogeneous topics that need no
subitems** — linter diagnostics, what's new items. The framework
root TOC (`qtdoc/doc/src/qtdoc-toc.qdoc:58`) uses
`\generatelist [descending] whatsnewqt6` this way. For individual
pages, and for any entry that needs sub-entries of its own, use
plain `\l` links.

**Requires QDoc 6.11+.** Navigation-link support for
`\generatelist` / `\annotatedlist` inside a TOC list landed in
qttools commit `79625eb96` ("qdoc: Allow generated lists in table
of contents structure"), first released in QDoc 6.11.0 — the
manual's "Since QDoc version 6.10" claim is wrong. On earlier QDoc
versions the list renders on the page, but the group members get
no previous/next links and no tree placement — silently.

Behavior details:

- Group members keep the **group page** as their navigation parent;
  only previous/next links are threaded through the TOC.
- Members cannot have subitems of their own in the tree.
- Non-page nodes, index (cross-module) nodes, and external pages are
  silently dropped from the generated entries.
- Order is alphabetical; `[descending]` reverses the whole list.
  A member with `\meta sortkey` sorts by that key ahead of all
  unkeyed members — so it leads in the default order but **trails**
  under `[descending]`, which reverses the same comparator
  (`node.cpp`, `Node::nodeSortKeyOrNameLessThan`).

## Legacy: `\nextpage` / `\previouspage` / `\startpage`

Superseded. Page order comes from the TOC page; `toctitles` overwrites
any `\nextpage`/`\previouspage` links on listed pages. Do not add these
commands to new documentation; remove them when touching pages that are
listed in a module TOC.

## `\toc` / `\tocentry` (QDoc 6.11+)

QDoc 6.11 introduced `\toc`/`\endtoc`/`\tocentry` context commands that
write a `<project>_toc.xml` file. **No Qt module uses them yet** — the
only occurrences are the QDoc manual and QDoc's own test data. Qt
modules use the `<module>-toc.qdoc` + `toctitles` mechanism described
above.

## Framework-level TOC

`qtdoc` applies the same mechanism at the root:
`qtdoc/doc/config/qtdoc.qdocconf` sets
`navigation.toctitles = "All Topics"`, resolved by
`qtdoc/doc/src/qtdoc-toc.qdoc` (`\page qtdoc-toc.html`,
`\title All Topics`). How module trees merge under this root is
defined by `tree_config.xml` — see `references/tree-config-xml.md`.

## Version History

- **v1.0** (2026-08-14): Initial version
