#!/usr/bin/env python3
"""Candidate 2 from docs/research/warp-self-improving-agents-article-audit-2026-08-28.md:
cluster type:feedback memories by which repo surface (skill/hook/script/doc) they
mention in prose, so recursive-improve's Observe step can see where human correction
has already accumulated -- without inventing a new memory-writing convention that
native ambient auto-memory (the majority writer, per skills/meta/learn/SKILL.md)
would never follow anyway.

Empirically validated against this repo's own store (2026-08-28, 83 feedback
memories): naive path-mention clustering surfaces real, repeated hits (hooks/gates/
x4, hooks/hooks.json x3, docs/METHODOLOGY.md x3) -- but 3 of the top 10 mentioned
paths no longer exist (renamed/retired surfaces). The existence filter below is not
optional polish; without it this signal is wrong about a third of the time.
"""
import collections
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))

# Reuse memory-lint's memory_dir() rather than re-deriving Claude Code's
# auto-memory path resolution (autoMemoryDirectory setting override, git-toplevel
# keying, CLAUDE_CODE_PROJECT_DIR_NAME) -- that logic is load-bearing and already
# has its own hard-won edge-case history; duplicating it here would be a second
# place for it to drift out of sync.
_spec = importlib.util.spec_from_file_location(
    "memory_lint", os.path.join(REPO_ROOT, "skills", "meta", "memory-lint", "scripts", "memory-lint.py")
)
assert _spec is not None and _spec.loader is not None, "memory-lint.py not found at expected path"
_memory_lint = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_memory_lint)

PATH_RE = re.compile(r"\b(?:skills|hooks|scripts|docs)/[A-Za-z0-9_./-]+")
TRAILING_PUNCT = ".,;:)]}'\""


def normalize(path):
    return path.rstrip(TRAILING_PUNCT).rstrip("/")


def surface_key(path):
    parts = path.split("/")
    return "/".join(parts[:3]) if len(parts) > 3 else path


def main():
    mem_dir = _memory_lint.memory_dir(sys.argv[1] if len(sys.argv) > 1 else None)
    if not os.path.isdir(mem_dir):
        print(f"no memory store found at {mem_dir}")
        return 0

    surfaces = collections.defaultdict(set)
    n_feedback = 0

    for fname in os.listdir(mem_dir):
        if not fname.endswith(".md") or fname == "MEMORY.md":
            continue
        text = open(os.path.join(mem_dir, fname), encoding="utf-8", errors="ignore").read()
        parts = text.split("---", 2)
        if len(parts) < 3:
            continue
        m = _memory_lint.TYPE_RE.search(parts[1])
        if not m or m.group(1) != "feedback":
            continue
        n_feedback += 1
        body = parts[2]
        for raw in PATH_RE.findall(body):
            clean = normalize(raw)
            if clean and os.path.exists(os.path.join(REPO_ROOT, clean)):
                surfaces[surface_key(clean)].add(fname)

    if n_feedback == 0:
        print("no type:feedback memories found")
        return 0

    clustered = {k: v for k, v in surfaces.items() if len(v) >= 2}
    if not clustered:
        print(f"{n_feedback} feedback memories scanned, no surface mentioned by 2+ of them")
        return 0

    print(f"{n_feedback} feedback memories scanned; surfaces mentioned by 2+ (heuristic, verify by reading):")
    for key, files in sorted(clustered.items(), key=lambda kv: -len(kv[1])):
        print(f"{len(files):3d}  {key}")
        for f in sorted(files):
            print(f"       {f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
