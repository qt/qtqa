#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

"""Prove that check_artifact.py catches the defects it claims to catch.

Copies the framework to a temporary directory, adds an agent and a
skill with one seeded defect per check, runs check_artifact.py with
--root on the copy, and compares the findings against the list below.
A check that stays silent on its seeded defect fails the self-test.

Exit status: 0 when every seeded defect is found and the shipped
artifacts have no blocking finding, 1 otherwise.
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
FRAMEWORK = HERE.parent.parent
CHECKER = HERE / "check_artifact.py"

# Assembled at run time so this file does not itself trip the checks.
HOME = "/" + "Users/someone/"
TELL = "del" + "ve"

BAD_AGENT = f"""---
name: wrong-name
description: {"x" * 160}
model: opus
tools: Read, Agent
---

# Bad agent

Uses [a missing page](no-such-page.md) and loads
`../skills/skill-not-there/SKILL.md`. Reads {HOME}code/file.txt.
The agent will {TELL} into the details.
"""

BAD_SKILL = """---
name: skill-other
description: A seeded skill for the checker self-test.
model: claude-opus-5-5
---

# Bad skill
"""

# (artifact, check, severity) triples the checker must report.
EXPECTED = {
    ("agents/bad-agent.md", "frontmatter", "High"),               # name differs from file
    ("agents/bad-agent.md", "model-pin", "High"),                 # alias, not pinned
    ("agents/bad-agent.md", "description-length", "Low"),         # 160 > 150
    ("agents/bad-agent.md", "overview-fields", "Medium"),         # no overview table
    ("agents/bad-agent.md", "verification-gate", "Medium"),       # no gate section
    ("agents/bad-agent.md", "registered-agents-readme", "Medium"),
    ("agents/bad-agent.md", "registered-orchestrator", "Medium"),
    ("agents/bad-agent.md", "instruction", "Low"),
    ("agents/bad-agent.md", "scenario-coverage", "Medium"),
    ("agents/bad-agent.md", "skill-path", "Medium"),
    ("agents/bad-agent.md", "link", "Medium"),
    ("agents/bad-agent.md", "boundary-home-path", "High"),
    ("agents/bad-agent.md", "ai-tell-tier1", "Medium"),
    ("skills/skill-bad/SKILL.md", "frontmatter", "High"),         # name differs from dir
    ("skills/skill-bad/SKILL.md", "model-pin", "Medium"),         # skills carry no model
    ("skills/skill-bad/SKILL.md", "registered-skills-readme", "Medium"),
    ("skills/skill-bad/SKILL.md", "loaded-by-agent", "Medium"),
}


def run(root, *paths):
    result = subprocess.run([sys.executable, str(CHECKER), "--root", str(root), "--json", *paths],
                            capture_output=True, text=True)
    if result.returncode == 2:
        sys.exit(f"checker error:\n{result.stderr}")
    return json.loads(result.stdout)


def main():
    failures = []
    with tempfile.TemporaryDirectory(prefix="check-artifact-") as tmp:
        root = Path(tmp) / "fw"
        shutil.copytree(FRAMEWORK, root, ignore=shutil.ignore_patterns(".DS_Store", "__pycache__"))
        (root / "agents" / "bad-agent.md").write_text(BAD_AGENT)
        (root / "skills" / "skill-bad").mkdir()
        (root / "skills" / "skill-bad" / "SKILL.md").write_text(BAD_SKILL)

        report = run(root, str(root / "agents/bad-agent.md"), str(root / "skills/skill-bad/SKILL.md"))
        found = {(r["artifact"], f["check"], f["severity"])
                 for r in report["results"] for f in r["findings"]}
        for item in sorted(EXPECTED - found):
            failures.append(f"missed seeded defect: {item}")

        # The fan-out check needs a registered agent: list bad-agent as
        # "no" in agents/README.md while its tools: include Agent.
        readme = root / "agents" / "README.md"
        readme.write_text(readme.read_text().replace(
            "| (all) | Dispatch | orchestrator | yes |",
            "| (all) | Dispatch | orchestrator | yes |\n| A | Seeded | bad-agent | no |"))
        report = run(root, str(root / "agents/bad-agent.md"))
        if not any(f["check"] == "fan-out-consistency" for f in report["results"][0]["findings"]):
            failures.append("missed seeded defect: fan-out-consistency")

    shipped = [str(p) for p in sorted((FRAMEWORK / "agents").glob("*.md")) if p.name != "README.md"]
    shipped += [str(p) for p in sorted((FRAMEWORK / "skills").rglob("SKILL.md"))]
    report = run(FRAMEWORK, *shipped)
    for r in report["results"]:
        for f in r["findings"]:
            if f["severity"] in ("Critical", "High"):
                failures.append(f"false blocker on shipped artifact: {r['artifact']}: "
                                f"{f['check']} {f['message']}")

    checked = len(EXPECTED) + 1
    if failures:
        print("\n".join(failures))
        print(f"FAIL: {len(failures)} problem(s)")
        return 1
    print(f"PASS: {checked} seeded defects found; {len(shipped)} shipped artifacts, 0 blocking")
    return 0


if __name__ == "__main__":
    sys.exit(main())
