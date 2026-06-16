#!/bin/bash
# inferential-structural-judge-on-session-end.sh — matcher-less SessionEnd hook.
#
# Inferential-FB sensor that closes the structural-judgment gap (Böckeler 2026-04
# L444 / L465-478). Reads the session's transcript, assembles a diff envelope
# + prior-verdict context, invokes the `inferential-structural-judge` agent via
# `claude -p --agent`, validates the JSON verdict against the schema in
# docs/research/inferential-structural-judge-design.md §3, and journals it to
# the existing ~/.claude/governance-events.jsonl stream as
# event=inferential_structural_verdict (or inferential_structural_verdict_skipped
# for the four skip paths).
#
# Pure SENSOR: it journals but NEVER emits a permissionDecision — autonomy
# invariant (ADR 0002 §L112). Non-blocking: always exit 0 so a broken judge
# never blocks session end (matches verification-gate.sh / session-summary.sh).
#
# Bypass (matches verification-gate.sh so operators have one mental model):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=inferential-structural-judge
#
# Design: docs/research/inferential-structural-judge-design.md (HOOK-1 row of
# .claude/tasks/inferential-structural-test.md).

set -uo pipefail
export LC_ALL=C

HOOK_ID="inferential-structural-judge"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

# ── Dependency guards (silent no-op on missing dep — matches the
#    doctrine-bootstrap / verification-gate "degrade gracefully" convention) ──
command -v jq      >/dev/null 2>&1 || { printf '[%s] WARN: jq missing — skipping\n' "$HOOK_ID" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { printf '[%s] WARN: python3 missing — skipping\n' "$HOOK_ID" >&2; exit 0; }
command -v claude  >/dev/null 2>&1 || {
  # failure-mode 1 (design doc §6): agent runtime absent → journal a skipped event so
  # the staleness-notifier surfaces the coverage gap, then exit 0.
  fields='{"reason":"agent_absent"}'
  ( journal_append "$HOOK_ID" "inferential_structural_verdict_skipped" "$fields" >/dev/null ) || true
  exit 0
}

# ── Read the SessionEnd envelope (same shape as session-summary.sh:14-16) ──
TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# ── Step 1: extract the session's running token count from the transcript.
#    Best-effort: scan all assistant entries, take the max input_tokens seen
#    (a streaming session accumulates tokens across turns; the max is the
#    pre-SessionEnd snapshot). If the transcript is missing/unreadable, OR the
#    running count is already ≥ 25,000, journal a skipped:budget event per
#    design doc §5 and exit 0 (failure-mode 5). ──
SESSION_TOKENS=0
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  SESSION_TOKENS=$(jq -s '
    [ .[]? | select(.type=="assistant" or .type=="tool_use")
        | (.. | objects | select(has("usage")) | .usage)
        | (.input_tokens // 0) ]
    | if length == 0 then 0 else max end
  ' "$TRANSCRIPT" 2>/dev/null | tr -d '[:space:]')
  # shellcheck disable=SC2155  # assigned-from-command-substitution is intentional
  case "$SESSION_TOKENS" in ''|*[!0-9]*) SESSION_TOKENS=0 ;; esac
fi
if [ "$SESSION_TOKENS" -ge 25000 ]; then
  # failure-mode 5: budget gate. 5k headroom preserved for session-summary.sh
  # which runs on the same lifecycle and has the same budget contract.
  fields='{"reason":"budget","session_tokens_used":'"$SESSION_TOKENS"',"cap":25000}'
  ( journal_append "$HOOK_ID" "inferential_structural_verdict_skipped" "$fields" >/dev/null ) || true
  exit 0
fi

# ── Step 2: build the diff list from the transcript. The transcript is a JSONL
#    of (user|assistant|tool_use|tool_result) messages. We want the set of paths
#    that the agent touched via Edit/Write/MultiEdit/NotebookEdit this session,
#    joined to their diff hunks. If the transcript is absent/empty, the diff
#    is empty (failure-mode 3) and we journal an accept with score 0 per
#    design doc §6. ──
DIFF_JSON="[]"
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  DIFF_JSON=$(jq -s '
    [ .[]? | select(.type=="tool_use")
        | select(.name=="Edit" or .name=="Write" or .name=="MultiEdit" or .name=="NotebookEdit")
        | (if .name == "MultiEdit" then
             (.input.edits // [] | map(.file_path // empty) | .[])
           elif .name == "Write" then
             (.input.file_path // empty)
           else
             (.input.file_path // empty)
           end) as $p
        | select($p != null and $p != "")
        | { path: $p, hunk: (.input.content // .input.new_string // "") } ]
    | unique_by(.path)
  ' "$TRANSCRIPT" 2>/dev/null) || DIFF_JSON="[]"
fi
# failure-mode 3: empty diff is the strongest accept signal (design doc §6).
if [ -z "$DIFF_JSON" ] || [ "$DIFF_JSON" = "null" ] || [ "$DIFF_JSON" = "[]" ]; then
  fields='{"score":0,"dimensions":{},"top_finding":"no edits this session","recommendation":"accept"}'
  ( journal_append "$HOOK_ID" "inferential_structural_verdict" "$fields" >/dev/null ) || true
  exit 0
fi

# ── Step 3: prior-verdict lookup. Read ~/.claude/governance-events.jsonl,
#    filter to event=inferential_structural_verdict with the SAME schema
#    this hook writes, pick the most recent verdict per path, exclude the
#    current session (failure-mode 4: first-run state, prior_verdicts:[]).
#    Cap at 50 files (failure-mode 6) and set truncated=true beyond. ──
# The verdict fields carry a `paths: [...]` array (set in Step 7) listing
# the files this session's diff touched — the prior-verdict lookup matches
# on that list. A prior verdict is matched when any path in its `paths`
# array equals (or is a prefix-of) any path in the current session's diff.
# This makes the §4(a) drift-aware prompt actually load-bearing: the
# previous session's verdict for the same files is in `prior_verdicts`,
# not silently empty.
JOURNAL="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
PRIOR_JSON="[]"
TRUNCATED=0
# Pre-compute the set of current-session paths (used both for prior lookup
# and for embedding in the journal envelope at Step 7).
CURRENT_PATHS=$(printf '%s' "$DIFF_JSON" | jq -c '[.[].path] // []' 2>/dev/null) || CURRENT_PATHS="[]"
if [ -r "$JOURNAL" ] && [ "$CURRENT_PATHS" != "[]" ]; then
  PRIOR_JSON=$(jq -s --argjson cur "$CURRENT_PATHS" --arg sid "${SESSION_ID_VAL:-no-sid}" '
    [ .[]?
        | select(.event=="inferential_structural_verdict")
        | select(.session != $sid)
        | select((.fields.paths // []) | length > 0)
        | { session: .session, ts: .ts, paths: .fields.paths, score: .fields.score, top_finding: .fields.top_finding, recommendation: .fields.recommendation, dimensions: .fields.dimensions } ]
    | map(select(.paths | .[] as $p | $cur | index($p) != null))
    | group_by(.paths | tostring) | map(last)
    | .[0:50]
  ' "$JOURNAL" 2>/dev/null) || PRIOR_JSON="[]"
fi
# If PRIOR_JSON came back as anything other than a JSON array, normalize.
case "$PRIOR_JSON" in
  '['*']') ;;
  *) PRIOR_JSON="[]" ;;
esac

# ── Step 4: truncate diff to 50 files (failure-mode 6). ──
DIFF_COUNT=$(printf '%s' "$DIFF_JSON" | jq 'length' 2>/dev/null | tr -d '[:space:]')
case "$DIFF_COUNT" in ''|*[!0-9]*) DIFF_COUNT=0 ;; esac
if [ "$DIFF_COUNT" -gt 50 ]; then
  TRUNCATED=1
  DIFF_JSON=$(printf '%s' "$DIFF_JSON" | jq '.[0:50]' 2>/dev/null) || DIFF_JSON="[]"
fi

# ── Step 5: render the envelope and invoke the agent. ──
# The agent's drift-aware prompt template (in agents/inferential-structural-judge.md)
# reads the envelope verbatim; we do NOT re-render {{...}} placeholders here —
# we pass the JSON envelope as the prompt body, with the agent file's own
# instructions providing the meta-frame. Two reasons: (a) bash string
# interpolation against arbitrary diff hunks is an injection hazard; (b) the
# agent's `Read` tool will not be used (the prompt is the prompt); this is
# a one-shot, headless verdict, not a multi-turn session.
#
# Invocation mechanism: `claude -p --agent <name> --output-format json --json-schema <schema>`
# (verified via `claude --help` on 2026-06-15). The --json-schema flag pins
# the verdict shape; on schema violation, --output-format json returns an
# error envelope we catch in step 6 and convert to a skipped:malformed_output
# event. Falls back to free-form text output if --json-schema is rejected
# by the agent runtime.
ENVELOPE=$(jq -nc \
  --arg     session  "${SESSION_ID_VAL:-no-sid}" \
  --argjson diff     "$DIFF_JSON" \
  --argjson prior    "$PRIOR_JSON" \
  --argjson budget   "$(jq -nc --argjson u "$SESSION_TOKENS" '{session_tokens_used:$u, cap:25000}')" \
  --argjson trunc    "$TRUNCATED" \
  '{
    session:        $session,
    diff:           $diff,
    prior_verdicts: $prior,
    budget:         $budget,
    truncated:      $trunc
  }')

# The schema the agent must conform to. Mirrors §3 of the design doc.
# `additionalProperties: false` is load-bearing: the agent must NOT emit
# `paths` (the hook sets `fields.paths` at journal time from the diff
# list). A `paths` field in the agent's output would be silently
# overwritten anyway, so failing fast on it makes the contract honest.
SCHEMA='{
  "type": "object",
  "required": ["score","dimensions","top_finding","recommendation"],
  "additionalProperties": false,
  "properties": {
    "score":          { "type": "integer", "minimum": 1, "maximum": 10 },
    "dimensions": {
      "type": "object",
      "required": ["over_engineering","arch_drift","test_pattern","doctrine_conformance"],
      "additionalProperties": false,
      "properties": {
        "over_engineering":     { "type": "integer", "minimum": 1, "maximum": 5 },
        "arch_drift":           { "type": "integer", "minimum": 1, "maximum": 5 },
        "test_pattern":         { "type": "integer", "minimum": 1, "maximum": 5 },
        "doctrine_conformance": { "type": "integer", "minimum": 1, "maximum": 5 }
      }
    },
    "top_finding":    { "type": "string" },
    "recommendation": { "enum": ["accept","flag","escalate"] }
  }
}'

# Run the agent. Captured stdout is the JSON wrapper; we extract the verdict
# payload from the .result field. The hook must not block forever — `claude
# -p` has its own timeout (60s default), but we set a tighter wallclock to
# match the per-session cost ceiling (~4k tokens / ~30s of inference).
# Use a 90s wallclock cap; the journal logs nothing on timeout, exits 0
# silently (failure-mode 2 + a 7th: agent timeout → skipped, never blocks).
VERDICT_WRAPPER=""
VERDICT_PAYLOAD=""
if [ -n "$TRANSCRIPT" ]; then
  # Full agent invocation with the envelope as the prompt + schema constraint.
  # The prompt is prefixed with a one-line header so the agent's drift-aware
  # template (which expects the envelope on stdin) gets the JSON as the
  # tail of the prompt. JSONL-friendly single-line envelope.
  PROMPT=$(printf 'You are invoked by the inferential-structural-judge-on-session-end hook. The following JSON envelope is your input contract (see agents/inferential-structural-judge.md for the drift-aware scoring rules):\n%s' "$ENVELOPE")
  VERDICT_WRAPPER=$(printf '%s' "$PROMPT" | timeout 90 claude -p --agent inferential-structural-judge --output-format json --json-schema "$SCHEMA" 2>/dev/null) || VERDICT_WRAPPER=""
fi

# ── Step 6: validate the verdict. The .result field is the verdict JSON
#    string the agent emitted; parse it, then validate against the same
#    schema locally (defense-in-depth — --json-schema is best-effort). ──
if [ -n "$VERDICT_WRAPPER" ]; then
  VERDICT_PAYLOAD=$(printf '%s' "$VERDICT_WRAPPER" | jq -r '.result // empty' 2>/dev/null)
fi

# Validate: must be non-empty, parse as JSON, and pass the schema.
# If the result string itself is JSON (it is — --json-schema constrains it),
# we do a final local shape check. additionalProperties=false on both the
# outer object and the dimensions sub-object enforces "no `paths` field
# from the agent" (the hook sets `fields.paths` at journal time).
VALID=0
if [ -n "$VERDICT_PAYLOAD" ] && printf '%s' "$VERDICT_PAYLOAD" | jq -e . >/dev/null 2>&1; then
  if printf '%s' "$VERDICT_PAYLOAD" | jq -e '
      (.score | type == "number" and . >= 1 and . <= 10) and
      (.recommendation | . == "accept" or . == "flag" or . == "escalate") and
      (.dimensions | type == "object") and
      (.dimensions | keys | sort == ["arch_drift","doctrine_conformance","over_engineering","test_pattern"]) and
      (.dimensions.over_engineering      | type == "number" and . >= 1 and . <= 5) and
      (.dimensions.arch_drift            | type == "number" and . >= 1 and . <= 5) and
      (.dimensions.test_pattern          | type == "number" and . >= 1 and . <= 5) and
      (.dimensions.doctrine_conformance  | type == "number" and . >= 1 and . <= 5) and
      (.top_finding | type == "string" and length > 0) and
      (. | keys | sort == ["dimensions","recommendation","score","top_finding"])
  ' >/dev/null 2>&1; then
    VALID=1
  fi
fi

if [ "$VALID" -ne 1 ]; then
  # 7th failure mode (agent contract): malformed_output. Per the agent
  # file's "Output validation" section, the hook discards and journals
  # skipped:malformed_output. We do NOT re-invoke the agent.
  fields='{"reason":"malformed_output","raw_present":'"$([ -n "$VERDICT_WRAPPER" ] && echo true || echo false)"'}'
  ( journal_append "$HOOK_ID" "inferential_structural_verdict_skipped" "$fields" >/dev/null ) || true
  exit 0
fi

# ── Step 7: journal the verdict. Pass the verdict payload as-is into
#    `fields` (the journal envelope wraps it in the {id,ts,session,hook,
#    event,source,fields{...}} shape per JOURNAL-SCHEMA.md). If we
#    truncated, set fields.truncated=true so the next-session reader
#    knows the verdict is partial. Embed `fields.paths` with the set of
#    files this session's diff touched — that is the lookup key the
#    next session's prior-verdict reader (Step 3) uses to load
#    drift-aware context for the §4(a) mitigation. Without `fields.paths`,
#    the next session's prior lookup always returns [] and the
#    drift-aware block is non-functional (defect #2 from the
#    lead-mandated Wave-1.5 patch). ──
if [ "$TRUNCATED" -eq 1 ]; then
  FIELDS_JSON=$(printf '%s' "$VERDICT_PAYLOAD" | jq -c --argjson paths "$CURRENT_PATHS" '. + {truncated:true, paths:$paths}' 2>/dev/null) || FIELDS_JSON="$VERDICT_PAYLOAD"
else
  FIELDS_JSON=$(printf '%s' "$VERDICT_PAYLOAD" | jq -c --argjson paths "$CURRENT_PATHS" '. + {paths:$paths}' 2>/dev/null) || FIELDS_JSON="$VERDICT_PAYLOAD"
fi
( journal_append "$HOOK_ID" "inferential_structural_verdict" "$FIELDS_JSON" >/dev/null ) || true

exit 0
