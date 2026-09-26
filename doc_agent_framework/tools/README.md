# tools

**Role:** local executables and helper scripts that skills call via
Pattern 5 (tool-based lookup) from
[`../doc/loading-patterns.md`](../doc/loading-patterns.md). Each
tool lives in its own subdirectory alongside its README.

**See also:** [`../README.md`](../README.md) for the framework
overview · [`../CONTRIBUTING.md`](../CONTRIBUTING.md) for how to add a
new tool.

## Purpose

Some skills delegate work to a script or binary rather than reasoning
about it inline — for example, Vale for prose linting, ImageMagick for
image verification, Mermaid for diagram rendering. This directory holds
those executables and their wrappers.

The framework's skills reference a tool through Pattern 5; the tool
itself lives here.

## Layout (target)

```
tools/
├── README.md
└── {tool-name}/
    ├── README.md               # What the tool does; which skills load it
    ├── {executable or wrapper}
    └── config/                 # Optional per-tool config
```

## Current state

| Tool | What it does | Used by |
|------|--------------|---------|
| [`c-rules-index`](c-rules-index/README.md) | Checks that every content type in `skill-c-rules` is listed in SKILL.md, the register dials, and the test content | `check-artifact`, when the target is `skill-c-rules` |
| [`check-artifact`](check-artifact/README.md) | Deterministic checks on an agent, skill, scenario, or tool before it lands | `framework-tester` Step 3 |
| [`c-rules`](c-rules/README.md) | Prints the page part, shared sub-rule, and requested node sub-rule of a C page (for example `C1.5`), so single-node jobs load about 60% of C1 | single-warning fixes, per-warning batch agents |
| [`register-dials`](register-dials/README.md) | Checks the tool dials of a register (sentence length, contraction density, "we", "So") for a content type; `--show C<n>` prints the resolved dials; `--selftest` validates the dials file | register check, skill-c-rules step 4 |
| [`doc-diff`](doc-diff/README.md) | The record schema; lint records, check new text, and render them as git diffs from the real file | `skill-doc-diff`, pipeline A agents |
