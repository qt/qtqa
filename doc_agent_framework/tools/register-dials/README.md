# register-dials

Checks the tool dials of a register for a content type. The dials are
tunable variables in
[`skills/skill-g-rules/references/register-dials.toml`](../../skills/skill-g-rules/references/register-dials.toml).

```
python3 tools/register-dials/check_dials.py --selftest          # validate the dials file
python3 tools/register-dials/check_dials.py --show C6           # resolved dials for a type
python3 tools/register-dials/check_dials.py --type C6 FILE      # check a page
python3 tools/register-dials/check_dials.py --type C4 --register tutorial FILE
```

Tool dials: `sentence_words_max`, `contraction_density_max`, `we_allowed`
(count only), `first_person_singular`, and the conversational `so_pattern`.
The output lists the LLM dials (person, tense, mood, tone, structure,
analogies, asides) for the reviewer to apply.

To tune: edit a value in the dials file (or add a per-type override under
`[content_types.C<n>.overrides]`), then run `--selftest`.
