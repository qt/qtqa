#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Render Doc Team diff records and evidence as the view people read.

    render_record.py RECORDS.jsonl --evidence EVIDENCE.json --root SRC
                     [--format doc-diff|gerrit|plain|codereview|audit]
                     [--verify VERIFY.json] [--context 3]

The model writes only the record (edit + judgment). Everything else comes
from tools: the Warning text and Category from the evidence, the header,
Source, and diff block (a git-style unified diff) from the file, Validation from the evidence,
verify_after.py, and (with --verify) verify_fix.py results. VERIFY.json
maps a record id to the JSON that verify_fix.py printed for it.

Formats:
  doc-diff    full suggestion blocks with the approval prompt (default)
  gerrit      one inline comment per record with a suggestion block
  plain       one line per record
  codereview  a document that explains each proposed change: what changes,
              why, the checks, and the evidence behind it, for sharing
Stdlib only.
"""
import argparse
import difflib
import json
import re
import os
import sys

import records as R

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import progress  # noqa: E402
from verify_after import verify

CATEGORY = {"link-diagnosis.md": "QDoc link", "link-syntax.md": "QDoc link",
            "markup-commands.md": "QDoc markup", "macros-warnings.md": "QDoc warning",
            "qml-topic-commands.md": "QDoc QML topic", "context-commands.md": "QDoc context command"}


def short(value, width=70):
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return text if len(text) <= width else text[:width - 1] + "…"


def facts(rec, evidence):
    rows = []
    for ev in rec["ev"]:
        ok, value = R.resolve(evidence, ev)
        rows.append((ev, short(value) if ok else f"UNRESOLVED ({value})", ok))
    return rows


# Plain-language names for evidence fields, so readers don't need to know
# the evidence file. The path stays in brackets for traceability.
EVIDENCE_LABELS = {
    "api.verdict": "Public or internal API (from the header and its export macro)",
    "api": "Where the API is declared",
    "snippet": "Source line",
    "args": "Name in the QDoc warning",
    "link.result": "Link target lookup in the .index files",
    "link.unqualified": "Similar names found in other modules",
    "link.close": "Close matches for the link target",
    "link.exact": "Exact match for the link target",
    "declarations": "Declaration in the header",
    "related": "Related warnings in the same file",
    "template": "QDoc message type",
    "message": "QDoc warning text",
}
LEGEND = "✓ = check passed · ✗ = check failed or not proven. Items marked *agent's judgment* are the agent's reasoning; everything else comes from tools."


def label(ev):
    parts = ev.split(".")[1:]
    for n in range(len(parts), 0, -1):
        key = ".".join(p for p in parts[:n] if not p.isdigit())
        if key in EVIDENCE_LABELS:
            return EVIDENCE_LABELS[key]
    return ".".join(parts) or "Warning record"


def rebuild_line(v):
    fixed, new = len(v.get("fixed", [])), len(v.get("new", []))
    if v.get("verified") is True:
        how = f" ({v['verified_by']})" if v.get("verified_by") else ""
        return f"- ✓ Rebuild check: QDoc was run with the fix; the warning is gone and no new warnings appeared{how}"
    reason = v.get("error") or (f"the warning is still there and {new} new warning(s) appeared" if new
                                else "the warning is still there")
    return f"- ✗ Rebuild check: not proven. QDoc was run with the fix, but {reason} (fixed {fixed}, new {new})"


def checks(rec, evidence, after, verified):
    lines = []
    for ev, value, ok in facts(rec, evidence):
        lines.append(f"- {'✓' if ok else '✗'} {label(ev)}: {value} [`{ev}`]")
    hits = after.get(rec["id"], [])
    lines.append("- ✓ New text passes the style checks (R39, R40, R47, R68, R4), the AI-writing checks, and the secrets check"
                 if not hits else
                 "- ✗ New text fails: " + "; ".join(f"{r} {x} ({w})" for w, r, x in hits))
    v = verified.get(str(rec["id"]))
    if v is not None:
        lines.append(rebuild_line(v))
    for check, passed, reason in rec["judge"]:
        lines.append(f"- {'✓' if passed else '✗'} {check.replace('-', ' ')} (*agent's judgment*): {reason}")
    lines.append(f"- Rules applied: {', '.join(rec['rules'])}")
    return lines


def unified(rec, root, context=3):
    """The record's edit as a git-style unified diff (applies with git apply)."""
    with open(os.path.join(root, rec["file"]), encoding="utf-8") as f:
        old = f.read().splitlines(keepends=True)
    a, b = rec["lines"]
    new = [l + "\n" for l in R.new_lines(rec)]
    mod = old[:a - 1] + new + old[b:]
    path = rec["file"]
    body = "".join(difflib.unified_diff(old, mod, f"a/{path}", f"b/{path}", n=context))
    return f"diff --git a/{path} b/{path}\n" + body


