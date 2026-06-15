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

# Tags that run in "tag-only" mode: the runner emits per-fixture status,
# computes the bucket-threshold pass criterion, and never fails --gate.
# The first entry is `inferential-structural-judge` (FIX-1 fixture +
# EVAL-1 wiring) — its 10-fixture suite is the hand-curated countermeasure
# to Böckeler L476's "we put a lot of faith into the AI-generated tests"
# test-quality problem (design doc §4(b)). Tag-only means: even if all 10
# fixtures fail, --gate exits 0. EVAL-1.5 (future) will lift the `manual`
# tag on the fixtures and the bucket-threshold scoring will then take
# over from the placeholder. Add a tag here ONLY when the matching
# fixture file ships a bucket-threshold `expected_score_range` shape
# AND the plan explicitly opts in to tag-only failure.
TAG_ONLY_TAGS = frozenset({"inferential-structural-judge"})
BUCKET_THRESHOLD_PASS_PER_BUCKET = 4  # ≥ 4/5 in each bucket (per plan Q9)


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
    tags = eval_item.get("tags", [])

    # Manual evals: behavior is exercised by human review + sibling regression
    # tests, but no automated grader exists. Mark them with `tags: [..., "manual"]`
    # AND a `manual_reason:` field, and the runner skips them with a clear
    # note in the per-eval detail. The eval still appears in the result list
    # so an operator can see it was considered (not silently dropped). Tagged
    # as `skipped` (not `failed`) so it doesn't pollute the failure count.
    # See .scratch/eval-fidelity-triage-2026-06-12.md F5 for the rationale.
    if "manual" in tags:
        reason = eval_item.get("manual_reason", "no automated grader exists; behavior tested via sibling regressions + human review")
        return {
            "id": ev_id,
            "skill": skill,
            "result": "skipped",
            "passed": 0,
            "failed": 0,
            "total": len(criteria),
            "skipped": True,
            "details": [{"criterion": c, "status": "skipped", "note": reason} for c in criteria],
        }

    passed = 0
    failed = 0
    details = []

    # Strategy: for harness-audit evals, run the actual audit script
    if skill == "harness-audit":
        repo = context.get("repo_root", str(REPO_ROOT))
        # Allow evals to override the freshness threshold (default 180d in
        # audit.sh) so the freshness check is testable in a known state:
        # context.kbg_eval_max_age_days=0 forces the audit to flag every
        # `last_reviewed:` marker as stale, surfacing the "eval-target
        # freshness" finding on stdout for the runner's content-check.
        # See harness-audit-eval-freshness eval.
        env = None
        max_age = context.get("kbg_eval_max_age_days")
        if max_age is not None:
            env = os.environ.copy()
            env["KBG_EVAL_MAX_AGE_DAYS"] = str(max_age)
        try:
            result = subprocess.run(
                ["bash", str(REPO_ROOT / "skills" / "harness-audit" / "scripts" / "audit.sh"), repo],
                capture_output=True, text=True, timeout=60,
                env=env,
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
                synonyms = {"missing": ["not"], "finding": ["crit", "warn"]}
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

    # Strategy: for observe-script evals, set up a temp projects dir with a
    # mock stalled session (a session jsonl containing an unmatched Bash
    # tool_use whose timestamp is older than --stall-threshold-min), run
    # recursive-improve-observe.py with --projects-dir, and assert the
    # stall signal is surfaced. Closes the SYNTHESIS row #11 / P2.1 gap —
    # "stall signal silently swallowed".
    #
    # For debt-ceiling evals, the same skill supports a `mock_journal` array
    # of journal events (dict per event). The script reads from --journal,
    # so the mock journal is written to a temp file and passed via --journal.
    elif skill == "observe-script" and "command" in context:
        import tempfile

        cmd_str = context["command"]
        threshold = context.get("stall_threshold_min", 10)
        staleness = context.get("staleness_min", 30)
        # debt-ceiling evals inject a mock journal; their context also sets
        # debt_open_prs, debt_ceiling, and expected_debt_count.
        mock_journal = context.get("mock_journal")
        debt_open_prs = context.get("debt_open_prs")
        debt_ceiling = context.get("debt_ceiling", 5)
        expected_breach = context.get("expected_breach", False)

        with tempfile.TemporaryDirectory() as tmpdir:
            # Always build the mock projects dir (needed for the stall
            # posture section; harmless for debt-only evals).
            from datetime import datetime, timezone, timedelta
            old_ts = (datetime.now(timezone.utc) - timedelta(minutes=staleness)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
            mock_proj = Path(tmpdir) / "testproj" / "fakesession"
            mock_proj.mkdir(parents=True)
            (mock_proj / "fakesession.jsonl").write_text(json.dumps({
                "timestamp": old_ts,
                "message": {
                    "content": [{
                        "type": "tool_use",
                        "id": "toolu_mock1",
                        "name": "Bash",
                        "input": {"command": "sleep 9999"},
                    }],
                },
            }) + "\n")

            journal_path = None
            if mock_journal is not None:
                journal_path = Path(tmpdir) / "mock-journal.jsonl"
                with journal_path.open("w") as jf:
                    for e in mock_journal:
                        jf.write(json.dumps(e) + "\n")

            full_cmd = [
                sys.executable,
                str(REPO_ROOT / "scripts" / "recursive-improve-observe.py"),
                "--projects-dir", str(Path(tmpdir)),
                "--stall-threshold-min", str(threshold),
                "--debt-ceiling", str(debt_ceiling),
            ]
            if journal_path:
                full_cmd.extend(["--journal", str(journal_path)])
            if debt_open_prs is not None:
                full_cmd.extend(["--debt-open-prs", str(debt_open_prs)])

            try:
                r = subprocess.run(full_cmd, capture_output=True, text=True, timeout=30, cwd=REPO_ROOT)
                stdout = r.stdout
                for crit in criteria:
                    crit_lower = crit.lower()
                    if "exits 0" in crit_lower and r.returncode == 0:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "loop posture" in crit_lower and "loop posture" in stdout:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "stalled" in crit_lower and "STALLED" in stdout:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "suggested action" in crit_lower and ("interrupt" in stdout or "review" in stdout or "check loop" in stdout):
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "verification table" in crit_lower and "session" in stdout and "features" in stdout:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    # Debt-ceiling criteria
                    if "debt ledger" in crit_lower and "comprehension debt ledger" in stdout:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "debt-ceiling breached" in crit_lower or "debt-ceiling breached marker" in crit_lower:
                        if ("DEBT-CEILING BREACHED" in stdout) == expected_breach:
                            passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                        failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"expected_breach={expected_breach}, got {'BREACHED' if 'DEBT-CEILING BREACHED' in stdout else 'ok'}"}); continue
                    if "debt_count" in crit_lower:
                        # Look for the literal number from the mock journal.
                        # The expected count = open_prs + unverified_changes + unreviewed_audit_findings
                        # The fixture's success_criteria phrase names the expected count.
                        m = re.search(r"debt_count[^0-9]*(\d+)", crit_lower)
                        if m:
                            want = int(m.group(1))
                            m2 = re.search(r"debt_count:\s+(\d+)", stdout)
                            if m2 and int(m2.group(1)) == want:
                                passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                            failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"want debt_count={want} got {m2.group(1) if m2 else 'none'}"}); continue
                    # Heuristic substring fallback
                    if crit_lower in stdout.lower():
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"rc={r.returncode} stdout_tail={stdout[-200:]!r}"})
            except Exception as e:
                failed = len(criteria)
                details = [{"criterion": c, "status": "error", "error": str(e)} for c in criteria]

    # Strategy: for docs-check evals, read the listed files and check that
    # required phrases appear. Used for memory-contract regressions like
    # bounded-agent-spawning — a doc-only fixture is still a real fixture if
    # the doctrine is the contract.
    elif skill == "docs-check" and "files_to_check" in context and "required_phrases" in context:
        files = context["files_to_check"]
        phrases = context["required_phrases"]
        try:
            combined = ""
            for rel in files:
                p = REPO_ROOT / rel
                if p.exists():
                    combined += "\n" + p.read_text(encoding="utf-8")
            combined_lower = combined.lower()
            for crit in criteria:
                crit_lower = crit.lower()
                # "At least one of the checked files references X" → X in any
                if "at least one" in crit_lower and "references" in crit_lower:
                    # Extract the phrase after "references"
                    m = re.search(r"references\s+([a-z0-9\-]+)", crit_lower)
                    target = m.group(1) if m else ""
                    if target and target in combined_lower:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"{target!r} not found"}); continue
                if "at least one" in crit_lower and ("cap" in crit_lower or "fan-out" in crit_lower):
                    if "cap" in combined_lower and "fan-out" in combined_lower:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "cap" in combined_lower or "fan-out" in combined_lower:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": "neither 'cap' nor 'fan-out' found"}); continue
                if "word fan-out" in crit_lower:
                    if "fan-out" in combined_lower or "fan out" in combined_lower:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": "'fan-out' not found"}); continue
                # Fallback substring match against combined
                if crit_lower in combined_lower:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                failed += 1; details.append({"criterion": crit, "status": "failed", "note": "criterion not in combined content"})
        except Exception as e:
            failed = len(criteria)
            details = [{"criterion": c, "status": "error", "error": str(e)} for c in criteria]

    # Strategy: for hook-script evals, feed stdin JSON to a hook and check the
    # emitted permissionDecision. Closes the regression-coverage gap for code-
    # side contracts (audit F1 validator-bash-guard, F2 memory contracts, etc.)
    # that the harness-audit grader can't directly observe.
    #
    # Fixture context shape:
    #   "hook_path": "hooks/validator-bash-guard.sh"
    #   "stdin":     {"agent_type": "code-reviewer", "tool_input": {"command": "git push"}}
    #   "expected_decision": "deny"   # or "allow" or "" (fail-open = no JSON)
    #   "must_contain": ["VALIDATOR-BASH", "code-reviewer"]   # substrings in stdout
    elif skill == "hook-script" and "hook_path" in context and "stdin" in context:
        hook_path = REPO_ROOT / context["hook_path"]
        stdin_obj = context["stdin"]
        expected = context.get("expected_decision", "")
        must_contain = context.get("must_contain", [])
        # TaskCompleted-style gating (vendor convention: exit 2 + stderr, NOT
        # exit 0 + JSON permissionDecision). Added for P2.3 — the
        # KBG_ENFORCE_TASK_COMPLETED escape hatch. P2.3 also needs `env` to
        # inject the toggle. See eval/regressions/task-completed-enforcement.json.
        expected_exit = context.get("expected_exit_code")
        expected_stderr_list = context.get("expected_stderr", [])
        env_overrides = context.get("env", {})
        try:
            run_env = os.environ.copy()
            run_env.update(env_overrides)
            result = subprocess.run(
                ["bash", str(hook_path)],
                input=json.dumps(stdin_obj),
                capture_output=True, text=True, timeout=10,
                env=run_env,
            )
            stdout = result.stdout
            stderr = result.stderr
            # Try to parse the JSON decision (if any)
            decision = ""
            try:
                j = json.loads(stdout) if stdout.strip() else {}
                decision = (j.get("hookSpecificOutput") or {}).get("permissionDecision", "")
            except json.JSONDecodeError:
                pass
            for crit in criteria:
                crit_lower = crit.lower()
                # ---- TaskCompleted-style checks (exit code + stderr) ----
                # Run BEFORE permissionDecision checks so per-criterion routing
                # is unambiguous when a fixture mixes both shapes (currently no
                # fixture does — but the order prevents future ambiguity).
                if expected_exit is not None and f"exits {expected_exit}" in crit_lower:
                    if result.returncode == expected_exit:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"got rc={result.returncode}"}); continue
                # Negation: "stderr does not contain X" (asserts the hook stayed
                # silent on a specific signal — used to prove an escape hatch
                # actually turned off the gate's feedback). MUST run BEFORE the
                # positive "stderr contains X" check, because the substring
                # "contains" appears inside "does not contain" and would
                # otherwise route the wrong branch.
                if expected_stderr_list and "stderr" in crit_lower and "does not contain" in crit_lower:
                    hit = next((s for s in expected_stderr_list if s in stderr), None)
                    if hit is None:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"found {hit!r} in stderr but expected absence"}); continue
                if expected_stderr_list and "stderr" in crit_lower and "contains" in crit_lower:
                    hit = next((s for s in expected_stderr_list if s in stderr), None)
                    if hit is not None:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"missing one of {expected_stderr_list} in stderr={stderr!r}"}); continue
                # Decision checks
                if expected and f"permissiondecision equal to {expected}" in crit_lower:
                    if decision == expected:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"got decision={decision!r}"}); continue
                if not expected and "does not contain permissiondecision" in crit_lower:
                    if decision == "":
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"got decision={decision!r}"}); continue
                if not expected and "does not block the call" in crit_lower:
                    # Fail-open = hook exits 0 AND no decision emitted
                    if result.returncode == 0 and decision == "":
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"rc={result.returncode} decision={decision!r}"}); continue
                # must_contain substring checks — used for both allow/deny cases
                # e.g. "Output contains the mutation pattern name (git push)"
                if must_contain and "contains" in crit_lower:
                    hit = next((s for s in must_contain if s in stdout), None)
                    if hit is not None:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"missing one of {must_contain} in {stdout!r}"}); continue
                # Heuristic fallback
                key_phrases = [p for p in re.findall(r"[a-z0-9_\-]+", crit_lower) if len(p) > 3]
                matched = sum(1 for p in key_phrases if p in stdout.lower())
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
                    # Exit-code checks: "exits 0" / "exits 4" / "non-zero" etc.
                    m = re.search(r"\bexits?\s+(\d+)\b", crit_lower)
                    if m:
                        want = int(m.group(1))
                        if result.returncode == want:
                            passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                        failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"got rc={result.returncode}"}); continue
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
                    if "at least 1 criterion" in crit_lower and "blocked" in crit_lower and ar_blocked >= 1:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "0 criteria with status failed" in crit_lower and ar_failed == 0:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    if "0 criteria with status passed" in crit_lower and ar_passed == 0:
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

    # Strategy: for script-cli evals, run an arbitrary shell command and
    # assert on stdout/exit code. General-purpose "does this script
    # behave correctly?" grader — used by orchestrate-dispatch-schema.json
    # and any future script-contract regression where the existing
    # harness-audit / hook-script / observe-script graders don't fit.
    #
    # Fixture context shape:
    #   "command": "<shell command to run, relative to REPO_ROOT>"
    #   "expected_exit_code": <int> (optional, default 0)
    #   "timeout": <int seconds> (optional, default 30)
    #
    # Per-criterion routing (substring, run in order):
    #   - "rc=<N>" or "exits <N>" → matches if returncode == N
    #   - "stdout contains <literal>" → matches if literal in stdout
    #   - "stderr contains <literal>" → matches if literal in stderr
    #   - "exit code 0" → matches if returncode == 0
    #
    # Why this skill exists: hook-script is hardcoded to stdin JSON →
    # hook; observe-script is hardcoded to recursive-improve-observe.py;
    # harness-audit runs audit.sh. None fit a one-off CLI contract test.
    # script-cli is the catch-all, intentionally minimal — extend only
    # when a real fixture needs a new assertion shape.
    elif skill == "script-cli" and "command" in context:
        cmd_str = context["command"]
        expected_rc = context.get("expected_exit_code")
        timeout_s = context.get("timeout", 30)
        try:
            r = subprocess.run(
                cmd_str, shell=True, capture_output=True, text=True,
                timeout=timeout_s, cwd=str(REPO_ROOT),
            )
            stdout = r.stdout
            stderr = r.stderr
            for crit in criteria:
                crit_lower = crit.lower()
                # Exit-code assertions: crit starts with "rc=N" (anchored)
                # OR contains "exits N" / "exit code N" / "returns N".
                # Anchor on rc= to avoid false-matching "rc=4" inside a
                # "stdout contains rc=4" assertion (the literal "rc=" is
                # the ASSET, not the exit code).
                m = re.match(r"^rc\s*=\s*(\d+)\b", crit_lower)
                if m:
                    want = int(m.group(1))
                    if r.returncode == want:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"want rc={want} got {r.returncode}"}); continue
                m = re.search(r"\b(?:exits?|exit code|returns?)\s+(\d+)\b", crit_lower)
                if m:
                    want = int(m.group(1))
                    if r.returncode == want:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"want rc={want} got {r.returncode}"}); continue
                # "stdout contains <literal>" — extract the literal after "contains"
                m = re.search(r"stdout\s+contains\s+(.+)", crit_lower)
                if m:
                    literal = crit[len(crit) - len(m.group(1)):]  # preserve original case
                    if literal in stdout:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"missing {literal!r} in stdout (last 200 chars): {stdout[-200:]!r}"}); continue
                # "stderr contains <literal>"
                m = re.search(r"stderr\s+contains\s+(.+)", crit_lower)
                if m:
                    literal = crit[len(crit) - len(m.group(1)):]
                    if literal in stderr:
                        passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                    failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"missing {literal!r} in stderr"}); continue
                # "exit code 0" / "exits 0" / "returns 0" — bare 0 assertion
                if r.returncode == 0 and ("0" in crit_lower and ("exit" in crit_lower or "return" in crit_lower)):
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                # Heuristic substring fallback against stdout
                if crit_lower in stdout.lower():
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"rc={r.returncode} stdout_tail={stdout[-200:]!r}"})
        except subprocess.TimeoutExpired:
            failed = len(criteria)
            details = [{"criterion": c, "status": "error", "error": f"timeout after {timeout_s}s"} for c in criteria]
        except Exception as e:
            failed = len(criteria)
            details = [{"criterion": c, "status": "error", "error": str(e)} for c in criteria]

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
    # Pass through skipped evals (manual / no automated grader) without
    # re-classifying them as pass or fail. See run_assertion_eval's
    # `tags: [..., "manual"]` branch and
    # .scratch/eval-fidelity-triage-2026-06-12.md F5.
    if base_result.get("result") == "skipped":
        return base_result
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


