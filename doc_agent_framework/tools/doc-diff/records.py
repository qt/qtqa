# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Shared code for Doc Team diff records: loading, evidence paths, rule IDs.

A record is one JSON object per line (JSON Lines), written by the agent:

    {"id": 2, "warn": "W1", "file": "src/foo.cpp", "lines": [157, 157],
     "new": "    \\sa minimum", "rules": ["C1/R41"], "ev": ["W1.link.result"],
     "cause": "...", "judge": [["dup-sa", true, "..."]],
     "options": null, "pick": null}

Evidence is the JSON that tools/qdoc-fix/evidence.py writes. An evidence ID
is a path into it: W<n> is warnings[n]; then keys or list indexes, for
example W1.api.verdict or W1.snippet.3. Stdlib only.
"""
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
FRAMEWORK = HERE.parents[1]
REQUIRED = ("id", "warn", "file", "lines", "new", "rules", "ev", "cause", "judge")


def load_records(path):
    records = []
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            if line.strip():
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError as e:
                    raise SystemExit(f"error: {path}:{number}: not JSON: {e}")
    return records


def load_evidence(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def resolve(evidence, ev_id):
    """Return (True, value) for an evidence path, or (False, reason)."""
    parts = ev_id.split(".")
    m = re.fullmatch(r"W(\d+)", parts[0])
    if not m:
        return False, "must start with W<n>"
    warnings = evidence.get("warnings", [])
    n = int(m.group(1))
    if n >= len(warnings):
        return False, f"only {len(warnings)} warnings"
    node = warnings[n]
    for key in parts[1:]:
        if isinstance(node, list) and key.isdigit() and int(key) < len(node):
            node = node[int(key)]
        elif isinstance(node, dict) and key in node:
            node = node[key]
        else:
            return False, f"no '{key}'"
    return True, node


def rule_ids(root=FRAMEWORK):
    """Valid C, R, and G IDs, parsed from the rule skills."""
    skills = pathlib.Path(root) / "skills"
    def read(name):
        p = skills / name / "SKILL.md"
        return p.read_text(encoding="utf-8") if p.exists() else ""
    r = set(re.findall(r"^\| (R\d+b?) \|", read("skill-r-rules"), re.M))
    g = {m.group(1) for m in re.finditer(r"^### (G\d+)\. (.*)$", read("skill-g-rules"), re.M)
         if "(Removed)" not in m.group(2)}
    c = set(re.findall(r"\| \[(C\d+)\]", read("skill-c-rules")))
    return c, r, g


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def new_lines(record):
    return record["new"].split("\n") if record["new"] else []
