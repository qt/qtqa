# How to Use the Doc Shaper Agent

Create and scaffold Qt documentation from source code. Generates stubs, complete documentation, or module structure.

## Prerequisites

Agent and skills must be in `~/.claude/`:
```
~/.claude/
├── CLAUDE.md
├── agents/doc-shaper.md
└── skills/
    ├── skill-doc-diff/
    ├── skill-language-style/
    ├── skill-qdoc/
    ├── skill-qdoc-output/
    ├── skill-line-wrap/
    ├── skill-module-export/
    └── skill-all-docs/
```

---

## When to Use This Agent

Use **doc-shaper** for:
- Generating QDoc stubs for undocumented classes
- Writing complete documentation from source code
- Setting up qdocconf and module structure for new modules
- Filling in empty `\property`/`\qmlproperty` blocks

Use **qt-doc-reviewer** instead for:
- Reviewing existing documentation for style issues

Use **qdoc-warning-fixer** instead for:
- Fixing warnings from build output

---

## Three Modes

| Mode | When to Use | Output |
|---|---|---|
| **Stub** | Quick skeleton — you'll fill in the prose | QDoc commands with `{TODO}` markers |
| **Full** | Complete docs from code analysis | Ready-to-use documentation |
| **Scaffold** | New module setup | qdocconf, overview page, group structure |

---

## Example Prompts

**Important:** Always name the agent explicitly to ensure reliable routing.

### Stub Mode — Quick Skeleton
```
run doc-shaper: shape stubs for qtbase/src/corelib/kernel/qobject.h
```

### Full Mode — Complete Documentation
```
run doc-shaper: fill docs for qtdeclarative/src/particles/qquicktargetdirection.cpp
```

### Full Mode — Using a Peer as Template
```
run doc-shaper: shape docs for qquickwander.cpp using qquickpointdirection.cpp as template
```

### Scaffold Mode — New Module Structure
```
run doc-shaper: scaffold module docs for qtpositioning/src/positioning/
```

---

## What It Generates

- `\class` / `\qmltype` with context commands (`\inmodule`, `\since`, `\ingroup`)
- `\property` / `\qmlproperty` with types, defaults, and behavior
- `\fn` with parameter descriptions and return values
- `\enum` with all `\value` entries from the header
- **Scaffold:** qdocconf file, module overview page, C++ classes group, examples group

## Uncertainty Handling

When behavior cannot be determined from source code, the shaper inserts `{TODO: hint}` markers explaining:
- What information is missing
- Where to look for it
- What the options might be

Example: `{TODO: unit — the setter has no clamping, check if this is pixels or a normalized 0-1 value}`

---

## Tips

- **Always review generated documentation.** The shaper infers from code — verify defaults and descriptions against the actual implementation.
- **Have both header and implementation available.** Full mode reads the constructor for defaults and setter methods for behavior.
- **Peer types improve consistency.** Specifying a well-documented peer type helps the shaper match existing patterns in the module.
- **Copyright year:** New .qdoc files use the current calendar year, not the source file's year.
