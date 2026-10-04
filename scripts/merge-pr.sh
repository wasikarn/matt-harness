#!/usr/bin/env bash
# merge-pr.sh <PR> — merge a PR only if its head contains the origin/develop tip
# (GH #450). The pre-push gauntlet then ran on the exact tree that merges, so two
# PRs green alone cannot land red together (#445 + #446). --match-head-commit
# pins the merge to the checked sha: a push after the check makes GitHub refuse.
# Checks are local-only; this narrows the race, it does not close it.
# Bash 3.2. Env: MERGE_PR_LOAD_MAX (default 4), MERGE_PR_LOAD_WAIT_SECS (900).
set -euo pipefail

pr="${1:-}"
if [ -z "$pr" ]; then
  echo "usage: merge-pr.sh <PR number>" >&2
  exit 2
fi

git fetch origin

info=$(gh pr view "$pr" --json headRefOid,baseRefName -q '.headRefOid + " " + .baseRefName')
head=${info% *}
base=${info#* }
if [ -z "$head" ] || [ "$head" = "$info" ]; then
  echo "merge-pr: could not read the head sha and base branch of PR $pr" >&2
  exit 1
fi
if [ "$base" != "develop" ]; then
  echo "merge-pr: PR $pr targets '$base', not develop; the origin/develop check would prove nothing." >&2
  exit 1
fi

rc=0
git merge-base --is-ancestor origin/develop "$head" || rc=$?
if [ "$rc" -eq 1 ]; then
  echo "merge-pr: PR $pr head $head does not contain origin/develop." >&2
  echo "Rebase on origin/develop and push; the pre-push gauntlet then runs on the exact tree that will merge." >&2
  exit 1
elif [ "$rc" -ne 0 ]; then
  echo "merge-pr: ancestry check failed (rc=$rc); is $head fetched locally?" >&2
  exit 1
fi

load_max="${MERGE_PR_LOAD_MAX:-4}"
wait_secs="${MERGE_PR_LOAD_WAIT_SECS:-900}"
waited=0
while :; do
  load=$(uptime | sed 's/.*load average[s]*: *//' | awk -F'[ ,]+' '{print $1}')
  if awk -v l="$load" -v m="$load_max" 'BEGIN { exit !(l + 0 < m + 0) }'; then
    break
  fi
  if [ "$waited" -ge "$wait_secs" ]; then
    echo "merge-pr: load $load is still >= $load_max after ${waited}s; not merging." >&2
    exit 1
  fi
  sleep 30
  waited=$((waited + 30))
done

gh pr merge "$pr" --merge --match-head-commit "$head"
gh pr view "$pr" --json mergeCommit -q .mergeCommit.oid
