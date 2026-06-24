#!/bin/bash
# post-push-tripwire.sh — ADR 0005 §floor 5 post-push witness (advisory only).
#
# A cheap OUTSIDE-THE-CAGE tripwire that fires AFTER a successful `git push` under an
# armed run and re-runs the cross-repo security-gate check against the range that just
# landed. Post-push can only DETECT + JOURNAL — the push already shipped, so this hook
# never emits a permissionDecision and always exits 0 (the 2×2 inferential-FB advisory
# invariant: a post-act sensor journals, it does not block). Its job is to witness a
# loosened brake that slipped through — the one path the pre-push CRIT cannot catch is
# the human Gate-2 override (KBG_REVIEW_DONE authorizes even a CRIT-flagged push); this
# tripwire surfaces that after the fact so the operator can revert.
#
# Keys on the same three ADR-named gates as the pre-push CRIT in push-gate.sh (c):
# secret-scan / block-dangerous-git / db-write-gate. A deletion or a removed deny line
# in the pushed range is a loosened brake → journals a `post_push_tripwire` CRIT event
# and prints to stderr. "Touches a gate" is NOT the trigger; "loosens a brake" is.
#
# PostToolUse:Bash, async. Reads tool_input.command; if it is not a `git push`, exits 0
# immediately. Only meaningful under autonomy_on (normal sessions push freely — the
# human is the gate). Best-effort: no network fetch (relies on the local origin/develop
# tracking ref, which `git push` updates on success); if the range can't be computed,
# degrade to HEAD~1..HEAD; if that fails too, journal a skipped verdict and exit 0.
#
# Bypass (normal sessions only — autonomy-immune, no effect when armed):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=post-push-tripwire

set -uo pipefail
export LC_ALL=C

HOOK_ID="post-push-tripwire"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

# Only meaningful under an armed run (normal sessions: the human owns the push).
autonomy_on || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v journal_append >/dev/null 2>&1 || exit 0

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || exit 0
[ -z "$COMMAND" ] && exit 0
STRIPPED=$(hook_strip_quoted "$COMMAND")
_GREP="command grep"
SEP='(^|[[:space:];&|()`])'
GOPT='((-c|-C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)[=[:space:]]+[^[:space:]]+[[:space:]]+|(-P|-p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--exec-path|--html-path|--man-path|--info-path)[[:space:]]+)*'
PUSH_PAT="${SEP}git[[:space:]]+${GOPT}push([[:space:]]|$)"
printf '%s\n' "$STRIPPED" | $_GREP -qE "$PUSH_PAT" || exit 0

# Resolve the range that just landed. `git push` updates the local origin/develop
# tracking ref on success, so no fetch is needed. If HEAD is not at origin/develop, the
# push didn't land HEAD to develop (or landed elsewhere) → nothing to witness here.
_head=$(git rev-parse HEAD 2>/dev/null || echo "")
_tip=$(git rev-parse origin/develop 2>/dev/null || echo "")
[ -n "$_head" ] && [ "$_head" = "$_tip" ] || exit 0

# Prior tip: remote-tracking reflog @{1}, degrade to HEAD~1.
_prior=$(git rev-parse 'origin/develop@{1}' 2>/dev/null || echo "")
_range=""
if [ -n "$_prior" ] && [ "$_prior" != "$_tip" ]; then
  _range="${_prior}..${_tip}"
else
  _range="HEAD~1..HEAD"
fi

# Re-run the 3-gate loosening check over the pushed range (mirrors push-gate.sh (c)).
_crit=0
_crit_msg=""
for _gate in hooks/gates/secret-scan.sh hooks/gates/block-dangerous-git.sh hooks/gates/db-write-gate.sh; do
  _existed_at_base=0; git cat-file -e "${_prior}:${_gate}" >/dev/null 2>&1 && _existed_at_base=1
  _exists_at_tip=0; git cat-file -e "${_tip}:${_gate}" >/dev/null 2>&1 && _exists_at_tip=1
  if [ "$_existed_at_base" = "1" ] && [ "$_exists_at_tip" = "0" ]; then
    _crit=1; _crit_msg="$_gate was deleted in the pushed range (loosened brake)"
  elif [ "$_existed_at_base" = "1" ] && [ "$_exists_at_tip" = "1" ]; then
    _removed=$(git diff "$_range" -- "$_gate" 2>/dev/null | $_GREP -E '^-.*(deny|DENY|CRIT|block|forbid|permissionDecision.*deny|dangerous|secret|password|token|db[._-]write|DB_WRITE)' || true)
    if [ -n "$_removed" ]; then
      _crit=1; _crit_msg="$_gate had a deny line removed in the pushed range (potential loosened brake)"
    fi
  fi
done

if [ "$_crit" = "1" ]; then
  _verdict="crit"
  echo "[$HOOK_ID] CRIT — $_crit_msg. The push already landed; review and revert if the loosening was unintended (ADR 0005 §floor 5 witness)." >&2
else
  _verdict="clean"
fi

journal_append "$HOOK_ID" "post_push_tripwire" \
  "{\"sha\":\"$_head\",\"range\":\"$_range\",\"verdict\":\"$_verdict\",\"finding\":\"$_crit_msg\"}" \
  >/dev/null 2>&1 || true

exit 0