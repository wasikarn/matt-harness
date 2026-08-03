#!/usr/bin/env bash
# review-pr Phase 7 — writes the machine-readable review-state contract
# /ship-merge's scored review gate reads. Explicit positional args, not
# inherited env — an inherited-but-unexported variable fails silently across
# a nested bash invocation like this one (same bug class as kbg-harness's
# wiki-scan, v0.68.107).
#
# Usage: write-review-state.sh <critical_count> <rehunt> <dispatch_failures> <head_sha> [worktree_path] [important_count] [minor_count]
#   critical_count    — number of Critical findings from Phase 5 (required)
#   rehunt            — Phase 5 step 3.6 outcome: clean|skipped-trivial|incomplete|n/a (required)
#   dispatch_failures — non-empty string if Phase 4 step 4 recorded any (pass "" if none)
#   head_sha          — Phase 2's pinned HEAD_SHA (required)
#   worktree_path     — Phase 2's $WT if this is a PR-by-number review; omit/empty for own-branch
#   important_count   — number of Important findings from Phase 5 (optional, default 0)
#   minor_count       — number of Minor findings from Phase 5 (optional, default 0)
#
# Round tracking: carries the prior round's counts forward from the same state file so Phase 7 can
# report a delta instead of starting cold each re-run. Own-branch reviews share one file
# (review-last.json) keyed by nothing but the branch name, so a round only continues when the old
# file's branch matches this run's — otherwise it's a different series and resets to round 1. This
# means reviewing branch A, then B, then A again resets A to round 1 on its second pass: a single
# shared slot can't represent interleaved series. PR-by-number is unaffected (keyed per PR).
#
# Prints the written state-file path to stdout on success, then a second line with the round-aware
# footer inputs (round/prev_*/stalled) so the caller renders from what this script computed instead
# of having to re-read the file back out — a skipped re-read would silently degrade the footer.
set -euo pipefail

CRITICAL_COUNT="${1:?critical_count required}"
REHUNT_RAW="${2:?rehunt required}"
DISPATCH_FAILURES="${3:-}"
HEAD_SHA="${4:?head_sha required}"
WT="${5:-}"
IMPORTANT_COUNT="${6:-0}"
MINOR_COUNT="${7:-0}"

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

# Carry the prior round forward. Own-branch only continues the series when the
# old file's branch matches this run's; PR-by-number is keyed per PR so any
# existing content is already the same PR's prior round.
PREV_ROUND=0
PREV_CRITICAL="n/a"
PREV_IMPORTANT="n/a"
PREV_MINOR="n/a"
if [ -s "$STATE_FILE" ]; then
  PREV_DATA=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception:
    print("|||||")
    sys.exit(0)
print("%s|%s|%s|%s|%s" % (
    d.get("branch", ""), d.get("round", 0),
    d.get("critical_count", "n/a"), d.get("important_count", "n/a"), d.get("minor_count", "n/a")))
' "$STATE_FILE" 2>/dev/null || echo "|||||")
  IFS='|' read -r PREV_BRANCH PREV_ROUND_READ PREV_CRITICAL_READ PREV_IMPORTANT_READ PREV_MINOR_READ <<< "$PREV_DATA"
  if [ -n "$WT" ] || [ "$PREV_BRANCH" = "$BRANCH" ]; then
    PREV_ROUND="${PREV_ROUND_READ:-0}"
    PREV_CRITICAL="${PREV_CRITICAL_READ:-n/a}"
    PREV_IMPORTANT="${PREV_IMPORTANT_READ:-n/a}"
    PREV_MINOR="${PREV_MINOR_READ:-n/a}"
  fi
fi
ROUND=$((PREV_ROUND + 1))

# Non-convergence signal: 3+ rounds in, still not clean, and no tier improved
# since the prior round. Not a round-count threshold on its own — the worst
# observed real case (PR #2632) reached 4 rounds and did converge, so a bare
# round cap would either never fire or fire on a PR that's still making
# progress (e.g. slowed by rehunt:incomplete/dispatch failures, not disputes).
STALLED=false
if [ "$ROUND" -ge 3 ] && [ "$CLEAN" = "false" ] \
   && [ "$PREV_CRITICAL" != "n/a" ] && [ "$PREV_IMPORTANT" != "n/a" ] && [ "$PREV_MINOR" != "n/a" ] \
   && [ "$CRITICAL_COUNT" -ge "$PREV_CRITICAL" ] \
   && [ "$IMPORTANT_COUNT" -ge "$PREV_IMPORTANT" ] \
   && [ "$MINOR_COUNT" -ge "$PREV_MINOR" ]; then
  STALLED=true
fi

printf '{"clean":%s,"critical_count":%s,"rehunt":"%s","last_sha":"%s","branch":"%s","review_mode":"%s","ts":"%s","round":%s,"important_count":%s,"minor_count":%s,"prev_critical_count":%s,"prev_important_count":%s,"prev_minor_count":%s,"stalled":%s}\n' \
  "$CLEAN" "$CRITICAL_COUNT" "$REHUNT" "$HEAD_SHA" "$BRANCH" "$REVIEW_MODE" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$ROUND" "$IMPORTANT_COUNT" "$MINOR_COUNT" \
  "$([ "$PREV_CRITICAL" = "n/a" ] && echo '"n/a"' || echo "$PREV_CRITICAL")" \
  "$([ "$PREV_IMPORTANT" = "n/a" ] && echo '"n/a"' || echo "$PREV_IMPORTANT")" \
  "$([ "$PREV_MINOR" = "n/a" ] && echo '"n/a"' || echo "$PREV_MINOR")" \
  "$STALLED" \
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
echo "round=$ROUND prev_critical=$PREV_CRITICAL prev_important=$PREV_IMPORTANT prev_minor=$PREV_MINOR stalled=$STALLED"
