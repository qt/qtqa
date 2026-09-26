# Suggestion verification

Back to [`skill-doc-diff`](../SKILL.md). **Blocking:** check every
suggestion against all applicable rules before presenting it.

## Why

A fix for one issue often adds another: removing passive voice but adding
words, shortening a sentence but leaving a Latin term, fixing grammar but
breaking the 80-column limit. Checking only the changed words misses this.

## Steps

1. **Run the tools first** (deterministic, no tokens):
   - The Vale, regex, and QDoc checks in skill-r-rules. Without a working
     Vale, the Vale rows (R2, R4, R24, R26, R38, R39, and others) are
     LLM checks.
   - `verify_after.py` for the R40 check and the other deterministic
     checks on the new text.
   - For link fixes: the target in the `.index` files (see below).
2. **Re-read the whole corrected sentence or paragraph**, not only the
   changed words, against the G-rules for its content type (skill-c-rules →
   skill-g-rules): G1 active voice, G2 terminology, G7 pronouns, and the
   register rule (G23-G29).
3. **If the fix breaks any rule, revise and repeat.** Present only a
   fully compliant suggestion.
4. **Run `lint_record.py`** on the records, then render the view with
   `render_record.py`.

Working notes (not in the output):

```
DRAFT: "..."
- [ ] Vale clean on the changed lines (R-rules)
- [ ] G1 active voice, G2 terms, G7 pronouns
- [ ] Register matches the C type
- [ ] R40: added lines within 80 columns
- [ ] Grammar: agreement, possessives
```

Example:

```
Original: "The data can be also assigned directly"
Draft 1:  "The data can also be assigned directly"   ✗ G1, still passive
Draft 2:  "You can also assign the data directly"    ✓ G1, R2, R38, R40
```

## Link suggestions

Before suggesting a `\l`, or commenting on autolinks, follow the
**Reviewer Verification Checklist** in skill-qdoc
`references/link-diagnosis.md`. Check the target in the module's `.index`
file and put the evidence in Validation. Don't present a link suggestion
until the check is done.

## Domain terms

Before flagging a word, confirm it isn't a valid technical term:

- C++ terms: in-place (construction), move semantics, RAII.
- Qt terms: Qt Terms and Concepts (S7).
- QML terms: QML Documentation Style (S4).

## Common mistakes

- Presenting before verifying: link targets, Output field, or rules unchecked.
- A partial fix: one rule fixed, another broken.
- Header without a line number (`for file.cpp:` instead of `for file.cpp:27:`).
- No Source, Category, or (for warning fixes) Warning field.
- Cause says what to change but not why.
- Fix Options when grep shows an existing pattern; or one option when
  several are equally valid and there's no pattern.
- Fewer than 2 context lines, or indentation not copied exactly.
- Validation without rule IDs.
- Wrong prompt text, or no ` ```diff ` fence.

`lint_record.py` and `render_record.py` prevent the format errors in this
list: the renderer writes the header, fields, and diff. They don't catch the
content errors.
