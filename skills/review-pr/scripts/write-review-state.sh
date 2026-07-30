#!/usr/bin/env bash
# review-pr Phase 7 — writes the machine-readable review-state contract
# /ship-merge's scored review gate reads. Explicit positional args, not
# inherited env — an inherited-but-unexported variable fails silently across
# a nested bash invocation like this one (same bug class as kbg-harness's
# wiki-scan, v0.68.107).
#
# Usage: write-review-state.sh <critical_count> <rehunt> <dispatch_failures> <head_sha> [worktree_path]
#   critical_count    — number of Critical findings from Phase 5 (required)
#   rehunt            — Phase 5 step 3.6 outcome: clean|skipped-trivial|incomplete|n/a (required)
#   dispatch_failures — non-empty string if Phase 4 step 4 recorded any (pass "" if none)
#   head_sha          — Phase 2's pinned HEAD_SHA (required)
#   worktree_path     — Phase 2's $WT if this is a PR-by-number review; omit/empty for own-branch
#
# Prints the written state-file path to stdout on success.
set -euo pipefail

CRITICAL_COUNT="${1:?critical_count required}"
REHUNT_RAW="${2:?rehunt required}"
DISPATCH_FAILURES="${3:-}"
HEAD_SHA="${4:?head_sha required}"
WT="${5:-}"

STATE_DIR="${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}"
mkdir -p "$STATE_DIR"

# Canonicalize to one of the 4 tokens. Audited 105 real production state files
# (2026-07-28): most sampled runs held free-text narrative instead of one of
# these — a comment alone doesn't constrain what a hand-authored write puts
# here. Anything non-canonical is treated as not-certified (fail closed).
case "$REHUNT_RAW" in
  clean|skipped-trivial|incomplete|n/a) REHUNT="$REHUNT_RAW" ;;
  *) REHUNT="incomplete" ;;
esac

# An incomplete re-hunt or any dispatch failure means the review never
# certified zero criticals — it must not reach /ship-merge as clean, or the
# machine gate reads critical_count:0 as a clean pass on an unfinished review.
if [ "$REHUNT" = "incomplete" ] || [ -n "$DISPATCH_FAILURES" ]; then
  CLEAN=false
else
  CLEAN=$([ "$CRITICAL_COUNT" -eq 0 ] && echo "true" || echo "false")
fi

REVIEW_MODE=$([ -n "$WT" ] && echo "pr-by-number" || echo "own-branch")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')

# PR-by-number reviews are keyed per PR (from $WT="<tmp>/review-pr-<#>") so a
# second PR's review can't clobber the first's before /ship-merge reads it
# (production incident: #357 overwritten by #358, run close together). Own-
# branch reviews have only one active branch per working tree, so the shared
# file is fine there.
if [ -n "$WT" ]; then
  STATE_FILE="$STATE_DIR/review-pr-${WT##*-}.json"
else
  STATE_FILE="$STATE_DIR/review-last.json"
fi

printf '{"clean":%s,"critical_count":%s,"rehunt":"%s","last_sha":"%s","branch":"%s","review_mode":"%s","ts":"%s"}\n' \
  "$CLEAN" "$CRITICAL_COUNT" "$REHUNT" "$HEAD_SHA" "$BRANCH" "$REVIEW_MODE" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$STATE_FILE"

# The state file MUST land outside $WT so worktree cleanup can't delete it
# (production incident: PR #2619's state file was written to $WT/.scratch/
# and lost with the worktree, so the merge gate read "no review ran").
if [ -n "$WT" ]; then
  STATE_FILE_DIR=$(cd -- "$(dirname -- "$STATE_FILE")" && pwd -P)
  WT_REAL=$(cd -- "$WT" && pwd -P)
  case "$STATE_FILE_DIR" in
    "$WT_REAL"|"$WT_REAL"/*)
      echo "ERROR: state file $STATE_FILE resolves INSIDE $WT — it will be deleted by cleanup. Fix REVIEW_PR_STATE_DIR and re-run before proceeding." >&2
      exit 1
      ;;
  esac
fi

test -s "$STATE_FILE" || { echo "ERROR: state file $STATE_FILE is missing/empty after write" >&2; exit 1; }

echo "$STATE_FILE"
