#!/bin/bash
# Pre-write secret scan — block Edit/Write/MultiEdit content containing
# high-confidence secret patterns (specific token formats only — generic
# KEY=value patterns are too noisy).
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=secret-scan
#
# Behavior (canonical per Claude Code hooks spec):
#   match found → exit 0 with hookSpecificOutput JSON: permissionDecision="deny" + reason
#   no match    → exit 0 silently
#   non-target tool or empty content → exit 0 (pass-through)
#   jq missing or input parse error → exit 1 (fail loud, Rule 12 — a blocker
#     that can't read input should not silently pass)

set -uo pipefail

HOOK_ID="secret-scan"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


# jq is mandatory for the content extraction below; if missing, fail loud.
if ! command -v jq >/dev/null 2>&1; then
  echo "[$HOOK_ID] ERROR: jq not found — cannot parse hook input" >&2
  exit 1
fi

case "$TOOL" in
  Write)
    CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.content // empty') || {
      echo "[$HOOK_ID] ERROR: failed to parse Write content" >&2
      exit 1
    }
    ;;
  Edit)
    CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.new_string // empty') || {
      echo "[$HOOK_ID] ERROR: failed to parse Edit new_string" >&2
      exit 1
    }
    ;;
  MultiEdit)
    CONTENT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '[.edits[]?.new_string] | join("\n")') || {
      echo "[$HOOK_ID] ERROR: failed to parse MultiEdit edits" >&2
      exit 1
    }
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$CONTENT" ] && exit 0

# Use command grep to bypass any wrappers
_GREP="command grep"

# High-confidence secret patterns. Each pattern label + regex:
#   AWS         AKIA + 16 uppercase alphanumeric
#   Anthropic   sk-ant-(api|sid|admin) + 40+ token chars
#   OpenAI      sk-(proj-)? + 40+ token chars
#   GitHub      ghp_/gho_/ghs_/github_pat_ + token chars
#   Slack       xox[bpoars]- + numeric/numeric/token
#   Stripe live (sk|pk|rk)_live_ + 24+ alnum
#   Google API  AIza + 35 token chars
#   Private key marker line
LABELS=(
  "AWS"
  "Anthropic"
  "OpenAI"
  "GitHub-PAT-classic"
  "GitHub-OAuth"
  "GitHub-App"
  "GitHub-PAT-fine"
  "GitLab-PAT"
  "HuggingFace"
  "Slack"
  "Stripe-live"
  "Google-API"
  "Private-key"
)
PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  'sk-ant-[a-zA-Z0-9_-]{20,}'
  'sk-(proj-)?[0-9a-zA-Z]{48}'
  'ghp_[0-9a-zA-Z]{36}'
  'gho_[0-9a-zA-Z]{36}'
  'ghs_[0-9a-zA-Z]{36}'
  'github_pat_[0-9a-zA-Z_]{82}'
  'glpat-[0-9A-Za-z_-]{20,}'
  'hf_[0-9a-zA-Z]{34,}'
  'xox[bpoars]-[0-9]+-[0-9]+-[0-9a-zA-Z]+'
  '(sk|pk|rk)_live_[0-9a-zA-Z]{24,}'
  'AIza[0-9A-Za-z_-]{35}'
  '-----BEGIN [A-Z ]*PRIVATE KEY[- ]'
)

for i in "${!PATTERNS[@]}"; do
  pat="${PATTERNS[$i]}"
  label="${LABELS[$i]}"
  if printf '%s\n' "$CONTENT" | $_GREP -qE -e "$pat"; then
    matched=$(printf '%s\n' "$CONTENT" | $_GREP -oE -e "$pat" | head -1)
    # Truncate displayed match to first 20 chars to avoid logging full secret
    preview=$(printf '%s\n' "$matched" | cut -c1-20)
    hook_decision deny "${label} token detected in ${TOOL}: '${preview}...'. Use env var or secret manager. Bypass: CLAUDE_DISABLED_HOOKS=secret-scan"
  fi
done

exit 0
