# 56. dev-tmux-transform updatedInput contract (ADR 0007) — rewrites a dev-server
# Bash command into a detached tmux session. Tool-input mutation MUST travel as
# `hookSpecificOutput.updatedInput` (hookEventName PreToolUse); printing a modified
# top-level `{"tool_input":{...}}` or `{"command":...}` + exit 0 is SILENTLY
# IGNORED and the ORIGINAL command runs — the agent blocks on a foreground dev
# server believing it was detouched. This is the EXACT bug ECC's auto-tmux-dev.js
# shipped (ADR 0007 contract #1); the bash port was built to the correct field.
# This check is the regression guard against a future re-widening to top-level
# mutation. CRIT: the failure mode is the agent hanging on a foreground process.
# Comments are stripped before grepping — the file's own header documents the
# contract (`hookSpecificOutput.updatedInput`) and would otherwise mask a code
# regression (verified: a comment-only mention must NOT satisfy the check).
_F=$(find "$CLAUDE_DIR/hooks" -type f -name "dev-tmux-transform.sh" 2>/dev/null | head -1)
if [ -f "$_F" ]; then
  sed '/^[[:space:]]*#/d' "$_F" 2>/dev/null | /usr/bin/grep -qE 'hookSpecificOutput.*updatedInput' \
    || crit "dev-tmux-transform.sh: rewrite does not use hookSpecificOutput.updatedInput — a top-level command mutation is silently ignored (ADR 0007 contract #1); the agent blocks on a foreground dev server"
fi