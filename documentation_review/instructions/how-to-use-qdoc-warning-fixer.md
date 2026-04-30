# How to Use the QDoc Warning Fixer Agent

Diagnose and fix QDoc warnings from build output. Reads source files, checks headers for public/private API status, and proposes fixes with correct QDoc commands.

## Prerequisites

Agent and skills must be in `~/.claude/`:
```
~/.claude/
├── CLAUDE.md
├── agents/qdoc-warning-fixer.md
└── skills/
    ├── skill-doc-diff/
    ├── skill-language-style/
    ├── skill-qdoc/
    ├── skill-qdoc-output/
    ├── skill-line-wrap/
    └── skill-module-export/
```

---

## When to Use This Agent

Use **qdoc-warning-fixer** for:
- Fixing "Can't link to 'X'" warnings
- Fixing "No documentation for 'X'" warnings
- Fixing "No such parameter 'x'" warnings
- Fixing missing `\inmodule` warnings
- Fixing "Failed to find function" signature mismatches
- Fixing missing alt text warnings
- Fixing undocumented enum value warnings
- Fixing QML method return type warnings
- Processing QDoc error files (ERR.*)
- Adding `\internal` tags to private classes

Use **qt-doc-reviewer** instead for:
- Reviewing patches before merge
- Grammar and style checking
- Pre-commit validation

---

## Example Prompts

**Important:** Always name the agent explicitly to ensure reliable routing.

### Paste Warnings from a Build Log
```
run qdoc-warning-fixer on these warnings:
/path/to/file.cpp:42: (qdoc) warning: Can't link to 'QFoo::bar()'
/path/to/file.cpp:58: (qdoc) warning: No documentation for 'QFoo::baz'
```

### Process a Warning File
```
run qdoc-warning-fixer on ERR.doc
```

### Fix a Specific Warning
```
run qdoc-warning-fixer on "Can't link to 'QFoo'" in qtwidgets/src/widgets/qfoo.cpp
```

### Fix All Warnings in a Module
```
run qdoc-warning-fixer on all warnings in qtwayland
```

---

## What It Handles

| Warning Type | What the Fixer Does |
|---|---|
| "Can't link to 'X'" | Searches index files, fixes target or switches `\l` to `\c` |
| "No such parameter 'x'" | Corrects `\a` parameter names to match function signature |
| "No documentation for 'X'" | Checks if public API; adds `\class`/`\fn` doc or `\internal` |
| "No \inmodule command" | Adds the correct `\inmodule` for the class |
| "Cannot find image file" | Checks imagedirs in qdocconf, fixes path |
| "Failed to find function 'X'" | Fixes `\fn` signature to match header declaration |
| "Undocumented return value" | Adds return value description |
| "Clashes with existing target" | Renames or removes duplicate `\target`/`\keyword` |
| "Missing alt text for image" | Adds alt text per QUIP 21 rules |
| "Undocumented enum value 'X'" | Adds `\value` entry for missing enum constant |
| "QML method has no return type" | Adds return type to `\qmlmethod` |
| Other warnings | Diagnoses from context, proposes fix or reports to developer |

## How It Works

The agent uses a **GATE-based** skill loading strategy — it only loads the skill relevant to each warning type at the moment of decision, rather than loading everything upfront.

1. **Parse** — Extract file, line, module, warning type
2. **Read source** — Read the file at the warning line (±5 lines context) plus the header
3. **Check header** — Export macro? QML registration? Public `.h` or private `_p.h`?
4. **Diagnose** — Load the skill matching the warning type and determine root cause
5. **Fix** — Propose the correct QDoc commands
6. **Write docs** — If adding new doc blocks, apply language rules (R1-R64)
7. **Verify `\since`** — For new documentation, trace via `git tag --contains` (never infer)
8. **Format** — Output in Doc Team diff format

---

## Key Behaviors

- **Export + `\internal` is valid.** Private classes (`_p.h`, `*Private`, QPA) can have export macros for ABI reasons. The fixer adds `\internal`, not full documentation.
- **`\since` is verified via git.** When adding new documentation, the fixer traces the commit that introduced the type and finds the earliest tag. It never infers from module date or peer types.
- **Link fixes are verified.** Before suggesting a `\l` fix, the fixer searches index files to confirm the target exists.

---

## Tips

- **Have sources locally.** The fixer reads actual source files and headers to diagnose warnings accurately.
- **Batch warnings together.** Paste multiple warnings at once — the fixer processes them sequentially and may identify related issues.
- **Review the Cause field.** Each suggestion explains why the warning occurs and what evidence was found.
