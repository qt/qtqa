# Instructions

**Role:** short, task-oriented how-tos for using the framework, end to
end and per pipeline. Ships with the code in qtqa. Long-form reference
lives alongside in [`../`](../).

**See also:** [`../../README.md`](../../README.md) for the framework
overview · [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md) for how to
add an instruction.

## Layout

Guides land here as each pipeline stabilizes. Expected shape:

| Pipeline | Guide | Scope |
|----------|-------|-------|
| (framework) | `how-to-use-the-framework.md` | Overview, orchestrator entry points, prompt patterns |
| A | *(planned)* | Patch review how-to — ships with the review-stage agents |
| B | `how-to-create-documentation.md` | Research to stub to fill to push |
| C | `how-to-fix-a-doc-bug.md` | Bug report to fix to resolution |
| D | `how-to-run-batch-fixes.md` | Task to multi-repo patch to review |
| (all) | `how-to-run-the-test-suite.md` | Sample doc set fixture, comparison method |
| (all) | `how-to-add-an-agent-or-skill.md` | S / R / T grounding, skill-loading pattern selection |

## Conventions

- Guides are Markdown, one file per audience task.
- Each guide names its target pipeline in the frontmatter or opening line.
- Sample prompts are literal (copy-paste ready) and pinned to
  `claude-opus-5-5`.
- Guides cross-link to the S-, R-, and T-rules the pipeline enforces.
