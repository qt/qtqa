# doc-diff

Deterministic parts of the Doc Team diff format
([`skill-doc-diff`](../../skills/skill-doc-diff/SKILL.md)). Every fix is
shown as a standard `git diff` (`diff --git`, `@@` hunks, 3 context lines)
in a `diff` fence. It copies and pastes into a prompt, an editor, or a
review, and it applies with `git apply`. The renderer builds it from the
real file, so line numbers and context never come from the model.

## Records (skill-doc-diff 7.0.0)

Since 7.0.0, agents don't write the Doc Team diff. They write **records**,
one JSON object per line, and these tools check and render the view people
read. Agents embed the schema below in their definition (Pattern 1), so
they don't load a skill during a run.

```json
{"id": 1, "warn": "W1", "file": "src/foo.cpp", "lines": [157, 157],
 "new": "    \\sa minimum", "rules": ["C1/R41"], "ev": ["W1.link.result", "W1.api.verdict"],
 "cause": "No setMin(); the setter is setMinimum(), which duplicates minimum.",
 "judge": [["sa-list-has-no-duplicate", true, "setMinimum() links to the same target as minimum"]],
 "options": null, "pick": null}
```

| Key | Rule |
|-----|------|
| `warn` | `W<n>` = `warnings[n]` in the evidence from `tools/qdoc-fix/evidence.py`, 0-based (the first is `W0`). Never retype the warning |
| `file`, `lines`, `new` | Path from the source root; the 1-based inclusive range replaced; the exact new text (`\n` between lines, `""` deletes) |
| `rules` | `C<n>/R<n>` or `C<n>/G<n>`, IDs from skill-c-rules, skill-r-rules, skill-g-rules. Not fix IDs |
| `ev` | Paths into the evidence (`W1.api.verdict`, `W1.snippet.3`). **Facts go here**, not in `cause` or `judge` |
| `cause` | At most 2 sentences, judgment only |
| `judge` | `[check, true/false, reason]`. Name the check as the property that must hold; `true` means it holds. Judgment only. A lookup result is evidence |
| `options`, `pick` | Only when the codebase has no established pattern: `[{"new", "why"}]` and the chosen 1-based index |

**Never delete content just to clear a warning.** A clean rebuild doesn't
justify it. A record with `"new": ""` that removes text needs
`["content-removed", true, reason]`; otherwise report the warning in Notes
(for example, a missing image asset).

**Gate (all must exit 0 before a record reaches a person):**

```
tools/doc-diff/lint_record.py RECORDS.jsonl --evidence EV.json --root SRC   # schema, IDs, evidence, lines
tools/doc-diff/verify_after.py RECORDS.jsonl                                # new text: R39 R40 R47 R68 R4, tells, secrets
tools/qdoc-fix/verify_fix.py --src SRC --qdocconf REL --fix N.diff ...      # rebuild: warning gone, nothing new
```

Then render with `render_record.py`. The orchestrator's LLM pass reviews
only `cause` and `judge` (Pattern 7). The tools:

- `lint_record.py`: schema, C/R/G rule IDs (parsed from the rule skills),
  evidence paths, line range, cause length, options, and content deletion.
- `verify_after.py`: the new text against R39, R40, R47, R68, R4, the Tier 1
  AI tells, and the secrets and home-path patterns (from `tools/check-artifact`).
- `render_record.py`: records + evidence → `doc-diff`, `gerrit`, `plain`, or
  `codereview`. It reads the real file and writes the header, Source, and
  the git diff.
- `execution_record.py`: an agent transcript → execution record JSON (prompt, model pinned vs
  actual, effort, time, requests, tokens, cost, classified tool calls, input and output files).
  `render_record.py --format audit --execution` adds it to the audit, with a machine-readable
  result summary.
- `records.py`: shared loading, evidence paths, and rule IDs.

```
lint_record.py RECORDS.jsonl --evidence EV.json --root SRC [--json]
verify_after.py RECORDS.jsonl [--json]
render_record.py RECORDS.jsonl --evidence EV.json --root SRC [--format F] [--verify VERIFY.json]
```

**Used by:** skill-doc-diff, and the pipeline A agents that write
suggestions. Tested by [`selftest_records.py`](selftest_records.py), which
checks that every rendered diff passes `git apply --check`. Stdlib only.
