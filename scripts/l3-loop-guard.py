#!/usr/bin/env python3
"""
l3-loop-guard.py — the single code-level enforcer of L3 bounded-autonomy bounds.

The L3 self-improvement loop (`recursive-improve --auto`, ADR 0003) calls this
guard at two points every cycle:

  1. precheck       — BEFORE a cycle: are the caps still satisfied?
  2. check-act      — BEFORE applying a candidate: does it touch a caged path?

and once after the gauntlet:

  3. record-result  — log green/red so fail-streak and the run-report can see it.

What this guard IS
------------------
- The deterministic bound on an unattended run: max-runs, max-duration,
  fail-streak, dirty-tree abort, and the cage-denylist (scripts/l3-cage.txt).
- Fail-CLOSED: an empty/missing cage, an unreadable state file, or the
  KBG_AUTONOMY_L3 flag being unset all resolve to STOP/REVERT, never CONTINUE.
- Flag-immutable: KBG_AUTONOMY_L3 is read ONCE at process start. The loop
  cannot self-elevate scope by re-exporting it mid-run.

What this guard IS NOT
----------------------
- NOT a model. Every decision here is a path match, an integer compare, or a
  `git status` — never an LLM judgment. The in-loop *quality* gate is the
  computational gauntlet (scripts/run-gauntlet.sh); this guard only bounds it.
- NOT the push gate. Pushing is blocked by a separate PreToolUse hook + Gate-2
  human review (ADR 0003). This guard never pushes and never reviews.
- NOT a cost meter. `--max-cost` is intentionally unimplemented: there is no
  reliable local token-cost signal in a plain script, and fabricating one would
  be dishonest. The hard bounds are --max-runs and --max-duration (both locally
  observable). If a real cost signal ever lands, add it here, not in prose.

Decision contract (printed as JSON on stdout, mirrored in the exit code):
  CONTINUE (exit 0)  — proceed
  SKIP     (exit 0)  — skip this candidate, keep looping (reserved; caller-driven)
  REVERT   (exit 20) — abort THIS cycle and git-reset to the pre-cycle tag
  STOP     (exit 10) — end the run (a cap tripped, or the flag is off)
  bad invocation (exit 2)
"""
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import NoReturn

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
CAGE_FILE = SCRIPT_DIR / "l3-cage.txt"

# --- flag captured ONCE at import (immutable for the process, ADR 0003) ---
_FLAG_AT_START = os.environ.get("KBG_AUTONOMY_L3", "")
L3_ACTIVE = _FLAG_AT_START == "1"

# Env vars whose appearance in a candidate command would disarm the safety layer.
TAMPER_VARS = (
    "KBG_AUTONOMY_L3",
    "CLAUDE_HOOK_PROFILE",
    "CLAUDE_DISABLED_HOOKS",
    "KBG_L3_REVIEW_DONE",
)

EXIT = {"CONTINUE": 0, "SKIP": 0, "STOP": 10, "REVERT": 20}


def _emit(decision, reason="", **extra) -> NoReturn:
    """Print the decision as JSON and exit with the contract code."""
    payload = {"decision": decision, "reason": reason}
    payload.update(extra)
    print(json.dumps(payload))
    sys.exit(EXIT.get(decision, 2))


def load_cage():
    """Return the cage globs, fail-CLOSED on empty/missing."""
    try:
        lines = CAGE_FILE.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        _emit("REVERT", f"cage denylist unreadable ({e}) — fail-closed")
    globs = [ln.strip() for ln in lines if ln.strip() and not ln.strip().startswith("#")]
    if not globs:
        _emit("REVERT", "cage denylist is empty — fail-closed")
    return globs


def _rel(path):
    """Repo-relative POSIX path, or None if the path is outside the repo."""
    try:
        return Path(path).resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return None


def is_caged(rel, globs):
    """True if rel matches a cage entry. Dumb matcher: '<dir>/**' or literal."""
    for g in globs:
        if g.endswith("/**"):
            d = g[:-3]
            if rel == d or rel.startswith(d + "/"):
                return True
        elif rel == g:
            return True
    return False


def cmd_check_act(args):
    """Deny if any target path is caged or outside the repo, or if the
    candidate command tampers with a safety env var."""
    if not L3_ACTIVE:
        _emit("STOP", "KBG_AUTONOMY_L3 is not set — L3 loop refuses to run")
    globs = load_cage()
    hits = []
    for p in args.paths:
        rel = _rel(p)
        if rel is None:
            hits.append(f"{p} (outside repo)")
        elif is_caged(rel, globs):
            hits.append(rel)
    if args.candidate_cmd:
        for var in TAMPER_VARS:
            if var in args.candidate_cmd:
                hits.append(f"tampers with ${var}")
    if hits:
        _emit("REVERT", "candidate targets caged path(s) / tamper", caged=hits)
    _emit("CONTINUE", "no caged path in candidate")


def _git_dirty():
    """True if the working tree has changes outside .scratch/."""
    try:
        out = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "status", "--porcelain"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        # can't tell → treat as dirty (fail-closed)
        return True, f"git status failed ({e})"
    for ln in out.splitlines():
        path = ln[3:].strip()
        if path and not path.startswith(".scratch/"):
            return True, path
    return False, ""


