#!/usr/bin/env bash
# Gate: a subagent (agent_id in the PreToolUse payload) may not run a bare
# `git stash|reset|clean` -- repo-wide mutation races peers on a shared tree
# (issue #135). Main session (no agent_id) is untouched; `claude --agent` main
# sessions also lack agent_id, so agent_type is NOT the discriminant.
# irrecoverable.sh already denies the destructive forms (reset --hard, clean -f,
# checkout --, restore <path>) for every session; this gate only adds the three
# non-force verbs, for subagents. Coarse pattern match, not a sandbox: quote-
# splitting or substitution of the word "git" itself is a non-goal, and a
# heredoc BODY line starting with "git stash" over-blocks (no heredoc parsing).
#
# No bash-level fast path on the agent_id key (2026-09-20 audit, same GH #154
# gap already fixed in subagent-spawn-guard.sh): a raw-text substring check
# ran before any JSON parsing and could be bypassed by writing that key with
# a JSON unicode escape instead of a literal underscore -- valid JSON, same
# decoded key, but absent from the raw text the substring check saw --
# live-confirmed. Every payload now always reaches python3, matching the
# sibling gates' convention.
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — subagent-git-guard gate cannot run; allowing (install python3 to restore the subagent git-guard rule)" >&2
  exit 0
fi

_input=$(cat)

_py="$(dirname "$0")/subagent-git-guard.py"
if [ ! -r "$_py" ]; then
  echo "[mh:gate] internal error: sibling script subagent-git-guard.py missing or unreadable — allowing (fail-safe = allow, same posture as this gate's own parse-error path)" >&2
  exit 0
fi

printf '%s' "$_input" | python3 "$_py"
exit $?
