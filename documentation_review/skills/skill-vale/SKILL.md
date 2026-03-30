---
name: skill-vale
description: Generic Vale configuration reference — config file resolution, StylesPath, vale sync, format detection, MinAlertLevel, exit codes, and common error diagnosis
metadata:
    version: "1.0"
---

# skill-vale

Reference for diagnosing Vale configuration and lint issues: config file
resolution, style loading, package sync, format detection, and common error
messages.

---

## How Vale resolves configuration

Vale searches for `.vale.ini` starting from the directory of the file being
linted and ascending the directory tree until it finds one. A `--config` flag
overrides this search entirely.

```sh
# Use an explicit config — bypasses auto-discovery
$VALE_QDOC_BIN --config=/path/to/.vale-qdoc.ini <files>
```

**Common mistake**: running Vale from a directory that has its own `.vale.ini`
higher up the tree. The wrong config is picked up silently. Use `ls-config` to
confirm which config is active:

```sh
$VALE_QDOC_BIN ls-config
```

This prints the fully resolved configuration as JSON, including the absolute
`StylesPath`, loaded styles, and `MinAlertLevel`. Use it as the first
debugging step whenever output looks wrong.

---

## StylesPath

`StylesPath` is the directory Vale searches for style folders and packages.
It must be set correctly in `.vale.ini` or Vale cannot find any rules.

```ini
StylesPath = styles
```

Relative paths are resolved from the location of the `.vale.ini` file, not
from the working directory. If `ls-config` shows an unexpected `StylesPath`,
check the path relative to the config file.

**Symptoms of a wrong StylesPath:**

- Zero alerts on files that should trigger rules
- `unknown style` error in output
- `vale sync` downloads to a different location than expected

---

## vale sync — downloading style packages

`vale sync` downloads and installs all packages listed under `Packages` in
`.vale.ini` into `StylesPath`. Always run it from the directory containing
the config file, or use `--config`:

```sh
cd <vale_linter_config-path>
$VALE_QDOC_BIN --config=.vale-qdoc.ini sync
```

**What sync does:**

- Style-only packages (e.g. `Microsoft`): extracts the style folder into
  `StylesPath/Microsoft/`
- Config-only packages: adds files to `StylesPath/.vale-config/`
- Complete packages: merges both

**Sync does not run automatically** — if `styles/Microsoft/` is absent,
rules from that package silently produce no alerts.

**Check after sync:**

```sh
ls <StylesPath>/Microsoft/
```

If the directory is empty or missing, re-run sync with the correct config.

---

## Rule files not found

Vale loads rules by looking up `StylesPath/<Style>/<Rule>.yml` for each entry
in `BasedOnStyles`.

**Rule is silently skipped if:**

- The file has a `.yaml` extension instead of `.yml` — Vale only detects `.yml`
- The style folder name does not exactly match the name in `BasedOnStyles`
- `StylesPath` points to the wrong directory

**Confirm a rule exists:**

```sh
ls <StylesPath>/Qt/QDocBrief.yml
```

**Confirm a rule's severity:**

```sh
grep 'level:' <StylesPath>/Qt/QDocBrief.yml
```

Note: `--output=line` does not include severity in its output. Always look it
up from the rule YAML directly.

---

## Format detection and the [formats] section

Vale determines how to parse a file from its extension. Extensions not
recognised by Vale default to plain text (no markup parsing).

Map unknown extensions to a supported format in `.vale.ini`:

```ini
[formats]
qdoc    = md
qdocinc = md
cpp     = qdoc
```

The patched Vale build adds `qdoc` as a built-in format. Standard Vale does
not recognise `.qdoc` or `.qdocinc` files — they are treated as plain text,
meaning markup-scoped rules (headings, paragraphs) do not fire.

**Verify format routing:**

```sh
$VALE_QDOC_BIN ls-config | grep -A5 '"Formats"'
```

---

## MinAlertLevel

Controls which severity levels appear in output.

```ini
MinAlertLevel = warning   # shows warning, error (suppresses suggestion)
MinAlertLevel = suggestion # shows all levels
MinAlertLevel = error      # shows error only
```

If expected alerts are missing and the rule YAML shows `level: suggestion`,
the alert is suppressed by `MinAlertLevel`. Lower the threshold to expose it.

---

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | No alerts at or above `MinAlertLevel` |
| `1` | One or more lint alerts found |
| `2` | Runtime error (config not found, binary error, etc.) |

Exit code `2` indicates a configuration or runtime problem, not a lint result.
Check stderr for the error message.

---

## Common diagnostic commands

| Goal | Command |
|------|---------|
| Show resolved config | `$VALE_QDOC_BIN ls-config` |
| Show default config dirs | `$VALE_QDOC_BIN ls-dirs` |
| Show supported env vars | `$VALE_QDOC_BIN ls-vars` |
| Check binary version | `$VALE_QDOC_BIN --version` |
| Sync packages | `$VALE_QDOC_BIN --config=<ini> sync` |
| Lint with explicit config | `$VALE_QDOC_BIN --config=<ini> --output=line <file>` |
| Treat file as plain text | `$VALE_QDOC_BIN --ignore-syntax <file>` |
| Filter by rule | `$VALE_QDOC_BIN --filter='Rule == "Qt.QDocBrief"' <file>` |

---

## Common error messages

### `unknown style 'X'`

`BasedOnStyles` references a style folder that does not exist under
`StylesPath`. Check that the folder name matches exactly (case-sensitive on
Linux) and that `vale sync` has been run.

### No output / zero alerts

Possible causes (check in order):

1. `VALE_QDOC_BIN` or `VALE_CONFIG_PATH` is unset — hook exits 0 silently
2. `MinAlertLevel` is set higher than the rule's `level:`
3. `StylesPath` is wrong — rules not loaded
4. File extension not mapped in `[formats]` — parsed as plain text
5. Rule file uses `.yaml` extension instead of `.yml` — silently skipped

### `could not find .vale.ini`

Vale searched from the current directory up to the filesystem root and found
no config file. Use `--config` to point directly to the correct `.vale.ini`.

### Rule fires twice on the same line

Known parser bug in Vale's `GetComments` for broad-scoped rules applied to
`\brief`, `\title`, and `\section*` lines. Deduplicate by
`(file, line, col, check)` before presenting results — this is not fixable
from config.

---

## YAML rule authoring pitfalls

- **Extension must be `.yml`**, not `.yaml` — Vale silently ignores `.yaml`
- **Regex patterns must be quoted** — unquoted patterns may be misread by the
  YAML parser; prefer single quotes (`'pattern'`)
- **`\b` word boundaries** are added automatically by `existence` and
  `substitution` rules; set `nonword: true` to disable
- **Scope `raw`** applies a rule to the unprocessed source file, bypassing
  markup parsing — useful when a rule needs to match markup syntax itself

---

## Version History

- **v1.0** (2026-03-30): Initial version
  - Vale config file resolution and `ls-config` debugging
  - `StylesPath` resolution and common symptoms of misconfiguration
  - `vale sync` package download procedure
  - Rule file detection (`.yml` vs `.yaml`, style folder matching)
  - Format detection and the `[formats]` section
  - `MinAlertLevel` and exit codes
  - Common diagnostic commands table
  - Common error messages: `unknown style`, zero alerts, config not found,
    duplicate rule-fires
  - YAML rule authoring pitfalls

