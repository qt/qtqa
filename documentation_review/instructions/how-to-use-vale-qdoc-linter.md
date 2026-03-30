# How to Use Vale QDoc Linter Agent

Lint QDoc source files using the patched Vale build with QDoc parser support.
Checks prose style, grammar, and QDoc-specific rules against staged changes,
individual files, or an entire directory tree.

## Prerequisites

Agent and skill must be in the `documentation_review` directory in qtqa:
```
documentation_review/
├── agents/vale-qdoc-linter.md
└── skills/
    └── skill-vale-qdoc-lint/
        └── SKILL.md
```

The agent will guide you through setup if the patched Vale binary or qtqa
config is not yet available.

---

## When to Use This Agent

Use **vale-qdoc-linter** for:
- Checking prose style issues in `.qdoc`, `.qdocinc`, `.qml`, and `.cpp`
  doc-comment blocks before committing
- Running Vale on all QDoc files in a directory (e.g. a full module audit)
- Setting up the Vale QDoc toolchain from scratch on a new machine
- Installing the pre-commit hook that runs Vale automatically on `git commit`

Use **qt-doc-reviewer** instead for:
- Full documentation patch reviews (QDoc syntax, templates, linking, alt text)
- Grammar and style review based on Qt Writing Guidelines (R1-R64)
- Gerrit patch review

---

## Example Prompts

### First-time setup
```
Set up vale-qdoc linting using vale-qdoc-linter.
```

### Lint staged changes
```
Lint my pending changes using vale-qdoc-linter.
```

### Lint all QDoc files in a directory
```
Lint all qdoc files under src/corelib/doc using vale-qdoc-linter.
```

### Lint specific files
```
Lint these files using vale-qdoc-linter:
src/corelib/doc/src/objectmodel.qdoc
src/corelib/doc/src/threads.qdoc
```

### Install the pre-commit hook
```
Install the vale pre-commit hook in this repository using vale-qdoc-linter.
```

### Check setup status
```
Check whether vale-qdoc is set up correctly using vale-qdoc-linter.
```

---

## What the Agent Checks

Rules are configured in `vale_linter_config/.vale-qdoc.ini`. Active checks:

| Rule | Category | What it catches |
|------|----------|----------------|
| `Qt.QDocBrief` | QDoc | `\brief` not ending with a period |
| `Qt.QDocPageTitle` | QDoc | `\title` not ending with a period |
| `Qt.QDocImageAlt` | QDoc | `\image` or `\inlineimage` missing alt text |
| `Qt.Headings` | QDoc | Section headings with incorrect capitalisation |
| `Qt.Spelling` | Spelling | Misspelled words (Qt vocabulary-aware) |
| `Qt.LoseLoose` | Grammar | "loose" vs "lose" confusion |
| `Qt.Repetition` | Grammar | Repeated words |
| `Microsoft.Passive` | Style | Passive voice constructions |
| `Microsoft.Wordiness` | Style | Wordy phrases ("in order to", "provides a way to") |
| `Microsoft.We` | Style | First-person plural ("we", "our") |
| `Microsoft.Dashes` | Style | Incorrect dash usage |
| `Microsoft.Headings` | Style | Heading capitalisation |
| `Microsoft.SentenceLength` | Style | Sentences over 30 words |
| `Microsoft.OxfordComma` | Style | Missing Oxford comma (suggestion level) |
| `Microsoft.Semicolon` | Style | Sentences that may be simplified (suggestion level) |
| `Vale.Terms` | Terminology | Qt vocabulary terms used with incorrect capitalisation |
| `Vale.Avoid` | Terminology | Discouraged terms from the Qt vocabulary reject list |
| `Microsoft.Spacing` | Style | Double spaces after punctuation |
| `Microsoft.HeadingAcronyms` | Style | Acronyms used in headings |
| `Microsoft.HeadingColons` | Style | Capitalisation after colons in headings |
| `Microsoft.HeadingPunctuation` | Style | End punctuation in headings |

Files covered: `.qdoc`, `.qdocinc`, `.qml`, `.cpp`, `.h`, `.cc`, `.cxx` (doc-comment blocks only for C++ source files).

