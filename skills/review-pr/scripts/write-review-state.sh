#!/usr/bin/env bash
# review-pr Phase 7 — writes the machine-readable review-state contract
# /ship-merge's scored review gate reads. Explicit positional args, not
# inherited env — an inherited-but-unexported variable fails silently across
# a nested bash invocation like this one (same bug class as kbg-harness's
# wiki-scan, v0.68.107).
#
# Usage: write-review-state.sh <critical_count> <rehunt> <dispatch_failures> <head_sha> [worktree_path] [important_count] [minor_count] [finding_files_path]
#   critical_count    — number of Critical findings from Phase 5 (required)
#   rehunt            — Phase 5 step 3.6 outcome: clean|skipped-trivial|incomplete|n/a (required)
#   dispatch_failures — non-empty string if Phase 4 step 4 recorded any (pass "" if none)
#   head_sha          — Phase 2's pinned HEAD_SHA (required)
#   worktree_path     — Phase 2's $WT if this is a PR-by-number review; omit/empty for own-branch
#   important_count   — number of Important findings from Phase 5 (optional, default 0)
#   minor_count       — number of Minor findings from Phase 5 (optional, default 0)
#   finding_files_path — temp file with one file-path per line holding Critical+Important
#                        findings this round (optional). Feeds file-level finding-identity
#                        tracking for the cross-pass convergence gate (regressed detection).
#
# Round tracking: carries the prior round's counts forward from the same state file so Phase 7 can
# report a delta instead of starting cold each re-run. Own-branch reviews share one file
# (review-last.json) keyed by nothing but the branch name, so a round only continues when the old
# file's branch matches this run's — otherwise it's a different series and resets to round 1. This
# means reviewing branch A, then B, then A again resets A to round 1 on its second pass: a single
# shared slot can't represent interleaved series. PR-by-number is unaffected (keyed per PR).
#
# Prints the written state-file path to stdout on success, then a second line with the round-aware
# footer inputs (round/prev_*/stalled/regressed/force_human/convergence_state/churn_files) so the
# caller renders from what this script computed instead of having to re-read the file back out — a
# skipped re-read would silently degrade the footer. convergence_state is one of converged/regressed/
# churning/stalled/progressing; churning is a same-file streak (a file flagged 3+ rounds running).
set -euo pipefail

# shellcheck source=../../../scripts/_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/err.sh"

CRITICAL_COUNT="${1:?critical_count required}"
REHUNT_RAW="${2:?rehunt required}"
DISPATCH_FAILURES="${3:-}"
HEAD_SHA="${4:?head_sha required}"
WT="${5:-}"
IMPORTANT_COUNT="${6:-0}"
MINOR_COUNT="${7:-0}"
FINDING_FILES_PATH="${8:-}"

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
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
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

# A predecessor file can carry hand-authored non-numeric values (same incident
# class ship-merge.md documents auditing: ~19% of 105 sampled state files held
# free-text instead of the canonical tokens their field expects). Treat
# anything that isn't a plain non-negative integer as absent, not as data —
# feeding a non-numeric PREV_* into the `-ge` checks below or the round
# arithmetic would either silently skip the STALLED check or crash the script.
case "$PREV_ROUND" in ''|*[!0-9]*) PREV_ROUND=0 ;; esac
case "$PREV_CRITICAL" in ''|*[!0-9]*) PREV_CRITICAL="n/a" ;; esac
case "$PREV_IMPORTANT" in ''|*[!0-9]*) PREV_IMPORTANT="n/a" ;; esac
case "$PREV_MINOR" in ''|*[!0-9]*) PREV_MINOR="n/a" ;; esac

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

