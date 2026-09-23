# tests

**Role:** framework test suite. Sample doc-set fixtures, comparison
harness, and expected outputs the framework runs its own artifacts
against.

**See also:** [`../README.md`](../README.md) for the framework
overview · [`../CONTRIBUTING.md`](../CONTRIBUTING.md) for how to add a
test.

## Purpose

The framework validates output correctness against a fixture: an
empty module with representative C++ and QML APIs. Each pipeline runs
its agents over the fixture; output is compared against human-edited
reference content. Audits and reports feed back to agents as new
grounding.

## Layout (target)

```
tests/
├── README.md
├── fixtures/                   # Sample doc set: C++ module, QML module
│   ├── cpp/
│   └── qml/
├── reference/                  # Human-edited expected output
├── harness/                    # Comparison and reporting scripts
└── reports/                    # Test-run outputs
```

## Current state

No fixtures shipped yet. The first test lands with the first agent
that produces content the framework needs to validate.