---

## Setup Workflow

When the patched Vale binary or config is not yet available, the agent
walks through setup step by step — **asking approval before each action**:

1. Detects whether the latest patched Vale binary is installed.
2. Downloads the correct binary for your platform if missing.
3. Asks whether qtqa is already cloned somewhere on your filesystem.
   If yes, uses that clone (checks out `dev`). If not, does a shallow
   sparse clone of `vale_linter_config/` only.
4. Downloads the Microsoft style package via `vale sync` if missing.
5. Offers to save all answers to `~/.vale-qdoc-agent.json` so setup is
   not repeated next time.

---

## Expected Output

### Lint staged changes — annotated diff

```
diff --git a/src/corelib/doc/src/objectmodel.qdoc b/src/corelib/doc/src/objectmodel.qdoc
@@ -42,7 +42,7 @@
 /*!
     \class QObject
-    \brief The QObject class is the base class of all Qt objects
+    \brief The QObject class is the base class of all Qt objects.
^^^ warning  Qt.QDocBrief: Brief descriptions should end with a period.
     \inmodule QtCore
```

### Lint all files — grouped listing

```
src/corelib/doc/src/objectmodel.qdoc
  42:5    warning   Qt.QDocBrief      Brief descriptions should end with a period.
  78:1    warning   Microsoft.Passive  Consider using active voice.

src/corelib/doc/src/threads.qdoc
  15:1    warning   Microsoft.We      Avoid using first-person plural.

2 files, 3 issues.
```

---

## Common Scenarios

### New machine — set up everything at once
```
Set up vale-qdoc linting and install the pre-commit hook using vale-qdoc-linter.
```
The agent runs `setup` then `install-hook`, asking approval at each step.

### Before pushing a commit to Gerrit
```
Lint my pending changes using vale-qdoc-linter.
```
The agent runs the pre-commit hook on staged files and shows an annotated diff.

### Module-wide prose audit
```
Lint all qdoc files under qtdeclarative/src/quick/doc using vale-qdoc-linter.
Show a grouped summary by file.
```

### Re-running after fixing issues
```
Lint my pending changes again using vale-qdoc-linter.
```
Setup is skipped (config loaded from `~/.vale-qdoc-agent.json`); Vale runs
directly on the updated staged changes.

### Checking a single file without staging it
```
Lint src/corelib/doc/src/objectmodel.qdoc using vale-qdoc-linter.
```

### Verifying the hook is active
```
Check whether the vale pre-commit hook is installed in this repository
using vale-qdoc-linter.
```

---

## Quick Reference

| Task | Prompt |
|------|--------|
| First-time setup | `Set up vale-qdoc linting using vale-qdoc-linter` |
| Lint staged changes | `Lint my pending changes using vale-qdoc-linter` |
| Lint a directory | `Lint all qdoc files under <path> using vale-qdoc-linter` |
| Lint specific files | `Lint <file1> <file2> using vale-qdoc-linter` |
| Install hook | `Install the vale pre-commit hook using vale-qdoc-linter` |
| Check setup | `Check whether vale-qdoc is set up using vale-qdoc-linter` |

---

## Key Points

- The agent **asks approval before every action** — no downloads or file
  writes happen without confirmation.
- Setup answers are saved to **`~/.vale-qdoc-agent.json`** and reused on
  subsequent runs. Saved paths are validated on startup.
- **Standard Vale** does not understand `.qdoc` files — always use the
  latest patched build from the veshivas/vale releases.
- Duplicate alerts for `\brief`, `\title`, and `\section*` text are
  **automatically deduplicated** in the report.
- **`python3` must be on PATH** — the pre-commit hook requires it (not
  listed in the Vale README).

---

## Resources

- Agent: `documentation_review/agents/vale-qdoc-linter.md` (in qtqa)
- Skill: `documentation_review/skills/skill-vale-qdoc-lint/SKILL.md` (in qtqa)
- Patched Vale releases: https://github.com/veshivas/vale/releases
- Vale documentation: https://vale.sh/docs/
- Qt Writing Guidelines: https://wiki.qt.io/Qt_Writing_Guidelines

---

**Version**: 1.0
