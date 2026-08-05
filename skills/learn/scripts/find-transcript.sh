#!/usr/bin/env bash
# find-transcript.sh — print the path of the current project's most recent
# Claude Code session transcript (.jsonl), for kbg:learn to mine.
#
# CC stores transcripts at ~/.claude/projects/<cwd-with-/-as->/<session>.jsonl
# (the project path with every "/" replaced by "-", NOT lowercased). Best-effort:
# prints the path on stdout, or a reason on stderr + exit 1 if none is found
# (the skill then falls back to the transcript path the SessionStart hook injects).
set -uo pipefail

CWD="${1:-$PWD}"
SLUG="${CWD//\//-}"
DIR="$HOME/.claude/projects/$SLUG"

[ -d "$DIR" ] || { echo "find-transcript: no transcript dir for $CWD ($DIR)" >&2; exit 1; }
latest=$(ls -t "$DIR"/*.jsonl 2>/dev/null | head -1)
[ -n "$latest" ] || { echo "find-transcript: no .jsonl transcripts in $DIR" >&2; exit 1; }
printf '%s\n' "$latest"