def diff(rec, root, context):
    return "```diff\n" + unified(rec, root, context).rstrip("\n") + "\n```"


def warning_of(rec, evidence):
    ok, w = R.resolve(evidence, rec["warn"])
    return w if ok else {}


def render_docdiff(recs, evidence, root, after, verified, context):
    out, total = [f"**Key:** {LEGEND}\n"], len(recs)
    for i, rec in enumerate(recs, 1):
        w = warning_of(rec, evidence)
        out.append(f"**Suggestion {i} of {total} for {os.path.basename(rec['file'])}:{rec['lines'][0]}:**\n")
        if w.get("message"):
            out.append(f"**Warning:** `{w['message']}`")
        out.append(f"**Category:** {CATEGORY.get(w.get('reference'), 'QDoc warning')}")
        out.append(f"**Source:** `{rec['file']}`\n")
        if rec.get("options"):
            out.append(f"**Cause:** {rec['cause']}\n\n**Fix Options:**")
            for n, o in enumerate(rec["options"], 1):
                out.append(f"{n}. {o.get('why', '')}")
            out.append(f"\n**Recommended:** Option {rec['pick']}\n")
            out.append(diff(rec, root, context) + "\n")
        else:
            out.append(diff(rec, root, context) + "\n")
            out.append(f"**Cause:** {rec['cause']}\n")
        out.append("**Validation:**")
        out += checks(rec, evidence, after, verified)
        out.append("")
        out.append("Which option should I apply? (1/2/3 or skip)" if rec.get("options")
                   else "Should I apply this fix to the file?")
        out.append("\n---\n")
    return "\n".join(out)


def render_gerrit(recs, evidence, root, after, verified, context):
    # Plain text only: Gerrit shows comments without Markdown (alt-formats.md).
    out = []
    for rec in recs:
        out.append(f"{rec['file']}:{rec['lines'][0]}")
        out.append(f"{rec['rules'][0]}: {rec['cause']}\n")
        out.append("```suggestion\n" + rec["new"] + "\n```\n")
    return "\n".join(out)


def render_plain(recs, evidence, root, after, verified, context):
    rows = []
    for rec in recs:
        issue = warning_of(rec, evidence).get("message", rec["cause"])
        fix = next((l.strip() for l in R.new_lines(rec) if l.strip()), "delete the lines")
        rows.append(f"Line {rec['lines'][0]}: {issue} ({rec['rules'][0]}). Fix: {fix}")
    return "\n".join(rows)


def render_codereview(recs, evidence, root, after, verified, context):
    out = ["# Proposed changes", "",
           f"{len(recs)} change(s). Each one lists what changes, why, the checks it passed, "
           "and the evidence behind it. The Validation and Evidence items come from tools, not the model.", ""]
    for i, rec in enumerate(recs, 1):
        w = warning_of(rec, evidence)
        out.append(f"## {i}. {rec['file']}:{rec['lines'][0]}")
        out.append("")
        if w.get("message"):
            out.append(f"**Reported by QDoc:** `{w['message']}`\n")
        out.append("**What changes:**\n")
        out.append(diff(rec, root, context) + "\n")
        out.append(f"**Why:** {rec['cause']}\n")
        if rec.get("options"):
            out.append("**Alternatives considered:**")
            for n, o in enumerate(rec["options"], 1):
                mark = " (chosen)" if n == rec["pick"] else ""
                out.append(f"{n}. {o.get('why', '')}{mark}")
            out.append("")
        out.append("**Checks:**")
        out += checks(rec, evidence, after, verified)
        out.append("")
    return "\n".join(out)


