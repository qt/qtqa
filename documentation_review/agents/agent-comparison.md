# Agent Comparison

## At a Glance

| Agent | What It Does | Input | Output |
|-------|-------------|-------|--------|
| **qt-doc-reviewer** | Reviews existing doc patches for style, QDoc, linking, alt text | Gerrit URL or patch diff | Doc-diff suggestions |
| **qdoc-warning-fixer** | Diagnoses and fixes QDoc build warnings | Warning text or log file | Doc-diff fixes |
| **doc-impact-analyzer** | Predicts doc breakage from code changes *before* warnings appear | Commit SHA or code diff | Impact report (Breaking/Stale/Cosmetic) |
| **doc-shaper** | Creates new documentation from source code | Header/source files or module path | Doc-diff with new/stub docs |
| **doc-structure-auditor** | Audits a module's entire doc structure for health | Module name/path | Audit report (Missing/Orphan/Broken/Incomplete) |
| **doc-builder** | Builds documentation locally | Product/module name + branch | Build output or troubleshooting |

## Sample Prompts

| Agent | Example |
|-------|---------|
| **qt-doc-reviewer** | "Review https://codereview.qt-project.org/c/qt/qtbase/+/612345" |
| **qdoc-warning-fixer** | "Fix: src/gui/doc/src/richtext.qdoc:42: (qdoc) Cannot find 'QTextFormat::type' in any header file" |
| **doc-impact-analyzer** | "Does commit abc123 (renamed QFoo to QBar) break any docs?" |
| **doc-shaper** | "Write full docs for qtbase/src/corelib/io/qsavefile.h" |
| **doc-structure-auditor** | "Audit Qt Wayland Compositor module documentation health" |
| **doc-builder** | "Build Qt Multimedia docs from dev branch" |

## Pipeline View

The agents form a natural pipeline with minimal overlap:

```
Code change
  -> doc-impact-analyzer  (predict what will break)
  -> doc-shaper           (create missing docs)
  -> doc-builder          (build to get warnings)
  -> qdoc-warning-fixer   (fix warnings from build)
  -> qt-doc-reviewer      (review the final patch)
  -> doc-structure-auditor (periodic health check)
```

## Overlap Analysis

### Where Boundaries Touch

1. **qt-doc-reviewer vs qdoc-warning-fixer** — Both fix QDoc issues, but
   the reviewer works from *patches* (human-authored changes) while the
   warning-fixer works from *QDoc build output* (compiler warnings). The
   reviewer checks language/style; the warning-fixer doesn't.

2. **doc-impact-analyzer vs qdoc-warning-fixer** — Both deal with broken
   references, but impact-analyzer is *predictive* (before the build) while
   warning-fixer is *reactive* (after warnings appear).

3. **doc-shaper vs qdoc-warning-fixer** — Both can write new documentation.
   The shaper creates docs from scratch (header -> full docs). The
   warning-fixer only writes the minimum needed to resolve a specific
   warning (e.g., adding a missing `\brief`).

4. **doc-structure-auditor vs doc-impact-analyzer** — Both find broken
   links, but the auditor does a *broad module sweep* while the
   impact-analyzer does *targeted analysis* of a specific change.

No real redundancy. Each has a distinct trigger (patch, warning, code
change, header, module, build) and a distinct goal.

## Deep Dive: doc-shaper vs doc-structure-auditor

### Core Difference

| | doc-shaper | doc-structure-auditor |
|---|---|---|
| **Verb** | *Creates* | *Inspects* |
| **Question it answers** | "Write the docs for this" | "Are the docs complete?" |
| **Output** | Doc-diff with actual QDoc content | Audit report (MISSING/ORPHAN/BROKEN/INCOMPLETE) |
| **Scope** | Single type, file, or module scaffold | Entire module, all 13 check categories |

### Where They Touch: Scaffold Mode

The closest overlap is doc-shaper scaffold mode vs doc-structure-auditor.
Both examine module-level structure (qdocconf, index page, groups,
examples). But they do different things with what they find:

| Check | doc-shaper (scaffold) | doc-structure-auditor |
|-------|----------------------|----------------------|
| Missing qdocconf | **Generates** one from scratch | **Reports** it as MISSING |
| Missing index page | **Generates** the page with sections | **Reports** which sections are absent |
| Missing examples group | **Generates** the `\group` page | **Reports** undocumented examples |
| Broken cross-refs | Not checked | **Traces** every `\l` link across modules |
| Orphan pages | Not checked | **Maps** full navigation tree, flags orphans |
| Image/snippet integrity | Not checked | **Verifies** every `\image` and `\snippet` path |
| Attribution pages | Not checked | **Cross-checks** against `qt_attribution.json` |

### When to Use Which

| Scenario | Agent |
|----------|-------|
| New module, docs don't exist yet | **doc-shaper** (scaffold) -> generates the structure |
| New module exists, want to check completeness | **doc-structure-auditor** -> finds gaps |
| Undocumented class needs docs | **doc-shaper** (stub/full) |
| Pre-release "are we ready?" check | **doc-structure-auditor** |
| Major restructuring — need new layout | **doc-shaper** (scaffold) |
| Major restructuring — verify nothing broke | **doc-structure-auditor** |

### Natural Pipeline

They're sequential, not redundant:

```
doc-shaper (scaffold)  ->  creates module structure
doc-shaper (stub/full) ->  creates API docs
doc-structure-auditor  ->  verifies everything is wired up
```

The auditor has 13 check categories (index, navigation, examples, CMake,
C++ API, QML API, cross-refs, attributions, images, snippets, includes,
example groups, tech preview status) — far broader than what the shaper validates. The shaper's
self-verification is limited to "is my generated output syntactically
correct," not "does this module's documentation form a complete, navigable
whole."

### Key Distinction

**doc-shaper** = "Here's nothing, make something."
**doc-structure-auditor** = "Here's something, tell me what's wrong."
