#!/bin/bash
# push-gate.sh — Gate 2 of the L3 bounded-autonomy loop (ADR 0003).
#
# The L3 loop (recursive-improve --auto) commits LOCAL-only; pushing the batch is
# a human decision made AFTER a pre-push review (Gate 2). This gate enforces that
# computationally: while an L3 run is active and the batch is unreviewed, DENY any
# command that would ship the work or disable the gauntlet —
#   - git push            (ships local commits)
#   - gh pr merge         (ships via GitHub — server-side merge, irreversible)
#   - git config …hooksPath / core.hooks…  (redirects/neuters the git-hook gauntlet)
# plus any command that inline-sets a safety env var (self-elevation / Gate-2 forge).
#
# `gh pr create` and `gh pr ready` are NOT gated (0002-addendum-push-gate-create-not-ship.md):
# opening a PR and marking it ready-for-review are reversible review-prep, not a ship —
# and gating them demanded a review_finding be journaled BEFORE a PR could be opened,
# which is backwards (you open a PR to GET review). Only the irreversible ship
# (merge / push / repo sync) stays gated, so the loop can open PRs without the flag
# dance or the `!` handoff that forced the operator to run gh pr create themselves.
#
# It is FLAG-SCOPED: with the autonomy flag unset (every normal session) this gate
# exits 0 immediately — force-push policy etc. stays owned by block-dangerous-git.
# The override is the human's: export KBG_REVIEW_DONE=1 after the Gate-2 review,
# then push. (You cannot inline-set your way past it — see the tamper check.)
#
# Bypass (normal sessions only — has no effect during an armed run, by autonomy
# immunity in _lib.sh):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=push-gate

set -uo pipefail

HOOK_ID="push-gate"
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
GH_PAT="${SEP}gh[[:space:]]+(pr[[:space:]]+merge|repo[[:space:]]+sync|.*push)"
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

