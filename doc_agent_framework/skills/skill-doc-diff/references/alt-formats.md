# Alternative formats and bug report verification

Back to [`skill-doc-diff`](../SKILL.md).

## Gerrit format

For inline comments on Gerrit. A plain-text comment, then a `suggestion`
block with only the replacement text, in its original indentation.

````
{Rule}: {short explanation}

```suggestion
    {replacement text, original indentation}
```
````

Example:

````
G1: Passive "is needed". Use active voice.

```suggestion
    The \c update() function returns a timestamp that tells you when
    the engine needs the next update.
```
````

- No Markdown in the comment text. Gerrit shows plain text.
- The suggestion block holds only the replacement text.
- One line of explanation is best.
- Before posting, apply skill-security-hygiene: the comment is public.

## Plain format

For quick summaries without validation.

```
Line X: {issue}. Fix: {replacement}
```

```
Line 42: Passive voice (G1). Fix: "when the engine needs the next update"
Line 58: Missing \c markup. Fix: \c{file://}
```

## Codereview format

For sharing: a document that explains each proposed change to people who
weren't in the run (reviewers, module maintainers). The model writes
nothing extra; the tool renders it from the records and the evidence:

```
tools/doc-diff/render_record.py RECORDS.jsonl --evidence EVIDENCE.json --root SRC \
    --format codereview [--verify VERIFY.json] > proposed-changes.md
```

Each change has four parts:

| Part | From |
|------|------|
| **Reported by QDoc** | the evidence (verbatim warning) |
| **What changes** | the diff block, rendered from the file |
| **Why** | the record's `cause`; **Alternatives considered** from `options`, with the chosen one marked |
| **Checks** | evidence values, verify_after, verify_fix (with `--verify`), and the `judge` entries marked "(judgment)" |

Share the rendered file and keep the records and the evidence next to it, so every
claim can be traced. Before sharing outside the team, apply skill-security-hygiene.

## Bug report verification

When the commit names a bug (`Task-number:`, `Fixes:`), the orchestrator
fetches it (see `agents/orchestrator.md`) and passes the context to the agent.
Report it before the suggestions:

```markdown
## Bug Report Verification

**Task-number:** QTBUG-XXXXX
**Issue:** {one-line summary of the report}
**Verdict:** ✓ The patch addresses the reported issue
```

Use `✗` with a reason if it doesn't. If the tracker can't be reached, write
"Unable to verify (bug tracker inaccessible)" and continue the review.