def compute_bucket_threshold(fixture_results: list[dict]) -> dict:
    """Bucket-threshold pass criterion for inferential-structural-judge.

    Plan Q9: pass = (good_pass_count >= 4) AND (bad_pass_count >= 4).
    `good` bucket: expected_score_range[0] <= 3 (the agent should accept).
    `bad`  bucket: expected_score_range[0] >= 7 (the agent should escalate).
    A fixture is "passed" when the actual score (parsed from stdout
    echo, or 0 if the fixture was manual-skipped) lands inside the
    expected band:
      - good → actual in [1, 3]
      - bad  → actual in [7, 10]
    The returned dict carries both counts and a boolean `passes` so the
    runner can log the verdict AND keep --gate green (tag-only).
    """
    good_total = 0
    good_pass_count = 0
    bad_total = 0
    bad_pass_count = 0
    skipped_count = 0
    for r in fixture_results:
        ev = r.get("_fixture", {})
        expected = ev.get("expected_score_range")
        if not expected or len(expected) != 2:
            # No expected range — treat as skipped (not bucket-eligible)
            skipped_count += 1
            continue
        lo, _hi = expected
        # Pull the actual score from the per-fixture stdout (if the
        # fixture actually ran; manual-skipped fixtures report None).
        actual = r.get("_actual_score")
        if lo <= 3:
            # Good bucket — actual should be in [1, 3]
            good_total += 1
            if actual is not None and 1 <= actual <= 3:
                good_pass_count += 1
        elif lo >= 7:
            # Bad bucket — actual should be in [7, 10]
            bad_total += 1
            if actual is not None and 7 <= actual <= 10:
                bad_pass_count += 1
        else:
            # Score range in the 4-6 flag band — not bucket-eligible
            skipped_count += 1
    passes = (good_pass_count >= BUCKET_THRESHOLD_PASS_PER_BUCKET
              and bad_pass_count >= BUCKET_THRESHOLD_PASS_PER_BUCKET)
    return {
        "good_total": good_total,
        "good_pass_count": good_pass_count,
        "bad_total": bad_total,
        "bad_pass_count": bad_pass_count,
        "skipped": skipped_count,
        "passes": passes,
    }


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
        # Tag-only mode: this tag is in TAG_ONLY_TAGS (e.g.
        # `inferential-structural-judge`). Failures here MUST NOT
        # fail --gate — the plan's EVAL-1 row is explicit ("tag-only
        # failure mode"). We still run every fixture (so the
        # bucket-threshold verdict is computable), but the per-fixture
        # result is re-classified as `tag-only` (or `skipped` if the
        # fixture is also tagged `manual`) and contributes zero to
        # overall_failed / overall_regressions.
        is_tag_only_mode = bool(args.tag) and args.tag in TAG_ONLY_TAGS
        if is_tag_only_mode and reg_evals:
            print(f"TAG-ONLY: tag={args.tag!r} — failure here does not fail global --gate "
                  f"(per plan EVAL-1 row, design doc §4(b))", file=sys.stdout)
        print(f"Running {len(reg_evals)} regression fixture(s)...", file=sys.stderr)
        bucket_inputs: list[dict] = []  # populated only in tag-only mode
        for ev in reg_evals:
            if args.verbose:
                print(f"  [{ev['id']}] running regression...", file=sys.stderr)
            result = run_regression_eval(ev, args.verbose)
            all_results.append(result)
            if is_tag_only_mode:
                # Re-classify: tag-only fixtures never fail the gate.
                # Preserves the base result in `result["result"]` only
                # if the fixture was `skipped` (manual) — that stays
                # `skipped` so the per-eval detail is honest. Otherwise
                # stamp the result as `tag-only` with a clear note.
                if result.get("result") == "skipped":
                    note = ("fixture is manual, skipped — will be live when "
                            "manual tag is removed (EVAL-1.5)")
                    result = {**result, "tag_only": True, "regression_note": note}
                else:
                    note = ("tag-only mode: bucket-threshold verdict applies, "
                            "per-fixture pass/fail does not fail --gate")
                    result = {**result, "result": "tag-only", "tag_only": True,
                              "regression_note": note}
                # Capture stdout for the bucket-threshold score parser
                # (only meaningful for fixtures that actually ran;
                # manual-skipped fixtures have no stdout).
                result["_fixture"] = ev
                # _actual_score stays None in the stub state: the
                # runner's run_regression_eval does not capture stdout,
                # and the inferential-structural-judge fixtures are
                # echo-only stubs until EVAL-1.5 wires the agent
                # dispatcher. When that lands, the agent's verdict
                # JSONL will be parsed for the actual score here.
                result["_actual_score"] = None
                bucket_inputs.append(result)
                # Counts: tag-only fixtures show as `passed` in the
                # console summary (the tag-only verdict is itself a
                # "pass the gate" event), with skipped/manual ones
                # counted as `skipped`.
                if result.get("result") == "skipped":
                    overall_skipped += 1
                else:
                    overall_passed += 1
                if args.verbose:
                    print(f"    → {result['result']} (tag-only) "
                          f"{result.get('regression_note', '')}", file=sys.stderr)
                continue
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

        # ---- Tag-only bucket-threshold verdict (e.g. EVAL-1) ----
        if is_tag_only_mode and bucket_inputs:
            bt = compute_bucket_threshold(bucket_inputs)
            verdict = "PASS" if bt["passes"] else "FAIL"
            print(
                f"TAG-ONLY: bucket-threshold verdict = {verdict} "
                f"(good: {bt['good_pass_count']}/{bt['good_total']} >= "
                f"{BUCKET_THRESHOLD_PASS_PER_BUCKET}, "
                f"bad: {bt['bad_pass_count']}/{bt['bad_total']} >= "
                f"{BUCKET_THRESHOLD_PASS_PER_BUCKET}, "
                f"skipped: {bt['skipped']})",
                file=sys.stdout,
            )

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
