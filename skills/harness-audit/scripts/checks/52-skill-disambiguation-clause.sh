#!/usr/bin/env bash
# 52. Skill disambiguation clause — every skill description should carry a
# narrow-form "Don't use for X" boundary clause. This is the fleet's own
# de-facto anti-duplication convention (30/30 skills currently follow it,
# previously unenforced) — see the `review-prompt-duplication-pattern`
# memory for the one confirmed incident this class of gap produced. Skills
# auto-trigger on description match, so a skill with no stated boundary is
# the one most likely to misfire against an adjacent skill's territory.
#
# Matcher is narrow-form only: "don't use for" / "don't use to" /
# "don't use it for" / "not for". Deliberately excludes loose forms like
# "; not X" or "— not X" — those match any prose containing the tokens, not
# just a boundary statement, and would report conformance the check isn't
# actually measuring. That's the same trap check 36's retired failure-mode
# proxy fell into (2026-07-16): a permissive regex is worse than no check.
#
# INFO only, matching check 36's stated policy (per the
# harness-audit-gauntlet-policy memory): doctrine-conformance, not doc-rot —
# the WARN/CRIT escalation trap is deliberately rejected for this class of
# advisory signal.
#
# Scope: skills only. Agents and commands are dispatched deliberately by a
# parent, not auto-triggered on description match, so the failure mode this
# check guards against doesn't apply to them the same way (a fleet-wide
# survey found only 2/19 agents and 14/19 commands conformant — enforcing
# there would be mostly low-value noise, not a signal).
for f in "$CLAUDE_DIR/skills"/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  name=$(basename "$(dirname "$f")")

  desc=$(fm_get "$f" "description" --block)

  if printf '%s' "$desc" | grep -qiE "don'?t use (for|to|it for)|not for"; then
    :
  else
    info "$name: description has no narrow-form disambiguation clause (\"don't use for X\") — skills auto-trigger on description match, an unstated boundary is the one most likely to misfire against an adjacent skill"
  fi
done
