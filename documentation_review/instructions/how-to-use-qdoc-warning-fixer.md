# How to Use QDoc Warning Fixer Agent

Fix QDoc warnings from build output. Processes warning files, diagnoses root causes, and outputs fixes in Doc Team diff format.

## Prerequisites

Agent and skills must be in `~/.claude/`:
```
~/.claude/
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
- Fixing undocumented class/function warnings
- Fixing missing `\inmodule` warnings
- Fixing signature mismatch warnings
- Processing QDoc error files (ERR.*)
- Adding `\internal` tags to private classes
- Fixing external page issues

Use **qt-doc-reviewer** instead for:
- Reviewing patches before merge
- Grammar and style checking
- Pre-commit validation
- Alt text review

---

## Example Prompts

### Process Warning File
```
Fix warnings in ERR.declarative using qdoc-warning-fixer.
Output fixes in Doc Team diff format.
```

### Fix Specific Warnings
```
Fix these QDoc warnings using qdoc-warning-fixer:

/path/file.qdoc:45: (qdoc) warning: Can't link to 'QWidget'
/path/file.qdoc:67: (qdoc) warning: Can't link to 'setValue()'
```

### Fix Link Warnings in Module
```
Fix QDoc link warnings in qtdeclarative using qdoc-warning-fixer.
```

### Fix Undocumented Warnings
```
Fix undocumented class warnings in qtquick using qdoc-warning-fixer.
Add \internal tags where appropriate.
```

### Process Build Log
```
Process QDoc warnings from build.log using qdoc-warning-fixer.
```

### Fix Specific File
```
Fix QDoc warnings in src/quick/items/qquickitem.cpp using qdoc-warning-fixer.
```

---

## Warning Types Handled

### Link Warnings ("Can't link to 'X'")
```
warning: Can't link to 'QWidget'
```
**Fixes:**
- Correct typos in link targets
- Add namespace/class qualification
- Convert to `\c` for internal types
- Fix QML property link syntax (`::` not `.`)

### Undocumented Warnings
```
warning: No documentation for 'QQuickItemPrivate'
```
**Fixes:**
- Add `\class`, `\inmodule`, `\internal` for private classes
- Add full documentation for public APIs

### Missing Module Warnings
```
warning: No \inmodule command for 'ClassName'
```
**Fixes:**
- Add `\inmodule QtModule` command

### Signature Mismatch
```
warning: Can't find 'void MyClass::myFunction(int)'
```
**Fixes:**
- Correct function signature to match declaration

### Undocumented Parameters
```
warning: Undocumented parameter 'value' in MyClass::setValue()
```
**Fixes:**
- Add `\a value` documentation

### Complex Warnings (Alternative Solutions)

Some warnings don't have simple fixes. The agent will consider:

| Situation | Agent Response |
|-----------|----------------|
| API was removed/renamed | Suggest section rewrite or bulk update |
| Multiple related warnings | Identify root cause, fix once |
| Docs don't match code | Compare code, suggest content update |
| Requires code change | Report to developer instead of doc fix |
| Content is obsolete | Suggest removal rather than fix |

---

## What the Agent Does

### Workflow for Each Warning

1. **Parse** - Extract file, line, module, warning type
2. **Read** - Load source file with context
3. **Verify** - Search index files for correct link targets
4. **Diagnose** - Determine root cause
5. **Fix** - Generate correction in Doc Team diff format

### Index File Verification

The agent verifies link targets before suggesting fixes:

**Online (recommended):**
```
https://doc-snapshots.qt.io/qt6-dev/{module}.index
```

**Local:**
```bash
grep 'name="TargetName"' */doc/*/*.index
```

---

## Expected Output Format

```markdown
**Suggestion 1 of 5 for qquickitem.cpp:123:**

**Category:** QDoc Link Error

**Warning:** `Can't link to 'QStirng'`

```diff
   121→    Returns the item's name as a string.
   122→
 - 123→    \sa QStirng, QByteArray
 +    →    \sa QString, QByteArray
   124→
   125→    \since 6.0
```

**Cause:** Typo in class name. Searched `grep 'name="QStirng"'` — no results. Searched `grep 'name="QString"'` — found in qtcore.index. Confirms typo; QString is correct target.

**Validation:** [LEAVE EMPTY - reviewer will fill]

**Comments:** Corrects typo to link to actual Qt class.

---
```

---

## Common Scenarios

### Batch Fix Module Warnings
```
Process all QDoc warnings for qtquick module using qdoc-warning-fixer.
Show progress as you work through them.
```

### Fix Private Class Warnings
```
Fix undocumented warnings for *Private classes in qtdeclarative.
Use \internal for classes without export macros.
```

### Fix After Refactoring
```
Fix QDoc warnings after the API refactoring.
Process ERR.widgets for new warnings.
```

### Verify Fixes Work
```
I fixed some link warnings. Verify the fixes using qdoc-warning-fixer.
```

### Generate Patch
```
Fix warnings in ERR.qml using qdoc-warning-fixer.
Output fixes I can apply as a patch.
```

---

## Understanding Fix Options

When multiple valid fixes exist, the agent presents options:

```markdown
**Fix Options:**
1. **Use \c** - Format as code without link (for internal API)
2. **Remove link** - Just use plain text
3. **Document the type** - Add \class documentation

**Recommended:** Option 1 because target is internal API.
```

### Common Option Scenarios

| Scenario | Options |
|----------|---------|
| Internal API | `\c` / Remove / Document |
| Ambiguous target | Qualify / Different target / `\c` |
| Deprecated API | Link replacement / `\c` with note / Remove |
| API removed | Rewrite section / Remove content / Report to dev |
| Multiple related warnings | Fix root cause / Individual fixes |
| Docs outdated | Standard fix / Content rewrite / Remove |

---

## Tips for Best Results

1. **Always request Doc Team diff format** - Add "Output in Doc Team diff format" to your prompt
2. **Run after QDoc build** to get current warnings
3. **Process one module at a time** for manageability
4. **Review skipped items** - public APIs need full docs
5. **Verify with rebuild** after applying fixes
6. **Use with warning files** for systematic processing

**Important:** If the agent outputs plain text suggestions instead of Doc Team diff format, remind it:
```
Use Doc Team diff format from skill-doc-diff for all suggestions.
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Process error file | `Fix warnings in [ERR.*] using qdoc-warning-fixer` |
| Fix module | `Fix QDoc warnings in [module] using qdoc-warning-fixer` |
| Fix specific file | `Fix warnings in [file] using qdoc-warning-fixer` |
| Paste warnings | `Fix these warnings using qdoc-warning-fixer: [paste]` |
| Undocumented only | `Fix undocumented warnings using qdoc-warning-fixer` |
| Link errors only | `Fix link warnings using qdoc-warning-fixer` |

---

## Key Points

- Agent **diagnoses and suggests fixes** for review
- **Verifies link targets** in index files before suggesting
- **Export + \internal is valid** for `*Private`, QPA, `_p.h` classes
- Output must be in **Doc Team diff format** (skill-doc-diff)
- **If agent forgets format**, remind: "Use Doc Team diff format"
- Always **rebuild QDoc** after applying fixes to verify

---

## Resources

- Agent: `~/.claude/agents/qdoc-warning-fixer.md`
- Skills: `~/.claude/skills/`
- QDoc Manual: https://doc.qt.io/qt-6/qdoc-index.html
- Doc Snapshots: https://doc-snapshots.qt.io/qt6-dev/

---

**Version**: 1.0