# Finding type and severity per warning template, using the skill-doc-audit
# 2.0 definitions: link failures prevent link resolution (CRITICAL); a
# public API without docs is a GAP that degrades accuracy (MODERATE).
AUDIT_CLASS = [
    ("Can't link to", "BROKEN", "CRITICAL"),
    ("No documentation for", "GAP", "MODERATE"),
    ("Undocumented", "GAP", "MODERATE"),
    ("Failed to find function", "BROKEN", "CRITICAL"),
    ("Missing image", "MISSING", "MODERATE"),
]


TYPE_MEANING = {"GAP": "public API with no documentation", "BROKEN": "a link or reference QDoc can't resolve",
                "MISSING": "a required file or element is missing", "INCOMPLETE": "documentation exists but is incomplete"}
SEV_MEANING = {"CRITICAL": "must fix: breaks the build, navigation, or links", "MODERATE": "should fix: readers miss information",
               "LOW": "nice to fix", "INFO": "no action needed"}


def audit_class(message):
    for prefix, ftype, severity in AUDIT_CLASS:
        if message.startswith(prefix):
            return ftype, severity
    return "INCOMPLETE", "LOW"


def short_target(text):
    """A readable form of a tool-call target: short paths, the real command."""
    s = text.replace("\n", " ")
    s = re.sub(r"/private/tmp/claude-\d+/[^ ]*?/scratchpad/", "scratchpad/", s)
    s = re.sub(r"/private/tmp/claude-\d+/", "tmp/", s)
    s = re.sub(r"/Users/[^/ ]+/code/cc-ph2/qtqa/doc_agent_framework/", "framework/", s)
    s = re.sub(r"/Users/[^/ ]+/code/cc-ph2/", "qt5/", s)
    s = re.sub(r"^(\s*[A-Z_]+=\S+;\s*)+", "", s)          # drop leading VAR=...; assignments
    s = re.sub(r"\$\{?[A-Z_]+\}?/", "", s)                # $R/file -> file
    return s if len(s) <= 90 else s[:89] + "…"


