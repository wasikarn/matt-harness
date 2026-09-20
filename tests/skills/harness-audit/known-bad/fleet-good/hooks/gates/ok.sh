#!/usr/bin/env bash
# wired by hooks.json; uses the real plugin-root variable
echo "${CLAUDE_PLUGIN_ROOT:-}"
# check-74 fixture siblings (not real hooks, never invoked) -- named here so
# check 11's orphan-hook scan treats them as transitively wired, same as the
# real irrecoverable.sh -> irrecoverable.py sibling-script pattern.
_py1="$(dirname "$0")/irrecoverable.py"
_py2="$(dirname "$0")/subagent-git-guard.py"
_py3="$(dirname "$0")/subagent-spawn-guard.py"
_py4="$(dirname "$0")/task-complete-separation.py"