def _load_state(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def cmd_precheck(args):
    """Check caps BEFORE a cycle. On CONTINUE, increment the run counter."""
    if not L3_ACTIVE:
        _emit("STOP", "KBG_AUTONOMY_L3 is not set — L3 loop refuses to run")
    st = _load_state(args.state)
    now = time.time()
    start = st.get("start_epoch", now)
    runs = st.get("runs_done", 0)
    fails = st.get("fail_streak", 0)
    flats = st.get("no_progress_streak", 0)

    if runs >= args.max_runs:
        _emit("STOP", f"max-runs reached ({runs}/{args.max_runs})")
    if args.max_duration and (now - start) >= args.max_duration:
        _emit("STOP", f"max-duration reached ({int(now - start)}s/{args.max_duration}s)")
    if fails >= args.fail_streak:
        _emit("STOP", f"fail-streak reached ({fails}/{args.fail_streak})")
    # no-progress cap: K consecutive GREEN-but-flat cycles (no audit/gaps delta) =
    # the loop is spinning without improving. A DIFFERENT signal from fail-streak
    # (which counts reds). The flat? decision is a numeric delta the loop computes
    # and passes via record-result --flat; the guard only counts (computational).
    if args.max_flat and flats >= args.max_flat:
        _emit("STOP", f"no-progress reached ({flats}/{args.max_flat} flat cycles)")
    if not args.no_dirty_abort:
        dirty, what = _git_dirty()
        if dirty:
            _emit("STOP", f"dirty working tree (uncommitted: {what}) — --dirty-abort")

    # CONTINUE: persist incremented state
    st.update({"start_epoch": start, "runs_done": runs + 1, "fail_streak": fails,
               "no_progress_streak": flats,
               "run_id": st.get("run_id", args.run_id or "")})
    try:
        Path(args.state).write_text(json.dumps(st), encoding="utf-8")
    except OSError as e:
        _emit("STOP", f"cannot persist run state ({e}) — fail-closed")
    _emit("CONTINUE", f"cycle {runs + 1}/{args.max_runs} authorized",
          runs_done=runs + 1)


def cmd_record_result(args):
    """Record a cycle's gauntlet outcome so fail-streak + the report can see it."""
    st = _load_state(args.state)
    if args.green:
        st["fail_streak"] = 0
        # --flat = the cycle passed the gauntlet but moved no audit/gaps metric
        # (the loop decides flat numerically; here we only track the streak). An
        # improved green resets it; a red leaves it (fail-streak owns reds).
        if args.flat:
            st["no_progress_streak"] = st.get("no_progress_streak", 0) + 1
        else:
            st["no_progress_streak"] = 0
    else:
        st["fail_streak"] = st.get("fail_streak", 0) + 1
    label = "red" if args.red else ("green-flat" if args.flat else "green")
    st.setdefault("results", []).append(label)
    try:
        Path(args.state).write_text(json.dumps(st), encoding="utf-8")
    except OSError as e:
        _emit("STOP", f"cannot persist run state ({e}) — fail-closed")
    _emit("CONTINUE", f"recorded {label}",
          fail_streak=st["fail_streak"], no_progress_streak=st.get("no_progress_streak", 0))


def cmd_selftest(_args):
    """Runnable check (ponytail): the matcher + fail-closed posture must hold."""
    globs = ["hooks/**", "skills/harness-audit/scripts/audit.sh", "docs/adr/**",
             "scripts/l3-cage.txt"]
    assert is_caged("hooks/gates/secret-scan.sh", globs)          # under /**
    assert is_caged("hooks/_lib.sh", globs)                       # direct child of /**
    assert is_caged("skills/harness-audit/scripts/audit.sh", globs)  # literal
    assert is_caged("docs/adr/0003-l3-bounded-autonomy.md", globs)   # ADR /**
    assert is_caged("scripts/l3-cage.txt", globs)                 # self-reference
    assert not is_caged("skills/fix-bug/SKILL.md", globs)         # editable skill
    assert not is_caged("README.md", globs)                       # not in this subset
    assert not is_caged("hooksX/y.sh", globs)                     # prefix not a dir boundary
    print("l3-loop-guard selftest: OK")


def main():
    ap = argparse.ArgumentParser(description="L3 bounded-autonomy guard (ADR 0003)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_act = sub.add_parser("check-act", help="deny if a candidate touches a caged path")
    p_act.add_argument("paths", nargs="*", help="repo paths the candidate would write")
    p_act.add_argument("--candidate-cmd", default="", help="candidate shell command (scanned for tamper vars)")
    p_act.set_defaults(func=cmd_check_act)

    p_pre = sub.add_parser("precheck", help="check caps before a cycle")
    p_pre.add_argument("--state", required=True, help="path to the run-state JSON")
    p_pre.add_argument("--run-id", default="", help="run id (recorded on first cycle)")
    p_pre.add_argument("--max-runs", type=int, default=3)
    p_pre.add_argument("--max-duration", type=int, default=0, help="seconds; 0 = off")
    p_pre.add_argument("--fail-streak", type=int, default=2)
    p_pre.add_argument("--max-flat", type=int, default=2,
                       help="stop after K consecutive green-but-flat (no-progress) cycles; 0 = off")
    p_pre.add_argument("--no-dirty-abort", action="store_true")
    p_pre.set_defaults(func=cmd_precheck)

    p_rec = sub.add_parser("record-result", help="record a cycle's gauntlet outcome")
    p_rec.add_argument("--state", required=True)
    g = p_rec.add_mutually_exclusive_group(required=True)
    g.add_argument("--green", action="store_true")
    g.add_argument("--red", action="store_true")
    p_rec.add_argument("--flat", action="store_true",
                       help="with --green: the cycle moved no audit/gaps metric (counts toward --max-flat)")
    p_rec.set_defaults(func=cmd_record_result)

    sub.add_parser("selftest", help="run the built-in matcher self-check").set_defaults(func=cmd_selftest)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
