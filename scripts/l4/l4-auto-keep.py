#!/usr/bin/env python3
"""l4-auto-keep.py — the L4 auto-apply writer (design §6, ADR 0004 #4).

Inside an authorized L4 run, consume the TOP-confidence candidate from the capture
queue and write it as a durable memory/<slug>.md via the SAME write path kbg:learn
uses (Step 5), then dispose it from the queue. LOCAL-ONLY + ship-gated: the writer
has NO ship verb (no git-push, no gh-CLI call) — the file stays local until Gate 2.

Confidence ORDERS (the upstream read-candidates.sh LIST is already sorted desc), it
never GATES: this file reads NO confidence number, only the first row — audit #47
blocker-A positively asserts there is no confidence comparison operator here. The
writer runs ONLY inside an armed run (autonomy_on, imported from loop-guard so
the predicate is not duplicated + this file carries no raw arming-key literal,
keeping audit #48c clean). memory/ is intentionally uncaged (the loop must write
there); the brakes are the push-gate + check-act (which exempts the sanctioned
memory dir — see loop-guard._memory_dir).

With the autonomy flag unset, nothing here runs; kbg:learn's Step-4 AskUserQuestion
gate path is byte-identical (the writer is a separate, armed-only path, not a
modification of the human-gated flow).

Usage:
  l4-auto-keep.py [--transcript <path>]   # auto-keep the top candidate
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPTS = SCRIPT_DIR.parent

# Reuse the canonical autonomy_on() (scripts/loop-guard.py) — no duplication of
# the predicate, and no raw KBG_AUTONOMY literal in this file (keeps #48c clean).
_spec = importlib.util.spec_from_file_location("_kbg_lg", SCRIPTS / "loop-guard.py")
if _spec is None or _spec.loader is None:
    sys.exit("l4-auto-keep: cannot load loop-guard.autonomy_on")
_lg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_lg)

KIND_TO_TYPE = {"correction": "feedback", "preference": "user", "workflow": "project"}


def _mem_dir(transcript):
    """The memory dir the writer targets. With a transcript, derive from its parent
    (matching read-candidates.sh); else from CLAUDE_PROJECT_DIR (the fallback)."""
    if transcript and Path(transcript).exists():
        return Path(transcript).resolve().parent / "memory"
    proj = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    slug = proj.replace("/", "-")
    return Path(os.path.expanduser("~/.claude/projects")) / slug / "memory"


def _list_candidates(transcript):
    """Run read-candidates.sh LIST; return parsed rows (already sorted by confidence
    desc). The writer takes only the FIRST — it reads no confidence number."""
    cmd = ["bash", str(SCRIPTS / "read-candidates.sh")]
    if transcript:
        cmd += ["--transcript", transcript]
    r = subprocess.run(cmd, capture_output=True, text=True)
    rows = []
    for ln in r.stdout.splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            rows.append(json.loads(ln))
        except json.JSONDecodeError:
            continue
    return rows


def _slugify(text, max_len=40):
    s = re.sub(r"[^a-z0-9]+", "-", str(text).lower()).strip("-")
    return (s[:max_len].rstrip("-") or "learning")


def _write_memory(mem_dir, row):
    """Write memory/<slug>.md + a MEMORY.md pointer (the kbg:learn Step-5 path).
    Returns the path written, or None if the file already exists (dedupe — never
    overwrite a hand-written memory; the queue should have drained it, but
    defense-in-depth)."""
    kind = row.get("kind", "preference")
    mtype = KIND_TO_TYPE.get(kind, "user")
    trigger = row.get("trigger", "")
    evidence = row.get("evidence", "")
    slug = _slugify(trigger or evidence)
    path = mem_dir / f"{slug}.md"
    if path.exists():
        return None
    description = (trigger or evidence or "auto-kept learning")[:120].strip()
    body = (evidence.strip() or trigger.strip() or "(no evidence captured)")
    out = [
        "---",
        f"name: {slug}",
        f"description: {description}",
        "metadata:",
        f"  type: {mtype}",
        "---",
        "",
        f"Auto-kept from a repeated `{kind}` signal across sessions (kbg:learn "
        f"capture queue, L4 auto-apply — ADR 0004 #4).",
        "",
        body,
    ]
    if mtype in ("feedback", "project"):
        out += ["",
                f"**Why:** the `{trigger}` signal recurred across sessions — the "
                "operator hit this more than once.",
                "**How to apply:** surface this next session; confirm against the "
                "current repo state before relying on it."]
    path.write_text("\n".join(out) + "\n", encoding="utf-8")
    # MEMORY.md pointer (the Step-5 index line).
    idx = mem_dir / "MEMORY.md"
    existing = idx.read_text(encoding="utf-8") if idx.exists() else ""
    if f"({slug}.md)" not in existing:
        idx.write_text(existing.rstrip() + "\n" + f"- [{slug}]({slug}.md) — {description}\n",
                       encoding="utf-8")
    return path


def _archive(transcript, key):
    """Dispose the promoted candidate so it cannot be double-promoted."""
    if not key:
        return
    cmd = ["bash", str(SCRIPTS / "read-candidates.sh"), "--archive", key, "promoted"]
    if transcript:
        cmd += ["--transcript", transcript]
    subprocess.run(cmd, capture_output=True, text=True)


def main():
    transcript = ""
    args = sys.argv[1:]
    while args:
        if args[0] == "--transcript" and len(args) > 1:
            transcript = args[1]
            args = args[2:]
        else:
            args = args[1:]
    if not _lg.autonomy_on():
        sys.exit("l4-auto-keep: autonomy flag not armed (per-repo) — refuse to auto-write")
    mem = _mem_dir(transcript)
    rows = _list_candidates(transcript)
    if not rows:
        return  # nothing staged — exit 0
    top = rows[0]
    written = _write_memory(mem, top)
    _archive(transcript, top.get("key", ""))
    if written is not None:
        print(f"l4-auto-keep: wrote {written}")


if __name__ == "__main__":
    main()