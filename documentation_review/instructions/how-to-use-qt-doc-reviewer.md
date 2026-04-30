# How to Use the Doc Reviewer Agent

Review documentation patches for Qt projects. Checks language (R1-R64), QDoc syntax, markup, linking, alt text, and 80-column compliance.

## Prerequisites

Agent and skills must be in `~/.claude/`:
```
~/.claude/
├── CLAUDE.md
├── agents/qt-doc-reviewer.md
└── skills/
    ├── skill-doc-diff/
    ├── skill-language-style/
    ├── skill-qdoc/
    ├── skill-qdoc-output/
    ├── skill-alttext/
    ├── skill-line-wrap/
    ├── skill-linking-check/
    ├── skill-module-export/
    └── skill-all-docs/
```

---

## When to Use This Agent

Use **qt-doc-reviewer** for:
- Reviewing documentation patches before merge
- Pre-commit validation of doc changes
- Checking grammar, style, and language (R1-R64)
- Verifying QDoc syntax and markup
- Reviewing alt text on images
- Ensuring 80-column compliance
- Checking link targets resolve in index files

Use **qdoc-warning-fixer** instead for:
- Fixing existing QDoc build warnings
- Processing warning files (ERR.*)
- Adding `\internal` tags to undocumented classes

Use **doc-impact-analyzer** instead for:
- Checking if a code change breaks documentation links
- Analyzing renames, removals, or API changes

---

## Example Prompts

**Important:** Always name the agent explicitly to ensure reliable routing.

### Review a Gerrit Patch
```
run doc reviewer on https://codereview.qt-project.org/c/qt/qtbase/+/593273
```

### Review with Gerrit-Ready Output
```
run doc reviewer on https://codereview.qt-project.org/c/qt/qtbase/+/593273 format: gerrit
```

### Review Local Changes
```
run doc reviewer on qtbase/src/corelib/doc/
```

### Review a Specific File
```
run doc reviewer on qtbase/src/gui/doc/src/richtext.qdoc
```

### Review with Plain Output (for Slack)
```
run doc reviewer on https://codereview.qt-project.org/c/qt/qtbase/+/593273 format: plain
```

---

## What It Checks

1. **Language audit (BLOCKING)** — Must complete before other checks
   - Line-by-line: R1-R10 (voice, tense, terminology), R11-R13 (grammar)
   - API patterns: R14-R19 (briefs, class/function/property docs)
   - Mandatory scans: Latin terms (R38), articles (R7), serial commas (R11), 80-column (R40), terminology (R3), title case (R12)
2. **Markup scan** — `\c` for code, `\l` for links, `\a` for parameters (R64)
3. **Admonitions** — `\note`/`\warning` usage and 8 anti-patterns (R63)
4. **Link verification (BLOCKING)** — Verifies `\l` targets in index files before suggesting
5. **Bug report alignment** — If commit references QTBUG, fetches it from Jira

## Output Format

Default is **Doc Team diff**. Each suggestion includes:
- **Category** — What kind of issue
- **Source** — Full file path
- **Output** — HTML page where it renders
- **Diff block** — Current text vs proposed fix with line numbers
- **Cause** — Why it's flagged, with evidence
- **Validation** — Checks performed with rule references

Request different formats by adding a suffix:
- `format: gerrit` — Inline comments for Gerrit code review
- `format: plain` — Quick summary
- `format: codereview` — Export to .md file

---

## Tips

- **Have sources locally.** The agent reads actual files to verify line numbers and link targets. Without local access, it can still review a diff but cannot perform verification.
- **Bug reports are automatic.** If the commit has a Task-number and the Atlassian MCP is configured, the agent fetches the bug and checks if the patch addresses it.
- **Suggestions are suggestions.** Always review before applying. The Cause and Validation fields show why and how each suggestion was verified.
