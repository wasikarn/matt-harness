#!/usr/bin/env bash
# Resolves the repo's actual default branch — never assume main/develop, a
# silent wrong default misroutes a PR exactly as effectively as a
# persuasive wrong guess does (same principle as this skill's hotfix-base
# guard). Extracted 2026-08-15: skills/pr/SKILL.md documented this full
# fallback chain, but the then-extant skills/review-pr/SKILL.md only ever
# inlined the first 2 lines of it — a correctness fix to one path never
# reached the other. Callers use this instead of re-describing/partially-implementing
# it.
#
# Stdout contract:
#   Resolved cleanly            -> the branch name, one line, exit 0.
#   Irreducibly ambiguous       -> "AMBIGUOUS: <reason>" on stdout, exit 1.
#                                   The caller (a skill's own flow) must turn
#                                   this into an actual AskUserQuestion —
#                                   this script cannot ask one itself.
#   No usable candidate at all  -> "UNRESOLVED" on stdout, exit 2.
set -uo pipefail

CANDIDATE=$(gh repo view --json defaultBranchRef -q .defaultBranchRefName 2>/dev/null)
if [ -z "$CANDIDATE" ] || [ "$CANDIDATE" = "null" ]; then
  CANDIDATE=$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')
fi

# Validate the result actually exists — a stale/dangling remote HEAD symref
# (fresh-mirrored or partially-configured remote) can return a name that
# isn't real; don't trust either signal blind.
branch_exists() {
  git show-ref --verify --quiet "refs/remotes/origin/$1" 2>/dev/null \
    || git show-ref --verify --quiet "refs/heads/$1" 2>/dev/null
}

if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "(unknown)" ] && branch_exists "$CANDIDATE"; then
  echo "$CANDIDATE"
  exit 0
fi

# Both signals failed or pointed at something that doesn't exist. Don't
# guess: list what actually exists and disambiguate via git merge-base —
# the candidate with the fewest commits between its merge-base and HEAD is
# the nearest, most likely real base (a distant ancestor like main sits
# further back than the branch actually forked from, e.g. develop).
CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
BEST=""
BEST_DIST=""
TIE=0

while IFS= read -r b; do
  b="${b#origin/}"
  [ "$b" = "HEAD" ] && continue
  [ "$b" = "$CURRENT" ] && continue
  MB=$(git merge-base HEAD "$b" 2>/dev/null) || continue
  DIST=$(git rev-list --count "$MB..HEAD" 2>/dev/null) || continue
  if [ -z "$BEST_DIST" ] || [ "$DIST" -lt "$BEST_DIST" ]; then
    BEST="$b"
    BEST_DIST="$DIST"
    TIE=0
  elif [ "$DIST" -eq "$BEST_DIST" ] && [ "$b" != "$BEST" ]; then
    TIE=1
  fi
done < <(git branch -a --format='%(refname:short)' 2>/dev/null | sort -u)

if [ -z "$BEST" ]; then
  echo "UNRESOLVED"
  exit 2
fi

if [ "$TIE" -eq 1 ]; then
  echo "AMBIGUOUS: more than one branch shares the closest merge-base distance to HEAD -- ask the user which one is the real base rather than picking one silently."
  exit 1
fi

echo "$BEST"
exit 0