# Cross-pass convergence gate (file-level finding-identity tracking).
#
# regressed = this round flagged a finding in a file that was NOT flagged last
# round — catches fix-induced cross-file regressions, the dominant non-
# convergence cause from PR #2632's >10-round loop (a fix in file X introduced
# a new Critical in file Y, which read as "improving" under the tier-count-only
# stalled check and never tripped). Computed deterministically here (the
# verifier), never by the model — maker/verifier holds: the convergence
# computation is a structural property of the review series, not an opinion.
#
# force_human = (round ≥ ceiling AND not clean) OR (regressed AND round ≥ 3).
# The ceiling is past PR #2632's known-convergent 4 rounds. Configurable via
# REVIEW_PR_ROUND_CEILING (default 5). Layer 2 (ship-merge's scored gate) reads
# force_human and trips the 40 floor; the model can't bypass it because
# ship-merge is disable-model-invocation (human-only).
#
# ponytail: file-level identity, deliberately NOT line-level. A new finding in
# a file that already had one is caught by the churn streak below, not by
# `regressed` (which stays file-set-only on purpose). Line-level fingerprints
# (file:start_line-end_line) were evaluated and rejected 2026-08-14: a fixed
# finding's fingerprint vanishes and a moved one changes every round, so
# cur ∩ prev ≈ ∅ on nearly every round by construction — `regressed` would fire
# on almost every round ≥ 2 and the 4-state token would collapse to
# "regressed" for the whole series. The churn streak below deliberately does
# NOT try to distinguish "same issue recurring" from "new issue, same module"
# — 3 rounds running on one file is the signal either way, and both are real
# fix-induced-regression risk. Confirmed empirically 2026-08-14: two real
# incidents (10-14 review rounds each) both showed same-file churn as the
# actual non-convergence cause, not cross-file regression.
#
# REVIEW_PR_ROUND_CEILING is read INSIDE this script (not across the nested-bash
# boundary the header's "explicit positional args, not inherited env" warning is
# about — that warning targets an inherited-but-unexported var failing silently
# across a nested invocation, which this isn't). Callers that want to override
# export it before invoking this script; review-pr Phase 7 lets the env default.
ROUND_CEILING="${REVIEW_PR_ROUND_CEILING:-5}"
case "$ROUND_CEILING" in ''|*[!0-9]*) ROUND_CEILING=5 ;; esac

REGRESSED=false
FORCE_HUMAN=false
CONVERGENCE_STATE="progressing"
FINDING_FILES_JSON="[]"
CHURN_FILES=""
FILE_STREAKS_JSON="{}"
CHURN_FILES_JSON="[]"

