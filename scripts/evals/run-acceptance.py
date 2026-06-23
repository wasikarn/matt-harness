#!/usr/bin/env python3
"""
run-acceptance.py — execute machine-checkable acceptance criteria from ACCEPTANCE.md

Reads .scratch/<slug>/ACCEPTANCE.md, extracts the ## Criteria section,
runs executable criteria (shell commands in backticks or explicit command lines),
and writes structured results to acceptance-results.json.

Usage:
    python3 scripts/evals/run-acceptance.py <slug> [--timeout 30] [--verbose]
    python3 scripts/evals/run-acceptance.py phase-1-safety-fixes-2026-06-12

Exit codes:
    0 — all executable criteria passed (or no executable criteria found)
    1 — one or more executable criteria FAILED (the code under test is broken)
    2 — bad invocation (missing slug, no ACCEPTANCE.md, --cwd does not exist)
    3 — parse error (malformed ACCEPTANCE.md)
    4 — at least one criterion was BLOCKED by the safety deny list and none
        failed. The runner refused to run it; the operator must explicitly
        acknowledge the BLOCK before ship. Distinct from exit 1 (FAIL) so
        that "all blocked" doesn't masquerade as "all passed" in CI.

The script does NOT emit permissionDecision — it is a deterministic runner,
not a gate. Blocking decisions belong in PreToolUse hooks or human gates.
"""

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from acceptance_cmd import detect_executable, extract_command


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCRATCH_DIR = REPO_ROOT / ".scratch"
DEFAULT_TIMEOUT = 60  # seconds per criterion. Deliberately low: the phase-1 contract
# has one criterion that runs the whole critical-hooks suite
# (`bash tests/hooks/runners/test-critical-hooks.sh`) — ~130s locally, 300s+ on CI runners, and
# the eval harness re-runs the contract ~3x, so no per-criterion ceiling that lets it
# pass also fits the eval-harness job's 10-min cap. That criterion is EXPECTED to time
# out here; the TimeoutExpired handler records it as a failed criterion (no crash), the
# CI seed step is non-gating, and the suite itself is verified by the pre-commit gate +
# local runs. Bumping this just burns the CI budget without ever letting the suite pass.


def parse_acceptance_md(path: Path) -> dict[str, Any]:
    """Parse ACCEPTANCE.md and extract structured criteria."""
    content = path.read_text(encoding="utf-8", errors="replace")

    # Strategy 1: look for explicit ## Criteria section
    criteria_block = ""
    criteria_match = re.search(
        r"^##\s+Criteria\s*$",
        content,
        re.MULTILINE | re.IGNORECASE,
    )
    if criteria_match:
        start = criteria_match.end()
        next_heading = re.search(r"\n##\s+", content[start:])
        if next_heading:
            criteria_block = content[start : start + next_heading.start()]
        else:
            criteria_block = content[start:]
    else:
        # Strategy 2: no explicit Criteria section — scan entire file for checkboxes
        # but skip the top metadata/frontmatter and trailing sections
        criteria_block = content

    # Extract each - [ ] line
    criteria = []
    for line in criteria_block.splitlines():
        # Match checkbox lines: - [ ] text or - [x] text
        m = re.match(r"^\s*-\s+\[([ xX])\]\s+(.*)$", line)
        if not m:
            continue
        checked = m.group(1).lower() == "x"
        text = m.group(2).strip()

        criteria.append(
            {
                "raw": text,
                "checked": checked,
                "executable": None,  # determined below
                "command": None,
                "result": None,
            }
        )

    # Malformed guard: a "## Criteria" heading the author explicitly wrote but
    # whose block yields ZERO parseable `- [ ]` items is a parse error, not a
    # legit "no criteria" file. Without this, such a file slips through with an
    # empty criteria list and main() returns exit 0 — a malformed contract
    # silently scored as PASS (the anti-cheat failure mode the exit-code split
    # exists to prevent). main() maps this ValueError to exit 3. A file with no
    # "## Criteria" heading at all is unaffected (legit "no criteria" -> exit 0).
    if criteria_match and not criteria:
        raise ValueError(
            f"'## Criteria' section found in {path.name} but it contains no "
            "parseable '- [ ] ...' checkbox items — malformed ACCEPTANCE.md"
        )

    # Extract metadata from YAML-like frontmatter
    task = None
    accepted = None
    start_sha = None
    executor = None

    for line in content.splitlines():
        if line.startswith("- task:"):
            task = line.split(":", 1)[1].strip()
        elif line.startswith("- accepted:"):
            accepted = line.split(":", 1)[1].strip()
        elif line.startswith("- start-sha:"):
            start_sha = line.split(":", 1)[1].strip()
        elif line.startswith("- executor:"):
            executor = line.split(":", 1)[1].strip()

    return {
        "source_file": str(path.relative_to(REPO_ROOT)),
        "task": task,
        "accepted": accepted,
        "start_sha": start_sha,
        "executor": executor,
        "criteria": criteria,
    }




