# skill-qdoc Changelog

- **1.1.0** (2026-08-14): Legacy navigation commands superseded
  - page-structure.md: Navigation Commands section replaced by a
    pointer to skill-toc-tree (page order comes from the module TOC
    tree; `\previouspage`/`\nextpage`/`\startpage` are legacy)
  - context-commands.md: same commands marked legacy in the table
    and subsection
  - stub-patterns.md: tutorial-chain row now requires an entry in
    `<module>-toc.qdoc` instead of `\nextpage`/`\previouspage`
  - advanced-qdocconf.md: corrected `subprojects.manual.indexTitle`
    example (`Qt Core module topics`, was `Qt Core`) and QML
    subprojects order; subproject/tree semantics deferred to
    skill-toc-tree/references/qhp-subprojects.md
- **1.0.0** (2026-03-27): Initial changelog
  - 18 reference files covering full QDoc architecture
  - Recent additions: advanced-qdocconf, examples-and-snippets,
    group-and-organization, module-declaration, namespaces-headers-macros,
    page-structure (all added or rewritten 2026-03-26)
  - Updated: context-commands (2026-03-12), link-resolution v1.3
    (2026-03-16), markup-commands (2026-03-01)
  - Stable since initial: admonitions, index-files, macros-warnings,
    node-system, qdocconf-reference, qt-help, source-file-location,
    structured-content (all 2025-02-25)
  - SKILL.md: overview + reference pointers (320 lines)
  - Total reference lines: 6,183
