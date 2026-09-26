#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Check Doc Team diff records against the schema, the evidence, and the files.

    lint_record.py RECORDS.jsonl --evidence EVIDENCE.json --root SRC [--json]

Checks per record: required keys; warn ID exists; each rule is C<n>/R<n>
or C<n>/G<n> with IDs that exist in skill-c/r/g-rules (when those skills
are not present, the IDs are not checked and a warning says so); each evidence ID
resolves; the line range is inside the file; cause is at most 2 sentences;
judge entries are [check, bool, reason]; options and pick agree. A record
that deletes content without adding any must carry a judge entry named
"content-removed", because a clean rebuild alone doesn't justify deleting.
Exit 0 when there are no errors, 1 otherwise. Stdlib only.
"""
import argparse
import json
import os
import re
import sys

import records as R


def lint(recs, evidence, root, ids):
    c_ids, r_ids, g_ids = ids
    out = []
    def err(rec, msg): out.append({"id": rec.get("id"), "level": "error", "msg": msg})
    def warn(rec, msg): out.append({"id": rec.get("id"), "level": "warning", "msg": msg})
    # Without the rule skills there is nothing to check an ID against. Say so once; the form check still runs.
    have_ids = bool(c_ids and r_ids and g_ids)
    if not have_ids:
        out.append({"id": None, "level": "warning",
                    "msg": "rule IDs not checked: skill-c-rules, skill-r-rules, or skill-g-rules not found"})
    seen = {}
    for rec in recs:
        missing = [k for k in R.REQUIRED if k not in rec]
        if missing:
            err(rec, f"missing keys: {', '.join(missing)}")
            continue
        ok, why = R.resolve(evidence, rec["warn"])
        if not ok:
            err(rec, f"warn {rec['warn']}: {why}")
        for rule in rec["rules"]:
            m = re.fullmatch(r"(C\d+)/(R\d+b?|G\d+)", rule)
            if not m:
                err(rec, f"rule '{rule}' is not C<n>/R<n> or C<n>/G<n>")
                continue
            c, x = m.groups()
            if not have_ids:
                continue
            if c not in c_ids:
                err(rec, f"rule '{rule}': {c} is not a content type")
            if x not in (r_ids if x.startswith("R") else g_ids):
                err(rec, f"rule '{rule}': {x} doesn't exist")
        if not rec["rules"]:
            err(rec, "no rules cited")
        for ev in rec["ev"]:
            ok, why = R.resolve(evidence, ev)
            if not ok:
                err(rec, f"evidence '{ev}': {why}")
        if not rec["ev"]:
            warn(rec, "no evidence cited")
        path = os.path.join(root, rec["file"])
        if not os.path.exists(path):
            err(rec, f"file not found: {rec['file']}")
            continue
        lines = R.read_lines(path)
        a, b = rec["lines"]
        if not (1 <= a <= b <= len(lines)):
            err(rec, f"lines {a}-{b} outside 1-{len(lines)}")
            continue
        old = lines[a - 1:b]
        new = R.new_lines(rec)
        if old == new:
            err(rec, "new text equals the old text")
        lost = [l for l in old if l.strip() and l.strip() not in {n.strip() for n in new}]
        if not new and lost and not any(j[0] == "content-removed" for j in rec["judge"]):
            err(rec, "deletes content with no replacement; add judge "
                     "['content-removed', true, reason] or propose a non-deleting fix")
        sentences = len(re.findall(r"[.!?](\s|$)", rec["cause"].strip()))
        if sentences > 2:
            err(rec, f"cause has {sentences} sentences (max 2)")
        for j in rec["judge"]:
            if not (isinstance(j, list) and len(j) == 3 and isinstance(j[1], bool)):
                err(rec, f"judge entry {j!r} is not [check, bool, reason]")
            elif j[1] is False:
                warn(rec, f"judge check failed: {j[0]}")
        opts, pick = rec.get("options"), rec.get("pick")
        if opts and not (isinstance(pick, int) and 1 <= pick <= len(opts)):
            err(rec, "options given but pick is not 1..N")
        key = (rec["file"], a, b, rec["new"])
        if key in seen:
            warn(rec, f"same edit as record {seen[key]}")
        else:
            seen[key] = rec["id"]
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("records")
    p.add_argument("--evidence", required=True)
    p.add_argument("--root", required=True, help="tree the record paths are relative to")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    found = lint(R.load_records(a.records), R.load_evidence(a.evidence), a.root, R.rule_ids())
    if a.json:
        print(json.dumps(found, indent=1))
    else:
        for f in found:
            where = "all records" if f["id"] is None else f"record {f['id']}"
            print(f"{f['level']:7} {where}: {f['msg']}")
        errors = sum(f["level"] == "error" for f in found)
        print(f"{errors} error(s), {len(found) - errors} warning(s)")
    sys.exit(1 if any(f["level"] == "error" for f in found) else 0)


if __name__ == "__main__":
    main()