def run_command(cmd: str, timeout: int, cwd: Path) -> dict[str, Any]:
    """Run a shell command and capture structured results."""
    start_time = time.time()
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        elapsed_ms = int((time.time() - start_time) * 1000)
        return {
            "exit_code": result.returncode,
            "stdout": result.stdout[-2000:] if len(result.stdout) > 2000 else result.stdout,
            "stderr": result.stderr[-2000:] if len(result.stderr) > 2000 else result.stderr,
            "timed_out": False,
            "latency_ms": elapsed_ms,
        }
    except subprocess.TimeoutExpired as e:
        elapsed_ms = int((time.time() - start_time) * 1000)
        # TimeoutExpired.stdout/.stderr come back as raw bytes even when the call
        # set text=True (CPython quirk — the decode only happens on the normal
        # communicate() path, not when the timeout kills it). Coerce to str here,
        # otherwise the bytes flow into json.dumps(results) at the end of main()
        # and crash the whole run with "Object of type bytes is not JSON serializable".
        out = e.stdout.decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        err = e.stderr.decode("utf-8", "replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        return {
            "exit_code": -1,
            "stdout": out[-2000:] if len(out) > 2000 else out,
            "stderr": err[-2000:] if len(err) > 2000 else err,
            "timed_out": True,
            "latency_ms": elapsed_ms,
        }
    except Exception as e:
        return {
            "exit_code": -1,
            "stdout": "",
            "stderr": str(e),
            "timed_out": False,
            "latency_ms": 0,
        }


