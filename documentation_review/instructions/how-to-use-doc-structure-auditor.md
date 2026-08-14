# How to Use the Doc Structure Auditor Agent

Audit an entire Qt module for structural completeness, navigation integrity, and cross-reference validity.

## Prerequisites

Agent and skills must be in `~/.claude/`:
```
~/.claude/
├── CLAUDE.md
├── agents/doc-structure-auditor.md
└── skills/
    ├── skill-all-docs/
    ├── skill-qdoc/
    ├── skill-language-style/
    ├── skill-linking-check/
    ├── skill-doc-audit/
    └── skill-qdoc-output/
```

---

## When to Use This Agent

Use **doc-structure-auditor** for:
- Auditing a module's documentation completeness
- Pre-release readiness checks
- Checking if all examples are documented
- Finding orphan pages and broken navigation
- Verifying tech preview markers are consistent
- Checking all public API types have documentation

Use **qt-doc-reviewer** instead for:
- Reviewing a single patch or file

Use **doc-impact-analyzer** instead for:
- Checking if a specific code change breaks links

---

## Example Prompts

**Important:** Always name the agent explicitly to ensure reliable routing.

### Full Module Audit
```
run doc-structure-auditor on the qtopenapi module
```

### Release Readiness Check
```
run doc-structure-auditor: is qtopenapi ready for Qt 6.11 release?
```

### Examples Check
```
run doc-structure-auditor: check if all qtopenapi examples are documented
```

### C++ API Coverage
```
run doc-structure-auditor: check if all public classes in qtgrpc are documented
```

---

## 13 Check Categories

| # | Category | What It Checks |
|---|---|---|
| 1 | Module Index Page | `\page`, `\title`, `\brief`, required sections (overview, using, reference, examples, licenses) |
| 2 | Navigation | All pages reachable from index, no orphan pages, breadcrumb paths; topic tree coverage via skill-toc-tree Procedure C |
| 3 | Examples | 11 mandatory elements per example (title, brief, screenshot, walkthrough...) |
| 4 | Examples Group | `\group` defined, `\ingroup all-examples` |
| 5 | CMake Commands | Group page, individual command pages, cross-links |
| 6 | C++ API | All exported classes have `\class` documentation, `\since` via git |
| 7 | QML API | All `QML_ELEMENT` types have `\qmltype` documentation, `\since` via git |
| 8 | Cross-References | All `\l` links resolve |
| 9 | Attributions | Match `qt_attribution.json` entries, linked from index |
| 10 | Images | Files exist in imagedirs, have alt text, meet QUIP 21 specs |
| 11 | Snippets | Source files exist, markers present and closed |
| 12 | Includes | Include files exist, `.qdocinc` extension |
| 13 | Tech Preview | `\modulestate`, `\preliminary` consistency, Qt.labs.* markers |

## Finding Types

| Type | Meaning |
|---|---|
| **MISSING** | Required element not present |
| **ORPHAN** | Page exists but not reachable from navigation |
| **BROKEN** | Link target does not exist |
| **INCOMPLETE** | Element partially defined |

---

## Tips

- **Large modules take longer.** Auditing qtbase or qtdeclarative may take 5-10 minutes due to the number of files.
- **Run before release.** The audit catches structural issues that individual patch reviews miss.
- **Tech preview detection uses signals.** The auditor checks 7 signals of varying strength (from `\modulestate Technology Preview` down to "few examples") and reports consistency.
