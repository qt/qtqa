#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Check the new text of each record against the tool-checkable rules.

    verify_after.py RECORDS.jsonl [--json]

Runs on the "new" text only (and on each option's text): R40 line length,
R39 space before a brace, R47 page.html#anchor links, R68 em dashes, R4
future tense (planned removals exempt), the Tier 1 AI-tell patterns, and
the secrets and home-path patterns from tools/check-artifact. Vale-based
R-rules run separately (tools/vale-rrules). Exit 0 when every text passes,
1 otherwise. Stdlib only.
"""
import argparse
import importlib.util
import json
import re
import sys

import records as R

spec = importlib.util.spec_from_file_location(
    "check_artifact", R.HERE.parent / "check-artifact" / "check_artifact.py")
CA = importlib.util.module_from_spec(spec)
spec.loader.exec_module(CA)

RULES = [
    ("R39", re.compile(r"\\(?!image\b|inlineimage\b)[a-z]+ +\{"), "space before '{'"),
    ("R47", re.compile(r"\\l\s*\{[^}]*\.html#"), "page.html#anchor link"),
    ("R68", re.compile(r"—"), "em dash"),
    ("R4", re.compile(r"\bwill (?!be removed|be deprecated)[a-z]+", re.I), "future tense"),
]


def check_text(text):
    hits = []
    for line in text.split("\n"):
        if len(line) > 80:
            hits.append(("R40", f"{len(line)} columns"))
        for rid, rx, what in RULES:
            if rx.search(line):
                hits.append((rid, what))
        for tid, rx in CA.AI_TELLS:
            if rx.search(line):
                hits.append((tid, "AI tell"))
        if CA.SECRET_RE.search(line):
            hits.append(("SH1", "secret"))
        if CA.HOME_RE.search(line):
            hits.append(("SH6", "home path"))
    return hits


def verify(recs):
    results = {}
    for rec in recs:
        texts = [("new", rec.get("new", ""))]
        texts += [(f"option {i}", o.get("new", "")) for i, o in enumerate(rec.get("options") or [], 1)]
        results[rec["id"]] = [(where, rid, what) for where, t in texts for rid, what in check_text(t)]
    return results


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("records")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    results = verify(R.load_records(a.records))
    if a.json:
        print(json.dumps(results, indent=1))
    else:
        for rid, hits in results.items():
            status = "PASS" if not hits else "FAIL"
            detail = "; ".join(f"{w}: {r} {x}" for w, r, x in hits)
            print(f"{status} record {rid}" + (f": {detail}" if hits else ""))
    sys.exit(1 if any(results.values()) else 0)


if __name__ == "__main__":
    main()