def evaluate_criterion(c: dict[str, Any], timeout: int, verbose: bool, cwd: Path) -> dict[str, Any]:
    """Evaluate a single criterion and return enriched result dict."""
    is_exec = detect_executable(c)
    c["executable"] = is_exec

    if not is_exec:
        c["result"] = {
            "status": "skipped",
            "reason": "not machine-checkable (manual verification required)",
        }
        if verbose:
            print(f"  [SKIP] {c['raw'][:60]}...")
        return c

    cmd = extract_command(c["raw"])
    if not cmd:
        c["result"] = {
            "status": "skipped",
            "reason": "could not extract runnable command from criterion text",
        }
        if verbose:
            print(f"  [SKIP-UNCLEAR] {c['raw'][:60]}...")
        return c

    c["command"] = cmd

    # Pre-run sanity: don't run destructive commands
    deny_patterns = [
        r"git\s+push",
        r"git\s+reset\s+--hard",
        r"git\s+clean\s+-fd",
        r"rm\s+-rf\s+/",
        r"chmod\s+",
        r"chown\s+",
        r">\s*/dev/",
        r"curl\s+.*\|\s*sh",
        r"npm\s+publish",
        r"pip\s+uninstall",
    ]
    for pat in deny_patterns:
        if re.search(pat, cmd, re.IGNORECASE):
            c["result"] = {
                "status": "blocked",
                "reason": f"command matches safety deny pattern: {pat}",
                "command": cmd,
            }
            if verbose:
                print(f"  [BLOCKED] {cmd[:60]}...")
            return c

    if verbose:
        print(f"  [RUN] {cmd[:80]}...")

    run_result = run_command(cmd, timeout, cwd)
    passed = run_result["exit_code"] == 0 and not run_result["timed_out"]

    c["result"] = {
        "status": "passed" if passed else "failed",
        "command": cmd,
        "exit_code": run_result["exit_code"],
        "stdout": run_result["stdout"],
        "stderr": run_result["stderr"],
        "timed_out": run_result["timed_out"],
        "latency_ms": run_result["latency_ms"],
    }

    if verbose:
        status_icon = "✓" if passed else "✗"
        print(f"  [{status_icon}] exit={run_result['exit_code']} in {run_result['latency_ms']}ms")

    return c


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run machine-checkable acceptance criteria from ACCEPTANCE.md"
    )
    parser.add_argument("slug", help="The .scratch/<slug> directory name")
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT,
        help=f"Timeout per criterion in seconds (default: {DEFAULT_TIMEOUT})",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Print per-criterion progress")
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default=None,
        help="Override output path for acceptance-results.json",
    )
    parser.add_argument(
        "--cwd",
        type=str,
        default=str(REPO_ROOT),
        help="Working directory for command execution (default: repo root)",
    )
    args = parser.parse_args()

    slug_dir = SCRATCH_DIR / args.slug
    acceptance_path = slug_dir / "ACCEPTANCE.md"

    if not acceptance_path.exists():
        print(f"ERROR: No ACCEPTANCE.md found at {acceptance_path}", file=sys.stderr)
        return 2

    try:
        parsed = parse_acceptance_md(acceptance_path)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 3

    criteria = parsed["criteria"]
    if not criteria:
        print("WARNING: No criteria found in ACCEPTANCE.md", file=sys.stderr)
        return 0

    cwd = Path(args.cwd)
    if not cwd.exists():
        print(f"ERROR: --cwd does not exist: {cwd}", file=sys.stderr)
        return 2

    if args.verbose:
        print(f"Running {len(criteria)} criteria from {acceptance_path}")
        print(f"Working directory: {cwd}")
        print()

    all_passed = True
    for i, c in enumerate(criteria, 1):
        if args.verbose:
            print(f"Criterion {i}/{len(criteria)}:")
        evaluate_criterion(c, args.timeout, args.verbose, cwd)
        if c["result"]["status"] == "failed":
            all_passed = False

    # Compute summary
    passed = sum(1 for c in criteria if c["result"]["status"] == "passed")
    failed = sum(1 for c in criteria if c["result"]["status"] == "failed")
    skipped = sum(1 for c in criteria if c["result"]["status"] == "skipped")
    blocked = sum(1 for c in criteria if c["result"]["status"] == "blocked")

    results = {
        "meta": {
            "slug": args.slug,
            "source_file": parsed["source_file"],
            "task": parsed["task"],
            "accepted": parsed["accepted"],
            "start_sha": parsed["start_sha"],
            "executor": parsed["executor"],
            "runner": "run-acceptance.py",
            "run_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "cwd": str(cwd),
        },
        "summary": {
            "total": len(criteria),
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "blocked": blocked,
            "all_passed": all_passed and failed == 0,
        },
        "criteria": criteria,
    }

    output_path = Path(args.output) if args.output else slug_dir / "acceptance-results.json"
    output_path.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")

    if args.verbose:
        print()
        print(f"Results: {passed} passed, {failed} failed, {skipped} skipped, {blocked} blocked")
        print(f"Written: {output_path}")

    # Exit codes are the scoreboard that the operator (or pre-ship-verify)
    # reads — keep them distinguishable so BLOCK ≠ FAIL ≠ PASS. The previous
    # binary `0 if failed == 0 else 1` collapsed all three into a single
    # "did anything fail?" verdict, which is exactly the anti-cheat failure
    # mode (SYNTHESIS row #15) — operators who ignored BLOCKs were seeing
    # them as PASSes. New contract uses exit 4 for the all-blocked-but-
    # none-failed case (see top-of-file docstring).
    if blocked > 0 and failed == 0:
        return 4
    if failed > 0:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
