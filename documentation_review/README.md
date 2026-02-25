# Qt Documentation Review Workflow for Claude Code

Agent-based workflow for reviewing Qt documentation patches, fixing QDoc warnings, and ensuring compliance with Qt Writing Guidelines.

## Installation

```bash
unzip qt-doc-review-workflow.zip -d ~/.claude/
```

## Contents

```
~/.claude/
├── CLAUDE.md                      # Dispatcher configuration
├── agents/
│   ├── qt-doc-reviewer.md         # Patch reviewer agent
│   └── qdoc-warning-fixer.md      # Warning fixer agent
├── skills/                        # Reference materials
│   ├── skill-doc-diff/            # Output format (mandatory)
│   ├── skill-language-style/      # Language rules R1-R51
│   ├── skill-qdoc/                # QDoc syntax and internals
│   ├── skill-qdoc-output/         # HTML filename patterns
│   ├── skill-alttext/             # Image alt text guidelines
│   ├── skill-line-wrap/           # 80-column rule
│   ├── skill-module-export/       # Qt export macros
│   └── skill-all-docs/            # Qt modules and products
└── instructions/
    ├── how-to-use-qt-doc-reviewer.md
    └── how-to-use-qdoc-warning-fixer.md
```

## Quick Start

### Review a Gerrit Patch
```
run doc reviewer on https://codereview.qt-project.org/c/qt/qtbase/+/123456
```

### Fix QDoc Warnings
```
fix these qdoc warnings using qdoc-warning-fixer: [paste warnings]
```
or
```
fix qdoc warnings in warnings.log using qdoc-warning-fixer
```

### Review Local Changes
```
review my documentation changes using qt-doc-reviewer
```

## Agent Documentation

Detailed usage instructions are in `~/.claude/instructions/`:

| Agent | Instructions | Purpose |
|-------|--------------|---------|
| qt-doc-reviewer | `how-to-use-qt-doc-reviewer.md` | Review patches before merge |
| qdoc-warning-fixer | `how-to-use-qdoc-warning-fixer.md` | Fix QDoc build warnings |

## Using with Claude Desktop (Cowork)

Claude Cowork provides file access in Claude Desktop without command line.

### Setup

1. Open **Claude Desktop** (macOS)
2. Start a new conversation
3. Click the **folder icon** to grant folder access
4. Select your Qt repository folder

### Loading Skills

At the start of your session:
```
Load all skills and agents from ~/.claude/
Use Doc Team diff format for all suggestions.
```

### Example Tasks

**Review a file:**
```
Load all skills from ~/.claude/

Review qtbase/src/corelib/doc/src/objectmodel/object.qdoc
Output suggestions in Doc Team diff format.
```

**Fix warnings (paste them in):**
```
I have these QDoc warnings:

/path/file.qdoc:45: warning: Can't link to 'QWidget'

Read the source files and suggest fixes in Doc Team diff format.
```

**Audit alt text:**
```
Find all \image commands in qtquick/doc/src/*.qdoc
Check if alt text follows skill-alttext guidelines.
```

### Claude Code vs Cowork

| Feature | Claude Code | Cowork |
|---------|-------------|--------|
| Shell commands | Yes | No |
| Git operations | Yes | No |
| Build QDoc | Yes | No |
| File read/edit | Yes | Yes |
| WebFetch | Yes | Yes |

**Use Claude Code for:** Builds, git, warning processing, Gerrit patches
**Use Cowork for:** Quick file reviews, reports, organizing

## Reference Links

- [Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines)
- [QDoc Manual](https://doc.qt.io/qt-6/qdoc-index.html)
- [Qt Doc Snapshots](https://doc-snapshots.qt.io/qt6-dev/)
- [QUIP 25](https://contribute.qt-project.org/quips/25)
- [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/)

## License

SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GFDL-1.3-no-invariants-only