if [ -n "$FINDING_FILES_PATH" ] && [ -f "$FINDING_FILES_PATH" ]; then
  # 7 newline-separated lines out: regressed, force_human, convergence_state,
  # churn_files (comma-joined, human-readable, MAY be empty — kept off the
  # last line on purpose: $() strips only trailing newlines from the very end
  # of the captured output, so an empty non-last line is fine, but a failing
  # `read -r` on a genuinely-absent last line would kill the script under
  # set -e), finding_files_json, file_streaks_json, churn_files_json (last
  # three are JSON via json.dumps — always >=2 chars, safe in any position).
  CONV_DATA=$(python3 -c '
import json, sys
state_file, finding_files_path, stalled, round_n, clean, ceiling = sys.argv[1:7]

def _norm_path(p):
    # Strip a leading "/" so a caller that reports a $WT-absolute path (own-
    # branch reviews sit at repo root; pr-by-number reviews cd into $WT) does
    # not create a second, non-matching identity for the same file across
    # rounds -- both `regressed` and the churn streak are exact-string set
    # comparisons. Enforced here (the verifier), not just documented in
    # SKILL.md prose, per the 2026-08-14 adversarial review: a bad caller
    # left unenforced can make `regressed` fire spuriously (a "new" absolute-
    # path string never in `prev`) while churn silently never accumulates
    # (its own prior-round string never matches either).
    return p.lstrip("/")

cur = []
try:
    with open(finding_files_path) as f:
        cur = sorted({_norm_path(l.strip()) for l in f if l.strip()})
except OSError:
    cur = []

rn = int(round_n)
prev = set()
prev_streaks = {}
try:
    d = json.load(open(state_file))
    prev = set(d.get("finding_files") or [])
    ps = d.get("file_streaks")
    if isinstance(ps, dict):
        prev_streaks = ps
except Exception:
    prev = set()
    prev_streaks = {}
# A fresh series (round 1) must not inherit another series'\'' streaks -- same
# reasoning as `regressed`'\''s own round>1 guard below.
if rn <= 1:
    prev_streaks = {}

# regressed needs a real prior round that recorded findings — otherwise the
# first round that supplies finding_files can'\''t diff against nothing.
regressed = (rn > 1 and len(cur) > 0 and len(prev) > 0
             and any(f not in prev for f in cur))

# Same-file churn: consecutive rounds a file has held a Critical/Important
# finding, regardless of whether it'\''s the same issue each time. A file
# absent this round simply is not in the new dict, so streaks reset by
# omission -- no separate reset logic needed. Threshold 3 is forced by the
# existing ROUND_CEILING default of 5, not chosen freely: it leaves a 2-round
# early-warning window (rounds 3-4) before the ceiling would fire anyway.
streaks = {}
for f in cur:
    p = prev_streaks.get(f)
    streaks[f] = (p if isinstance(p, int) and p > 0 else 0) + 1
churn = sorted(f for f, n in streaks.items() if n >= 3)

cl = (clean == "true"); st = (stalled == "true"); ce = int(ceiling)
if cl:
    state = "converged"
elif regressed:
    state = "regressed"
elif churn:
    state = "churning"
elif st:
    state = "stalled"
else:
    state = "progressing"
# churn implies rn >= 3 (a streak of 3 takes 3 rounds to build), so no
# separate round guard is needed here, unlike the `regressed and rn >= 3`
# clause. `and not cl` preserves the writer'\''s invariant that a converged
# review never sets force_human -- ship-merge and the Phase 7 footer both
# rely on clean winning regardless of any other signal.
force = (rn >= ce and not cl) or (regressed and rn >= 3) or (bool(churn) and not cl)
print(str(regressed).lower())
print(str(force).lower())
print(state)
print(",".join(churn))
print(json.dumps(cur))
print(json.dumps(streaks))
print(json.dumps(churn))
' "$STATE_FILE" "$FINDING_FILES_PATH" "$STALLED" "$ROUND" "$CLEAN" "$ROUND_CEILING" 2>/dev/null \
    || { if [ "$CLEAN" = "true" ]; then
           printf 'false\nfalse\nconverged\n\n[]\n{}\n[]\n'
         else
           printf 'false\ntrue\nprogressing\n\n[]\n{}\n[]\n'
         fi; })
  # Fail-closed: a python3 crash (OOM, missing binary, unhandled path) on a
  # NON-clean review must not silently downgrade to force_human=false — that
  # would let a non-converged review reach ship-merge's one-way door with the
  # gate reading "all clear." $CLEAN is a bash var in scope here (computed at
  # the top of the script), so the fallback branches on it without re-entering
  # python3. $ROUND/$ROUND_CEILING are intentionally NOT consulted in the
  # fallback — when the verifier can't compute convergence at all, blocking on
  # any non-clean review is the safe superset of the ceiling+regressed+churn
  # checks.
  { read -r REGRESSED; read -r FORCE_HUMAN; read -r CONVERGENCE_STATE; read -r CHURN_FILES
    read -r FINDING_FILES_JSON; read -r FILE_STREAKS_JSON; read -r CHURN_FILES_JSON; } <<< "$CONV_DATA"
  # Re-validate all three JSON pieces parsed cleanly; if any didn'\''t (a path
  # contained a newline — theoretical only), fall back to empty for all three
  # — regressed/force/state were already computed from the actual comparison,
  # so only the stored blobs are lost, matching the existing conservative
  # direction for this class of failure.
  python3 -c 'import json,sys; [json.loads(a) for a in sys.argv[1:]]' \
    "$FINDING_FILES_JSON" "$FILE_STREAKS_JSON" "$CHURN_FILES_JSON" 2>/dev/null \
    || { FINDING_FILES_JSON="[]"; FILE_STREAKS_JSON="{}"; CHURN_FILES_JSON="[]"; }
