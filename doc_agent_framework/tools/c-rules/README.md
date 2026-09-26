# c-rules

`section.py` prints only the parts of a C-rule page that one topic block
needs, so a single-node job doesn't load every node sub-rule.

```
python3 tools/c-rules/section.py C1.5            # page part + shared C1.0 + C1.5
python3 tools/c-rules/section.py C1.4 C1.5       # several sub-rules
python3 tools/c-rules/section.py C1.5 --no-page  # sub-rules only
python3 tools/c-rules/section.py C6              # whole page (no sub-rules)
python3 tools/c-rules/section.py --list          # IDs and token estimates
python3 tools/c-rules/section.py --selftest
```

Use it for single-node work (one QDoc warning, batch per-warning agents).
For a full page review, load the whole C page: it touches most node types.
