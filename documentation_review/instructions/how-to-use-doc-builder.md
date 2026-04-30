# How to Use the Doc Builder Agent

Build Qt documentation locally. Handles environment setup, dependency
detection, and build execution for Qt modules and PySide.

## Prerequisites

Agent must be in `~/.claude/`:
```
~/.claude/
├── CLAUDE.md
└── agents/doc-builder.md
```

**System requirements:**
- macOS or Linux
- Git, CMake, Ninja, Python 3
- Qt installation (via Qt Online Installer)
- LLVM/Clang (for QDoc's parser)
- SSH access to codereview.qt-project.org (to clone repos)

---

## When to Use This Agent

Use **doc-builder** for:
- Building documentation for a Qt module locally
- Setting up a doc build environment on a new machine
- Troubleshooting doc build failures
- Building PySide documentation
- Testing doc changes before submitting a patch

Use **qdoc-warning-fixer** instead for:
- Fixing specific QDoc warnings (the builder finds them, the fixer
  resolves them)

Use **qt-doc-reviewer** instead for:
- Reviewing documentation content, language, and style

---

## Example Prompts

### First-Time Setup
```
run doc-builder: set up doc build environment
run doc-builder: check if I can build docs
```

### Build Qt Module Docs
```
run doc-builder: build qt6 docs
run doc-builder: build docs for qtwayland
run doc-builder: build html_docs_qtcore
```

### Build PySide Docs
```
run doc-builder: build pyside documentation
```

### Troubleshooting
```
run doc-builder: why did my doc build fail
run doc-builder: fix my doc build environment
```

---

## What It Does

1. **Pre-flight checks** — Detects platform, verifies tools (git,
   cmake, ninja, python3, LLVM), finds Qt installation
2. **Environment setup** — Offers to install missing tools, sets PATH
   and environment variables
3. **Build execution** — Runs CMake + Ninja, direct QDoc, or PySide
   setup.py depending on the product
4. **Output reporting** — Locates HTML output and warning logs,
   summarizes warning counts

## Build Methods

| Method | Use Case |
|--------|----------|
| CMake + Ninja | Full Qt super-repo or module builds |
| Direct QDoc | Single module without full CMake setup |
| setup.py | PySide documentation |

## Important Notes

- On macOS, install GNU coreutils (`brew install coreutils`) — Qt
  build scripts use GNU-specific commands
- On macOS, use Qt 6 qdoc even for Qt 5 projects (Qt 5 qdoc has
  `--single-exec` bugs)
- Qt documentation index files are at `~/Qt/Docs/` — use
  `qmake -query QT_INSTALL_DOCS` to find the path

## Tips

- Have the Qt super-repo (`qt5.git`) cloned locally for full builds
- Pre-built Qt documentation (index files) enables cross-module linking
- Use `ninja html_docs_<Module>` to build a single module faster
