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
| [`check-artifact`](check-artifact/README.md) | Deterministic checks on an agent, skill, scenario, or tool before it lands | `framework-tester` Step 3 |
