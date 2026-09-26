#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Offline checks for lint_record.py, verify_after.py, and render_record.py.

    selftest_records.py

Builds a small file, evidence, and records in a temporary directory.
Exit 0 when every check passes. Stdlib only.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import records as R  # noqa: E402

FAILS = []


def run(*args):
    return subprocess.run([sys.executable, *args], capture_output=True, text=True, cwd=HERE)


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)


def main():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "src")
        os.makedirs(src)
        with open(os.path.join(src, "a.cpp"), "w") as f:
            f.write("/*!\n    \\class A\n    \\brief Holds a value.\n\n    \\sa setVal()\n"
                    "    \\image a.png {Window}\n*/\n")
        ev = {"warnings": [{"message": "Can't link to 'setVal()'", "reference": "link-diagnosis.md",
                            "link": {"result": "close"}, "api": {"verdict": "public"}}]}
        evp = os.path.join(d, "ev.json")
        json.dump(ev, open(evp, "w"))
        good = {"id": 1, "warn": "W0", "file": "src/a.cpp", "lines": [5, 5], "new": "    \\sa setValue()",
                "rules": ["C1/R41"], "ev": ["W0.link.result", "W0.api.verdict"],
                "cause": "Typo for setValue().", "judge": [["name-matches-header", True, "a.h declares setValue"]],
                "options": None, "pick": None}
        def write(name, recs):
            p = os.path.join(d, name)
            open(p, "w").write("\n".join(json.dumps(r) for r in recs) + "\n")
            return p
        gp = write("good.jsonl", [good])
        r = run("lint_record.py", gp, "--evidence", evp, "--root", d)
        check("lint: good record passes", r.returncode == 0)

        bad_rule = dict(good, rules=["C10"])
        r = run("lint_record.py", write("r.jsonl", [bad_rule]), "--evidence", evp, "--root", d)
        check("lint: bare 'C10' rejected", r.returncode == 1 and "not C<n>/R<n>" in r.stdout)
        r = run("lint_record.py", write("r5.jsonl", [dict(good, rules=["C1/R5"])]), "--evidence", evp, "--root", d)
        if all(R.rule_ids()):
            check("lint: nonexistent R5 rejected", r.returncode == 1 and "R5 doesn't exist" in r.stdout)
        else:   # the rule skills are in a later patch of the series
            check("lint: rule IDs not checked without the rule skills (warning, exit 0)",
                  r.returncode == 0 and "rule IDs not checked" in r.stdout)
        r = run("lint_record.py", write("ev.jsonl", [dict(good, ev=["W0.nope"])]), "--evidence", evp, "--root", d)
        check("lint: unresolved evidence rejected", r.returncode == 1 and "evidence 'W0.nope'" in r.stdout)
        delete = dict(good, lines=[6, 6], new="")
        r = run("lint_record.py", write("del.jsonl", [delete]), "--evidence", evp, "--root", d)
        check("lint: content deletion without judge rejected", r.returncode == 1 and "content-removed" in r.stdout)
        ok_del = dict(delete, judge=[["content-removed", True, "image is obsolete"]])
        r = run("lint_record.py", write("okdel.jsonl", [ok_del]), "--evidence", evp, "--root", d)
        check("lint: deletion with content-removed judge passes", r.returncode == 0)
        r = run("lint_record.py", write("lines.jsonl", [dict(good, lines=[40, 41])]), "--evidence", evp, "--root", d)
        check("lint: line range outside the file rejected", r.returncode == 1)
        long_cause = dict(good, cause="One. Two. Three.")
        r = run("lint_record.py", write("cause.jsonl", [long_cause]), "--evidence", evp, "--root", d)
        check("lint: cause over 2 sentences rejected", r.returncode == 1)

        r = run("verify_after.py", gp)
        check("verify_after: clean text passes", r.returncode == 0)
        dirty = dict(good, new="    \\sa setValue() — see \\l {A} and the value will change" + "x" * 40)
        r = run("verify_after.py", write("dirty.jsonl", [dirty]), "--json")
        hits = {h[1] for h in json.loads(r.stdout)["1"]}
        check("verify_after: catches R40, R39, R68, R4", {"R40", "R39", "R68", "R4"} <= hits)
        planned = dict(good, new="    This function will be removed in Qt 7.")
        r = run("verify_after.py", write("planned.jsonl", [planned]))
        check("verify_after: 'will be removed' is exempt from R4", r.returncode == 0)

        for fmt in ("doc-diff", "gerrit", "plain", "codereview"):
            r = run("render_record.py", gp, "--evidence", evp, "--root", d, "--format", fmt)
            check(f"render: {fmt}", r.returncode == 0 and "setValue()" in r.stdout)
        view = os.path.join(d, "view.md")
        open(view, "w").write(run("render_record.py", gp, "--evidence", evp, "--root", d).stdout)
        body = open(view).read().split("```diff\n", 1)[1].split("\n```", 1)[0] + "\n"
        patch = os.path.join(d, "view.patch")
        open(patch, "w").write(body)
        r = subprocess.run(["git", "apply", "--check", patch], capture_output=True, text=True, cwd=d)
        check("render: diff block is a git diff that applies (git apply --check)",
              r.returncode == 0 and body.startswith("diff --git a/src/a.cpp"))
        pure = dict(good, lines=[6, 6], new="    \\image a.png {Window}\n    \\note Added.")
        r = run("render_record.py", write("ins.jsonl", [pure]), "--evidence", evp, "--root", d)
        check("render: unchanged lines stay context (pure insertion shows no '-')",
              "\n-    \\image" not in r.stdout and "+    \\note Added." in r.stdout)
        r = run("render_record.py", gp, "--evidence", evp, "--root", d, "--format", "codereview")
        check("render: codereview explains the change", all(s in r.stdout for s in ("**What changes:**", "**Why:**", "**Checks:**")))
        r = run("render_record.py", gp, "--evidence", evp, "--root", d, "--format", "audit")
        check("render: audit has skill-doc-audit 2.0 sections",
              all(s in r.stdout for s in ("## Summary", "**Finding 1 of 1:**", "**Type:** BROKEN", "**Severity:** CRITICAL", "## Notes", "## Verdict")))

        # execution record from a synthetic transcript
        tr = os.path.join(d, "t.jsonl")
        rows = [
            {"type": "user", "timestamp": "2026-01-01T00:00:00Z", "message": {"content": "Fix the warnings."}},
            {"type": "assistant", "timestamp": "2026-01-01T00:00:10Z", "requestId": "r1", "effort": "low",
             "message": {"model": "claude-opus-5-5", "usage": {"input_tokens": 10, "cache_creation_input_tokens": 1000000,
                                                            "cache_read_input_tokens": 0, "output_tokens": 0},
                         "content": [{"type": "tool_use", "id": "a", "name": "Read", "input": {"file_path": "/x/agents/fixer.md"}},
                                     {"type": "tool_use", "id": "b", "name": "Bash", "input": {"command": "sed -n 1,9p /x/tools/qdoc-fix/verify_fix.py"}}]}},
            {"type": "user", "timestamp": "2026-01-01T00:01:00Z", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "a", "content": "1\t---\n4\tmodel: claude-opus-4-8\n"},
                {"type": "tool_result", "tool_use_id": "b", "content": "code"}]}}]
        open(tr, "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
        ex = os.path.join(d, "ex.json")
        r = run("execution_record.py", tr, "-o", ex)
        e = json.load(open(ex)) if r.returncode == 0 else {}
        check("execution: model pin seen at run time vs model that ran",
              e.get("model", {}).get("requested") == "claude-opus-4-8" and e["model"]["actual"] == "claude-opus-5-5"
              and e["model"]["matches"] is False)
        check("execution: classes setup and off-task", e.get("tool_call_classes") == {"setup": 1, "off-task": 1})
        check("execution: cost from usage (1M cache-write tokens = $5)", abs(e.get("cost_usd", {}).get("total", 0) - 5.0) < 0.01)
        check("execution: duration and prompt", e.get("time", {}).get("duration_s") == 60.0 and e.get("prompt") == "Fix the warnings.")
        r = run("render_record.py", gp, "--evidence", evp, "--root", d, "--format", "audit", "--execution", ex)
        blocks = [json.loads(b) for b in __import__("re").findall(r"```json\n(.*?)\n```", r.stdout, __import__("re").S)]
        check("audit: execution section and two parseable JSON blocks",
              "## Execution record" in r.stdout and "differs from the pin" in r.stdout
              and [b["schema"] for b in blocks] == ["doc-agent-framework/execution-record/v1", "doc-agent-framework/audit-result/v1"])
    print(f"{'OK' if not FAILS else 'FAILED'}: {len(FAILS)} failure(s)")
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
