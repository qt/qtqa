# check-artifact

**Role:** deterministic checks on a framework artifact before it lands.
Step 3 of [`framework-tester`](../../agents/framework-tester.md).

**See also:** [`../README.md`](../README.md) for the tools overview ·
[`../../CONTRIBUTING.md`](../../CONTRIBUTING.md) for the landing rules.

## Usage

```
python3 tools/check-artifact/check_artifact.py <path> [<path> ...]
python3 tools/check-artifact/check_artifact.py --json agents/my-agent.md
python3 tools/check-artifact/check_artifact.py --min-severity Medium skills/skill-foo/SKILL.md
python3 tools/check-artifact/check_artifact.py --root <framework-copy> <framework-copy>/agents/x.md
```

The kind of artifact comes from its location: `agents/<name>.md`,
`skills/**/SKILL.md`, a `tests/scenarios/<name>/` directory, or a
`tools/<name>/` directory. Any other file gets the common checks only.

Exit status: 0 when no finding is High or Critical, 1 when at least
one is, 2 on a usage error.

## Checks

| Check | Applies to | Severity | Source rule |
|-------|------------|----------|-------------|
| `frontmatter` | agent, skill | High | CONTRIBUTING, "Adding an agent" step 2 and "Adding a skill" step 1 |
| `model-pin` | agent, skill | High (agent), Medium (skill) | CONTRIBUTING ground rule 3 |
| `description-length` | agent, skill | Low over 150, High over 1,536 chars | skill-framework-fitness Layer 2 |
| `body-size` | agent, skill | Low over 200 lines (skills), High over 20,000 chars | skill-framework-fitness Layer 2 |
| `overview-fields` | agent | Medium | Pipeline, Fan-out, and Loading pattern rows (CONTRIBUTING step 3) |
| `verification-gate` | agent | Medium | CONTRIBUTING step 3 |
| `registered-agents-readme` | agent | Medium | CONTRIBUTING step 4 |
| `registered-orchestrator` | agent | Medium | CONTRIBUTING step 5 |
| `instruction` | agent | Low | CONTRIBUTING step 6 |
| `fan-out-consistency` | agent | High | agents/README.md Fan-out column against `tools:` |
| `skill-path` | agent | Medium | Every `../skills/<name>/SKILL.md` exists in the framework |
| `scenario-coverage` | agent | Medium | A row in the tests/README.md scenario table |
| `registered-skills-readme` | skill | Medium | CONTRIBUTING, "Adding a skill" step 4 |
| `loaded-by-agent` | skill | Medium | skill-framework-fitness Layer 4 |
| `scenario-files`, `registered-tests-readme`, `scenario-agent-exists` | scenario | High, Medium, Medium | tests/README.md, "Adding a scenario" |
| `tool-readme`, `registered-tools-readme`, `spdx` | tool | Medium | tools/README.md layout |
| `link` | Markdown | Medium | Relative links resolve |
| `boundary-home-path` | all | High | skill-security-hygiene, framework boundary |
| `boundary-host` | all | Medium, a person confirms | skill-security-hygiene, framework boundary |
| `secret` | all | Critical | skill-security-hygiene, hardcoded secrets |
| `ai-tell-tier1` | Markdown | Medium, High once a person confirms | skill-ai-tells Tier 1 patterns |

Two checks report candidates, not verdicts. The Tier 1 AI-tell
patterns also match quoted patterns and literal uses ("not only the
hunks"), and a Qt host may be public. `framework-tester` confirms or
dismisses each one in its Step 7.

## Self-test

```
python3 tools/check-artifact/selftest.py
```

Copies the framework to a temporary directory, adds an agent and a
skill with one seeded defect per check, and fails if any check stays
silent. It also fails if any shipped agent or skill has a blocking
finding. Run it after every change to `check_artifact.py`.