else
  # No finding files supplied — regressed/churn are unknown (false),
  # convergence_state derives from clean/stalled only. The round ceiling
  # still applies.
  if [ "$CLEAN" = "true" ]; then
    CONVERGENCE_STATE="converged"
  elif [ "$STALLED" = "true" ]; then
    CONVERGENCE_STATE="stalled"
  fi
  if [ "$ROUND" -ge "$ROUND_CEILING" ] && [ "$CLEAN" = "false" ]; then
    FORCE_HUMAN=true
  fi
fi

# json.dumps via argv, not printf %s splicing — a branch name containing a
# literal " (git permits it; only ":" and a handful of other characters are
# disallowed) previously broke the hand-built JSON string (found 2026-08-06).
# Every field goes through argv, not just the one that was flagged, since a
# printf %s field is unsafe by construction regardless of which value is
# realistically attacker-influenceable today.
python3 -c '
import json, sys

def _numeric_or_na(s):
    return s if s == "n/a" else int(s)

d = {
    "clean": sys.argv[1] == "true",
    "critical_count": int(sys.argv[2]),
    "rehunt": sys.argv[3],
    "last_sha": sys.argv[4],
    "branch": sys.argv[5],
    "review_mode": sys.argv[6],
    "ts": sys.argv[7],
    "round": int(sys.argv[8]),
    "important_count": int(sys.argv[9]),
    "minor_count": int(sys.argv[10]),
    "prev_critical_count": _numeric_or_na(sys.argv[11]),
    "prev_important_count": _numeric_or_na(sys.argv[12]),
    "prev_minor_count": _numeric_or_na(sys.argv[13]),
    "stalled": sys.argv[14] == "true",
    "finding_files": json.loads(sys.argv[15]),
    "regressed": sys.argv[16] == "true",
    "force_human": sys.argv[17] == "true",
    "convergence_state": sys.argv[18],
    "file_streaks": json.loads(sys.argv[19]),
    "churn_files": json.loads(sys.argv[20]),
}
with open(sys.argv[21], "w") as f:
    json.dump(d, f)
    f.write("\n")
' "$CLEAN" "$CRITICAL_COUNT" "$REHUNT" "$HEAD_SHA" "$BRANCH" "$REVIEW_MODE" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$ROUND" "$IMPORTANT_COUNT" "$MINOR_COUNT" \
  "$PREV_CRITICAL" "$PREV_IMPORTANT" "$PREV_MINOR" \
  "$STALLED" "$FINDING_FILES_JSON" "$REGRESSED" "$FORCE_HUMAN" "$CONVERGENCE_STATE" \
  "$FILE_STREAKS_JSON" "$CHURN_FILES_JSON" "$STATE_FILE"
# ponytail: if a future edit drops "file_streaks" from this write, the next
# round's `prev_streaks` read (above) always sees {}, every streak resets to
# 1, and churn detection silently never fires again -- this field is
# load-bearing INPUT to the next round, not just output. Machine-checked by
# harness-audit check 56 (writer-side grep for the field name).

# The state file MUST land outside $WT so worktree cleanup can't delete it
# (production incident: PR #2619's state file was written to $WT/.scratch/
# and lost with the worktree, so the merge gate read "no review ran").
if [ -n "$WT" ]; then
  STATE_FILE_DIR=$(cd -- "$(dirname -- "$STATE_FILE")" && pwd -P)
  WT_REAL=$(cd -- "$WT" && pwd -P)
  case "$STATE_FILE_DIR" in
    "$WT_REAL"|"$WT_REAL"/*)
      err_die "state file $STATE_FILE resolves INSIDE $WT — it will be deleted by cleanup. Fix REVIEW_PR_STATE_DIR and re-run before proceeding."
      ;;
  esac
fi

test -s "$STATE_FILE" || err_die "state file $STATE_FILE is missing/empty after write"

echo "$STATE_FILE"
echo "round=$ROUND prev_critical=$PREV_CRITICAL prev_important=$PREV_IMPORTANT prev_minor=$PREV_MINOR stalled=$STALLED regressed=$REGRESSED force_human=$FORCE_HUMAN convergence_state=$CONVERGENCE_STATE churn_files=$CHURN_FILES"
