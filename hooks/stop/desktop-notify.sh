#!/usr/bin/env bash
# Stop: send macOS desktop notification with first line of last assistant response
set -uo pipefail

payload=$(cat)

msg=$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""' 2>/dev/null |
  /usr/bin/grep -v '^[[:space:]]*$' | head -1 | cut -c1-100)

if [[ -n "$msg" && "$(uname)" == "Darwin" ]]; then
  # Strip chars that break AppleScript string embedding
  safe=$(printf '%s' "$msg" | LC_ALL=C tr -cd '[:print:]' | tr -d '"\\`$!')
  osascript -e "display notification \"${safe}\" with title \"Claude Code\"" 2>/dev/null || true
fi

printf '%s' "$payload"
exit 0
