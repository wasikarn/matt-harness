#!/bin/bash
# ideate-rotate.sh — SessionStart hook for kbg:ideate frame rotation + budget warning.
#
# Two jobs:
#   1. Frame rotation: maintain a deterministic round-robin of 5-frame sets so
#      repeated ideate runs on similar problems do not converge to the same
#      vantages. Writes state to ~/.claude/state/ideate-rotation.json.
#   2. Budget warning: count ideate invocations in today's captured sessions
#      and print a soft warning if the daily threshold is exceeded. This is
#      advisory only — no enforcement, no permissionDecision (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model).
#
# The hook emits a SessionStart additionalContext JSON envelope. The markdown
# payload carries <ideate-rotation> and <ideate-budget> blocks; Claude Code
# injects it as additionalContext. The skill body in skills/ideate/SKILL.md
# reads these tags and prefers the rotated frames when present, falling back
# to the deterministic picker if absent.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=ideate-rotate
#
# Failure mode: silent. Always exit 0; never block SessionStart.

HOOK_ID="ideate-rotate"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

FRAME_IDS=(
  hardware-eyes
  regulator
  ten-year-old
  adversary
  biology
  logistics
  game-design
  markets
  inversion
  extreme-zero
  extreme-infinite
  remove-assumption
  speedrunner
  ant-colony
  ops-3am
)

FRAMES_PER_RUN=5
STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${STATE_DIR}/ideate-rotation.json"
USAGE_FILE="${STATE_DIR}/ideate-usage.jsonl"
DAILY_THRESHOLD="${KBG_IDEATE_DAILY_THRESHOLD:-10}"

mkdir -p "$STATE_DIR"

# ---- Frame rotation ----

# Build a deterministic permutation of all 15 frames seeded by a stable but
# slowly-advancing counter. We rotate the seed by the session index so the
# same problem in different sessions gets different vantages.
rotate_frames() {
  local seed="$1"
  # Knuth-style multiplicative hash to scatter indices without relying on shuf
  local h=$(( (seed * 2654435761) % 2147483647 ))
  local idx
  local picked=()
  local used=()
  for ((i = 0; i < ${#FRAME_IDS[@]}; i++)); do used[i]=0; done

  for ((i = 0; i < FRAMES_PER_RUN; i++)); do
    idx=$(( (h + i * 97) % ${#FRAME_IDS[@]} ))
    while [ "${used[$idx]}" -eq 1 ]; do
      idx=$(( (idx + 1) % ${#FRAME_IDS[@]} ))
    done
    used[idx]=1
    picked+=("${FRAME_IDS[$idx]}")
  done

  # Ensure at least one wild-tagged frame in every set.
  # Wild frames: biology, markets, extreme-infinite, remove-assumption,
  # speedrunner, ant-colony, hardware-eyes.
  local wild=(biology markets extreme-infinite remove-assumption speedrunner ant-colony hardware-eyes)
  local has_wild=0
  for p in "${picked[@]}"; do
    for w in "${wild[@]}"; do
      if [ "$p" = "$w" ]; then has_wild=1; break 2; fi
    done
  done
  if [ "$has_wild" -eq 0 ]; then
    # Replace the last picked frame with a deterministic wild frame.
    local wild_idx=$(( h % ${#wild[@]} ))
    picked[-1]="${wild[$wild_idx]}"
  fi

  printf '%s\n' "${picked[@]}"
}

# Read or initialize state.
if [ -s "$STATE_FILE" ]; then
  STATE=$(cat "$STATE_FILE" 2>/dev/null) || STATE=''
  INDEX=$(printf '%s' "$STATE" | jq -r '.index // 0' 2>/dev/null) || INDEX=0
  [ -z "$INDEX" ] && INDEX=0
else
  INDEX=0
fi

PICKED=$(rotate_frames "$INDEX")
INDEX=$((INDEX + 1))

printf '{"index": %d, "generated_at": "%s"}\n' "$INDEX" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE" || true

# ---- Budget warning ----

TODAY=$(date -u +%Y-%m-%d)
TODAY_COUNT=0
if [ -s "$USAGE_FILE" ]; then
  TODAY_COUNT=$(jq -s --arg today "$TODAY" '
    [ .[] | select(.date == $today) | .invocations ] | add // 0
  ' "$USAGE_FILE" 2>/dev/null) || TODAY_COUNT=0
fi

BUDGET_STATUS="ok"
BUDGET_MESSAGE=""
if [ "$TODAY_COUNT" -ge "$DAILY_THRESHOLD" ]; then
  BUDGET_STATUS="warning"
  BUDGET_MESSAGE="Today's ideate invocations: $TODAY_COUNT (threshold: $DAILY_THRESHOLD). Consider whether the next open-ended prompt really needs divergent ideation."
fi

# ---- Output ----
# Build a markdown payload that the skill body can detect via substring.

ROTATION_MARKDOWN=$(cat <<EOF
# /ideate session advisory

If you are about to run \`/ideate\` in this session, prefer this frame
rotation unless the user explicitly asks for different frames:

<ideate-rotation index="$INDEX">
$(printf '%s\n' "$PICKED" | sed 's/^/- /')
</ideate-rotation>

These frames already satisfy the 1-wild minimum. If this block is absent,
use the deterministic picker in the command body instead.

<ideate-budget status="$BUDGET_STATUS" today="$TODAY_COUNT" threshold="$DAILY_THRESHOLD">
${BUDGET_MESSAGE:+$BUDGET_MESSAGE}
</ideate-budget>

If the budget block shows \`status="warning"\`, do not auto-fire \`/ideate\`
from the pre-flight gate unless the user explicitly invoked \`/ideate\`; if they
did, surface the warning in the brief.
EOF
)

CTX=$(printf '%s' "$ROTATION_MARKDOWN" | jq -cRs . 2>/dev/null) || CTX=''
if [ -n "$CTX" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CTX"
fi

exit 0
