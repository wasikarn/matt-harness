#!/usr/bin/env python3
"""Held-out eval for GH #120's delegation-ratio trigger specifically (not
the plan-mode heredoc). Scores whether the "Broad/multi-file scope detected"
marker fires/stays-silent against a label, per category. Not derived from
tests/hooks/test-flow-nudge.sh's own cases -- fresh prompts, same discipline
as docs/research/plan-mode-nudge-audit-2026-08-05.md's held-out methodology.

Run from repo root: python3 scripts/research/delegation-nudge-eval-2026-09-01.py
Shipped result (2026-09-01, post adjective-gap fix): n=24 TP=8 FP=0 TN=15 FN=1,
precision=1.000 recall=0.889. The one miss (R2, "controller" as the artifact
noun) is a documented, deliberately unfixed gap -- see FILES_NOUN's scope note
in hooks/advisory/flow-nudge.sh.
"""
import json
import subprocess
from collections import defaultdict

HOOK = "hooks/advisory/flow-nudge.sh"
MARKER = "Broad/multi-file scope detected"

cases = [
    # read/research-heavy, >3 files named -> should fire (the exact gap #120 closes)
    {"id": "R1", "category": "read-research-many-files", "prompt": "read through these 6 files and explain the auth flow", "expected": True},
    {"id": "R2", "category": "read-research-many-files", "prompt": "go over every controller in the api directory and list what each one does", "expected": True},
    {"id": "R3", "category": "read-research-many-files", "prompt": "audit the 5 config files for hardcoded secrets", "expected": True},
    {"id": "R4", "category": "read-research-many-files", "prompt": "scan every script in the deploy folder for hardcoded paths", "expected": True},
    {"id": "R5", "category": "read-research-many-files", "prompt": "can you look through all the modules in src/services and tell me which ones still use the old logger", "expected": True},
    # single-file / trivial read -> should stay silent
    {"id": "S1", "category": "single-file-read", "prompt": "read auth.ts and tell me what it does", "expected": False},
    {"id": "S2", "category": "single-file-read", "prompt": "check this one file for bugs", "expected": False},
    {"id": "S3", "category": "single-file-read", "prompt": "look at the README and summarize it", "expected": False},
    {"id": "S4", "category": "single-file-read", "prompt": "what does this function do", "expected": False},
    # discussion/question, no files at all -> should stay silent
    {"id": "D1", "category": "discussion-question", "prompt": "what's the difference between let and const", "expected": False},
    {"id": "D2", "category": "discussion-question", "prompt": "why did the last deploy fail", "expected": False},
    {"id": "D3", "category": "discussion-question", "prompt": "how does jwt expiration work", "expected": False},
    # impl verb + many files -> should fire (files+breadth applies regardless of IMPL)
    {"id": "I1", "category": "impl-many-files", "prompt": "refactor these 6 modules to use the new logger", "expected": True},
    {"id": "I2", "category": "impl-many-files", "prompt": "migrate every script in the tools directory to typescript", "expected": True},
    # impl verb, single file / no breadth -> delegation trigger should stay silent
    # (plan-mode heredoc may still fire -- only checking the MARKER here)
    {"id": "I3", "category": "impl-no-breadth", "prompt": "add a rate limiter to the public api", "expected": False},
    {"id": "I4", "category": "impl-no-breadth", "prompt": "fix the login bug in auth.ts", "expected": False},
    {"id": "I5", "category": "impl-no-breadth", "prompt": "implement dark mode for the settings page", "expected": False},
    # breadth word present but NOT about files -> should stay silent
    {"id": "B1", "category": "breadth-no-files", "prompt": "check this across every environment", "expected": False},
    {"id": "B2", "category": "breadth-no-files", "prompt": "the bug happens across all regions", "expected": False},
    {"id": "B3", "category": "breadth-no-files", "prompt": "validate this across every browser we support", "expected": False},
    # explicit count boundary: <=3 must NOT fire (anchor is ">~3 files")
    {"id": "C1", "category": "count-boundary-under", "prompt": "look at these 3 files and summarize them", "expected": False},
    {"id": "C2", "category": "count-boundary-under", "prompt": "review these 2 modules for style issues", "expected": False},
    # explicit count boundary: >3 must fire
    {"id": "C3", "category": "count-boundary-over", "prompt": "look at these 4 files and summarize them", "expected": True},
    {"id": "C4", "category": "count-boundary-over", "prompt": "review these 5 modules for style issues", "expected": True},
]

results = []
for c in cases:
    payload = json.dumps({"tool_name": "UserPromptSubmit", "prompt": c["prompt"]}, ensure_ascii=False)
    out = subprocess.run(["bash", HOOK], input=payload, capture_output=True, text=True)
    fired = MARKER in out.stdout
    expected = c["expected"]
    results.append({**c, "fired": fired, "correct": fired == expected})

tp = sum(1 for r in results if r["expected"] and r["fired"])
fp = sum(1 for r in results if not r["expected"] and r["fired"])
tn = sum(1 for r in results if not r["expected"] and not r["fired"])
fn = sum(1 for r in results if r["expected"] and not r["fired"])
precision = tp / (tp + fp) if (tp + fp) else float("nan")
recall = tp / (tp + fn) if (tp + fn) else float("nan")
f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else float("nan")
accuracy = (tp + tn) / len(results)

print(f"n={len(results)}  TP={tp} FP={fp} TN={tn} FN={fn}")
print(f"precision={precision:.3f}  recall={recall:.3f}  f1={f1:.3f}  accuracy={accuracy:.3f}\n")
by_cat = defaultdict(list)
for r in results:
    by_cat[r["category"]].append(r)
for cat, rs in sorted(by_cat.items()):
    n = len(rs)
    ok = sum(1 for r in rs if r["correct"])
    print(f"{cat:<24}{n:<5}{ok:<9}{ok/n:.2f}")
print("\nmisses:")
for r in results:
    if not r["correct"]:
        want = "FIRE" if r["expected"] else "SILENT"
        got = "FIRE" if r["fired"] else "SILENT"
        print(f"  [{r['id']}/{r['category']}] want={want} got={got} :: {r['prompt']}")