# 2b. L5 auto-push ship-gate (ADR 0005 + addendum 0005-addendum-manual-push-precondition-
#     waiver.md, design §8.5, #35). With the human out of the push loop (manual armed
#     push under the addendum; the unattended launchd loop stays paused behind the
#     N≥20-cycle precondition), a green-gauntlet batch may auto-push — BUT only to a
#     dest in KBG_L5_SHIP_ALLOWLIST (default EMPTY → an un-configured install pushes
#     NOWHERE), only after a SHA-bound green gauntlet, and only if the push range does
#     NOT loosen a cross-repo security gate. The model never authorizes the ship — this
#     leg is purely computational. Fail-closed: missing green / un-configured / CRIT →
#     fall through to the unreviewed-deny. Flag-OFF + L4 (KBG_REVIEW_DONE) behaviour is
#     unchanged — this leg only fires when Gate 2 was NOT cleared. It ports the
#     MECHANISM of the owner's cross-org push rule (origin-vs-destination divergence),
#     never the named orgs — the portable substitute is the host+org allowlist, default
#     empty.
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$PUSH_PAT"; then
  _rem=$(printf '%s\n' "$STRIPPED" | awk '{for(i=1;i<=NF;i++) if($i=="push"){for(j=i+1;j<=NF;j++) if($j !~ /^-/){print $j; exit}}}')
  _dest=""
  if [ -n "$_rem" ] && command -v git >/dev/null 2>&1; then
    _url=$(git remote get-url "$_rem" 2>/dev/null || true)
    # ponytail: normalize ssh + https URLs to host:org (the first path segment).
    _dest=$(printf '%s\n' "$_url" | sed -E 's#^(git@|ssh://git@|https?://|git://)##; s#\.git$##; s#^([^/:]+)[:/]([^/]+)/.*$#\1:\2#')
  fi
  _allow="${KBG_L5_SHIP_ALLOWLIST:-}"
  # (a) Allowlist gate: dest must be configured. Empty allowlist → pushes nowhere.
  _allow_ok=0
  if [ -n "$_dest" ] && [ -n "$_allow" ]; then
    case ",$_allow," in *",$_dest,"*) _allow_ok=1 ;; esac
  fi
  # (b) SHA-bound green gauntlet: the MOST RECENT gauntlet_run for the HEAD being
  #     pushed must be green. Not a stale any-green (a prior run's green must NOT
  #     authorize an unrelated commit), and not a model verdict (a quality_gate /
  #     review_finding green does not satisfy this — the model cannot self-bless; it
  #     must run the deterministic gauntlet, which journals gauntlet_run). A later red
  #     for the same sha denies.
  _green=0
  _head=""
  _jpath="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
  if command -v git >/dev/null 2>&1; then
    _head=$(git rev-parse HEAD 2>/dev/null || echo "")
  fi
  if [ -n "$_head" ] && [ -f "$_jpath" ]; then
    _last=$(tail -n 5000 "$_jpath" 2>/dev/null | $_GREP -F "\"sha\":\"$_head\"" | $_GREP 'gauntlet_run' | tail -1)
    if [ -n "$_last" ] && printf '%s' "$_last" | $_GREP -q '"outcome":"green"'; then
      _green=1
    fi
  fi
  # (c) Cross-repo CRIT (ADR 0005 §floor 2): block a push that LOOSENS a security brake.
  #     Keys on the three ADR-named gates (secret-scan / block-dangerous-git /
  #     db-write-gate): a file deletion in the push range, or a removed deny line, is a
  #     loosened brake → CRIT deny. "Touches a gate" is NOT the trigger (the owner
  #     legitimately edits gates — including this very change); "loosens a brake" is.
  #     The human-review override (KBG_REVIEW_DONE, the Gate-2 block above) still
  #     authorizes the exceptional case. Degrade: if the range can't be computed, skip
  #     (green-for-HEAD still applies).
  _crit=0
  _crit_msg=""
  if command -v git >/dev/null 2>&1 && [ -n "$_head" ]; then
    _base=$(git merge-base origin/develop HEAD 2>/dev/null || echo "")
    if [ -n "$_base" ] && [ "$_base" != "$_head" ]; then
      for _gate in hooks/gates/secret-scan.sh hooks/gates/block-dangerous-git.sh hooks/gates/db-write-gate.sh; do
        _existed_at_base=0; git cat-file -e "${_base}:${_gate}" >/dev/null 2>&1 && _existed_at_base=1
        _exists_at_head=0; git cat-file -e "HEAD:${_gate}" >/dev/null 2>&1 && _exists_at_head=1
        if [ "$_existed_at_base" = "1" ] && [ "$_exists_at_head" = "0" ]; then
          _crit=1; _crit_msg="$_gate was deleted in the push range (loosened brake)"
        elif [ "$_existed_at_base" = "1" ] && [ "$_exists_at_head" = "1" ]; then
          _removed=$(git diff "$_base" HEAD -- "$_gate" 2>/dev/null | $_GREP -E '^-.*(deny|DENY|CRIT|block|forbid|permissionDecision.*deny|dangerous|secret|password|token|db[._-]write|DB_WRITE)' || true)
          if [ -n "$_removed" ]; then
            _crit=1; _crit_msg="$_gate had a deny line removed in the push range (potential loosened brake)"
          fi
        fi
      done
    fi
  fi
  if [ "$_crit" = "1" ]; then
    hook_decision deny "autonomy run (L5 ship-gate): cross-repo CRIT — $_crit_msg. A push that loosens a security brake is never part of shipping (ADR 0005 §floor 2). Review the change and push via the Gate-2 path (KBG_REVIEW_DONE) if the loosening is intended."
  fi
  # Allow ONLY if allowlisted AND green-for-HEAD. Else fall through to the unreviewed-deny.
  if [ "$_allow_ok" = "1" ] && [ "$_green" = "1" ]; then
    exit 0
  fi
fi

# 3. Unreviewed batch → deny ship / merge / gauntlet-disable.
for pattern in "$PUSH_PAT" "$GH_PAT" "$HOOKSPATH_PAT"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "(git|gh)[[:space:]][^#]*" | head -1 | xargs)
    hook_decision deny "autonomy run, batch unreviewed: '$matched' is push-gated (ADR 0004 Gate 2 / ADR 0005 L5 ship-gate). Review the run (kbg:review-pr → KBG_REVIEW_DONE=1) OR, under L5, auto-push only to an allowlisted host+org after a green gauntlet."
  fi
done

exit 0