def execution_section(ex):
    """Execution record and input/output, for people (tables) and for LLMs (JSON)."""
    m, tm, tok, cost = ex.get("model", {}), ex.get("time", {}), ex.get("tokens", {}), ex.get("cost_usd") or {}
    match = m.get("matches")
    model_line = f"`{m.get('actual')}`"
    if m.get("requested"):
        flag = "" if match else " ⚠ **differs from the pin**"
        model_line = f"asked for `{m.get('requested')}` ({m.get('requested_source')}); ran on `{m.get('actual')}`{flag}"
    out = ["## Execution record", "",
           "How the agent ran, taken from its transcript by `execution_record.py` (no model involved).", "",
           "| Item | Value |", "|------|-------|",
           f"| Agent definition | `{ex.get('agent_definition')}` |",
           f"| Model | {model_line} |",
           f"| Effort | {ex.get('effort')} |",
           f"| Started / ended (UTC) | {tm.get('start')} / {tm.get('end')} |",
           f"| Duration | {tm.get('duration_s')} s |",
           f"| Model requests | {ex.get('requests')} |",
           f"| Tokens | cache write {tok.get('cache_creation_input_tokens', 0):,} · cache read {tok.get('cache_read_input_tokens', 0):,} · "
           f"output {tok.get('output_tokens', 0):,} (lower bound) · input {tok.get('input_tokens', 0):,} |",
           f"| Cost | **${cost.get('total', 0):.3f}** (cache write ${cost.get('cache_write', 0):.3f}, cache read ${cost.get('cache_read', 0):.3f}, "
           f"output ${cost.get('output', 0):.3f}); {ex.get('price_source')} |", "",
           "**Prompt given to the agent (verbatim):**", "", "```text", (ex.get("prompt") or "").strip(), "```", "",
           f"**Tool calls:** {len(ex.get('tool_calls', []))}, by class: "
           + ", ".join(f"{k} {v}" for k, v in ex.get("tool_call_classes", {}).items())
           + ". Classes are rule-based; *off-task* and *manual* calls are the ones to question.", "",
           "| # | Tool | Class | What | OK | Result size |", "|---|------|-------|------|----|-------------|"]
    for c in ex.get("tool_calls", []):
        what = short_target(c["target"]).replace("|", "\\|")
        out.append(f"| {c['n']} | {c['tool']} | {c['class']} | `{what}` | {'✓' if c['ok'] else '✗' if c['ok'] is False else '?'} | {c['result_chars']:,} chars |")
    out += ["", "## Input and output", "", "| Direction | File | Size | SHA-1 |", "|-----------|------|------|-------|"]
    for d, files in (("input", ex.get("inputs", [])), ("output", ex.get("outputs", []))):
        for f in files:
            out.append(f"| {d} | `{short_target(f['path'])}` | {f.get('bytes', 0):,} bytes | `{f.get('sha1', 'missing')}` |")
    out += ["", "**Execution record (machine-readable):**", "", "```json", json.dumps(ex, indent=1, ensure_ascii=False), "```", ""]
    return out


