#!/usr/bin/env bash
# gate:skill:review-pr-loop — ask-tier enforcement of review-pr's bounded
# auto-loop verdict (ADR 0009 family; closes the known-gap first flagged in
# docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md).
#
# Fires ONLY at genuine exhaustion: a Skill(kbg:review-pr) call while
# review-last.json's persisted loop verdict says the loop died un-clean
# (loop_reason in ceiling|regressed|churning|stalled, or force_human=true)
# AND the state still describes the current HEAD (last_sha == git HEAD;
# HEAD moved means a human did work since — allow) AND the state's branch
# is the current branch. Everything else allows:
#   - converged / no-findings-nonclean stops — the loop ended WELL; asking
#     there is alarm fatigue on the success path (2026-08-21 plan-review
#     finding, Critical);
#   - missing/malformed/stale state — first review, another repo, old work;
#   - any git error resolving HEAD/branch (fail-open: a redundant re-review
#     is recoverable cost, not a one-way door).
# "ask", not "deny": after a stop, a human asking for another round is
# legitimate — this gate makes ADR 0009's human-at-exhaustion computational
# (one deliberate click), it does not overrule the human.
#
# KNOWN LIMITS (stated, not hidden):
#   - a loop that skips Phase 7 entirely (never writes state, never runs
#     should-continue-loop.sh) is out of reach; force_human=true written by
#     write-review-state.sh partially covers a skipped decision script, an
#     unwritten round covers nothing.
#   - write-review-state.sh --amend rebuilds its fixed field dict and drops
#     loop_decision/loop_reason — an amend after a stop disarms this gate
#     (fail-open by design, stated here).
#   - reads ${REVIEW_PR_STATE_DIR:-~/.claude/state} from the HOOK process
#     env; a review run under a custom state dir writes where this gate
#     does not read (fail-open divergence).
#   - user-typed /kbg:review-pr may surface as the same Skill call → one ask
#     click at exhaustion is intended friction. Whether a SlashCommand-shaped
#     invocation bypasses the Skill matcher is unresolved (no live payload
#     observed) — the journal below is how a dead gate gets noticed.
# Headless runs (claude -p, cron): set KBG_SKIP_LOOP_GATE=1 — an ask has no
# human to click there.
# Journals every MATCHED decision (ask or allow+why) to
# ~/.local/share/kbg/metrics/review-pr-loop-gate.jsonl so live-fire behavior
# is auditable (observability finding from the same plan review).
set -uo pipefail

[ -n "${KBG_SKIP_LOOP_GATE:-}" ] && exit 0

INPUT="$(cat)"

# Fast path: no review-pr anywhere in the payload → not ours, no python spawn.
grep -q 'review-pr' <<<"$INPUT" || exit 0

GATE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf '%s' "$INPUT" | python3 -c '
import json, os, re, subprocess, sys, time

lib_dir = sys.argv[1]

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)  # malformed payload is irrecoverable.sh territory; fail-open

if d.get("tool_name") != "Skill":
    sys.exit(0)
skill = str((d.get("tool_input") or {}).get("skill") or "")
# Anchored both ways: unqualified "review-pr" matches (payload shape not
# observed live), review-pr-finish / review-pr-tier can never match.
if not re.match(r"^(kbg:)?review-pr$", skill):
    sys.exit(0)

def journal(decision, why):
    try:
        p = os.path.join(os.path.expanduser("~"), ".local", "share", "kbg", "metrics")
        os.makedirs(p, exist_ok=True)
        with open(os.path.join(p, "review-pr-loop-gate.jsonl"), "a") as f:
            f.write(json.dumps({"ts": int(time.time()), "decision": decision,
                                "why": why, "skill": skill}) + "\n")
    except Exception:
        pass

state_dir = os.environ.get("REVIEW_PR_STATE_DIR") or os.path.join(
    os.path.expanduser("~"), ".claude", "state")
state_path = os.path.join(state_dir, "review-last.json")

try:
    with open(state_path) as f:
        st = json.load(f)
    if not isinstance(st, dict):
        raise ValueError("not a dict")
except Exception:
    journal("allow", "no-or-malformed-state")
    sys.exit(0)

EXHAUSTED = ("ceiling", "regressed", "churning", "stalled")
stopped_exhausted = (st.get("loop_decision") == "stop"
                     and st.get("loop_reason") in EXHAUSTED)
forced = st.get("force_human") is True
if not (stopped_exhausted or forced):
    journal("allow", "not-exhausted")
    sys.exit(0)

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, timeout=5)

try:
    head = git("rev-parse", "HEAD")
    br = git("rev-parse", "--abbrev-ref", "HEAD")
    if head.returncode != 0 or br.returncode != 0:
        raise RuntimeError("git failed")
    head_sha = head.stdout.strip()
    branch = br.stdout.strip()
except Exception:
    journal("allow", "git-error")
    sys.exit(0)

if st.get("last_sha") != head_sha:
    journal("allow", "head-moved")
    sys.exit(0)
if st.get("branch") != branch:
    journal("allow", "other-branch")
    sys.exit(0)

journal("ask", "exhausted-same-head")
sys.path.insert(0, lib_dir)
from _hook_output import emit_ask
emit_ask(
    "review-pr loop exhausted on this exact HEAD (loop_reason=%s, "
    "force_human=%s, round=%s). ADR 0009 hands control to a human here — "
    "approve to deliberately run another round, or address the open findings "
    "/ ship instead. Headless: KBG_SKIP_LOOP_GATE=1."
    % (st.get("loop_reason") or "-", st.get("force_human"), st.get("round"))
)
' "$GATE_DIR/lib"
