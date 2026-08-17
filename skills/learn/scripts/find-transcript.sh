#!/usr/bin/env bash
# find-transcript.sh — print the path and byte size of the current project's
# most recent Claude Code session transcript (.jsonl), for kbg:learn to mine.
#
# CC stores transcripts at ~/.claude/projects/<cwd-with-/-as->/<session>.jsonl
# (the project path with every "/" replaced by "-", NOT lowercased). Best-effort:
# prints "<path> <bytes>" on stdout, or a reason on stderr + exit 1 if none is
# found (the skill then falls back to the transcript path the SessionStart hook
# injects). The size is reported so the skill can decide whether to read the
# transcript whole or fall back to a bounded pre-filter — this repo's own
# transcripts range up to 83MB (2026-08-17 reducer-engineering audit); reading
# that whole into one mining pass is the same "cut what your model has to
# read" problem the audit found in this fleet's fan-out/synthesis steps.
set -uo pipefail

CWD="${1:-$PWD}"
SLUG="${CWD//\//-}"
DIR="$HOME/.claude/projects/$SLUG"

[ -d "$DIR" ] || { echo "find-transcript: no transcript dir for $CWD ($DIR)" >&2; exit 1; }
latest=$(ls -t "$DIR"/*.jsonl 2>/dev/null | head -1)
[ -n "$latest" ] || { echo "find-transcript: no .jsonl transcripts in $DIR" >&2; exit 1; }
size=$(wc -c < "$latest" | tr -d ' ')
printf '%s %s\n' "$latest" "$size"
