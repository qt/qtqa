# How to Use Qt Doc Reviewer Agent

Review documentation patches for Qt projects. Checks for QDoc warnings, syntax, language, style, and alt text compliance.

## Prerequisites

Agent and skills must be in `~/.claude/`:
```
~/.claude/
├── agents/qt-doc-reviewer.md
└── skills/
    ├── skill-doc-diff/
    ├── skill-language-style/
    ├── skill-qdoc/
    ├── skill-qdoc-output/
    ├── skill-alttext/
    ├── skill-line-wrap/
    └── skill-module-export/
```

---

## When to Use This Agent

Use **qt-doc-reviewer** for:
- Reviewing documentation patches before merge
- Pre-commit validation of doc changes
- Checking grammar, style, and language (R1-R57)
- Verifying QDoc syntax is correct
- Reviewing alt text on images
- Ensuring 80-column compliance

Use **qdoc-warning-fixer** instead for:
- Fixing existing QDoc build warnings
- Processing warning files (ERR.*)
- Adding `\internal` tags to undocumented classes

---

## Example Prompts

### Review Gerrit Patch
```
Review this Gerrit patch using qt-doc-reviewer.
Output suggestions in Doc Team diff format.
https://codereview.qt-project.org/c/qt/qtbase/+/123456
```

### Review Uncommitted Changes
```
Review my documentation changes using qt-doc-reviewer.
```

### Review Specific Commit
```
Review documentation in commit abc123 using qt-doc-reviewer.
```

### Review Specific File
```
Review documentation changes in src/corelib/doc/src/objectmodel.qdoc
using qt-doc-reviewer.
```

### Pre-Commit Review
```
Pre-commit review using qt-doc-reviewer.
Show me critical issues that would block the commit.
```

### Grammar and Style Only
```
Review my documentation for grammar and style issues only using qt-doc-reviewer.
```

### Critical Issues Only
```
Check for critical issues only using qt-doc-reviewer.
Focus on QDoc syntax errors and broken links.
```

---

## What the Agent Reviews

### Review Checklist (All Mandatory)

1. **Language** - **PRIMARY** - Grammar, voice, tense, terminology (R1-R57)
2. **QDoc Syntax** - Correct commands, proper usage
3. **Templates** - Required elements (`\brief`, `\since`, `\inmodule`)
4. **Linking** - Valid targets, correct `\l` vs `\c` usage
5. **Alt Text** - Images have proper alt text (if applicable)
6. **QUIP/MS Compliance** - Style guidelines
7. **Bug Report** - If referenced, verify patch addresses it

### Language Rules Checked

| Rule | Description |
|------|-------------|
| R1 | Active voice preferred |
| R2 | Concise language |
| R7, R38 | No Latin terms (via, e.g., i.e., etc.) |
| R10 | Articles present ("the X argument") |
| R17-R19 | API brief patterns |
| R40 | 80-column limit |

---

## Expected Output Format

All suggestions use **Doc Team diff format**:

```markdown
**Suggestion 1 of 3 for qtquickcontrols-buttons.qdoc:45:**

**Category:** Grammar

**Source:** `qtquickcontrols/doc/src/qtquickcontrols-buttons.qdoc`
**Output:** `qtquickcontrols-buttons.html`

```diff
    43→    The button component provides an interactive control
    44→
  - 45→    that accepts a ID parameter for tracking.
  +   →    that accepts an ID parameter for tracking.
    46→
    47→    See the example below for usage.
```

**Cause:** Incorrect article before vowel sound. "ID" is pronounced with vowel sound.

**Validation:**
- ✓ Grammar: "an ID" correct article before vowel sound (R10)
- ✓ Line length: 52 characters (R40)

**Comments:** Correct article usage improves professional quality.

Should I apply this fix to the file?
```

---

## Tips for Best Results

1. **Always request Doc Team diff format** - Add "Output in Doc Team diff format" to your prompt
2. **Be specific about scope** - commit hash, file path, or "uncommitted changes"
3. **Request verbosity level** - "brief review" or "comprehensive review"
4. **Filter by issue type** - "grammar only" or "critical issues only"
5. **Review large patches incrementally** - file by file
6. **Ask for explanations** - "Why is passive voice discouraged?"

**Important:** If the agent outputs plain text suggestions instead of Doc Team diff format, remind it:
```
Use Doc Team diff format from skill-doc-diff for all suggestions.
```

---

## Common Scenarios

### Pre-Gerrit Upload
```
Pre-commit review using qt-doc-reviewer.
Check my staged documentation changes before I push to Gerrit.
```

### Review Colleague's Patch
```
Review this Gerrit patch using qt-doc-reviewer:
https://codereview.qt-project.org/c/qt/qtdeclarative/+/567890

Give me a summary I can post as a review comment.
```

### Focus on Specific Issues
```
Review using qt-doc-reviewer but skip formatting issues.
We're in release freeze.
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Quick review | `Brief review using qt-doc-reviewer` |
| Full review | `Comprehensive review using qt-doc-reviewer` |
| Grammar only | `Grammar and style check using qt-doc-reviewer` |
| Critical only | `Critical issues only using qt-doc-reviewer` |
| Pre-commit | `Pre-commit review using qt-doc-reviewer` |
| Specific file | `Review [filepath] using qt-doc-reviewer` |
| Gerrit patch | `Review [gerrit-url] using qt-doc-reviewer` |

---

## Key Points

- Agent **reviews but does not modify** files without approval
- Uses **Qt Writing Guidelines, QUIP 25, and Microsoft Style Guide**
- All suggestions include **rule citations** (R1-R57)
- Output must be in **Doc Team diff format** (skill-doc-diff)
- **If agent forgets format**, remind: "Use Doc Team diff format"

---

## Resources

- Agent: `~/.claude/agents/qt-doc-reviewer.md`
- Skills: `~/.claude/skills/`
- Qt Writing Guidelines: https://wiki.qt.io/Qt_Writing_Guidelines
- QUIP 25: https://quips.qt.io/quip-0025

---

**Version**: 2.0
