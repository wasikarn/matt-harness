#!/usr/bin/env bash
# review-pr Phase 7 — deterministic continue/stop decision for the bounded
# auto-loop ADR 0009 authorizes (docs/research/adr-0009-bounded-review-fix-
# auto-loop.md). Reads the state file write-review-state.sh just wrote and
# decides whether the model may automatically re-invoke review-pr for
# another round, or must hand control back to a human. The decision is
# computational (this script), never re-derived by the model from raw state
# fields in SKILL.md prose — that re-derivation was an unenforceable
# sync-seam the ADR's Implementation requirements section exists to close.
#
# Usage: should-continue-loop.sh <expected_head_sha> [worktree_path]
#   expected_head_sha — the HEAD_SHA this round's write-review-state.sh call
#                        was just given. Confirms the state file this script
#                        reads is THIS round's write, not a stale leftover.
#   worktree_path      — Phase 2's $WT for a PR-by-number review; omit/empty
#                        for own-branch (same convention as write-review-
#                        state.sh's own 5th positional arg — mirrored here so
#                        both scripts derive the identical STATE_FILE path).
#
# Call this from Phase 7 step 1, immediately after write-review-state.sh —
# not from Phase 2 of the next round. The last_sha staleness check below only
# holds right after the write it's checking.
#
# Stdout contract (mirrors write-review-state.sh's own two-line pattern):
#   line 1: "continue" or "stop"
#   line 2 (stop only): "reason=<token>"
# Exit code: 0 = continue, any non-zero = stop. The caller branches on exit
# code for control flow; the reason line is for rendering only — never
# branch on which non-zero code came back.
#
# Checks run in a fixed order, first match wins (fail-closed/type-validation
# before semantic checks):
#   missing-state                — state file absent/empty
#   malformed-state               — state file present, not valid JSON, or
#                                    valid JSON that isn't a top-level object
#                                    (e.g. a bare array/string/null — parses
#                                    fine but has no .get() to read fields
#                                    from; caught explicitly so this fails
#                                    closed with the documented stop/reason
#                                    contract instead of an uncaught
#                                    exception, found by a compliance-audit
#                                    adversarial pass, 2026-08-14)
#   stale-sha                     — last_sha != expected (or absent)
#   reviewer-flow                 — review_mode != own-branch. Auto-continue
#                                    is scoped to self-review only — a
#                                    PR-by-number reviewer can't act on
#                                    someone else's diff, so auto-looping it
#                                    just burns dispatch cost with nothing to
#                                    show for it.
#   malformed-round                — round absent or not a real int
#   malformed-force-human          — force_human absent or not a real bool
#   malformed-convergence-state    — convergence_state absent or not one of
#                                     the 5 canonical tokens
#   converged/regressed/churning/stalled — convergence_state itself, when
#                                     not "progressing"
#   ceiling                        — progressing + force_human=true. On this
#                                     branch force_human=true means ONLY the
#                                     round-ceiling case: write-review-
#                                     state.sh's own force_human formula
#                                     (force = (round>=ceiling and not clean)
#                                     or (regressed and round>=3) or (churn
#                                     and not clean)) means the regressed/
#                                     churn disjuncts already routed through
#                                     their own convergence_state branch
#                                     above — never conflate this with a
#                                     corrupted force_human field (a real
#                                     production-adjacent bug caught during
#                                     plan review: routing both through the
#                                     same reason misdirects the operator at
#                                     the exact hard-stop the ADR depends on).
#   no-findings-nonclean            — round>=2 and finding_files is empty (or
#                                      absent/non-list, normalized to empty).
#                                      convergence_state=="progressing"
#                                      already implies not-clean by
#                                      construction, so that isn't re-checked
#                                      here. Closes a hole neither the ADR
#                                      nor write-review-state.sh names:
#                                      regressed/churning can only be
#                                      computed from finding_files, so an
#                                      empty set silently disables that
#                                      detection on a non-clean round — this
#                                      guard is the auto-loop's own backstop
#                                      for it, since unattended continuation
#                                      is exactly where that gap bites.
#   otherwise: continue
set -euo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/err.sh"

EXPECTED_SHA="${1:-}"
[ -n "$EXPECTED_SHA" ] || err_die "expected_head_sha required"
WT="${2:-}"

STATE_DIR="${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}"
if [ -n "$WT" ]; then
  STATE_FILE="$STATE_DIR/review-pr-${WT##*-}.json"
else
  STATE_FILE="$STATE_DIR/review-last.json"
fi

# A missing/empty state file needs no python invocation to diagnose.
if [ ! -s "$STATE_FILE" ]; then
  echo "stop"
  echo "reason=missing-state"
  exit 1
fi

# Every branch below prints its verdict and exits 0 from python's own
# perspective -- the shell decides the PROCESS exit code afterward from the
# printed text, not from python's exit status. A python exit failure here
# would trip `set -e` on the assignment below before the stdout contract
# (the two lines a caller reads) ever got printed.
DECISION=$(python3 -c '
import json, sys

state_file, expected_sha = sys.argv[1:3]

try:
    with open(state_file) as f:
        d = json.load(f)
    if not isinstance(d, dict):
        raise ValueError("top-level JSON is not an object")
except Exception:
    print("stop"); print("reason=malformed-state"); sys.exit(0)

def is_bool(v):
    return isinstance(v, bool)

def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)

last_sha = d.get("last_sha")
if not isinstance(last_sha, str) or last_sha != expected_sha:
    print("stop"); print("reason=stale-sha"); sys.exit(0)

if d.get("review_mode") != "own-branch":
    print("stop"); print("reason=reviewer-flow"); sys.exit(0)

round_n = d.get("round")
if not is_int(round_n) or round_n < 0:
    print("stop"); print("reason=malformed-round"); sys.exit(0)

force_human = d.get("force_human")
if not is_bool(force_human):
    print("stop"); print("reason=malformed-force-human"); sys.exit(0)

CANONICAL = ("converged", "regressed", "churning", "stalled", "progressing")
convergence_state = d.get("convergence_state")
if convergence_state not in CANONICAL:
    print("stop"); print("reason=malformed-convergence-state"); sys.exit(0)

if convergence_state != "progressing":
    print("stop"); print("reason=%s" % convergence_state); sys.exit(0)

if force_human:
    # Reachable ONLY as the round-ceiling case -- regressed/churning already
    # exited above via convergence_state != "progressing". See the header
    # comment for the force_human formula this depends on.
    print("stop"); print("reason=ceiling"); sys.exit(0)

finding_files = d.get("finding_files")
if not isinstance(finding_files, list):
    finding_files = []
if round_n >= 2 and len(finding_files) == 0:
    print("stop"); print("reason=no-findings-nonclean"); sys.exit(0)

print("continue")
' "$STATE_FILE" "$EXPECTED_SHA")

echo "$DECISION"
case "$DECISION" in
  continue*) exit 0 ;;
  *) exit 1 ;;
esac
