#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

"""Check that every place that lists content types agrees.

A content type is one file, skills/skill-c-rules/references/c<N>-*.md.
That file is the source of truth. This script checks that each type is
also listed everywhere else that needs it, and that no place lists a
type that has no file:

  1. SKILL.md table: one row per reference file, linking to it
  2. SKILL.md description: the C-ID ranges cover every type
  3. SKILL.md shared-rules line: covers every prose type (not C10,
     C11, C16), and names the same shared G-rules as the pages
  4. Reference file: title "# C<N>. ..." and the required sections
  5. register-dials.toml: a [content_types.C<N>] table
  6. tests/README.md: a row in the content-type test-content table
  7. Reserved IDs (SKILL.md "Reserved" paragraph) have no file

Exit status: 0 when everything agrees, 1 on a mismatch, 2 on a setup
error.
"""

import argparse
import re
import sys
from pathlib import Path

FRAMEWORK = Path(__file__).resolve().parent.parent.parent
REQUIRED_SECTIONS = ["Purpose and style", "Detect", "Rules", "Gaps", "Sample"]
NON_PROSE = {10, 11, 16}


def ids_in_ranges(text):
    """Expand 'C1-C12, C16' (hyphen or en dash) into a set of numbers."""
    found = set()
    for a, b in re.findall(r"C(\d+)\s*[-–]\s*C(\d+)", text):
        found.update(range(int(a), int(b) + 1))
    for n in re.findall(r"(?<![-–\w])C(\d+)(?!\s*[-–]\s*C\d)", text):
        found.add(int(n))
    return found


def g_rules(line):
    return set(re.findall(r"\bG\d+\b", line))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=str(FRAMEWORK), help="framework root")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    skill = root / "skills" / "skill-c-rules"
    skill_md = skill / "SKILL.md"
    dials = root / "skills" / "skill-g-rules" / "references" / "register-dials.toml"
    tests_readme = root / "tests" / "README.md"
    for path in (skill_md, dials, tests_readme):
        if not path.is_file():
            print(f"error: missing {path}", file=sys.stderr)
            return 2

    problems = []
    refs = {}
    for path in sorted((skill / "references").glob("c*.md")):
        match = re.match(r"c(\d+)-", path.name)
        if match:
            refs[int(match.group(1))] = path
    text = skill_md.read_text()
    desc = re.search(r"^description:(.*)$", text, re.M)
    desc = desc.group(1) if desc else ""

    rows = {int(n): f for n, f in re.findall(r"^\| \[C(\d+)\]\(references/([^)]+)\)", text, re.M)}
    shared = re.search(r"^Every prose type \(([^)]*)\) shares:", text, re.M)
    shared_ids = ids_in_ranges(shared.group(1)) if shared else set()
    shared_g = re.search(r"^- \*\*G \(LLM\):\*\*(.*)$", text[shared.end():] if shared else "", re.M)
    shared_g = g_rules(shared_g.group(1)) if shared_g else set()
    reserved = re.search(r"\*\*Reserved[^\n]*(?:\n(?!\n)[^\n]*)*", text)
    reserved_ids = {int(n) for n in re.findall(r"\bC(\d+) [A-Z]", reserved.group(0))} if reserved else set()
    reserved_ids -= set(refs)  # "C16 is the commit message, above"

    dial_ids = {int(n) for n in re.findall(r"^\[content_types\.C(\d+)\]", dials.read_text(), re.M)}
    test_ids = {int(n) for n in re.findall(r"^\| C(\d+) ", tests_readme.read_text(), re.M)}

    for n, path in refs.items():
        name = f"C{n}"
        body = path.read_text()
        if n not in rows:
            problems.append(f"{name}: no row in SKILL.md table")
        elif rows[n] != path.name:
            problems.append(f"{name}: SKILL.md row links {rows[n]}, file is {path.name}")
        if n not in ids_in_ranges(desc):
            problems.append(f"{name}: not in the SKILL.md description ({desc.strip()[:60]}...)")
        if n not in NON_PROSE and n not in shared_ids:
            problems.append(f"{name}: not in 'Every prose type (...)' in SKILL.md")
        if not re.match(rf"# C{n}\. ", body):
            problems.append(f"{name}: {path.name} does not start with '# C{n}. '")
        headings = re.findall(r"^## (.+)$", body, re.M)
        for section in REQUIRED_SECTIONS:
            if section not in headings:
                problems.append(f"{name}: {path.name} has no '## {section}' section")
        page_g = re.search(r"^- \*\*Shared G \(LLM\):\*\*(.*)$", body, re.M)
        if page_g and shared_g and g_rules(page_g.group(1)) != shared_g:
            diff = sorted(g_rules(page_g.group(1)) ^ shared_g)
            problems.append(f"{name}: shared G-rules differ from SKILL.md: {', '.join(diff)}")
        if n not in dial_ids:
            problems.append(f"{name}: no [content_types.{name}] in register-dials.toml")
        if n not in test_ids:
            problems.append(f"{name}: no row in the tests/README.md content-type table")
    for n in sorted(set(rows) - set(refs)):
        problems.append(f"C{n}: SKILL.md row but no references/c{n}-*.md")
    for n in sorted(reserved_ids & set(refs)):
        problems.append(f"C{n}: reserved ID has a reference file")

    for p in problems:
        print(p)
    if problems:
        print(f"FAIL: {len(problems)} mismatch(es) across {len(refs)} content types")
        return 1
    print(f"PASS: {len(refs)} content types agree across SKILL.md, references, dials, and tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())
