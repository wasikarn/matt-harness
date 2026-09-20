#!/usr/bin/env bash
# 74. Subagent-scoped gate agent_id presence-check invariant (harness gap-audit,
# 2026-09-20). Four gates key their entire subagent-only behavior on whether
# `agent_id` is PRESENT in the PreToolUse payload, never on whether it's
# truthy -- an empty-string or JSON-null agent_id is still a real subagent
# call and must still be gated. A truthiness check (`d.get("agent_id")` or a
# bare `if agent_id:`) silently skips the check for exactly that shape,
# reproduced live as a real bypass in irrecoverable.py (both
# `_nested_spawn` call sites) and subagent-git-guard.py before the 2026-09-20
# fix pass -- see docs/reference/operating-model.md's "three [now four]
# subagent-scoped gates, one posture" invariant. This makes that invariant
# mechanical instead of relying on remembering to check it by hand on every
# future edit to any of these four files.
#
# CRIT: any of the four files is missing the presence-check idiom
# (`"agent_id" in d` / `"agent_id" not in d`) entirely -- either the file was
# never fixed, or a future edit regressed it back to a truthiness gate
# without leaving the presence-check string anywhere in the file.
_AGENT_ID_GATE_FILES="irrecoverable.py subagent-git-guard.py subagent-spawn-guard.py task-complete-separation.py"
for _f in $_AGENT_ID_GATE_FILES; do
  _path="$CLAUDE_DIR/hooks/gates/$_f"
  if [ ! -f "$_path" ]; then
    crit "hooks/gates/$_f missing -- can't verify its agent_id presence-check invariant"
    continue
  fi
  # Comments stripped first (same convention as hook_wired_transitively above
  # in audit.sh) so a prose mention of the idiom in a docstring/comment can't
  # substitute for the real code check. grep WITHOUT -q, redirected instead:
  # under this script's `set -o pipefail`, grep -q's early-exit-on-first-match
  # can SIGPIPE the still-writing sed upstream of it, and pipefail then
  # reports that SIGPIPE (141) as the pipeline's status instead of grep's own
  # 0 -- a real match gets misreported as "not found" (live-reproduced while
  # writing this check against irrecoverable.py's own file).
  if ! sed 's/#.*$//' "$_path" 2>/dev/null | /usr/bin/grep -E '"agent_id"[[:space:]]+(not[[:space:]]+)?in[[:space:]]+d\b' >/dev/null 2>&1; then
    crit "hooks/gates/$_f has no \"agent_id\" (not )in d presence-check -- may have regressed to a truthiness gate that skips an empty-string/null agent_id (see docs/reference/operating-model.md)"
  fi
done
unset _f _path _AGENT_ID_GATE_FILES
