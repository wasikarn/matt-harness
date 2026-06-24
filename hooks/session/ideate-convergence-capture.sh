#!/bin/bash
# ideate-convergence-capture.sh — SessionEnd hook that detects convergence
# across /ideate (and legacy kbg:ideate) runs using local Ollama embeddings.
#
# Advisory only. Never blocks. Never mutates the repo. Appends one JSONL row
# per ideate run to ~/.claude/state/ideate-embeddings.jsonl.
#
# The heavy work — transcript parse, Ollama embedding, same-day similarity,
# and the JSONL append — runs in a `nohup` background child
# (scripts/ideate-convergence-capture.py) so this hook returns in <50ms and
# the Claude CLI never cancels it. fc27033 backgrounded the sibling
# memory-capture hook to close "Hook cancelled" on SessionEnd but only
# timeout-capped this one, so the cancellation recurred. Backgrounding finishes
# the job. Losing the record to an immediate power-off is acceptable for
# advisory convergence telemetry.
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

# No transcript = nothing to capture (normal for very short sessions).
[ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SCRIPT="${PLUGIN_ROOT}/scripts/ideate-convergence-capture.py"

# Fork the heavy work to a detached background child; return immediately so
# SessionEnd never gets cancelled by the CLI. Mirrors ideate-memory-capture.sh.
if [ -x "${SCRIPT}" ] || [ -f "${SCRIPT}" ]; then
  nohup python3 "$SCRIPT" \
    --transcript "$TRANSCRIPT" \
    --session-id "$SESSION_ID_VAL" \
    --embeddings-file "$EMB_FILE" \
    --ollama-timeout "${KBG_IDEATE_OLLAMA_TIMEOUT:-8}" \
    >/dev/null 2>&1 &
fi

exit 0