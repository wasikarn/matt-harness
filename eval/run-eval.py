#!/usr/bin/env python3
"""Eval harness entry point: run datasets, regressions, and gate.

Usage:
    python3 eval/run-eval.py --dataset eval/datasets/           # run all datasets
    python3 eval/run-eval.py --regression                       # run regressions only
    python3 eval/run-eval.py --dataset eval/datasets/ --gate    # CI mode: non-zero on failure
    python3 eval/run-eval.py --tag ship-change                  # filter by tag

Prerequisites:
    - Datasets are JSON files matching eval/SCHEMA.md.
    - Regression fixtures are JSON files in eval/regressions/.
    - scripts/run-acceptance.py exists (for acceptance-type evals).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
EVAL_DIR = REPO_ROOT / "eval"
DATASETS_DIR = EVAL_DIR / "datasets"
REGRESSIONS_DIR = EVAL_DIR / "regressions"
RESULTS_DIR = EVAL_DIR / "results"
RUN_ACCEPTANCE = REPO_ROOT / "scripts" / "run-acceptance.py"


def load_json_files(directory: Path) -> list[dict]:
    """Load all .json files from a directory."""
    entries = []
    if not directory.exists():
        return entries
    for p in sorted(directory.glob("*.json")):
        try:
            data = json.loads(p.read_text())
            data["_source_file"] = str(p.name)
            entries.append(data)
        except json.JSONDecodeError as e:
            print(f"  [WARN] Bad JSON in {p}: {e}", file=sys.stderr)
    return entries


def flatten_evals(datasets: list[dict]) -> list[dict]:
    """Flatten dataset files into individual eval records."""
    flat = []
    for ds in datasets:
        for ev in ds.get("evals", []):
            ev["_dataset_name"] = ds.get("dataset_name", ds.get("_source_file", "unknown"))
            flat.append(ev)
    return flat


def run_assertion_eval(eval_item: dict, verbose: bool) -> dict:
    """Run an assertion-type eval and return structured result."""
    ev_id = eval_item.get("id", "unknown")
    skill = eval_item.get("skill", "unknown")
    criteria = eval_item.get("success_criteria", [])
    context = eval_item.get("context", {})

    passed = 0
    failed = 0
    details = []

    # Strategy: for harness-audit evals, run the actual audit script
    if skill == "harness-audit":
        repo = context.get("repo_root", str(REPO_ROOT))
        try:
            result = subprocess.run(
                ["bash", str(REPO_ROOT / "skills" / "harness-audit" / "scripts" / "audit.sh"), repo],
                capture_output=True, text=True, timeout=60,
            )
            stdout = result.stdout + result.stderr
            for crit in criteria:
                crit_lower = crit.lower()
                # Exit-code checks first
                if re.search(r"\bexits?\s+0\b", crit_lower) and result.returncode == 0:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                if "non-zero" in crit_lower and result.returncode != 0:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                # Content checks
                if crit_lower in stdout.lower():
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                # Partial matches for common patterns
                # Smart keyword matching for prose criteria
                key_phrases = [p for p in re.findall(r"[a-z0-9_\-]+", crit_lower) if len(p) > 3]
                # Special case: "missing symlink" can match "not symlinked"
                synonyms = {"missing": ["not"], "symlink": ["symlinked"], "finding": ["crit", "warn"]}
                matched = 0
                for p in key_phrases:
                    if p in stdout.lower():
                        matched += 1
                    elif p in synonyms:
                        for syn in synonyms[p]:
                            if syn in stdout.lower():
                                matched += 1
                                break
                if matched >= max(1, len(key_phrases) // 2):
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                failed += 1; details.append({"criterion": crit, "status": "failed", "note": "not found in output"})
        except Exception as e:
            failed = len(criteria)
            details = [{"criterion": c, "status": "error", "error": str(e)} for c in criteria]

    # Strategy: for acceptance-contract evals, run run-acceptance.py if slug exists
    elif skill in ("ship-change", "review-pr", "pre-ship-verify") and "slug" in context:
        slug = context["slug"]
        acceptance_md = REPO_ROOT / ".scratch" / slug / "ACCEPTANCE.md"
        if acceptance_md.exists() and RUN_ACCEPTANCE.exists():
            try:
                result = subprocess.run(
                    [sys.executable, str(RUN_ACCEPTANCE), slug],
                    capture_output=True, text=True, timeout=120, cwd=REPO_ROOT,
                )
                results_json = REPO_ROOT / ".scratch" / slug / "acceptance-results.json"
                ar = json.loads(results_json.read_text()) if results_json.exists() else {}
                crit_counts = ar.get("criteria", [])
                ar_passed = sum(1 for c in crit_counts if c.get("result", {}).get("status") == "passed")
                ar_failed = sum(1 for c in crit_counts if c.get("result", {}).get("status") == "failed")
                ar_blocked = sum(1 for c in crit_counts if c.get("result", {}).get("status") == "blocked")
                for crit in criteria:
                    crit_lower = crit.lower()
                    if re.search(r"\bexits?\s+0\b", crit_lower) and result.returncode == 0:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "results.json" in crit_lower and results_json.exists():
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "exists" in crit_lower and acceptance_md.exists():
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if re.search(r"at least \d+ criteria passed", crit_lower):
                        m = re.search(r"at least (\d+)", crit_lower)
                        threshold = int(m.group(1)) if m else 1
                        if ar_passed >= threshold:
                            passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "zero criteria failed" in crit_lower and ar_failed == 0:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": "heuristic miss"})
            except Exception as e:
                failed = len(criteria)
                details = [{"criterion": c, "status": "error", "error": str(e)} for c in criteria]
        else:
            # No acceptance.md — test the "no contract" path
            for crit in criteria:
                crit_lower = crit.lower()
                if "no" in crit_lower and not acceptance_md.exists():
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                if "skip" in crit_lower:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                if "not found" in crit_lower and not acceptance_md.exists():
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                failed += 1; details.append({"criterion": crit, "status": "failed", "note": "no contract available"})

    # Default: heuristic pass (mark as skipped if we can't verify)
    else:
        for crit in criteria:
            details.append({"criterion": crit, "status": "skipped", "note": "no automated grader for this skill"})

    total = len(criteria)
    if failed > 0:
        status = "failed"
    elif all(d["status"] in ("passed", "skipped") for d in details):
        status = "passed" if passed == total else "warning"
    else:
        status = "failed"

    return {
        "id": ev_id,
        "skill": skill,
        "result": status,
        "passed": passed,
        "failed": failed,
        "total": total,
        "details": details,
    }


def run_regression_eval(eval_item: dict, verbose: bool) -> dict:
    """Run a regression fixture and verify the expected failure state."""
    base_result = run_assertion_eval(eval_item, verbose)
    expected_failure = eval_item.get("expected_failure", False)

    # Regression logic:
    # - expected_failure=true  → the task should FAIL (bug not fixed yet, or guard against recurrence)
    # - expected_failure=false → the task should PASS (bug is fixed, must stay fixed)
    actual_passed = base_result["result"] == "passed"

    if expected_failure:
        # We expect failure; if it passes, that's a regression (the bug recurred or test is stale)
        if actual_passed:
            reg_status = "regression"
            note = f"Expected failure but task passed — regression? (pattern: {eval_item.get('failure_pattern', 'unknown')})"
        else:
            reg_status = "passed"
            note = "Task still fails as expected (guard active)"
    else:
        # We expect pass; if it fails, that's a failure
        if actual_passed:
            reg_status = "passed"
            note = "Task passes as expected (fix holds)"
        else:
            reg_status = "failed"
            note = f"Expected pass but task failed — guard broken? (pattern: {eval_item.get('failure_pattern', 'unknown')})"

    return {
        **base_result,
        "result": reg_status,
        "regression_note": note,
        "expected_failure": expected_failure,
    }


def filter_by_tag(eval_items: list[dict], tag: str | None) -> list[dict]:
    if not tag:
        return eval_items
    return [ev for ev in eval_items if tag in ev.get("tags", [])]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run eval harness")
    parser.add_argument("--dataset", type=str, help="Directory containing dataset JSON files")
    parser.add_argument("--regression", action="store_true", help="Run regression fixtures only")
    parser.add_argument("--gate", action="store_true", help="Exit non-zero on any failure/regression")
    parser.add_argument("--tag", type=str, help="Filter evals by tag")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print per-eval details")
    parser.add_argument("--output", "-o", type=str, help="Override results directory")
    args = parser.parse_args()

    results_dir = Path(args.output) if args.output else RESULTS_DIR
    results_dir.mkdir(parents=True, exist_ok=True)
    run_id = time.strftime("%Y-%m-%dT%H-%M-%SZ", time.gmtime())
    run_dir = results_dir / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    all_results = []
    overall_passed = 0
    overall_failed = 0
    overall_regressions = 0
    overall_skipped = 0

    # ---- Datasets ----
    if args.dataset:
        ds_path = Path(args.dataset)
        if not ds_path.exists():
            print(f"Error: dataset directory not found: {ds_path}", file=sys.stderr)
            return 1
        datasets = load_json_files(ds_path)
        evals = filter_by_tag(flatten_evals(datasets), args.tag)
        print(f"Running {len(evals)} eval(s) from {len(datasets)} dataset(s)...", file=sys.stderr)
        for ev in evals:
            if args.verbose:
                print(f"  [{ev['id']}] running...", file=sys.stderr)
            result = run_assertion_eval(ev, args.verbose)
            all_results.append(result)
            if result["result"] == "passed":
                overall_passed += 1
            elif result["result"] == "failed":
                overall_failed += 1
            else:
                overall_skipped += 1
            if args.verbose:
                print(f"    → {result['result']} ({result['passed']}/{result['total']})", file=sys.stderr)

    # ---- Regressions ----
    if args.regression or (not args.dataset and not args.regression):
        # Default: if neither flag, run both datasets (if default dir exists) and regressions
        if not args.dataset and DATASETS_DIR.exists() and any(DATASETS_DIR.glob("*.json")):
            datasets = load_json_files(DATASETS_DIR)
            evals = filter_by_tag(flatten_evals(datasets), args.tag)
            print(f"Running {len(evals)} eval(s) from default datasets/...", file=sys.stderr)
            for ev in evals:
                if args.verbose:
                    print(f"  [{ev['id']}] running...", file=sys.stderr)
                result = run_assertion_eval(ev, args.verbose)
                all_results.append(result)
                if result["result"] == "passed":
                    overall_passed += 1
                elif result["result"] == "failed":
                    overall_failed += 1
                else:
                    overall_skipped += 1
                if args.verbose:
                    print(f"    → {result['result']} ({result['passed']}/{result['total']})", file=sys.stderr)

        regressions = load_json_files(REGRESSIONS_DIR)
        reg_evals = filter_by_tag(flatten_evals(regressions), args.tag)
        print(f"Running {len(reg_evals)} regression fixture(s)...", file=sys.stderr)
        for ev in reg_evals:
            if args.verbose:
                print(f"  [{ev['id']}] running regression...", file=sys.stderr)
            result = run_regression_eval(ev, args.verbose)
            all_results.append(result)
            if result["result"] == "passed":
                overall_passed += 1
            elif result["result"] == "regression":
                overall_regressions += 1
            elif result["result"] == "failed":
                overall_failed += 1
            else:
                overall_skipped += 1
            if args.verbose:
                print(f"    → {result['result']} ({result.get('regression_note', '')})", file=sys.stderr)

    # ---- Summary ----
    summary = {
        "run_id": run_id,
        "args": vars(args),
        "summary": {
            "total": len(all_results),
            "passed": overall_passed,
            "failed": overall_failed,
            "regressions": overall_regressions,
            "skipped": overall_skipped,
        },
        "results": all_results,
    }

    summary_path = run_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2))
    print(f"\nResults written to: {summary_path}", file=sys.stderr)

    # Console summary
    print(f"\n{'='*40}", file=sys.stderr)
    print(f"Eval Run: {run_id}", file=sys.stderr)
    print(f"  Total:      {len(all_results)}", file=sys.stderr)
    print(f"  Passed:     {overall_passed}", file=sys.stderr)
    print(f"  Failed:     {overall_failed}", file=sys.stderr)
    print(f"  Regressions: {overall_regressions}", file=sys.stderr)
    print(f"  Skipped:    {overall_skipped}", file=sys.stderr)
    print(f"{'='*40}", file=sys.stderr)

    if args.gate and (overall_failed > 0 or overall_regressions > 0):
        print("\n[GATE] FAIL — exiting non-zero", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
