#!/usr/bin/env bash
# review-pr's 3-skill chain — fail-closed read of the checkpoint
# write-review-checkpoint.sh writes at each hand-off. Called as the FIRST
# action by review-pr-tier and review-pr-finish, before anything else.
# Mirrors should-continue-loop.sh's own fail-closed, first-match-wins
# pattern and stdout contract.
#
# Usage: read-review-checkpoint.sh <expected_phase> <expected_head_sha> [worktree_path]
#   expected_phase     — 2, 4, or 5. The phase the CALLING skill needs to
#                         already be complete (e.g. review-pr-tier, which
#                         starts at Phase 5, expects phase=4 — the checkpoint
#                         written when Phase 4 finished).
#   expected_head_sha  — the $HEAD_SHA value the calling skill already holds
#                         from its own prior hand-off. This script does NOT
#                         call git itself — same convention as
#                         should-continue-loop.sh (a pure last_sha string
#                         compare, zero git invocations of its own). This
#                         matters specifically for PR-by-number reviews: a
#                         live `git rev-parse HEAD` at read time, run from
#                         the wrong cwd relative to $WT, would reject every
#                         legitimate PR-by-number hand-off as stale-sha.
#   worktree_path       — Phase 2's $WT for a PR-by-number review; omit/empty
#                          for own-branch (same convention as the writer's
#                          3rd positional arg — mirrored here so both scripts
#                          derive the identical STATE_FILE path).
#
# Stdout contract:
#   line 1: "ok" or "stop"
#   line 2 (stop only): "reason=<token>"
#   (ok only) the checkpoint JSON, on stdout, after line 1
# Exit code: 0 = ok, any non-zero = stop.
#
# Checks run in a fixed order, first match wins:
#   missing-checkpoint          — file absent/empty
#   malformed-checkpoint        — not valid JSON, or valid JSON that isn't a
#                                  top-level object
#   stale-checkpoint-phase      — checkpoint's phase field != expected_phase,
#                                  EXACT equality, not >=. A >= comparison has
#                                  a live hole: a completed PRIOR review of
#                                  the same branch could leave a LATER phase
#                                  on disk, and if HEAD hasn't moved since,
#                                  the stale-sha check below wouldn't catch
#                                  it either — exact equality closes this
#                                  with no separate cleanup step needed.
#   stale-sha                   — head_sha != expected_head_sha
#   malformed-checkpoint-fields — any field required for expected_phase is
#                                  missing or the wrong type
#
# On any failure: stop, print the exact reason token, never guess or proceed
# on partial/assumed values — the calling skill must surface this to the
# human, not improvise from conversational memory of what it thinks the
# missing state probably was.
set -euo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/err.sh"

EXPECTED_PHASE_RAW="${1:?expected_phase required (2, 4, or 5)}"
EXPECTED_SHA="${2:?expected_head_sha required}"
WT="${3:-}"

case "$EXPECTED_PHASE_RAW" in
  2|4|5) EXPECTED_PHASE="$EXPECTED_PHASE_RAW" ;;
  *) err_die "unrecognized expected_phase '$EXPECTED_PHASE_RAW' — expected 2, 4, or 5" ;;
esac

STATE_DIR="${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}"
if [ -n "$WT" ]; then
  STATE_FILE="$STATE_DIR/review-checkpoint-${WT##*-}.json"
else
  STATE_FILE="$STATE_DIR/review-checkpoint-last.json"
fi

# A missing/empty checkpoint needs no python invocation to diagnose.
if [ ! -s "$STATE_FILE" ]; then
  echo "stop"
  echo "reason=missing-checkpoint"
  exit 1
fi

# Every branch below prints its verdict and exits 0 from python's own
# perspective — the shell decides the PROCESS exit code afterward from the
# printed text, same pattern as should-continue-loop.sh.
DECISION=$(python3 -c '
import json, sys

state_file, expected_phase, expected_sha = sys.argv[1:4]
expected_phase = int(expected_phase)

try:
    with open(state_file) as f:
        d = json.load(f)
    if not isinstance(d, dict):
        raise ValueError("top-level JSON is not an object")
except Exception:
    print("stop"); print("reason=malformed-checkpoint"); sys.exit(0)

def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)

phase = d.get("phase")
if not is_int(phase) or phase != expected_phase:
    print("stop"); print("reason=stale-checkpoint-phase"); sys.exit(0)

head_sha = d.get("head_sha")
if not isinstance(head_sha, str) or head_sha != expected_sha:
    print("stop"); print("reason=stale-sha"); sys.exit(0)

REQUIRED = {
    2: ["base_sha"],
    4: ["base_sha", "agent_findings", "dispatch_failures"],
    5: ["base_sha", "agent_findings", "dispatch_failures", "tier_list"],
}[expected_phase]
TYPES = {
    "base_sha": str,
    "agent_findings": list,
    "dispatch_failures": str,
    "tier_list": list,
}
for k in REQUIRED:
    if k not in d or not isinstance(d[k], TYPES[k]):
        print("stop"); print("reason=malformed-checkpoint-fields"); sys.exit(0)

print("ok")
print(json.dumps(d))
' "$STATE_FILE" "$EXPECTED_PHASE" "$EXPECTED_SHA")

FIRST_LINE=$(printf '%s\n' "$DECISION" | head -n1)
case "$FIRST_LINE" in
  ok)
    echo "$DECISION"
    exit 0
    ;;
  *)
    echo "$DECISION"
    exit 1
    ;;
esac
