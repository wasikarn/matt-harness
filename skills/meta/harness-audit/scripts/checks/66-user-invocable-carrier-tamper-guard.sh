#!/usr/bin/env bash
# 66. user-invocable: false carriers must keep the flag (WARN).
# Mirrors checks 30/58-65's role for disable-model-invocation, but as ONE
# check instead of one-file-per-skill: user-invocable's stakes are lower
# (dropping it un-hides a pure agent-preload catalog from the `/` menu; it
# doesn't remove a safety block the way a dropped disable-model-invocation
# does), so it doesn't earn the same one-CRIT-file-per-carrier granularity —
# proportionate coverage, not the full pattern. Two passes in one file:
#
#   1. presence guard: each of the 8 known carriers (all pure agent-preload
#      catalogs whose own description reads "Auto-loads when <agent> runs" —
#      applied 2026-08-31) must still carry `user-invocable: false`.
#   2. self-extension guard: any OTHER skill carrying `user-invocable: false`
#      that isn't in the known list below gets flagged too, so a future
#      addition doesn't silently go unprotected the way an 11th
#      disable-model-invocation carrier did before check 65 existed.
#
# WARN throughout: a coverage gap or a dropped flag here is a menu-visibility
# regression, not a safety hole.
_known_carriers=(
  "skills/agent-support/performance-optimizer-algorithms/SKILL.md"
  "skills/agent-support/plan-reviewer-format/SKILL.md"
  "skills/agent-support/requirement-analyst-format/SKILL.md"
  "skills/agent-support/summarizer-format/SKILL.md"
  "skills/review/blind-spot-hunter-shapes/SKILL.md"
  "skills/review/review-lens-nextjs-routing/SKILL.md"
  "skills/review/security-reviewer-patterns/SKILL.md"
)
for _rel in "${_known_carriers[@]}"; do
  _f="$CLAUDE_DIR/$_rel"
  if [ -f "$_f" ]; then
    [ "$(fm_get "$_f" user-invocable)" = "false" ] || \
      warn "'$_rel': missing 'user-invocable: false' — this pure agent-preload catalog should stay hidden from the / menu"
  else
    warn "$_rel not found — cannot verify its user-invocable: false flag (renamed or deleted agent-preload catalog?)"
  fi
done
for _f2 in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/*/SKILL.md; do
  [ -f "$_f2" ] || continue
  [ "$(fm_get "$_f2" user-invocable)" = "false" ] || continue
  _rel2="${_f2#"$CLAUDE_DIR"/}"
  _found=0
  for _k in "${_known_carriers[@]}"; do [ "$_k" = "$_rel2" ] && _found=1 && break; done
  [ "$_found" = 1 ] || warn "'$_rel2': carries user-invocable: false but isn't in check 66's known-carrier list — add it here so a future silent drop gets caught"
done
unset _rel _f _f2 _rel2 _found _k _known_carriers
