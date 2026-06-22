#!/bin/bash
# l3-push-gate.sh — Gate 2 of the L3 bounded-autonomy loop (ADR 0003).
#
# The L3 loop (recursive-improve --auto) commits LOCAL-only; pushing the batch is
# a human decision made AFTER a pre-push review (Gate 2). This gate enforces that
# computationally: while an L3 run is active and the batch is unreviewed, DENY any
# command that would ship the work or disable the gauntlet —
#   - git push            (ships local commits)
#   - gh pr create|merge  (ships via GitHub)
#   - git config …hooksPath / core.hooks…  (redirects/neuters the git-hook gauntlet)
# plus any command that inline-sets a safety env var (self-elevation / Gate-2 forge).
#
# It is FLAG-SCOPED: with the autonomy flag unset (every normal session) this gate
# exits 0 immediately — force-push policy etc. stays owned by block-dangerous-git.
# The override is the human's: export KBG_REVIEW_DONE=1 after the Gate-2 review,
# then push. (You cannot inline-set your way past it — see the tamper check.)
#
# Bypass (normal sessions only — has no effect during an armed run, by autonomy
# immunity in _lib.sh):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=l3-push-gate

set -uo pipefail

HOOK_ID="l3-push-gate"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable

# Flag-scoped: only active inside an authorized autonomy run (single-key
# autonomy_on predicate, design §5 F1 — armed only from a per-repo
# .claude/settings.local.json, so a user-global flag arms nothing). Captured from
# the hook's own env (the loop cannot un-set it for the gate without tripping the
# tamper check below). No auto-push carve-out: the gate also fires under L4/L5 —
# Gate 2 (human push review) stays the one permanent irreversible boundary.
autonomy_on || exit 0

hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(hook_strip_quoted "$COMMAND")
_GREP="command grep"
SEP='(^|[[:space:];&|()`])'

# Same global-option allowance as block-dangerous-git: options sit between `git`
# and the subcommand (`git -c k=v push`), so without GOPT the adjacency breaks and
# the gate is bypassed.
GOPT='((-c|-C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)[=[:space:]]+[^[:space:]]+[[:space:]]+|(-P|-p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--exec-path|--html-path|--man-path|--info-path)[[:space:]]+)*'

# 1. Tamper: any command that inline-sets a safety env var is denied OUTRIGHT
#    (self-elevation, profile-off, or forging the Gate-2 review flag). This runs
#    BEFORE the review-done short-circuit so review-done can't be inline-forged.
TAMPER_PAT="${SEP}(KBG_AUTONOMY|KBG_REVIEW_DONE|CLAUDE_HOOK_PROFILE|CLAUDE_DISABLED_HOOKS)="
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$TAMPER_PAT"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "${TAMPER_PAT}[^[:space:]]*" | head -1 | xargs)
  hook_decision deny "autonomy run: command sets a safety env var ('$matched'). The loop may not self-elevate, disable hooks, or forge the Gate-2 review flag. Set KBG_REVIEW_DONE=1 in your shell out-of-band, not inline."
fi

# Ship + gauntlet-disable patterns (denied unless Gate 2 is cleared).
PUSH_PAT="${SEP}git[[:space:]]+${GOPT}push([[:space:]]|$)"
GH_PAT="${SEP}gh[[:space:]]+(pr[[:space:]]+(create|merge|ready)|repo[[:space:]]+sync|.*push)"
# Match hooksPath / core.hooks ANYWHERE after `git` — catches both the persistent
# `git config core.hooksPath <path>` and the ephemeral `git -c core.hooksPath=x …`
# forms (GOPT would otherwise consume the `-c core.hooksPath=` before `config`).
HOOKSPATH_PAT="${SEP}git[[:space:]][^#]*(hooksPath|core\.hooks)"

# 2. Gate-2 cleared (human reviewed the batch) → allow ship/merge. The hooksPath
#    redirect stays denied even post-review: it disables the gauntlet, never a
#    legitimate part of shipping.
if [ "${KBG_REVIEW_DONE:-}" = "1" ]; then
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$HOOKSPATH_PAT"; then
    hook_decision deny "autonomy run: refusing to redirect git hooksPath — that disables the gauntlet. This is never part of a push, reviewed or not."
  fi
  # Gate-2 strengthening (design §10, #30): under an armed run, KBG_REVIEW_DONE=1 is
  # honored ONLY if a maker≠checker kbg:review-pr pass is in the recent audit trail
  # (a review_finding journal event). Without it, the review flag could be set with
  # no actual fresh-context review — a rubber-stamp the quarterly decay sweep must be
  # able to observe. The gate is armed-only (autonomy_on above), so normal sessions
  # are unaffected.
  _jpath="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
  if [ -f "$_jpath" ] && tail -n 500 "$_jpath" 2>/dev/null | $_GREP -q 'review_finding'; then
    exit 0
  fi
  hook_decision deny "autonomy run: KBG_REVIEW_DONE=1 is set but no maker≠checker kbg:review-pr pass (review_finding event) is in the recent audit trail — run kbg:review-pr on the batch first, THEN set KBG_REVIEW_DONE=1 (design §10, ADR 0004 Gate-2 strengthening)."
fi

# 3. Unreviewed batch → deny ship / merge / gauntlet-disable.
for pattern in "$PUSH_PAT" "$GH_PAT" "$HOOKSPATH_PAT"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "(git|gh)[[:space:]][^#]*" | head -1 | xargs)
    hook_decision deny "autonomy run, batch unreviewed: '$matched' is push-gated (ADR 0004 Gate 2). Review the run locally (kbg:review-pr on the batch), then export KBG_REVIEW_DONE=1 and retry."
  fi
done

exit 0
