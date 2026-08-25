#!/usr/bin/env bash
# 47. Skill disambiguation clause — every skill description should carry a
# narrow-form "Don't use for X" boundary clause. This is the fleet's own
# de-facto anti-duplication convention (30/30 skills currently follow it,
# previously unenforced) — see the `review-prompt-duplication-pattern`
# memory for the one confirmed incident this class of gap produced. Skills
# auto-trigger on description match, so a skill with no stated boundary is
# the one most likely to misfire against an adjacent skill's territory.
#
# Matcher is narrow-form only: "don't use for" / "don't use to" /
# "don't use it for". Deliberately excludes loose forms like "; not X",
# "— not X", or a bare "not for" — those match any prose containing the
# tokens, not just a boundary statement, and would report conformance the
# check isn't actually measuring. That's the same trap check 34's retired
# failure-mode proxy fell into (2026-07-16): a permissive regex is worse
# than no check. A bare "not for" alternative shipped in v0.68.122 and was
# removed in a compliance-audit remediation the same day (2026-08-01) after
# an adversarial verifier found it live-matched ordinary prose ("this
# dashboard is not for production traffic") with no real boundary clause —
# confirmed dead weight first: 0/30 conformant skills relied on it standalone,
# every one already matches via "don't use for/to/it for".
#
# INFO only, matching check 34's stated policy (per the
# harness-audit-gauntlet-policy memory): doctrine-conformance, not doc-rot —
# the WARN/CRIT escalation trap is deliberately rejected for this class of
# advisory signal.
#
# Scope: skills only. Agents and commands are dispatched deliberately by a
# parent, not auto-triggered on description match, so the failure mode this
# check guards against doesn't apply to them the same way (a fleet-wide
# survey found only 2/19 agents and 14/19 commands conformant — enforcing
# there would be mostly low-value noise, not a signal).
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  name=$(basename "$(dirname "$f")")

  desc=$(fm_get "$f" "description" --block)

  if printf '%s' "$desc" | grep -qiE "don'?t use (for|to|it for)"; then
    :
  else
    info "$name: description has no narrow-form disambiguation clause (\"don't use for X\") — skills auto-trigger on description match, an unstated boundary is the one most likely to misfire against an adjacent skill"
  fi
done
