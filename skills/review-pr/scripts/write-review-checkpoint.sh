#!/usr/bin/env bash
# review-pr's 3-skill chain (review-pr -> review-pr-tier -> review-pr-finish)
# — writes an intermediate checkpoint at each hand-off so runtime state
# survives a compaction event between skill invocations. Distinct from
# write-review-state.sh (Phase 7's FINAL state, the contract /ship-merge's
# gate reads) — this script is NOT an extension of that one: a differently-
# shaped intermediate write through the same file/round-tracking contract
# risks corrupting the convergence chain should-continue-loop.sh depends on,
# or having /ship-merge read an in-progress checkpoint as a certified result.
#
# Checkpoints ONLY what's genuinely unrecoverable after a compaction event —
# not every cross-phase value. $WT, the changed-file list, the routed-agent
# list, and the 3 tier counts are all cheaply re-derivable from git/gh at the
# start of the next skill and are deliberately NOT stored here. base_sha/
# head_sha look re-derivable (`git rev-parse HEAD`) but aren't idempotent —
# if the branch moved since Phase 2 pinned them, recompute silently returns
# a DIFFERENT, wrong value with no error, which is why they're checkpointed
# rather than left to re-derivation.
#
# Usage: write-review-checkpoint.sh <phase> <head_sha> [worktree_path] [payload_json_path]
#   phase             — the phase JUST COMPLETED: 2 | 4 | 5 (required)
#   head_sha          — Phase 2's pinned HEAD_SHA (required)
#   worktree_path     — Phase 2's $WT for a PR-by-number review; omit/empty
#                        for own-branch (same convention as write-review-
#                        state.sh's own 5th positional arg)
#   payload_json_path — a temp file holding this phase's payload object
#                        (passed by file, not argv, same reason
#                        finding_files_path is in write-review-state.sh).
#                        Required fields per phase (all must already be
#                        valid JSON in the payload object):
#                          phase=2 -> base_sha (required); jira_ticket (object or
#                          null — included in the payload but not enforced by
#                          the required-field check below)
#                          phase=4 -> agent_findings (list), dispatch_failures (string)
#                          phase=5 -> tier_list (list)
#
# One accumulating file per review (read-prior-then-rewrite, same pattern as
# write-review-state.sh's own PREV_* carry-forward) — a reading skill only
# ever opens one path regardless of which phase it's resuming from.
#
# File naming deliberately does NOT start with "review-pr-": hooks/gates/
# convergence-merge-gate.sh's _any_at_risk_state() globs "review-pr-*.json"
# in the state dir and blocks any ambiguous merge if a matched file lacks
# clean:true. A checkpoint (written mid-review, no clean field, never
# cleaned up) named review-pr-checkpoint-*.json would match that glob and
# permanently block merges — found during planning, before any code shipped.
# "review-checkpoint-*" is verified clear of every glob in this repo.
set -euo pipefail

# shellcheck source=../../../scripts/_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/err.sh"

PHASE_RAW="${1:?phase required (2, 4, or 5)}"
HEAD_SHA="${2:?head_sha required}"
WT="${3:-}"
PAYLOAD_PATH="${4:-}"

case "$PHASE_RAW" in
  2|4|5) PHASE="$PHASE_RAW" ;;
  *) err_die "unrecognized phase '$PHASE_RAW' — expected 2, 4, or 5" ;;
esac

[ -n "$PAYLOAD_PATH" ] && [ -f "$PAYLOAD_PATH" ] || err_die "payload_json_path required and must exist: '$PAYLOAD_PATH'"

STATE_DIR="${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR"

REVIEW_MODE=$([ -n "$WT" ] && echo "pr-by-number" || echo "own-branch")

if [ -n "$WT" ]; then
  STATE_FILE="$STATE_DIR/review-checkpoint-${WT##*-}.json"
else
  STATE_FILE="$STATE_DIR/review-checkpoint-last.json"
fi

# Read-prior-then-merge: an existing checkpoint's fields carry forward
# unchanged except what this phase's payload supplies. A malformed/corrupt
# existing file is treated as absent (start fresh), never crashes the write
# — the FAIL-CLOSED side of this mechanism is the read script, not the
# writer; the writer's job is to durably record what it's given.
python3 -c '
import json, sys

state_file, phase, head_sha, review_mode, wt, payload_path, ts = sys.argv[1:8]

try:
    with open(state_file) as f:
        prior = json.load(f)
    if not isinstance(prior, dict):
        prior = {}
except Exception:
    prior = {}

try:
    with open(payload_path) as f:
        payload = json.load(f)
    if not isinstance(payload, dict):
        raise ValueError("payload is not a JSON object")
except Exception as e:
    print("ERROR: payload_json_path %r is not a valid JSON object: %s" % (payload_path, e), file=sys.stderr)
    sys.exit(1)

required = {
    "2": ["base_sha"],
    "4": ["agent_findings", "dispatch_failures"],
    "5": ["tier_list"],
}[phase]
missing = [k for k in required if k not in payload]
if missing:
    print("ERROR: payload for phase %s missing required field(s): %s" % (phase, ", ".join(missing)), file=sys.stderr)
    sys.exit(1)

merged = dict(prior)
merged.update(payload)
merged["phase"] = int(phase)
merged["head_sha"] = head_sha
merged["review_mode"] = review_mode
merged["ts"] = ts

with open(state_file, "w") as f:
    json.dump(merged, f)
    f.write("\n")
' "$STATE_FILE" "$PHASE" "$HEAD_SHA" "$REVIEW_MODE" "$WT" "$PAYLOAD_PATH" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  || err_die "failed to write checkpoint to $STATE_FILE"

# The checkpoint MUST land outside $WT so worktree cleanup can't delete it —
# same production-incident reasoning write-review-state.sh's own guard cites
# (PR #2619's state file was written to $WT/.scratch/ and lost with the
# worktree). Only checkable while $WT still exists on disk.
if [ -n "$WT" ] && [ -d "$WT" ]; then
  STATE_FILE_DIR=$(cd -- "$(dirname -- "$STATE_FILE")" && pwd -P)
  WT_REAL=$(cd -- "$WT" && pwd -P)
  case "$STATE_FILE_DIR" in
    "$WT_REAL"|"$WT_REAL"/*)
      err_die "checkpoint file $STATE_FILE resolves INSIDE $WT — it will be deleted by cleanup. Fix REVIEW_PR_STATE_DIR and re-run before proceeding."
      ;;
  esac
fi

test -s "$STATE_FILE" || err_die "checkpoint file $STATE_FILE is missing/empty after write"

echo "$STATE_FILE"
