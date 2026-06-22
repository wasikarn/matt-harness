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
- Fail-CLOSED: an empty/missing cage, an unreadable state file, or the autonomy
  flag being unset all resolve to STOP/REVERT, never CONTINUE.
- Flag-immutable: KBG_AUTONOMY is read ONCE at process start (via autonomy_on(),
  armed only from a per-repo .claude/settings.local.json). The loop cannot
  self-elevate scope by re-exporting it mid-run.

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
import tempfile
import time
from pathlib import Path
from typing import NoReturn

SCRIPT_DIR = Path(__file__).resolve().parent
# REPO_ROOT / CAGE_FILE / WINDOW_STATE_FILE are PLACEHOLDERS at import (the guard's
# own home). _assert_repo_root() (design §5 F4) re-anchors them to the MUTATED tree
# (CWD's git toplevel, confirmed to be a kbg-harness checkout) on every armed
# invocation — an unattended loop must never mutate the wrong tree. Resolved in the
# armed path (check-act / precheck), not at import, so a flag-off invocation STOPs
# at the activation gate before any tree is touched.
REPO_ROOT = SCRIPT_DIR.parent
CAGE_FILE = SCRIPT_DIR / "l3-cage.txt"
# R4 cumulative-ceiling state (design §5 R4): a SEPARATE caged file so a
# self-launcher that restarts repeatedly cannot reset its own cross-run ceiling.
# Caged via scripts/l4/** — the loop may not Edit/Write it (check-act denies);
# the guard's own bookkeeping write is not a loop candidate.
WINDOW_STATE_FILE = SCRIPT_DIR / "l4" / ".window-state.json"


