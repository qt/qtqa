---
name: skill-doc-diff
description: Qt Doc Team diff format for documentation fixes that need human approval. Load before writing a suggestion in a review, warning fix, or scaffold.
metadata:
  version: "7.0.0"
  loading: "Pattern 1: agents embed the record schema (tools/doc-diff/README.md); this file is not loaded during a run. Pattern 3 (GATE) for references/. Tools render the view (Pattern 5/6)."
  ported-from: "documentation_review/skills/skill-doc-diff 5.22"
  verified: "2026-09-26"
  qdoc-version: "6.13.0"
  qttools-commit: "cff41040fa1fdc4c1cd957a7bf3e8d2ea23505c4"
  fitness: "2026-09-28; framework-fitness layers 1-4, 6, 7 (5, 8, 9 need an agent run); security-hygiene PASS"
---

# skill-doc-diff

The Doc Team diff is the output format for every actionable suggestion:
one numbered block per fix, with the evidence and checks a reviewer needs
to approve it. Used by pipeline A agents (review, warning fix) and
doc-shaper.

## Records (what agents write)

Since 7.0.0, agents don't write the Doc Team diff. They write **records**,
one JSON object per line, and tools render the view people read. The record
schema, the gate, and the render command live in
[`tools/doc-diff/README.md`](../../tools/doc-diff/README.md). Agents embed
the schema in their definition (Pattern 1), so they don't load this skill
during a run.

## Loading

This file is the reference for people and for the renderer. The sections
below describe the **rendered view**. Load a reference only when the step
needs it, and at most once per run:

| Step | Load |
|------|------|
| The Output field for a new page, the Validation rule-ID table, or an unfamiliar field. The field rules below cover the normal case | [`references/fields.md`](references/fields.md) |
| First suggestion of a run that rewrites prose; once per run, not per suggestion | [`references/verification.md`](references/verification.md) |
| Unsure what a finished block looks like | [`references/examples.md`](references/examples.md) |
| Format is `gerrit` or `plain`, or the commit names a bug | [`references/alt-formats.md`](references/alt-formats.md) |

## Deterministic first

The model writes the judgment fields (Cause, fix choice, Comments). Tools
produce everything else:

| Part | Tool |
|------|------|
| Header, Source, diff block (a git-style unified diff) | `tools/doc-diff/render_record.py RECORDS.jsonl --evidence EV.json --root SRC` |
| Diff applies to the file | `git apply --check` on the diff block (the renderer's selftest covers it) |
| Output field for a new page | the skill-qdoc-output algorithm, or `grep 'name="Type"'` in the `.index` files |
| Warning field | copy the line from the QDoc log (`tools/qdoc-warnings/parse_warnings.py`), never retype it |
| Line length (R40) | `verify_after.py` reports added lines over 80 columns |

Never type a diff by hand; the renderer builds it from the real file.

## Template

````markdown
**Suggestion N of X for {basename}:{line}:**

**Warning:** `{exact QDoc warning text}`
**Category:** {issue type}
**Source:** `{path/from/repo/root}`
**Output:** `{page.html}`

```diff
diff --git a/{path} b/{path}
--- a/{path}
+++ b/{path}
@@ -{old start},{count} +{new start},{count} @@
 {context}
-{removed}
+{added}
 {context}
```

**Cause:** {why it happens, with the evidence}

**Validation:**
- ✓/✗ {check}: {detail} ({rule ID})

**Comments:** {why the change matters, 1-2 sentences}

Should I apply this fix to the file?
````

With several valid fixes, put **Cause**, then **Fix Options** (numbered),
then **Recommended:** Option N because {reason}, before the diff. End with
`Which option should I apply? (1/2/3 or skip)`.

## Field rules

- **Order:** Warning, Category, Source, Output, then the diff, Cause,
  Validation, Comments, prompt.
- **Warning:** only for QDoc warnings. Verbatim, in backticks.
- **Category** and **Validation:** always.
- **Source:** full path from the repository root. Omit only when a single
  file is already established in the conversation.
- **Output:** the page where the edited text appears, not the link target.
  Add `(new)` for a page the change creates. **If you can't verify it, omit
  it. Never guess.**
- **Numbering:** count only actionable suggestions. Exemptions and
  "checked, no change" go in a `## Notes` section at the end, unnumbered.
- **Fix Options:** only when the codebase has no established pattern.
  Grep first; if one pattern exists, recommend it directly.
- **Diff:** a standard git unified diff (`diff --git`, `---`/`+++`, `@@`
  hunks, 3 context lines) in a ` ```diff ` fence, so it applies with
  `git apply`. Unchanged lines stay context, so an insertion shows only `+`
  lines. Changes under 10 lines apart share one block; over 20 lines apart
  get separate suggestions.
- **Prompt:** exactly `Should I apply this fix to the file?` (single fix).
  Answers: yes/y/ok/apply → apply with Edit; no/n/skip → skip;
  modify/change → revise.

## Output formats

| Format | Use | Where |
|--------|-----|-------|
| `doc-diff` | Default: full review with validation | this file |
| `gerrit` | Inline Gerrit comments with `suggestion` blocks | [`alt-formats.md`](references/alt-formats.md) |
| `plain` | Quick summary, one line per issue | [`alt-formats.md`](references/alt-formats.md) |
| `codereview` | A document that explains each proposed change, for sharing | [`alt-formats.md`](references/alt-formats.md) |

All four formats render from the same records and evidence with
`render_record.py --format`. No format costs extra model tokens.

## Related skills

- `skill-qdoc`: warning diagnosis, link checks (`references/link-diagnosis.md`)
- `skill-qdoc-output`: output filenames
- `skill-c-rules`, `skill-r-rules`, `skill-g-rules`: the rule IDs cited in Validation
- `skill-security-hygiene`: no secrets or personal data in suggestion text

**Changelog:** [`CHANGELOG.md`](CHANGELOG.md)
