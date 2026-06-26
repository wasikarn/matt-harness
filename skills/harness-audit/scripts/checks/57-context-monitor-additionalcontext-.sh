# 57. context-monitor additionalContext contract + advisory-only (ADR 0007) —
# PostToolUse scope/loop advisory. Advisory injection MUST travel as
# `hookSpecificOutput.additionalContext` with hookEventName PostToolUse; a
# top-level `{"additionalContext":...}` is SILENTLY IGNORED (verified contract
# #2 — the same field the hypothesis-gate sibling bug used). Second leg: this
# hook is OBSERVE-ONLY by design — it must never emit a `permissionDecision`,
# or it silently turns an advisory into a block. CRIT on the contract field
# (silent no-op = the nudge never reaches the model); CRIT on advisory-only (a
# PostToolUse hook emitting permissionDecision is a category error that can
# block after the edit already landed).
_F=$(find "$CLAUDE_DIR/hooks" -type f -name "context-monitor.sh" 2>/dev/null | head -1)
if [ -f "$_F" ]; then
  /usr/bin/grep -qE 'hookSpecificOutput.*additionalContext' "$_F" 2>/dev/null \
    || crit "context-monitor.sh: advisory does not use hookSpecificOutput.additionalContext — a top-level additionalContext is silently ignored (ADR 0007 contract #2)"
  /usr/bin/grep -qE 'hookEventName.*PostToolUse' "$_F" 2>/dev/null \
    || crit "context-monitor.sh: additionalContext missing hookEventName:\"PostToolUse\" — advisory is dropped (ADR 0007 contract #2)"
  # advisory-only: a PostToolUse hook emitting permissionDecision is a category
  # error (it would block AFTER the edit landed). Use an if-guard, NOT `&& crit`,
  # so the clean case (permissionDecision absent → grep exits 1) doesn't trip
  # `set -e` and kill the whole audit before the summary prints.
  if /usr/bin/grep -qE 'permissionDecision' "$_F" 2>/dev/null; then
    crit "context-monitor.sh: emits permissionDecision — a PostToolUse advisory must be observe-only (ADR 0007); a deny here is a category error"
  fi
fi