def render_audit(recs, evidence, root, after, verified, context, notes=None, title=None, execution=None):
    import datetime
    rows = []
    for rec in recs:
        w = warning_of(rec, evidence)
        ftype, sev = audit_class(w.get("message", ""))
        rows.append((rec, w, ftype, sev, CATEGORY.get(w.get("reference"), "QDoc warning")))
    cats = {}
    for _, _, _, sev, cat in rows:
        cats.setdefault(cat, {"CRITICAL": 0, "MODERATE": 0, "LOW": 0, "INFO": 0})[sev] += 1
    module = next((w.get("module") for _, w, *_ in rows if w.get("module")), "unknown module")
    ok = sum(1 for rec, *_ in rows if verified.get(str(rec["id"]), {}).get("verified") is True)
    out = [f"# {title or 'Documentation Warning Fix Audit: ' + module}", "",
           f"**Date:** {datetime.date.today().isoformat()}", "**Agent:** qdoc-warning-fixer",
           f"**Warnings in evidence:** {len(evidence.get('warnings', []))}",
           f"**Format:** skill-doc-audit 2.0, rendered by tools/doc-diff/render_record.py", "",
           f"**Key:** {LEGEND}", "", "## Summary", "", "| # | Category | CRITICAL | MODERATE | LOW | INFO | Status |",
           "|---|----------|----------|----------|-----|------|--------|"]
    for n, (cat, c) in enumerate(sorted(cats.items()), 1):
        status = "fix proposed" if ok == len(rows) else "needs review"
        out.append(f"| {n} | {cat} | {c['CRITICAL']} | {c['MODERATE']} | {c['LOW']} | {c['INFO']} | {status} |")
    out.append("")
    for i, (rec, w, ftype, sev, cat) in enumerate(rows, 1):
        v = verified.get(str(rec["id"]))
        out += ["---", "", f"**Finding {i} of {len(rows)}:**", "",
                f"**Type:** {ftype} ({TYPE_MEANING.get(ftype, '')})", f"**Severity:** {sev} ({SEV_MEANING[sev]})", f"**Category:** {cat}",
                f"**File:line:** `{rec['file']}:{rec['lines'][0]}`", "", "**Validation:**",
                f"- ✗ Problem reported by QDoc: `{w.get('message', '')}`"]
        out += checks(rec, evidence, after, verified)
        out += ["", f"**Cause:** {rec['cause']}", "", "**Fix:**", "", diff(rec, root, context), ""]
        if v is None:
            out.append("*Not rebuild-verified.*\n")
    out += ["## Notes", ""]
    notes = re.sub(r"^\s*#+\s*Notes\s*\n", "", notes or "")  # the Notes heading is already there
    out += [notes.strip(), ""] if notes.strip() else ["**Coverage:** every record passed lint_record.py and verify_after.py before rendering.", ""]
    if ok == len(rows):
        verdict = f"Ready for approval. All {len(rows)} fixes were rebuilt with QDoc; the warnings are gone and nothing new appeared."
    else:
        verdict = (f"Not ready. {len(rows) - ok} of {len(rows)} fixes couldn't be proven by a QDoc rebuild; "
                   "a person must check them, or rerun the rebuild, before approval.")
    out += ["## Verdict", "", f"**Result:** {verdict}", "", "**Checklist:**",
            f"- [{'x' if ok == len(rows) else ' '}] Every fix proven by a QDoc rebuild ({ok} of {len(rows)})",
            f"- [{'x' if not any(after.values()) else ' '}] New text passes the style, AI-writing, and secrets checks",
            "- [ ] Approved by a person", ""]
    if execution:
        out += execution_section(execution)
    summary = {"schema": "doc-agent-framework/audit-result/v1",
               "verdict": "ready" if ok == len(rows) else "not-ready",
               "verified": ok, "total": len(rows),
               "findings": [{"n": i, "record_id": rec["id"], "file": rec["file"], "line": rec["lines"][0],
                             "warning": w.get("message"), "type": ft, "severity": sv, "rules": rec["rules"],
                             "verified": verified.get(str(rec["id"]), {}).get("verified") is True,
                             "verified_by": verified.get(str(rec["id"]), {}).get("verified_by", "verify_fix.py" if str(rec["id"]) in verified else None),
                             "new_text_checks_pass": not after.get(rec["id"])}
                            for i, (rec, w, ft, sv, _) in enumerate(rows, 1)]}
    out += ["## Result summary (machine-readable)", "",
            "One entry per finding, and the verdict. The same data as the sections above.", "",
            "```json", json.dumps(summary, indent=1, ensure_ascii=False), "```"]
    return "\n".join(out)


FORMATS = {"doc-diff": render_docdiff, "gerrit": render_gerrit,
           "plain": render_plain, "codereview": render_codereview, "audit": render_audit}


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("records")
    p.add_argument("--evidence", required=True)
    p.add_argument("--root", required=True)
    p.add_argument("--format", choices=FORMATS, default="doc-diff")
    p.add_argument("--verify", help="JSON: record id -> verify_fix.py output")
    p.add_argument("--context", type=int, default=3, help="context lines (git default: 3)")
    p.add_argument("--notes", help="audit: Markdown file with the Notes section body")
    p.add_argument("--title", help="audit: report title")
    p.add_argument("--execution", help="audit: execution record JSON from execution_record.py")
    a = p.parse_args()
    recs = R.load_records(a.records)
    evidence = R.load_evidence(a.evidence)
    verified = json.load(open(a.verify, encoding="utf-8")) if a.verify else {}
    extra = {}
    if a.format == "audit":
        extra = {"notes": open(a.notes, encoding="utf-8").read() if a.notes else None, "title": a.title,
                 "execution": json.load(open(a.execution, encoding="utf-8")) if a.execution else None}
    try:
        print(FORMATS[a.format](recs, evidence, a.root, verify(recs), verified, a.context, **extra))
        ok = sum(1 for v in verified.values() if v.get("verified") is True)
        progress.done(f"rendered {len(recs)} record(s) as {a.format}"
                      + (f"; {ok} of {len(verified)} rebuild-verified" if verified else "; no rebuild results given"))
    except (OSError, IndexError) as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
