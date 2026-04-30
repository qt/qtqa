# How to Use the Doc Impact Analyzer Agent

Predict broken links, stale references, and missing documentation updates after code changes — before QDoc warnings appear.

## Prerequisites

Agent and skills must be in `~/.claude/`:
```
~/.claude/
├── CLAUDE.md
├── agents/doc-impact-analyzer.md
└── skills/
    ├── skill-linking-check/
    ├── skill-qdoc/
    ├── skill-all-docs/
    ├── skill-doc-audit/
    ├── skill-cross-product-check/
    └── skill-doc-diff/
```

---

## When to Use This Agent

Use **doc-impact-analyzer** for:
- Checking if a commit breaks documentation links
- Finding what docs need updating after a rename
- Analyzing a Gerrit patch for documentation impact
- Checking cross-module and cross-product dependencies
- Pre-merge impact assessment

Use **qt-doc-reviewer** instead for:
- Reviewing documentation content and style
- Language and grammar checking

Use **qdoc-warning-fixer** instead for:
- Fixing warnings that already exist in build output

---

## Example Prompts

**Important:** Always name the agent explicitly to ensure reliable routing.

### Analyze a Commit
```
run doc-impact-analyzer on commit 69c2495ea9 in qtdeclarative
```

### Check a Rename
```
run doc-impact-analyzer: I'm renaming QFoo to QBar, what docs need updating?
```

### Check a Gerrit Patch
```
run doc-impact-analyzer on https://codereview.qt-project.org/c/qt/qtbase/+/123456
```

### Check a Page Title Rename
```
run doc-impact-analyzer: I want to rename "Supported Platforms" to "Supported platforms", what breaks?
```

---

## What It Searches

- `\l{}` links and `\sa` references across all Qt modules
- `\class`, `\qmltype`, `\fn` topic commands
- Index files for cross-module dependencies
- `\image` and `\inlineimage` references (if image files changed)
- **Cross-product impact** — Qt for Python, Qt Creator, Qt Design Studio, marketing materials

## Severity Levels

| Severity | Meaning | Action |
|---|---|---|
| **Breaking** | Links will fail, QDoc warnings will appear | Must fix before/with commit |
| **Stale** | References outdated but may still work | Should fix |
| **Gap** | New content needs documentation | Should add docs |
| **Cosmetic** | Comments/prose mention old name | Nice to fix |
| **Flag** | Requires other team review (marketing/legal) | Notify team |

---

## Tips

- **Have the full super-repo available.** The analyzer searches across all `qt*/` directories for references.
- **Title-based links are case-sensitive.** Changing `\title Supported Platforms` to `\title Supported platforms` breaks all `\l{Supported Platforms}` links.
- **Consider the `\keyword` workaround.** Adding `\keyword OldTitle` preserves backward compatibility without updating every link.
