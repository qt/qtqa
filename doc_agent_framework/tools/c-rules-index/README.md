# c-rules-index

**Role:** keeps the content-type list in
[`skill-c-rules`](../../skills/skill-c-rules/SKILL.md) in step with its
reference files.

**See also:** [`../README.md`](../README.md) for the tools overview.

## Usage

```
python3 tools/c-rules-index/check_c_index.py
```

Each `skills/skill-c-rules/references/c<N>-*.md` file defines one
content type. The script checks that the type also appears in:

- the SKILL.md table, description range, and "Every prose type" line
- `skill-g-rules/references/register-dials.toml` (`[content_types.C<N>]`)
- the content-type test-content table in `tests/README.md`

It also checks each page's title and required sections, that its shared
G-rules match SKILL.md, and that no reserved ID has a file.

Exit status: 0 when everything agrees, 1 on a mismatch, 2 on a setup
error. `check_artifact.py` runs it when the target is `skill-c-rules`.
The procedure for adding a type is in SKILL.md, "Adding a content type".
