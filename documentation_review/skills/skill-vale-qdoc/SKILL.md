---
name: skill-vale-qdoc
description: Vale QDoc parser fork reference — file routing by extension, QDoc scopes produced, code block exclusion, sentence-rule requirements, and common rule-not-firing causes
metadata:
    version: "1.0"
---

# skill-vale-qdoc

Reference for the vale-qdoc fork — the patched Vale build with QDoc parser
support. Covers file routing, scopes, config, and common lint issues.

---

## File routing

| Extension | Linted by default | Notes |
|-----------|-------------------|-------|
| `.qdoc`, `.qdocinc` | Yes | Full QDoc markup pipeline |
| `.cpp`, `.qml` | Yes, with opt-in | Requires `[formats]` entry (see below) |
| `.h`, `.cxx`, `.cc` | No | Add via `[formats]` the same way as `.cpp` |

Standard Vale treats `.qdoc` and `.qdocinc` as plain text — always use the
patched build.

### Enabling C++ and QML linting

Add to `.vale-qdoc.ini`:

```ini
[formats]
cpp  = qdoc
qml  = qdoc
h    = qdoc
cxx  = qdoc
```

Only `/*!...*/` doc-comment blocks are routed through the QDoc pipeline.
Regular `//` and `/* */` comments are skipped — they are not QDoc
documentation.

---

## Scopes produced

Rules target specific QDoc commands via these scopes:

| Scope | QDoc command |
|-------|-------------|
| `text.comment.heading` | `\section1`–`\section6` |
| `text.comment.brief` | `\brief` |
| `text.comment.note` | `\note` |
| `text.comment.warning` | `\warning` |
| `text.comment.title` | `\title` |
| `text.comment.block` | General multi-line prose (enables sentence rules) |
| `text.comment.line` | General single-line text |
| `meta.image` | `\image` / `\inlineimage` filename (no alt text only) |
| `meta.anchor` | `\target` / `\keyword` argument |

`meta.*` scopes prevent prose rules (`Vale.Terms`, `Microsoft.*`) from
firing on image filenames and anchor identifiers.

---

## Key caveats

### Code block content is excluded

Text inside `\code`…`\endcode`, `\badcode`…`\endcode`, and
`\qml`…`\endqml` blocks is not linted. `\badcode` ends with `\endcode`,
not `\endbadcode`. `\snippet` has no end counterpart.

### Sentence-scope rules require multi-line prose

Rules using `scope: sentence` (e.g. `Microsoft.OxfordComma`,
`Microsoft.SentenceLength`) only fire on `text.comment.block` — full prose
spanning a `/*!...*/` block. They do not fire on single-line scopes
(`heading`, `brief`, `title`).

### Duplicate alerts

Duplicate alerts for `\brief`, `\note`, and `\warning` were fixed in
v3.14.2-qdocsupport-alpha1. If duplicates appear for any command, report
them as a bug.

---

## Generic Vale issues

For issues not specific to QDoc — config file resolution, `StylesPath`,
`vale sync`, exit codes, `ls-config` — see **skill-vale**
(`skills/skill-vale/SKILL.md`).

---

## Common "rule not firing" causes

1. **Wrong extension** — `.cpp`/`.qml`/`.h` not mapped in `[formats]`; file
   treated as plain C++ code, not QDoc.
2. **Rule scoped too narrowly** — a rule scoped to `text.comment.brief` will
   not fire on `text.comment.line` or `text.comment.block`.
3. **Content inside a code block** — excluded from linting by design.
4. **Sentence rule on a one-line brief** — `scope: sentence` requires
   multi-line prose; single-line commands are not sentence-segmented.
5. **`MinAlertLevel` too high** — check the rule's `level:` in its `.yml`
   file and compare against `MinAlertLevel` in `.vale-qdoc.ini`.

---

## Version History

- **v1.0** (2026-03-30): Initial version
  - File routing table for `.qdoc`, `.qdocinc`, `.cpp`, `.qml`, `.h`, `.cxx`
  - Enabling C++ and QML linting via `[formats]`
  - Scopes produced by the QDoc parser for all QDoc commands
  - `meta.*` scopes for image filenames and anchor identifiers
  - Key caveats: code block exclusion, sentence-scope rules, duplicate alerts
  - Cross-reference to skill-vale for generic Vale issues
  - Common "rule not firing" causes

