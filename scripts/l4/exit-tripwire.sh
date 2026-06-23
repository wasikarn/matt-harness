#!/usr/bin/env bash
# exit-tripwire.sh — ADR 0004 exit-trigger-2 detector (design §10, #32).
#
# A cheap POST-PUSH tripwire that CRITs if any cross-repo SECURITY GATE's content
# changed in an L4-authored commit. Lives OUTSIDE the cage's own assertion path —
# the cage cannot be its own witness (ADR 0004's second exit trigger can only fire
# AFTER the cage already failed silently, so this detector is independent of
# audit #43-#49, which the cage itself gates).
#
# An L4-authored commit carries the `L4-authored: yes` git trailer (the recursive-
# improve --auto cycle adds it to every commit). A security gate = any caged safety
# surface (the gates, the cage, the guard, the audit, the gauntlet, the manifests,
# the git hooks, scripts/l4/**). An L4-authored commit touching one is the
# exit-trigger-2 condition: the loop edited its own safety surface, which the cage
# should have prevented — a silent cage failure this tripwire catches post-push.
#
# Usage: exit-tripwire.sh [<commit-range>]   # default: HEAD~1..HEAD (the last commit)
# Exit: 0 (clean) | 1 (CRIT — a security gate changed in an L4-authored commit)
set -uo pipefail

RANGE="${1:-HEAD~1..HEAD}"
# Security-gate paths (the caged safety surface — mirrors cage.txt's load-bearing
# entries). A change to any of these in an L4-authored commit is the tripwire condition.
SEC_PATS=(
  'hooks/gates/' 'hooks/_lib\.sh' 'hooks/hooks\.json' 'scripts/cage\.txt'
  'scripts/loop-guard\.py' 'skills/harness-audit/scripts/audit\.sh'
  'scripts/run-gauntlet\.sh' 'scripts/l4/' 'git-hooks/'
  '\.claude-plugin/plugin\.json' '\.claude-plugin/marketplace\.json'
)

_l4commits=$(git log --pretty='%H' --grep='L4-authored: yes' "$RANGE" 2>/dev/null || true)
if [ -z "$_l4commits" ]; then
  echo "exit-tripwire: no L4-authored commits in $RANGE — clean"
  exit 0
fi

_rc=0
while IFS= read -r _h; do
  [ -n "$_h" ] || continue
  _files=$(git diff-tree --no-commit-id --name-only -r "$_h" 2>/dev/null || true)
  for _pat in "${SEC_PATS[@]}"; do
    if printf '%s\n' "$_files" | grep -qE "^${_pat}"; then
      _hit=$(printf '%s\n' "$_files" | grep -E "^${_pat}" | tr '\n' ' ')
      echo "exit-tripwire: CRIT — L4-authored commit ${_h:0:8} touched security gate '$_pat' (files: $_hit) — ADR 0004 exit-trigger-2: a safety surface changed under an armed run; the cage should have prevented it" >&2
      _rc=1
    fi
  done
done <<<"$_l4commits"

[ "$_rc" -eq 0 ] && echo "exit-tripwire: L4-authored commits in $RANGE touched no security gate — clean"
exit $_rc