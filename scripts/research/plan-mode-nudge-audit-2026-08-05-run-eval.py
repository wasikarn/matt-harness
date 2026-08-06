#!/usr/bin/env python3
"""Score hooks/advisory/flow-nudge.sh against a held-out eval set.
Usage: run_eval.py <hook_path> <cases.json> [label]
Prints per-category + overall precision/recall/F1, writes <label>.json.
"""
import json
import subprocess
import sys
from collections import defaultdict

hook_path, cases_path = sys.argv[1], sys.argv[2]
label = sys.argv[3] if len(sys.argv) > 3 else "run"

cases = json.load(open(cases_path))

results = []
for c in cases:
    payload = json.dumps({"tool_name": "UserPromptSubmit", "prompt": c["prompt"]}, ensure_ascii=False)
    out = subprocess.run(["bash", hook_path], input=payload, capture_output=True, text=True)
    fired = bool(out.stdout.strip())
    expected = c["expected"]
    correct = fired == expected
    results.append({**c, "fired": fired, "correct": correct})

# Confusion matrix overall
tp = sum(1 for r in results if r["expected"] and r["fired"])
fp = sum(1 for r in results if not r["expected"] and r["fired"])
tn = sum(1 for r in results if not r["expected"] and not r["fired"])
fn = sum(1 for r in results if r["expected"] and not r["fired"])

precision = tp / (tp + fp) if (tp + fp) else float("nan")
recall = tp / (tp + fn) if (tp + fn) else float("nan")
f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else float("nan")
accuracy = (tp + tn) / len(results)

print(f"=== {label}: {hook_path} ===")
print(f"n={len(results)}  TP={tp} FP={fp} TN={tn} FN={fn}")
print(f"precision={precision:.3f}  recall={recall:.3f}  f1={f1:.3f}  accuracy={accuracy:.3f}")
print()
print(f"{'category':<24}{'n':<5}{'correct':<9}{'acc':<7}")
by_cat = defaultdict(list)
for r in results:
    by_cat[r["category"]].append(r)
for cat, rs in sorted(by_cat.items()):
    n = len(rs)
    ok = sum(1 for r in rs if r["correct"])
    print(f"{cat:<24}{n:<5}{ok:<9}{ok/n:<7.2f}")

print()
print("misses:")
for r in results:
    if not r["correct"]:
        want = "NUDGE" if r["expected"] else "SILENT"
        got = "NUDGE" if r["fired"] else "SILENT"
        print(f"  [{r['id']}/{r['category']}] want={want} got={got} :: {r['prompt']}")

out_path = f"{label}.json"
json.dump(
    {
        "hook": hook_path,
        "n": len(results),
        "tp": tp, "fp": fp, "tn": tn, "fn": fn,
        "precision": precision, "recall": recall, "f1": f1, "accuracy": accuracy,
        "results": results,
    },
    open(out_path, "w"),
    indent=2, ensure_ascii=False,
)
print(f"\nwrote {out_path}")
