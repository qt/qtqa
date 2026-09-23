# doc

**Role:** documentation for the Qt Doc Agent Framework — long-form
reference (this dir) and short, task-oriented how-tos
([`instructions/`](instructions/)). Qt Group renders the doc site
internally.

**See also:** [`../README.md`](../README.md) for the framework
overview · [`../CONTRIBUTING.md`](../CONTRIBUTING.md) for how to add a
doc page.

Status: **skeleton**. This directory holds one canonical reference
([`loading-patterns.md`](loading-patterns.md)) plus the intended shape
for the rendered doc site. More pages, images, and the publish script
are added incrementally.

## Purpose

Long-form reference material about the framework itself: architecture,
the four layers, the seven skill-loading patterns, the S / R / T rule
model, the test suite, and deployment. Distinct from
[`instructions/`](instructions/) (also in this dir), which is short,
task-oriented how-tos.

Model the shape on the existing internal Qt Group `qt-doc-agent-guide`:
`index.html` as the landing page, one HTML page per topic, Markdown
source files alongside, an `images/` directory.

## Audience

- Doc team members who dispatch the framework.
- External Qt contributors who want to review patches with it.
- Development teams in the Qt BU and elsewhere in Qt Group who write
  Qt documentation and want to adopt or extend the framework.

## Current pages

| Page | Scope |
|------|-------|
| [`loading-patterns.md`](loading-patterns.md) | The seven skill-loading patterns — summary table, decision tree, per-pattern detail with framework examples |

## Planned pages

| Page | Scope |
|------|-------|
| `index.html` | Overview, audience, what the framework is |
| `architecture.html` | The four-layer chain: harness → orchestrator → agent → skill |
| `pipelines.html` | Pipelines A / B / C / D, when to use each |
| `grounding.html` | S-sources, R-rules, T-rules; how to add each |
| `orchestrator.html` | Dispatch, pre-flight, verification gates |
| `agents.html` | Stage agents, fan-out agents, conventions |
| `skills.html` | Skill authoring, GATE loading, tool-based lookup |
| `test-suite.html` | Sample doc set, comparison method, feedback loop |
| `deployment.html` | Internal deploy process, DNS, rsync |

Pages are added in whatever order the framework work drives.

## Deployment

Once HTML pages exist, Qt Group renders them internally via the same
rsync process that already ships `qt-doc-agent-guide`. Deploy script
and target path land in `../scripts/` when the first page is ready.
The target URL is not repeated in this public tree; it lives with the
internal deploy configuration.

## Layout (target)

```
doc/
├── README.md               # This file
├── loading-patterns.md     # Seven skill-loading patterns reference
├── index.html              # Landing page
├── {topic}.html            # One per planned page above
├── {topic}-content.md      # Markdown source, when the HTML is generated
└── images/                 # Referenced screenshots and diagrams
```

## Reference

- `qt-doc-agent-guide` (internal Qt Group doc) — the shape to mirror.
