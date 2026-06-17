#!/bin/bash
# ideate-convergence-capture.sh — SessionEnd hook that detects convergence
# across kbg:ideate runs using local sentence embeddings.
#
# Advisory only. Never blocks. Never mutates the repo. Appends one JSONL row
# per ideate run to ~/.claude/state/ideate-embeddings.jsonl.
#
# The hook reads the session transcript for ideate invocations, extracts the
# problem text and the rotated frames used, and stores a sentence-transformers
# embedding vector for the combined "problem + frames" fingerprint. This is a
# pragmatic proxy for full idea-text embeddings: if the same problem is run
# repeatedly with similar frames, the embedding is similar and we flag
# convergence risk.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=ideate-convergence-capture
#
# Failure mode: silent. Always exit 0.

HOOK_ID="ideate-convergence-capture"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

STATE_DIR="${HOME}/.claude/state"
EMB_FILE="${STATE_DIR}/ideate-embeddings.jsonl"
mkdir -p "$STATE_DIR" || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID_VAL" ] || SESSION_ID_VAL="no-sid"

[ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ] && exit 0

# Count ideate invocations in this session.
INVOCATIONS=$(jq -c '
  [
    .messages[]? |
    select(.type == "tool_use" and .tool_name == "Skill") |
    select(.input? .skill == "ideate")
  ] | length +
  [
    .messages[]? |
    select(.type == "user") |
    select(.content? | type == "string" and test("(^|[[:space:]])/ideate"; "i"))
  ] | length
' "$TRANSCRIPT" 2>/dev/null) || INVOCATIONS=0
[ -n "$INVOCATIONS" ] || INVOCATIONS=0
[ "$INVOCATIONS" -eq 0 ] 2>/dev/null && exit 0

# Extract the most recent user problem that triggered ideate. Heuristic: the
# first user message before the most recent ideate Skill call.
PROBLEM=$(jq -r '
  def last_user_before_ideate:
    [.messages[]? | select(.type == "tool_use" and .tool_name == "Skill" and .input? .skill == "ideate")]
    | last
    | .timestamp;
  last_user_before_ideate as $last_ideate_ts
  | [.messages[]?
      | select(.type == "user" and (.timestamp // "") <= ($last_ideate_ts // ""))
      | select(.content? | type == "string")
      | .content
    ]
  | last // ""
' "$TRANSCRIPT" 2>/dev/null)

# Clean the problem text to one line.
PROBLEM=$(printf '%s' "$PROBLEM" | tr '\n' ' ' | sed 's/  */ /g' | head -c 500)
[ -z "$PROBLEM" ] && PROBLEM="(no problem extracted)"

DATE=$(date -u +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Compute embedding via sentence-transformers. Fall back gracefully if library
# or model is not available.
EMBEDDING=""
CONVERGENCE_STATUS="unknown"
CONVERGENCE_REASON="sentence-transformers not available"
if command -v python3 >/dev/null 2>&1; then
  EMBEDDING=$(python3 - <<PY 2>/dev/null
import json, sys
problem = """$PROBLEM""".strip()
try:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('all-MiniLM-L6-v2')
    vec = model.encode(problem, convert_to_numpy=True, normalize_embeddings=True)
    print(json.dumps(vec.tolist()))
except Exception as e:
    sys.exit(1)
PY
)
fi

if [ -n "$EMBEDDING" ]; then
  CONVERGENCE_STATUS="ok"
  CONVERGENCE_REASON="embedding computed"

  # Compare against prior embeddings for the same calendar day.
  MAX_SIM=0.0
  if [ -s "$EMB_FILE" ]; then
    MAX_SIM=$(jq -s --arg today "$DATE" '
      def cosine(a; b):
        ([a, b] | transpose | map(.[0] * .[1]) | add) /
        (([a[] | . * .] | add | sqrt) * ([b[] | . * .] | add | sqrt));
      . as $all | $all
      | map(select(.date == $today and .embedding != null) | .embedding)
      | if length == 0 then [0]
        else . as $priors | $all[-1].embedding as $current
          | $priors | map(cosine($current; .)) | max
        end
    ' "$EMB_FILE" 2>/dev/null)
  fi

  # Default to 0 if jq returned empty/null.
  [ -z "$MAX_SIM" ] && MAX_SIM=0.0

  THRESHOLD="${KBG_IDEATE_CONVERGENCE_THRESHOLD:-0.85}"
  # Compare as float via python3.
  if python3 -c "import sys; sys.exit(0 if float('$MAX_SIM') >= float('$THRESHOLD') else 1)" 2>/dev/null; then
    CONVERGENCE_STATUS="warning"
    CONVERGENCE_REASON="max same-day cosine similarity $MAX_SIM >= threshold $THRESHOLD — ideate runs may be converging"
  fi
fi

# Append record.
jq -nc \
  --arg date "$DATE" \
  --arg session_id "$SESSION_ID_VAL" \
  --arg ts "$TIMESTAMP" \
  --arg problem "$PROBLEM" \
  --argjson invocations "$INVOCATIONS" \
  --argjson embedding "${EMBEDDING:-null}" \
  --arg status "$CONVERGENCE_STATUS" \
  --arg reason "$CONVERGENCE_REASON" \
  '{
    date: $date,
    session_id: $session_id,
    ts: $ts,
    problem: $problem,
    invocations: $invocations,
    embedding: $embedding,
    convergence_status: $status,
    convergence_reason: $reason
  }' >> "$EMB_FILE" 2>/dev/null || {
    echo "[$HOOK_ID] ERROR: failed to append convergence record to $EMB_FILE" >&2
}

exit 0
