#!/bin/bash
# decision-provenance-nudge.sh — advisory PreToolUse sensor (computational-FF).
#
# When an Edit/Write/MultiEdit targets a CONSEQUENTIAL surface, journal a
# `decision_rationale` provenance event and emit an additionalContext nudge
# reminding the operator to record the decision-sizing triad (one-way door /
# blast radius / riskiest assumption) in their response.
#
# Advisory ONLY — it journals + nudges, it NEVER emits a permissionDecision
# (no deny/ask/allow). Omitting permissionDecision = the harness proceeds
# (allow) with the nudge injected. This is deliberate:
#   - JOURNAL-SCHEMA.md gate↔evidence invariant (#29): a hook that emits a
#     permissionDecision must NOT also journal. This hook journals, so it
#     emits no decision.
#   - LLM-judge-circularity (CLAUDE.md §): an inferential-FB sensor emitting a
#     permissionDecision is a model-driven mutation gate — forbidden by the
#     autonomy invariant. This hook is pure computational path-match (cage.txt
#     + doctrine basename), no LLM, no decision — it structurally cannot
#     become a model-driven gate.
#
# "Consequential" = the one-way-door class (narrow, NOT blanket — avoids the
# #31.1 trap where a presence-only check on too much manufactures the
# boilerplate it polices):
#   1. an in-repo path that is CAGED per scripts/cage.txt (the safety surface:
#      hooks/**, gauntlet, audit, eval corpus, doctrine basenames, ADRs, L4
#      launch, manifests) — read from cage.txt so this never drifts from the
#      cage (sync-seam discipline; cage.txt is the single source).
#   2. an out-of-repo doctrine basename (e.g. the dotfiles ~/.claude/CLAUDE.md
#      symlink) under a claude/.claude/kbg-harness dir.
# doctrine-edit-gate.sh already gates (asks) the in-repo doctrine subset; this
# hook covers the full caged set + out-of-repo doctrine for PROVENANCE. The
# two coexist orthogonally (gate decides, this journals).
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=decision-provenance-nudge

set -uo pipefail

HOOK_ID="decision-provenance-nudge"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
# Advisory fail-OPEN: on unparseable input or missing jq, emit nothing + exit 0.
# We deliberately do NOT call hook_guard_unreadable — that emits a
# permissionDecision `ask`, which this advisory hook must never produce
# (gate↔evidence invariant #29 + LLM-judge-circularity). Missing a nudge is
# harmless; a spuriously blocking decision is not.

case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // empty') || exit 0
[ -z "$FILE_PATH" ] && exit 0

# Repo root = two levels up from this hook (hooks/advisory/ -> repo root).
# Resolves correctly under both the source tree and the plugin cache.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAGE_FILE="$REPO_ROOT/scripts/cage.txt"

# Strip the repo-root prefix to get a repo-relative path. If FILE_PATH is not
# under REPO_ROOT (out-of-repo, e.g. dotfiles), REL stays absolute and will not
# match any cage.txt pattern — we then fall through to the doctrine-basename
# check for the out-of-repo case.
REL="${FILE_PATH#$REPO_ROOT/}"
if [ "$REL" = "$FILE_PATH" ]; then
  in_repo=0
else
  in_repo=1
fi

consequential=0
class=""
surface=""

if [ "$in_repo" = 1 ] && [ -f "$CAGE_FILE" ]; then
  # Match REL against cage.txt patterns (single source — no re-declaration).
  # Syntax per cage.txt: "<dir>/**" = dir + everything under; "<path>" = exact.
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    if [ "${line: -3}" = "/**" ]; then
      dir="${line::${#line}-3}"
      case "$REL" in
        "$dir"|"$dir"/*) consequential=1; class="caged"; surface="$REL"; break ;;
      esac
    else
      if [ "$REL" = "$line" ]; then
        consequential=1; class="caged"; surface="$REL"; break
      fi
    fi
  done < "$CAGE_FILE"
fi

if [ "$consequential" = 0 ]; then
  # Out-of-repo doctrine basename (dotfiles ~/.claude/CLAUDE.md symlink, etc.).
  # Dir must be under claude/.claude/kbg-harness (mirror doctrine-edit-gate's
  # dir guard) so we don't fire on an unrelated file that happens to share a name.
  BASE="$(basename "$FILE_PATH")"
  DIR="$(dirname "$FILE_PATH")"
  case "$DIR" in
    */claude|*/claude/*|*/.claude|*/.claude/*|*/kbg-harness|*/kbg-harness/*) ;;
    *) exit 0 ;;
  esac
  case "$BASE" in
    CLAUDE.md|METHODOLOGY.md|RTK.md|ACLI.md|DBGATE.md|CONTEXT.md|DOMAINS.md|settings.json|.mcp.json|mcp-servers.json)
      consequential=1; class="doctrine"; surface="$FILE_PATH"
      ;;
  esac
fi

[ "$consequential" = 0 ] && exit 0

# Journal the machine-provenance half. The human-readable half (the triad
# rationale) is the operator's to record in their response — the nudge below
# asks for it. source=journal_append (envelope pinned by JOURNAL-SCHEMA.md).
fields=$(jq -nc --arg s "$surface" --arg c "$class" \
  '{surface_touched:$s, consequential_class:$c, one_way_door:true}')
journal_append "$HOOK_ID" "decision_rationale" "$fields" >/dev/null 2>&1 || true

# Advisory nudge via additionalContext (NO permissionDecision -> allow + inject).
# The triad is the staff-engineer decision-sizing loop (METHODOLOGY Rule 1).
nudge="Consequential surface touched: ${surface} (${class}) — one-way-door-class edit. Before finalizing, record the decision-sizing triad in your response: (1) one-way door? (2) blast radius — what downstream breaks / what this couples to? (3) riskiest assumption — stated and verified? A decision_rationale provenance event is journaled; your triad is the human-readable half that accompanies it."
ctx="$(printf '%s' "$nudge" | jq -cRs . 2>/dev/null)" || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$ctx"
exit 0