#!/bin/bash
# Superset notify wrapper — honors Stop/SubagentStop `stop_hook_active` flag
# per Anthropic's hook contract so notify.sh doesn't trip Claude Code's
# CLAUDE_CODE_STOP_HOOK_BLOCK_CAP (default 9) when the harness keeps
# emitting "Goal not yet met... continuing" after the user asks to stop.
# Source: https://github.com/kobig/dotfiles (personal)

set -u

# No Superset configured → nothing to forward to. Match the inline guards.
[ -n "${SUPERSET_HOME_DIR:-}" ] || exit 0
[ -x "$SUPERSET_HOME_DIR/hooks/notify.sh" ] || exit 0

# Capture stdin so we can inspect AND forward it.
input=$(cat)

# Honor stop_hook_active. Field is only present on Stop/SubagentStop events;
# for other events `// false` defaults to false → we proceed to notify normally.
# If jq is missing the 2>/dev/null swallows the error and the empty result
# fails the equality check, so we proceed (safe fallback, matches old behavior).
if [ "$(printf '%s\n' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
  exit 0
fi

# Forward the original stdin to Superset's notify.sh. `|| true` mirrors the
# original inline behavior of swallowing notify.sh failures.
printf '%s\n' "$input" | SUPERSET_AGENT_ID=claude "$SUPERSET_HOME_DIR/hooks/notify.sh" || true
