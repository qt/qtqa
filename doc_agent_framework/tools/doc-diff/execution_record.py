#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Build the execution record of an agent run from its transcript.

    execution_record.py TRANSCRIPT.jsonl [--agent-def AGENT.md]
                        [--input FILE ...] [--output FILE ...]
                        [--work-dir DIR] [-o EXEC.json]

Reads the Claude Code subagent transcript (one JSON object per line) and
writes a JSON record: the prompt the agent got (verbatim), the model the
agent definition asks for and the model that ran, the effort level, the
start and end times, API usage per token type and its cost, every tool call
with a class and an outcome, and the input and output files with sizes and
SHA-1 checksums. No model is involved, so the record is exact.

Tool-call classes (rules, in order; the first match wins):
  setup      reads an agent definition or a skill
  input      reads a file given with --input, or an image
  verify     runs verify_fix, git apply, lint_record, verify_after, or render
  off-task   reads or greps a tool's own source code (tools/*.py)
  manual     inspects a verify_fix scratch directory by hand
  output     writes or edits a file in --work-dir
  report     the final hand-back
  task       anything else
Stdlib only.
"""
import argparse
import collections
import datetime
import hashlib
import json
import os
import re
import sys

# USD per million tokens, from the claude-api skill model table (cached
# 2026-06-24). 5-minute cache writes cost 1.25x input.
PRICES = {
    "claude-opus-5-5": {"input": 4.0, "output": 20.0, "cache_read": 0.20, "cache_write": 5.0},
    "claude-opus-5": {"input": 5.0, "output": 25.0, "cache_read": 0.50, "cache_write": 6.25},
    "claude-sonnet-5-5": {"input": 2.0, "output": 10.0, "cache_read": 0.20, "cache_write": 2.5},
    "claude-sonnet-5": {"input": 2.0, "output": 10.0, "cache_read": 0.20, "cache_write": 2.5},
}
PRICE_SOURCE = "claude-api skill model table (cached 2026-06-24); cache writes at 1.25x input (5-minute cache)"


def load(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def file_info(path):
    try:
        data = open(path, "rb").read()
    except OSError:
        return {"path": path, "exists": False}
    return {"path": path, "exists": True, "bytes": len(data), "sha1": hashlib.sha1(data).hexdigest()[:12]}


def frontmatter_model(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return None
    m = re.search(r"^---\n(.*?)\n---", text, re.S)
    mm = re.search(r"^model:\s*(\S+)", m.group(1), re.M) if m else None
    return mm.group(1) if mm else None


def classify(name, inp, inputs, work_dir):
    target = inp.get("file_path") or inp.get("command") or inp.get("pattern") or ""
    if name == "SubagentHandback":
        return "report", "final hand-back"
    if name == "Read":
        if re.search(r"/agents/[^/]+\.md$|/skills/.+\.md$", target):
            return "setup", target
        if target in inputs or re.search(r"\.(png|webp|jpe?g|gif|svg)$", target):
            return "input", target
        return "task", target
    if name in ("Write", "Edit"):
        return ("output" if work_dir and target.startswith(work_dir) else "task"), target
    if name == "Bash":
        cmd = target
        if re.search(r"(sed|cat|head|tail|grep|less)\b[^|;]*tools/[^ ]*\.py", cmd):
            return "off-task", cmd
        if "verify-fix-" in cmd:
            return "manual", cmd
        if re.search(r"verify_fix\.py|git (-C \S+ )?apply|lint_record\.py|verify_after\.py|render_record\.py", cmd):
            return "verify", cmd
        return "task", cmd
    return "task", target


def build(transcript, agent_def=None, inputs=(), outputs=(), work_dir=None):
    rows = load(transcript)
    prompt, model_counts, efforts, stamps = None, collections.Counter(), collections.Counter(), []
    usage = collections.defaultdict(dict)
    calls, results = [], {}
    def_reads, pin_seen = set(), []
    for d in rows:
        if d.get("timestamp"):
            stamps.append(d["timestamp"])
        if d.get("effort"):
            efforts[str(d["effort"])] += 1
        m = d.get("message") or {}
        content = m.get("content")
        if d.get("type") == "user" and prompt is None:
            if isinstance(content, str):
                prompt = content
            elif isinstance(content, list):
                texts = [b.get("text", "") for b in content if b.get("type") == "text"]
                if texts:
                    prompt = "\n".join(texts)
        if d.get("type") == "assistant":
            if m.get("model"):
                model_counts[m["model"]] += 1
            u = m.get("usage")
            if u:
                r = usage[d.get("requestId")]
                for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"):
                    r[k] = max(r.get(k, 0), u.get(k, 0) or 0)
            if isinstance(content, list):
                for b in content:
                    if b.get("type") == "tool_use":
                        cls, target = classify(b["name"], b.get("input", {}), set(inputs), work_dir)
                        if b["name"] == "Read" and re.search(r"/agents/[^/]+\.md$", target):
                            def_reads.add(b["id"])
                        calls.append({"n": len(calls) + 1, "id": b["id"], "tool": b["name"],
                                      "class": cls, "target": target[:300]})
        if d.get("type") == "user" and isinstance(content, list):
            for b in content:
                if b.get("type") == "tool_result":
                    c = b.get("content")
                    text = c if isinstance(c, str) else json.dumps(c)
                    results[b.get("tool_use_id")] = {"ok": not b.get("is_error", False), "chars": len(text)}
                    seen = re.search(r"^\s*\d*\s*model:\s*(\S+)", text, re.M)
                    if seen and b.get("tool_use_id") in def_reads:
                        pin_seen.append(seen.group(1).strip('\\n"'))
    for c in calls:
        r = results.pop(c["id"], {"ok": None, "chars": 0})
        c.update({"ok": r["ok"], "result_chars": r["chars"]})
        del c["id"]
    tok = {k: sum(r.get(k, 0) for r in usage.values())
           for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")}
    model = model_counts.most_common(1)[0][0] if model_counts else None
    price = PRICES.get(model)
    cost = None
    if price:
        parts = {"input": tok["input_tokens"] * price["input"] / 1e6,
                 "cache_write": tok["cache_creation_input_tokens"] * price["cache_write"] / 1e6,
                 "cache_read": tok["cache_read_input_tokens"] * price["cache_read"] / 1e6,
                 "output": tok["output_tokens"] * price["output"] / 1e6}
        cost = {k: round(v, 4) for k, v in parts.items()}
        cost["total"] = round(sum(parts.values()), 4)
    start = min(stamps) if stamps else None
    end = max(stamps) if stamps else None
    duration = None
    if start and end:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        duration = round((t(end) - t(start)).total_seconds(), 1)
    # The pin the agent saw at run time (from its own read of the definition);
    # the file on disk may have changed since.
    requested = pin_seen[0] if pin_seen else (frontmatter_model(agent_def) if agent_def else None)
    requested_source = ("agent's read of its definition during the run" if pin_seen
                        else "agent definition file now (may differ from run time)" if requested else None)
    return {
        "schema": "doc-agent-framework/execution-record/v1",
        "transcript": os.path.basename(transcript),
        "agent_definition": agent_def,
        "prompt": prompt,
        "model": {"requested": requested, "requested_source": requested_source, "actual": model,
                  "matches": (requested == model) if requested and model else None,
                  "all_turns": dict(model_counts)},
        "effort": efforts.most_common(1)[0][0] if efforts else None,
        "time": {"start": start, "end": end, "duration_s": duration},
        "requests": len(usage),
        "tokens": tok,
        "tokens_note": "output_tokens is a lower bound: the transcript logs usage when a stream starts",
        "cost_usd": cost,
        "price_source": PRICE_SOURCE if cost else f"no price for model {model}",
        "tool_calls": calls,
        "tool_call_classes": dict(collections.Counter(c["class"] for c in calls)),
        "tool_call_classes_note": "rule-based (see execution_record.py); a person should confirm off-task and manual calls",
        "inputs": [file_info(p) for p in inputs],
        "outputs": [file_info(p) for p in outputs],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("transcript")
    p.add_argument("--agent-def")
    p.add_argument("--input", action="append", default=[])
    p.add_argument("--output", action="append", default=[])
    p.add_argument("--work-dir")
    p.add_argument("-o", "--out", help="write the JSON here (default: stdout)")
    a = p.parse_args()
    rec = build(a.transcript, a.agent_def, a.input, a.output, a.work_dir)
    text = json.dumps(rec, indent=1, ensure_ascii=False)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(text + "\n")
        print(f"wrote {a.out}: {len(rec['tool_calls'])} tool calls, {rec['requests']} requests, "
              f"${(rec['cost_usd'] or {}).get('total', 0):.3f}", file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
