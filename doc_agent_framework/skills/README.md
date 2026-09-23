# Skills

**Role:** reference material that agents load on demand.

**See also:** [`../README.md`](../README.md) for the framework
overview · [`../CONTRIBUTING.md`](../CONTRIBUTING.md) for how to add a
new skill.

## Rule classes

The framework groups skills by the rule class they codify:

- **S-sources.** Root style authorities (QUIPs, Qt Writing Guidelines,
  Microsoft Style Guide). Skills that surface source rules verbatim.
- **R-rules.** Concrete language rules distilled from S-sources.
  `skill-language-style` carries R1–R64 and expansions.
- **T-rules.** AI tells to suppress in generated prose.
  `skill-ai-tells` carries T1–T19, calibrated against 2.4M words of
  Qt reference documentation.

## Loading

Agents load skills using the seven skill-loading patterns documented
in [`../doc/loading-patterns.md`](../doc/loading-patterns.md):

- Upfront load (every-stage skills such as `skill-doc-diff`).
- Conditional load (patch-content-gated skills such as `skill-alttext`).
- GATE load (agent forks, loads, blocks progress until returned).
- Tool-based lookup (Vale, ImageMagick, Mermaid).
- Hierarchical prompt (Orchestrator, Agent, Skill).

## Initial check (all pipelines)

The initial check runs `tools/check-artifact/check_artifact.py` first.
These two skills load only when the input is a framework artifact or the
tool reports a finding (see `agents/orchestrator.md`, "Initial check").

| Skill | Purpose |
|-------|---------|
| [`skill-framework-fitness`](skill-framework-fitness/SKILL.md) | 9-layer fitness test — pipeline mapping, four-layer chain, S/R/T grounding, cross-links, registration |
| [`skill-security-hygiene`](skill-security-hygiene/SKILL.md) | Hardcoded secrets, PII, deprecated crypto, plain-text auth, logging hygiene, public/internal boundary |

## Pipeline mapping

| Pipeline | Load pattern | Skills |
|----------|--------------|--------|
| (all) | Tool first (initial check) | `tools/check-artifact`; then skill-framework-fitness (framework artifacts) or skill-security-hygiene (tool finding, published output) |
| A | Upfront | skill-doc-diff, skill-language-style, skill-ai-tells |
| A | Conditional | skill-alttext, skill-line-wrap, skill-linking-check, skill-module-export, skill-qdoc-output, skill-cross-product-check |
| A | Tool-based | skill-vale-qdoc-lint |
| A | GATE | skill-qdoc (deep syntax reference) |
| B | Upfront | *(TBD)* |
| C | Conditional | *(TBD)* |
| D | Tool-based | *(TBD)* |

Every skill listed above lives (or will live) in this directory. New
skills land here as each pipeline stabilizes.
