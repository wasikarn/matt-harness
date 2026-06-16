#!/bin/bash
# Stop hook — audit-log every "X is fabricated / doesn't exist / ไม่มีจริง"
# verdict the agent emits, annotated with whether the turn ran any
# ground-truth tool (WebFetch/WebSearch/context7/qmd/Bash/Read/Grep).
#
# Why: METHODOLOGY Rule 1 + the verify-before-asserting failure mode. The
# agent cannot tell confident-right from confident-wrong internally, and no
# hook can gate free-text BEFORE it is shown (verified 2026-05-25:
# code.claude.com/docs/en/hooks — no pre-response event exists). So this does
# the one thing that IS possible: surface every fabrication verdict post-hoc
# for human review, turning "do I still slip?" from vibes into data.
#
# This is a LOGGER, not a gate — never blocks, best-effort (Rule 12 does not
# apply: a logger that can't run must not stall the turn). It does NOT
# adjudicate: it logs the verdict + tool context; the human judges. Known
# limits — turn-level tool detection cannot tell "verified A, asserted B" from
# "verified this exact claim"; and meta-conversations about fabrication (like
# the session that birthed it) trip it by design.
#
# Log: ~/.claude/fabrication-verdict.log
#   tab-separated: ts \t session \t gt_tool_count \t tools_csv \t verdict \t snippet
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=fabrication-verdict-log

HOOK_ID="fabrication-verdict-log"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

command -v jq >/dev/null 2>&1 || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# Scope to the current turn: slice from the last *human* prompt to the end.
# A real human prompt is a user line whose .message.content is a STRING and is
# not meta and not a system-injected <...> wrapper (verified 2026-05-25 against
# live transcripts — tool_result lines store content as an array, so the
# earlier array+text filter never matched real prompts and sliced the whole
# session). Emit {prose, tools} for that slice.
SCOPED=$(jq -s '
  . as $all
  | ([ $all | to_entries[]
       | select(.value.type=="user")
       | select((.value.isMeta // false) != true)
       | select((.value.message.content | type) == "string")
       | select((.value.message.content | startswith("<")) | not)
       | .key ] | last) as $start
  | $all[ ($start // 0) : ]
  | {
      prose: ([ .[] | select(.type=="assistant")
                | (.message.content[]? | select(.type=="text") | .text) ] | join("\n")),
      tools: ([ .[] | select(.type=="assistant")
                | (.message.content[]? | select(.type=="tool_use") | .name) ])
    }
' "$TRANSCRIPT" 2>/dev/null)
[ -z "$SCOPED" ] && exit 0

PROSE=$(printf '%s\n' "$SCOPED" | jq -r '.prose // empty' 2>/dev/null)
[ -z "$PROSE" ] && exit 0

# Fabrication-verdict phrases (English + Thai). Logger tolerates some noise.
# NB: two tokens deliberately excluded after observing live false positives —
#   "fabrication" (noun) matched this hook's own name ("fabrication-verdict-
#     log") in meta-discussion, logging itself ("fabricated", the verdict verb,
#     does not appear in the hook name);
#   "มั่ว" is polysemous (sloppy / random / wrong, not specifically fabricated)
#     and fired on phrasings like "gt_count มั่ว".
# Residual meta-noise (saying "fabricated" while discussing this very topic)
# is inherent and accepted; the detector's value is in non-meta sessions.
VERDICT_RE='fabricated|does(n.?t| not) exist|no such (thing|field|param|setting|feature|key|option)|not a real|made[ -]up|isn.?t real|is not real|invented (feature|param|rationale|setting)|ไม่มีจริง|กุขึ้น'

printf '%s\n' "$PROSE" | command grep -qiE "$VERDICT_RE" || exit 0

# A verdict was emitted this turn. Gather context for review.
VERDICT=$(printf '%s\n' "$PROSE" | command grep -oiE "$VERDICT_RE" | head -1)
SNIPPET=$(printf '%s\n' "$PROSE" | command grep -iE "$VERDICT_RE" | head -1 | cut -c1-160 | tr '\t\n' '  ')

# Ground-truth tool calls this turn (external/authoritative sources).
GT_RE='WebFetch|WebSearch|context7|qmd|^Bash$|^Read$|^Grep$|code-review-graph'
TOOLS_CSV=$(printf '%s\n' "$SCOPED" | jq -r '.tools | join(",")' 2>/dev/null)
GT_COUNT=$(printf '%s\n' "$SCOPED" | jq -r --arg re "$GT_RE" '[.tools[] | select(test($re))] | length' 2>/dev/null)
[ -z "$GT_COUNT" ] && GT_COUNT=0

# Log format is 6 columns: ts, sid, gt_count, tools_csv, verdict, snippet.
# Emit manually to preserve the verbatim column order.
LOG="$HOME/.claude/fabrication-verdict.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" "$GT_COUNT" "${TOOLS_CSV:-none}" "$VERDICT" "$SNIPPET" >> "$LOG"

exit 0
