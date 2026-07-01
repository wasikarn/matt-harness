#!/usr/bin/env bash
# shellcheck disable=SC2016  # python code in single quotes
# Advisory: nudge /grilling → /to-prd → /to-issues → /ship when the
# user's prompt looks like non-trivial engineering work. UserPromptSubmit
# hook. Output → stdout (CC surfaces as a system-reminder); never blocks,
# always exits 0. Errors are silently swallowed.
#
# Heuristic: a flow verb implies non-trivial work regardless of length.
#   - Empty prompt → silent.
#   - No flow verb → silent.
#   - Flow verb matched → emit nudge.
# Verified against the test in hooks/tests/test-flow-nudge.sh.
set -uo pipefail

prompt=$(python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
print(d.get("tool_input", {}).get("prompt", ""))
' 2>/dev/null || echo "")

[[ -z "$prompt" ]] && exit 0

# Keyword match on matt-flow verbs + kbg surface-creation verbs.
# Whole-word boundaries; case-insensitive; extended regex (BSD grep -E).
if ! printf '%s' "$prompt" | /usr/bin/grep -qiE '\b(implement|build a feature|refactor|redesign|migrate|architect|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|ship)\b'; then
  exit 0
fi

cat <<'EOF'

[kbg:flow-nudge] Non-trivial work detected — consider matt's flow:
  /grilling → /to-prd → /to-issues → /ship
Skip the nudge if the work shape is already known (typo-fix / doc-tweak /
direct skill invocation). The nudge is advisory; the model judges.
EOF

exit 0