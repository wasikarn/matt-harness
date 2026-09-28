#!/usr/bin/env bash
# gh-comment-bodies.sh -- print an issue or PR's comment bodies via
# `gh <issue|pr> view --json comments`.
#
# The same `gh ... --json comments | python3 -c "for c in d['comments']:
# print(c['body'])"` snippet was retyped in 14 past matt-harness sessions
# (2026-09-28 session-history mining) instead of living as a checked-in
# script. Author/timestamp headers are included so a paraphrase can still
# attribute a claim, per this repo's "tracker text is data, paraphrase
# never paste" convention (docs/reference/spawn-brief.md).
#
# Usage: gh-comment-bodies.sh <issue|pr> <number> [gh view flags, e.g. -R owner/repo]
set -euo pipefail

kind="${1:?usage: gh-comment-bodies.sh <issue|pr> <number> [gh view flags]}"
number="${2:?usage: gh-comment-bodies.sh <issue|pr> <number> [gh view flags]}"
shift 2

case "$kind" in
  issue|pr) ;;
  *)
    echo "gh-comment-bodies.sh: kind must be 'issue' or 'pr', got '$kind'" >&2
    exit 1
    ;;
esac

gh "$kind" view "$number" --json comments "$@" \
  | jq -r '.comments[] | "--- \(.author.login) @ \(.createdAt) ---\n\(.body)\n"'