def _assert_repo_root():
    """F4 installer fail-safe (design §5 F4 + §12 guards 1+2). Anchor REPO_ROOT to
    the tree the loop actually mutates — CWD's `git rev-parse --show-toplevel` — and
    affirmatively assert THAT tree is a genuine kbg-harness checkout. STOP if CWD is
    not a git working tree, or if the tree is not kbg (sentinel .claude-plugin/
    plugin.json name=='kbg', and where remotes exist at least one references
    'kbg-harness' — org-agnostic, portable; never an is-this-KOBIG test). This
    replaces the silent, brittle protection where a flag-armed installer was stopped
    only because the plugin cache has no .git (_git_dirty failing closed). Guards
    1+2 also gate Slice 3 self-launch — an unattended loop amplifies the mis-anchor."""
    global REPO_ROOT, CAGE_FILE, WINDOW_STATE_FILE
    cwd = os.getcwd()
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True, cwd=cwd).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        _emit("STOP", f"F4: CWD ({cwd}) is not a git working tree — autonomy self-improves a kbg-harness checkout, not a bare directory")
    root = Path(out)
    manifest = root / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        _emit("STOP", f"F4: REPO_ROOT ({root}) is not a kbg-harness checkout — no .claude-plugin/plugin.json. L3/L4/L5 self-improves the kbg-harness itself, not your project.")
    try:
        mf = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        _emit("STOP", f"F4: REPO_ROOT ({root}) .claude-plugin/plugin.json unreadable — cannot confirm repo identity")
    if mf.get("name") != "kbg":
        _emit("STOP", f"F4: REPO_ROOT ({root}) plugin.json name='{mf.get('name')}' != 'kbg' — autonomy self-improves the kbg-harness checkout, not this project")
    # Where remotes are configured, at least one should reference the kbg-harness
    # repo (org-agnostic — any fork/clone of kbg-harness passes; an unrelated repo
    # that happens to carry a name='kbg' manifest does not). A remote-less local
    # checkout falls back to the sentinel alone.
    try:
        remotes = subprocess.run(["git", "-C", str(root), "remote", "-v"],
                                 capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        remotes = ""
    if remotes.strip() and "kbg-harness" not in remotes:
        _emit("STOP", f"F4: REPO_ROOT ({root}) remotes do not reference kbg-harness — autonomy self-improves a kbg-harness checkout, not a same-named unrelated repo")
    REPO_ROOT = root
    CAGE_FILE = root / "scripts" / "l3-cage.txt"
    WINDOW_STATE_FILE = root / "scripts" / "l4" / ".window-state.json"

def autonomy_on():
    """The single arming predicate (ADR 0004 single-key collapse + installer
    fail-safe guard 3, design §5 F1). Armed iff BOTH hold:
      1. KBG_AUTONOMY=1 is in the process env.
      2. That arming is confirmed by the per-repo settings file
         $CLAUDE_PROJECT_DIR/.claude/settings.local.json (its env.KBG_AUTONOMY).
    A bare USER-GLOBAL KBG_AUTONOMY=1 (which reaches every repo's hooks) arms
    NOTHING — only the per-repo local settings (gitignored, per-operator) does.
    Fail-closed for autonomy: absent/unreadable provenance → not armed. This is
    the Python half of the predicate; the bash half lives in hooks/_lib.sh.
    Defined before the module-level capture so the flag is read ONCE at import
    (immutable for the process — the loop cannot self-elevate mid-run)."""
    if os.environ.get("KBG_AUTONOMY", "") != "1":
        return False
    proj = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if not proj:
        return False
    home = Path(proj) / ".claude" / "settings.local.json"
    try:
        data = json.loads(home.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return data.get("env", {}).get("KBG_AUTONOMY", "") == "1"


# --- arming captured ONCE at import via autonomy_on() (immutable for the
#     process, ADR 0003/0004 single-key). The loop cannot self-elevate mid-run. ---
ARMED_AT_START = autonomy_on()

# Env vars whose appearance in a candidate command would disarm the safety layer.
TAMPER_VARS = (
    "KBG_AUTONOMY",
    "CLAUDE_HOOK_PROFILE",
    "CLAUDE_DISABLED_HOOKS",
    "KBG_REVIEW_DONE",
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
    if not ARMED_AT_START:
        _emit("STOP", "autonomy flag not armed (KBG_AUTONOMY=1 per-repo) — loop refuses to run")
    _assert_repo_root()  # F4: anchor to the mutated tree + confirm it is kbg
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


def _load_window(path):
    """R4 window state: {launches:[ts...], wall:[[ts,sec]...]}. Empty on missing."""
    try:
        d = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"launches": [], "wall": []}
    if not isinstance(d, dict):
        return {"launches": [], "wall": []}
    d.setdefault("launches", [])
    d.setdefault("wall", [])
    return d


def _save_window(path, data):
    """Persist the R4 window state; fail-closed (STOP) if unwritable — an
    un-persistable ceiling means the loop could re-launch unbounded."""
    try:
        Path(path).write_text(json.dumps(data), encoding="utf-8")
    except OSError as e:
        _emit("STOP", f"cannot persist R4 window state ({e}) — fail-closed (the cumulative ceiling must be writable)")


def cmd_precheck(args):
    """Check caps BEFORE a cycle. On CONTINUE, increment the run counter."""
    if not ARMED_AT_START:
        _emit("STOP", "autonomy flag not armed (KBG_AUTONOMY=1 per-repo) — loop refuses to run")
    _assert_repo_root()  # F4: anchor to the mutated tree + confirm it is kbg
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

    # R4 cumulative ceiling (design §5 R4): a self-launcher restarts repeatedly and
    # never trips the per-run caps above. Cross-run caps over a sliding window,
    # persisted in a SEPARATE caged file (scripts/l4/.window-state.json) the loop
    # cannot reset. max-runs-per-window = launch count in the window; max-wall-per-
    # window = total wall seconds (fed by record-result --wall-seconds). 0 = off.
    if args.max_runs_per_window or args.max_wall_per_window:
        if not args.window_seconds:
            _emit("STOP", "R4 window cap set but --window-seconds is 0 — refuse an unbounded window")
        wstate_path = args.window_state or str(WINDOW_STATE_FILE)
        wst = _load_window(wstate_path)
        now_w = time.time()
        launches = [t for t in wst.get("launches", []) if now_w - t <= args.window_seconds]
        wall = [p for p in wst.get("wall", []) if now_w - p[0] <= args.window_seconds]
        if args.max_runs_per_window and len(launches) >= args.max_runs_per_window:
            _emit("STOP", f"R4 max-runs-per-window reached ({len(launches)}/{args.max_runs_per_window} launches in last {args.window_seconds}s)")
        wall_sum = sum(p[1] for p in wall)
        if args.max_wall_per_window and wall_sum >= args.max_wall_per_window:
            _emit("STOP", f"R4 max-wall-per-window reached ({int(wall_sum)}s/{args.max_wall_per_window}s in last {args.window_seconds}s)")
        # CONTINUE: record this launch (a STOP above never reaches here).
        wst["launches"] = launches + [now_w]
        wst["wall"] = wall
        _save_window(wstate_path, wst)

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
    # R4 wall accounting (design §5 R4): record this cycle's wall seconds into the
    # caged window state so the next precheck's --max-wall-per-window can see it.
    # Optional + self-pruning; skipped unless the caller passes --wall-seconds > 0.
    if args.wall_seconds and args.window_seconds:
        wpath = args.window_state or str(WINDOW_STATE_FILE)
        wst = _load_window(wpath)
        now_w = time.time()
        wall = [p for p in wst.get("wall", []) if now_w - p[0] <= args.window_seconds]
        wall.append([now_w, args.wall_seconds])
        wst["wall"] = wall
        _save_window(wpath, wst)
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

    # autonomy_on() (design §5 F1, guard 3): per-repo arming honors; a user-global
    # flag (env set but the per-repo file does not carry it) arms NOTHING; flag off
    # never arms. Mutates os.environ only inside this subprocess; restored after.
    _old_proj = os.environ.get("CLAUDE_PROJECT_DIR")
    _old_flag = os.environ.get("KBG_AUTONOMY")
    try:
        with tempfile.TemporaryDirectory() as td:
            (Path(td) / ".claude").mkdir()
            sf = Path(td) / ".claude" / "settings.local.json"
            os.environ["KBG_AUTONOMY"] = "1"
            os.environ["CLAUDE_PROJECT_DIR"] = td
            sf.write_text('{"env":{"KBG_AUTONOMY":"1"}}', encoding="utf-8")
            assert autonomy_on() is True, "per-repo arming should arm"
            sf.write_text('{"permissions":{}}', encoding="utf-8")
            assert autonomy_on() is False, "user-global flag without per-repo confirm must NOT arm"
            os.environ["KBG_AUTONOMY"] = "0"
            assert autonomy_on() is False, "flag off must not arm"
    finally:
        for _k, _v in (("CLAUDE_PROJECT_DIR", _old_proj), ("KBG_AUTONOMY", _old_flag)):
            if _v is None:
                os.environ.pop(_k, None)
            else:
                os.environ[_k] = _v
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
    # R4 cumulative ceiling (design §5 R4): cross-run caps over a sliding window.
    p_pre.add_argument("--max-runs-per-window", type=int, default=0,
                       help="R4: stop after N launches in the last --window-seconds; 0 = off")
    p_pre.add_argument("--max-wall-per-window", type=int, default=0,
                       help="R4: stop after S cumulative wall seconds in the window (fed by record-result --wall-seconds); 0 = off")
    p_pre.add_argument("--window-seconds", type=int, default=0,
                       help="R4: the sliding-window size in seconds; required if either R4 cap is set")
    p_pre.add_argument("--window-state", default="",
                       help="R4: path to the caged window-state JSON (default <REPO_ROOT>/scripts/l4/.window-state.json — resolved after F4 anchoring)")
    p_pre.set_defaults(func=cmd_precheck)

    p_rec = sub.add_parser("record-result", help="record a cycle's gauntlet outcome")
    p_rec.add_argument("--state", required=True)
    g = p_rec.add_mutually_exclusive_group(required=True)
    g.add_argument("--green", action="store_true")
    g.add_argument("--red", action="store_true")
    p_rec.add_argument("--flat", action="store_true",
                       help="with --green: the cycle moved no audit/gaps metric (counts toward --max-flat)")
    p_rec.add_argument("--wall-seconds", type=int, default=0,
                       help="R4: this cycle's wall seconds, recorded into the window state for --max-wall-per-window (0 = skip)")
    p_rec.add_argument("--window-seconds", type=int, default=0,
                       help="R4: sliding-window size for pruning --wall-seconds entries")
    p_rec.add_argument("--window-state", default="",
                       help="R4: window-state path (defaults to scripts/l4/.window-state.json)")
    p_rec.set_defaults(func=cmd_record_result)

    sub.add_parser("selftest", help="run the built-in matcher self-check").set_defaults(func=cmd_selftest)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
