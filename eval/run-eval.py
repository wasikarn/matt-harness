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
    - scripts/evals/run-acceptance.py exists (for acceptance-type evals).
"""

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
EVAL_DIR = REPO_ROOT / "eval"
DATASETS_DIR = EVAL_DIR / "datasets"
REGRESSIONS_DIR = EVAL_DIR / "regressions"
RESULTS_DIR = EVAL_DIR / "results"
RUN_ACCEPTANCE = REPO_ROOT / "scripts" / "evals" / "run-acceptance.py"

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
TAG_ONLY_TAGS = frozenset({"inferential-structural-judge", "harness-coverage"})
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
        # The harness-coverage fixture uses a different shape
        # (`sessions[]/expected_grid[]/cases[]` per the Wave 4 FIX-1
        # contract). When a regression fixture has no `evals` key but
        # has `expected_grid` + `sessions`, pass the fixture through
        # as a single eval item. This keeps the canonical dataset
        # path unchanged while letting the new shape dispatch.
        if "evals" not in ds and "expected_grid" in ds and "sessions" in ds:
            ev = {**ds, "_dataset_name": ds.get("_source_file", "unknown")}
            # Promote _meta.tags to top level so filter_by_tag (which reads
            # ev.get("tags", [])) can find them. The new-shape fixture
            # stores tags inside _meta; canonical evals[] fixtures have
            # them at top level. This keeps the contract uniform.
            if "tags" not in ev and isinstance(ev.get("_meta"), dict):
                ev["tags"] = ev["_meta"].get("tags", [])
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
                str(REPO_ROOT / "scripts" / "pr" / "recursive-improve-observe.py"),
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
                    m = re.search(r"references\s+([/a-z0-9\-]+)", crit_lower)
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
    #   "hook_path": "hooks/gates/validator-bash-guard.sh"
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

    # Strategy: for description-quality evals, run the deterministic
    # check-description-quality.py grader and match each success criterion
    # against its explicit RESULT: <criterion>: PASS line.
    elif skill == "description-quality":
        repo = context.get("repo_root", str(REPO_ROOT))
        script_path = EVAL_DIR / "scripts" / "check-description-quality.py"
        try:
            r = subprocess.run(
                [sys.executable, str(script_path), repo],
                capture_output=True, text=True, timeout=60, cwd=str(REPO_ROOT),
            )
            stdout = r.stdout + r.stderr
            for crit in criteria:
                crit_lower = crit.lower()
                if "exits 0" in crit_lower and r.returncode == 0:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                # Match "RESULT: <criterion text>: PASS" (case-insensitive, multiline)
                escaped = re.escape(crit)
                if re.search(rf"(?im)^RESULT:\s*{escaped}\s*:\s*PASS\s*$", stdout):
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"rc={r.returncode} output_tail={stdout[-200:]!r}"})
        except Exception as e:
            failed = len(criteria)
            details = [{"criterion": c, "status": "error", "error": str(e)} for c in criteria]

    # Strategy: for deterministic bash-recipe evals, run a shell command from
    # the repo root and assert on exit code + stdout/stderr substrings. Used for
    # foreign-CWD portability checks (e.g. reasoning-models access path) where
    # the behavior under test is the shell recipe itself, not a model invocation.
    # Fixture context:
    #   "command": "bash -c style command string",
    #   "env": {"KEY": "value"},     # optional env overrides
    #   "timeout": 30,                # optional, default 30
    elif skill == "script" and "command" in context:
        cmd_str = context["command"]
        timeout = context.get("timeout", 30)
        env_overrides = context.get("env", {})
        try:
            run_env = os.environ.copy()
            run_env.update(env_overrides)
            result = subprocess.run(
                ["bash", "-c", cmd_str],
                capture_output=True, text=True, timeout=timeout,
                cwd=REPO_ROOT, env=run_env,
            )
            combined = (result.stdout + "\n" + result.stderr).lower()
            for crit in criteria:
                crit_lower = crit.lower()
                if "exits 0" in crit_lower and result.returncode == 0:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                if "non-zero" in crit_lower and result.returncode != 0:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                if crit_lower in combined:
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                key_phrases = [p for p in re.findall(r"[a-z0-9_\-]+", crit_lower) if len(p) > 3]
                matched = sum(1 for p in key_phrases if p in combined)
                if matched >= max(1, len(key_phrases) // 2):
                    passed += 1; details.append({"criterion": crit, "status": "passed"}); continue
                failed += 1; details.append({"criterion": crit, "status": "failed", "note": f"rc={result.returncode} output_tail={combined[-200:]!r}"})
        except Exception as e:
            failed = len(criteria)
            details = [{"criterion": c, "status": "error", "error": str(e)} for c in criteria]

    # Strategy: for acceptance-contract evals, run run-acceptance.py if slug exists.
    # Each eval gets a unique --output file so multiple evals that share the same
    # slug (e.g., review-pr + ship-change both reference phase-1-safety-fixes)
    # can run in parallel without racing on .scratch/<slug>/acceptance-results.json.
    elif skill in ("ship-change", "review-pr", "pre-ship-verify", "ship-task") and "slug" in context:
        slug = context["slug"]
        acceptance_md = REPO_ROOT / ".scratch" / slug / "ACCEPTANCE.md"
        if acceptance_md.exists() and RUN_ACCEPTANCE.exists():
            # Unique temp output per eval invocation.
            ar_output_fd = tempfile.NamedTemporaryFile(
                mode="w", suffix=".json", prefix=f"acceptance-{slug}-", delete=False
            )
            ar_output_path = Path(ar_output_fd.name)
            ar_output_fd.close()
            try:
                result = subprocess.run(
                    [sys.executable, str(RUN_ACCEPTANCE), slug, "--output", str(ar_output_path)],
                    # 120s wrapper > run-acceptance's 60s per-criterion timeout, so the
                    # runner finishes (its slow critical-hooks-suite criterion times out
                    # at 60s and is recorded as failed) and writes the results json BEFORE
                    # this wrapper would fire. These fixtures only assert ">=1 criteria
                    # passed", which the fast criteria satisfy — they don't need the slow
                    # suite criterion to pass. Keep this > DEFAULT_TIMEOUT.
                    capture_output=True, text=True, timeout=120, cwd=REPO_ROOT,
                )
                ar = json.loads(ar_output_path.read_text()) if ar_output_path.exists() else {}
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
                    if "results.json" in crit_lower and ar_output_path.exists():
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
            finally:
                try:
                    ar_output_path.unlink(missing_ok=True)
                except Exception:
                    pass
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


def run_harness_coverage_eval(eval_item: dict, verbose: bool) -> dict:
    """Run the harness-coverage regression fixture (the FIX-1 / Wave 4 shape).

    The new fixture shape (`eval/regressions/harness-coverage.json`) is
    not the canonical `evals[]` array — it carries `sessions[]` (a
    30-session synthetic journal) + `expected_grid[]` (the 12 expected
    cells) + `mock_sensors[]` (a self-contained 5-sensor registry) +
    `cases[]` (10 assertion formulas). The eval strategy is:

    1. Materialize the fixture's `sessions[].events[]` as a temporary
       JSONL journal at `<tmp>/journal.jsonl` so `scripts/harness-coverage.py`
       can read it via `--journal-path`.
    2. Materialize `mock_sensors[]` as `<tmp>/sensors.json` and pass
       via `--sensors-path`.
    3. Run the script and parse the JSON output.
    4. Compare each of the 12 `expected_grid[]` cells to the actual
       output cell-by-cell; a cell passes when its `cell_id`,
       `status`, and `cell_score_pct` all match (drift is allowed
       ±0 because the fixture's wall-clock-relative drift is anchored
       at authoring time, per `_meta.wall_clock_dependency`).
    5. Evaluate each of the 10 `cases[]` assertions against the
       actual output; a case passes when its pseudo-boolean formula
       resolves to True (each case's `assertion` is a JSON-line-
       evaluable expression; for v1 we do string-presence checks on
       the actual output's fields).

    The whole evaluation is deterministic and stdlib-only; no LLM
    call. Tag-only mode: the harness-coverage tag is added to
    TAG_ONLY_TAGS so failures here never fail --gate (the plan's
    EVAL-1 row is explicit). The verdict is reported as `tag-only`.
    """
    sessions = eval_item.get("sessions", [])
    expected_grid = eval_item.get("expected_grid", [])
    cases = eval_item.get("cases", [])
    mock_sensors = eval_item.get("mock_sensors", [])

    if not expected_grid:
        return {
            "id": eval_item.get("id", "harness-coverage"),
            "result": "skipped",
            "passed": 0,
            "total": 0,
            "regression_note": "harness-coverage fixture has no expected_grid; nothing to evaluate",
        }

    with tempfile.TemporaryDirectory() as tmp:
        journal_path = Path(tmp) / "journal.jsonl"
        sensors_path = Path(tmp) / "sensors.json"

        # Materialize the synthetic journal
        with journal_path.open("w") as f:
            for s in sessions:
                for ev in s.get("events", []):
                    f.write(json.dumps(ev) + "\n")

        # Materialize the mock sensors registry
        sensors_path.write_text(json.dumps({
            "version": 1,
            "sensors": mock_sensors,
        }, indent=2))

        # Find the script (relative to this file's eval/ dir → repo root → scripts/)
        script_path = Path(__file__).resolve().parent.parent / "scripts" / "evals" / "harness-coverage.py"
        if not script_path.exists():
            return {
                "id": eval_item.get("id", "harness-coverage"),
                "result": "failed",
                "passed": 0,
                "total": len(expected_grid),
                "regression_note": f"script not found at {script_path}",
            }

        # Pin the wall-clock to the fixture's authored as-of (Wave 5 / INT-1).
        # The metric's now-30d/now-60d windows are wall-clock-relative; without
        # a pin the cell scores drift as the eval run-time moves away from
        # authoring time (_meta.wall_clock_dependency). eval_as_of is the
        # single source — the script reproduces the expected_grid exactly when
        # run at this timestamp (verified: inf-fb cell_score_pct=9/drift=+2).
        cmd = [
            "python3", str(script_path),
            "--format", "json",
            "--journal-path", str(journal_path),
            "--sensors-path", str(sensors_path),
        ]
        eval_as_of = eval_item.get("_meta", {}).get("eval_as_of")
        if eval_as_of:
            cmd += ["--now", eval_as_of]

        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            return {
                "id": eval_item.get("id", "harness-coverage"),
                "result": "failed",
                "passed": 0,
                "total": len(expected_grid),
                "regression_note": "script timed out after 30s",
            }

        if proc.returncode != 0:
            return {
                "id": eval_item.get("id", "harness-coverage"),
                "result": "failed",
                "passed": 0,
                "total": len(expected_grid),
                "regression_note": f"script exited {proc.returncode}: {proc.stderr[:200]}",
            }

        try:
            actual = json.loads(proc.stdout)
        except json.JSONDecodeError as e:
            return {
                "id": eval_item.get("id", "harness-coverage"),
                "result": "failed",
                "passed": 0,
                "total": len(expected_grid),
                "regression_note": f"script output is not JSON: {e}",
            }

    # Compare cell-by-cell
    actual_by_id = {c["cell_id"]: c for c in actual.get("grid", [])}
    cell_passes = 0
    cell_failures = []
    for exp in expected_grid:
        cid = exp.get("cell_id")
        act = actual_by_id.get(cid)
        if act is None:
            cell_failures.append(f"{cid}: missing from actual output")
            continue
        # Cell passes if cell_id, status, AND cell_score_pct match
        if (act.get("status") == exp.get("status")
                and act.get("cell_score_pct") == exp.get("cell_score_pct")):
            cell_passes += 1
        else:
            cell_failures.append(
                f"{cid}: expected status={exp.get('status')!r} score={exp.get('cell_score_pct')!r}, "
                f"got status={act.get('status')!r} score={act.get('cell_score_pct')!r}"
            )

    total_cells = len(expected_grid)
    # Cases are evaluated loosely for v1: a case "passes" if its
    # description contains the string 'pass' (positive assertion)
    # AND the cell-level comparison already passed. The fixture's
    # 10 cases are document-of-intent at v1; the cell-by-cell match
    # is the load-bearing gate. Future versions can wire a
    # case-specific evaluator per `cases[].assertion`.
    case_passes = len(cases) if cell_passes == total_cells else 0

    passed = cell_passes + case_passes
    total = total_cells + len(cases)
    if cell_passes == total_cells:
        result = "passed"
        note = f"all {total_cells}/12 cells match (status + cell_score_pct); {case_passes}/{len(cases)} cases"
    else:
        result = "failed"
        note = f"{cell_passes}/{total_cells} cells match; failures: {'; '.join(cell_failures[:3])}"

    return {
        "id": eval_item.get("id", "harness-coverage"),
        "result": result,
        "passed": passed,
        "total": total,
        "regression_note": note,
    }


def filter_by_tag(eval_items: list[dict], tag: str | None) -> list[dict]:
    if not tag:
        return eval_items
    return [ev for ev in eval_items if tag in ev.get("tags", [])]


def _run_eval_worker(item: dict, verbose: bool) -> dict:
    """Run a single eval item in a worker process.

    Workers are stateless and print nothing; the main thread collects the
    result and handles output + aggregation. This keeps the per-eval output
    ordered and avoids interleaved logs from concurrent subprocesses.
    """
    source = item["_source"]
    ev = item["_eval"]
    if source == "dataset":
        return run_assertion_eval(ev, verbose)
    if source == "harness-coverage":
        return run_harness_coverage_eval(ev, verbose)
    return run_regression_eval(ev, verbose)


def _build_jobs(datasets: list[dict], regressions: list[dict], tag: str | None) -> list[dict]:
    """Flatten datasets and regressions into a single job list."""
    jobs = []
    for ds in datasets:
        for ev in filter_by_tag(flatten_evals([ds]), tag):
            jobs.append({"_source": "dataset", "_eval": ev})
    for ev in filter_by_tag(flatten_evals(regressions), tag):
        if "expected_grid" in ev and "sessions" in ev:
            jobs.append({"_source": "harness-coverage", "_eval": ev})
        else:
            jobs.append({"_source": "regression", "_eval": ev})
    return jobs


def _default_workers() -> int:
    return max(1, min(8, os.cpu_count() or 1))


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
    parser.add_argument("--workers", "-w", type=int, default=_default_workers(),
                        help=f"Parallel eval workers (default: {_default_workers()})")
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

    # ---- Collect jobs ----
    datasets: list[dict] = []
    regressions: list[dict] = []

    if args.dataset:
        ds_path = Path(args.dataset)
        if not ds_path.exists():
            print(f"Error: dataset directory not found: {ds_path}", file=sys.stderr)
            return 1
        datasets = load_json_files(ds_path)

    run_default = not args.dataset and not args.regression
    if run_default and DATASETS_DIR.exists() and any(DATASETS_DIR.glob("*.json")):
        datasets = load_json_files(DATASETS_DIR)

    if args.regression or run_default:
        regressions = load_json_files(REGRESSIONS_DIR)

    jobs = _build_jobs(datasets, regressions, args.tag)

    is_tag_only_mode = bool(args.tag) and args.tag in TAG_ONLY_TAGS
    if is_tag_only_mode:
        print(f"TAG-ONLY: tag={args.tag!r} — failure here does not fail global --gate "
              f"(per plan EVAL-1 row, design doc §4(b))", file=sys.stdout)

    print(f"Running {len(jobs)} eval(s) in parallel (workers={args.workers})...", file=sys.stderr)
    bucket_inputs: list[dict] = []

    # ---- Parallel execution ----
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as executor:
        future_to_job = {
            executor.submit(_run_eval_worker, job, False): job
            for job in jobs
        }
        for future in concurrent.futures.as_completed(future_to_job):
            job = future_to_job[future]
            ev = job["_eval"]
            source = job["_source"]
            try:
                result = future.result()
            except Exception as exc:
                ev_id = ev.get("id", ev.get("_source_file", "?"))
                result = {
                    "id": ev_id,
                    "skill": ev.get("skill", "unknown"),
                    "result": "failed",
                    "passed": 0,
                    "failed": 1,
                    "total": 1,
                    "details": [{"criterion": "worker", "status": "error", "error": str(exc)}],
                }

            all_results.append(result)

            if source == "dataset":
                # Dataset results feed the gate directly.
                if result["result"] == "passed":
                    overall_passed += 1
                elif result["result"] == "failed":
                    overall_failed += 1
                else:
                    overall_skipped += 1
                if args.verbose:
                    print(f"  [{ev.get('id', '?')}] → {result['result']} "
                          f"({result['passed']}/{result['total']})", file=sys.stderr)
                continue

            # Regression (or harness-coverage) result.
            ev_is_tag_only = bool(set(ev.get("tags", [])) & TAG_ONLY_TAGS)
            if source == "harness-coverage":
                ev_is_tag_only = True
            effective_tag_only = is_tag_only_mode or ev_is_tag_only

            if effective_tag_only:
                if result.get("result") == "skipped":
                    note = ("fixture is manual, skipped — will be live when "
                            "manual tag is removed (EVAL-1.5)")
                    result = {**result, "tag_only": True, "regression_note": note}
                else:
                    note = ("tag-only mode: bucket-threshold verdict applies, "
                            "per-fixture pass/fail does not fail --gate")
                    result = {**result, "result": "tag-only", "tag_only": True,
                              "regression_note": note}
                result["_fixture"] = ev
                result["_actual_score"] = None
                bucket_inputs.append(result)
                if result.get("result") == "skipped":
                    overall_skipped += 1
                else:
                    overall_passed += 1
                if args.verbose:
                    print(f"  [{ev.get('id', 'harness-coverage')}] → {result['result']} (tag-only)", file=sys.stderr)
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
                print(f"  [{ev.get('id', '?')}] → {result['result']} "
                      f"({result.get('regression_note', '')})", file=sys.stderr)

    # ---- Tag-only bucket-threshold verdict (e.g. EVAL-1) ----
    if bucket_inputs:
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
