"""_orchestrate_executor.py — command-stage execution for orchestrate-dispatch."""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_TIMEOUT = 60  # seconds per command-typed stage


# ---------------------------------------------------------------------------
# Execution (command-typed stages only)
# ---------------------------------------------------------------------------

def execute_command_stage(stage: dict[str, Any], timeout: int) -> tuple[bool, str, str, int]:
    """Run a `command`-typed stage via subprocess. Returns (ok, stdout, stderr, rc)."""
    cmd = stage["command"]
    started = time.time()
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout, cwd=str(REPO_ROOT),
        )
        elapsed = time.time() - started
        ok = result.returncode == 0
        suffix = f" [rc={result.returncode}, {elapsed:.1f}s]"
        if ok:
            print(f"  ✓ {stage['id']}{suffix}")
        else:
            print(f"  ✗ {stage['id']}{suffix}", file=sys.stderr)
            if result.stderr.strip():
                tail = "\n".join(result.stderr.strip().splitlines()[-5:])
                print(f"    stderr (last 5 lines):\n{tail}", file=sys.stderr)
        return ok, result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        print(f"  ⏱ {stage['id']} timed out after {timeout}s", file=sys.stderr)
        return False, "", f"timeout after {timeout}s", 124


def run_execute(plan: dict[str, Any], timeout: int) -> int:
    """Run command-typed stages in wave order. Agent/parallel/loop stages
    are reported as "would-spawn" and skipped — a lead or human must
    dispatch them. Returns 0 if all command stages exit 0, else 1.
    """
    failed = 0
    for wave in plan["waves"]:
        print(f"Wave {wave['index']} ({len(wave['stage_ids'])} stage(s)):")
        for stage in wave["stages"]:
            stype = stage.get("type", "command")
            if stype == "command":
                ok, _, _, _ = execute_command_stage(stage, timeout=timeout)
                if not ok:
                    failed += 1
            elif stype == "agent":
                print(
                    f"  → would-spawn: agent_type={stage.get('agent_type')!r} "
                    f"id={stage['id']!r} (lead dispatch required)"
                )
            elif stype == "parallel":
                print(
                    f"  → parallel stage {stage['id']!r}: "
                    f"{len(stage.get('stages', []))} sub-stage(s) "
                    f"(dispatch as one wave)"
                )
            elif stype == "loop":
                print(
                    f"  → loop stage {stage['id']!r} until {stage.get('loop_until')!r}: "
                    f"{len(stage.get('body', []))} body stage(s) "
                    f"(loop semantics; spec-render only)"
                )
    return 1 if failed else 0
