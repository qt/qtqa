# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Progress output for the framework tools, so people can see a long run working.

Messages go to stderr; stdout stays clean for the JSON that tools read.
Set DOC_AGENT_QUIET=1 (or call quiet()) to turn them off.

    import progress
    progress.step(1, 5, "Baseline build")
    with progress.heartbeat("QDoc build", log_path):
        subprocess.run(...)
    progress.done("Verified: the warning is gone")

Stdlib only.
"""
import os
import re
import sys
import threading
import time

_QUIET = os.environ.get("DOC_AGENT_QUIET") == "1"
_START = time.monotonic()
WARN_RE = re.compile(r"\((?:qdoc)\) warning:|: warning:")


def quiet(on=True):
    global _QUIET
    _QUIET = on
    os.environ["DOC_AGENT_QUIET"] = "1" if on else "0"   # child tools inherit it


def _elapsed():
    # Wall-clock time, so lines from nested tools (verify_fix -> build.py) line up.
    return time.strftime("%H:%M:%S")


def say(msg):
    if not _QUIET:
        print(f"[{_elapsed()}] {msg}", file=sys.stderr, flush=True)


def step(n, total, msg):
    say(f"Step {n}/{total}: {msg}")


def done(msg):
    say(f"Done: {msg}")


def _log_stats(path):
    try:
        with open(path, errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return None
    return len(lines), sum(1 for l in lines if WARN_RE.search(l))


class heartbeat:
    """Print a status line every `every` seconds until the block ends."""

    def __init__(self, label, log=None, every=None):
        self.label, self.log = label, log
        self.every = every or float(os.environ.get("DOC_AGENT_HEARTBEAT", "15"))
        self._stop = threading.Event()

    def _run(self):
        start = time.monotonic()
        while not self._stop.wait(self.every):
            s = int(time.monotonic() - start)
            extra = ""
            if self.log:
                stats = _log_stats(self.log)
                if stats:
                    extra = f", log {stats[0]:,} lines, {stats[1]:,} warnings so far"
            say(f"{self.label} still running ({s // 60}m {s % 60:02d}s{extra})")

    def __enter__(self):
        self._t0 = time.monotonic()
        say(f"{self.label} started")
        if not _QUIET:
            self._thread = threading.Thread(target=self._run, daemon=True)
            self._thread.start()
        return self

    def __exit__(self, *exc):
        self._stop.set()
        s = int(time.monotonic() - self._t0)
        say(f"{self.label} finished in {s // 60}m {s % 60:02d}s")
        return False
