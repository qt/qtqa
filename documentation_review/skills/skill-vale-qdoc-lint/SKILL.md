---
name: skill-vale-qdoc-lint
description: >-
  Vale binary setup, qtqa sparse-clone procedure, persisted config,
  pre-commit hook installation, lint commands, annotated diff and
  grouped report formats, known caveats
metadata:
    version: "1.0"
---

# skill-vale-qdoc-lint

Knowledge for the `vale-qdoc-linter` agent: detecting and installing the
patched Vale binary, running Vale on QDoc sources, and formatting the results.

---

## Persisted configuration

The agent saves answers to setup questions in `~/.vale-qdoc-agent.json` so
they are not asked again on subsequent runs.

### Config file location

`~/.vale-qdoc-agent.json`

### Fields

```json
{
  "vale_qdoc_bin": "/path/to/vale-qdoc",
  "qtqa_path": "/path/to/qtqa",
  "vale_config_path": "/path/to/qtqa/vale_linter_config/.vale-qdoc.ini"
}
```

### Read at startup

At the start of every run, check whether `~/.vale-qdoc-agent.json` exists
and load any fields present. Use loaded values in place of asking the user.
Only ask for values that are missing from the file or that no longer resolve
(e.g. a saved binary path that no longer exists).

### Write after setup

After any setup step that produces a new value (binary installed, qtqa path
confirmed, config path resolved), update the corresponding field in
`~/.vale-qdoc-agent.json`. Ask approval before writing:

> "I will save the setup answers to `~/.vale-qdoc-agent.json` so you won't
> be asked again. May I write the file?"

### Stale value handling

Before using a saved path, verify it still exists:
- `vale_qdoc_bin`: check the file is executable
- `qtqa_path`: check `<qtqa_path>/vale_linter_config/.vale-qdoc.ini` exists
- `vale_config_path`: check the file exists

If a saved value is stale, inform the user and re-run the relevant setup step.

---

## Patched Vale binary

System Vale does **not** have QDoc parser support. The patched build is
required for `.qdoc`, `.qdocinc`, `.qml`, and `.cpp` doc-comment linting.

### Detection

```sh
VALE_BIN="${VALE_QDOC_BIN:-$(command -v vale 2>/dev/null)}"
$VALE_BIN --version   # patched build version string contains "qdocsupport"
```

### Download

Releases: https://github.com/veshivas/vale/releases

Resolve the latest release by `published_at` timestamp (includes pre-releases):
```sh
TAG=$(curl -fsSL https://api.github.com/repos/veshivas/vale/releases \
      | python3 -c "
import json, sys
releases = json.load(sys.stdin)
latest = max(releases, key=lambda r: r['published_at'])
print(latest['tag_name'])
")
VER=${TAG#v}   # strip leading "v" for asset filenames
```

| OS + arch       | Asset                                          |
|-----------------|------------------------------------------------|
| macOS (any)     | `vale_${VER}_macOS_all.tar.gz`                 |
| Linux x86_64    | `vale_${VER}_Linux_64-bit.tar.gz`              |
| Linux ARM64     | `vale_${VER}_Linux_arm64.tar.gz`               |
| Windows x86_64  | `vale_${VER}_Windows_64-bit.zip`               |

Base URL: `https://github.com/veshivas/vale/releases/download/${TAG}/`

Binary inside archive: `vale` (Linux/macOS) or `vale.exe` (Windows).

```sh
# macOS — installed as vale-qdoc to avoid shadowing system vale
curl -L <base-url>/<asset> | tar -xz -C ~/.local/bin/ vale
mv ~/.local/bin/vale ~/.local/bin/vale-qdoc
chmod +x ~/.local/bin/vale-qdoc
export VALE_QDOC_BIN=~/.local/bin/vale-qdoc
```

---

## qtqa and vale_linter_config

The Vale config, styles, vocabulary, and pre-commit hook all live under
`qtqa/vale_linter_config/`.

### Locating an existing clone

Ask the user first. If they provide a path:
```sh
cd <provided-path>
git fetch origin dev && git checkout dev
```

Set `VALE_CONFIG_PATH=<provided-path>/vale_linter_config/.vale-qdoc.ini`.

### Shallow sparse clone (if not already available)

```sh
git clone --depth=1 --filter=blob:none --sparse --branch dev \
    https://code.qt.io/qt/qtqa.git <directory>
cd <directory>
git sparse-checkout set vale_linter_config
```

### Microsoft style package (vale sync)

Required before first use. Check whether `styles/Microsoft/` exists; if not:
```sh
cd <vale_linter_config-path>
$VALE_QDOC_BIN --config=.vale-qdoc.ini sync
```

---

## Environment variables

```sh
export VALE_QDOC_BIN=/path/to/vale-qdoc          # patched binary
export VALE_CONFIG_PATH=/path/to/qtqa/vale_linter_config/.vale-qdoc.ini
```

**Silent-skip pitfall**: if `VALE_QDOC_BIN` is unset and `vale` is not on
PATH, or if `VALE_CONFIG_PATH` is missing, the hook exits 0 and lints nothing.
Always verify after setup.

**python3 required**: the pre-commit hook embeds a Python3 script.
`python3` must be on PATH.

---

## Pre-commit hook installation

The hook (`vale_linter_config/vale-pre-commit`) lints only changed lines of
staged files — column-precise for single-line edits.

### Check first
```sh
[ -e <repo>/.git/hooks/pre-commit ] && echo "exists" || echo "missing"
```

### Symlink as `pre-commit-vale`
```sh
ln -sf <qtqa>/vale_linter_config/vale-pre-commit <repo>/.git/hooks/pre-commit-vale
```

### No existing `pre-commit` — create one

Create `<repo>/.git/hooks/pre-commit` containing:
```sh
#!/bin/sh
"<qtqa>/vale_linter_config/vale-pre-commit" || exit 1
```
Then make it executable: `chmod +x <repo>/.git/hooks/pre-commit`.

### Existing hook (e.g. clang-format) — prepend

Add at the **very top**, before any early exits (clang-format has an `exit 0`
guard that would swallow anything placed after it):
```sh
"<qtqa>/vale_linter_config/vale-pre-commit" || exit 1
```

---

## Running Vale

### Lint staged changes (via pre-commit hook)

Filters alerts to changed lines only, column-precise:
```sh
VALE_QDOC_BIN=... VALE_CONFIG_PATH=... \
  <qtqa>/vale_linter_config/vale-pre-commit
```

### Lint all files in a directory tree

```sh
$VALE_QDOC_BIN --config=$VALE_CONFIG_PATH --output=line <directory>
```

### Lint specific files

```sh
$VALE_QDOC_BIN --config=$VALE_CONFIG_PATH --output=line <file1> <file2> ...
```

### Output format (`--output=line`)

```
/abs/path/file.qdoc:16:35:Qt.QDocBrief:Brief descriptions should end with a period.
```

Fields: `filepath:line:col:check:message`. **Severity is absent.**

To look up severity: read `level:` from `styles/<Style>/<Rule>.yml`
(e.g. `styles/Qt/QDocBrief.yml` → `level: warning`).

---

## Report formats

### Annotated diff (for staged changes)

Print `git diff --cached -U3` per affected file, inserting a `^^^` warning
line immediately below each `+` line that triggered an alert:

```
diff --git a/doc/src/myfile.qdoc b/doc/src/myfile.qdoc
@@ -15,4 +15,4 @@
 /*!
-    \brief Old brief description
+    \brief New brief without period
^^^ warning  Qt.QDocBrief: Brief descriptions should end with a period.
     \since 6.8
```

### Grouped listing (for full-file or directory lint)

```
doc/src/myfile.qdoc
  16:35   warning   Qt.QDocBrief       Brief descriptions should end with a period.
  23:1    warning   Microsoft.Passive  In general, use active voice.

1 file, 2 issues.
```

### Deduplication

Deduplicate alerts by `(file, line, col, check)` before formatting.
**Why**: broad-scoped rules (e.g. `Microsoft.We`) fire twice on `\brief`,
`\title`, and `\section*` lines due to a known parser bug in Vale's
`GetComments` (`internal/lint/code/comments.go`). This is not fixable from
config alone.

---

## Known caveats

- **`Microsoft.OxfordComma`** is `level: suggestion`. Only shown when
  `MinAlertLevel = suggestion` in `.vale-qdoc.ini`.
- **`.cpp`/`.h` linting** requires `cpp = qdoc` in `[formats]` and the
  patched Vale build. Standard Vale ignores `.cpp` doc-comment blocks.
- **`--output=line` lacks severity** — always look it up from rule YAML.

---

## Version History

- **v1.0** (2026-03-30): Initial version
  - Persisted config (`~/.vale-qdoc-agent.json`): fields, read/write/stale handling
  - Patched Vale binary: detection, download procedure, asset table by platform
  - qtqa and `vale_linter_config`: locating existing clone, shallow sparse clone,
    `vale sync` for Microsoft style package
  - Environment variables (`VALE_QDOC_BIN`, `VALE_CONFIG_PATH`) and silent-skip pitfall
  - Pre-commit hook installation: symlink, new hook, prepend to existing hook
  - Running Vale: staged changes, directory tree, specific files
  - `--output=line` format and severity lookup
  - Report formats: annotated diff and grouped listing
  - Deduplication by `(file, line, col, check)` and reason
  - Known caveats: `Microsoft.OxfordComma` level, `.cpp`/`.h` linting, severity absence
