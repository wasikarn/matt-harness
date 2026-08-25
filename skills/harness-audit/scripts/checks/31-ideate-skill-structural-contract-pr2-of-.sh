#!/usr/bin/env bash
# 31. ideate skill — structural contract (PR2 of ideate-adhd-port). The
# surface is now `mh:ideate`, ported from the upstream ADHD skill
# (docs/research/kbg-vs-adhd.md). The structural contract must hold or the next
# refactor will silently collapse the algorithm (the 2026-06-12 44→105-agent
# failure mode that bounded-agent-spawning.md was written to prevent). WARNs
# (not CRITs) on missing pieces. This check IS the sole guard now — the
# former regression fixture eval/regressions/ideate-fanout-cap.json (and the
# whole eval/ tree) was deleted in the 2026-06-27 owner-authorized reset
# (c452102); this check survived as the inline editor / pre-commit guard.
#
# Repointed from commands/ideate/COMMAND.md to skills/ideate/SKILL.md
# 2026-08-25 (#104, commands→skills convergence, spec #101).
#
# On the disable-model-invocation assertion: #104's own ticket text assumed
# "a skill's default behavior for automatic invocation is the opposite of a
# command's" and asked for the assertion to be re-decided, not mechanically
# repointed. Checked against actual evidence in this repo (checks 30/55 read
# disable-model-invocation via ONE shared code path with no branch on
# commands/ vs skills/ origin, and ideate already relied on this exact
# `false` flag to auto-fire AS A COMMAND before this move) — the premise
# doesn't hold. The flag's meaning is identical either way; converting to a
# skill changes nothing about what `false` does. What DOES change: `false`
# is a skill's *default* value (redundant if merely present), so the
# structural-contract risk here isn't "assert the wrong value" — the
# assertion was always correct — it's "a future cleanup pass drops the
# now-seemingly-redundant explicit `false`+reason pair, losing the
# documented deliberate-opt-in intent it exists to preserve as a
# self-documenting decision, not to change runtime behavior." So this check
# now additionally requires the reason field, which is not otherwise checked
# anywhere else in the fleet.
IDEATE_CMD="$CLAUDE_DIR/skills/ideate/SKILL.md"
if [ -f "$IDEATE_CMD" ]; then
  if [ -z "$(fm_get "$IDEATE_CMD" "name" --block)" ]; then
    warn "ideate skill missing 'name:' in frontmatter"
  elif [ "$(fm_get "$IDEATE_CMD" "name" --block | tr -d ' ')" != "ideate" ]; then
    warn "ideate skill frontmatter name mismatch"
  fi
  if [ "$(fm_get "$IDEATE_CMD" "disable-model-invocation" --block | tr -d ' ')" != "false" ]; then
    warn "ideate skill must have disable-model-invocation: false (user opted in to auto-fire on vague open-ended prompts; F8.5 orchestrate is the actual cap)"
  elif [ -z "$(fm_get "$IDEATE_CMD" "disable-model-invocation-reason" --block)" ]; then
    warn "ideate skill has disable-model-invocation: false with no -reason field — for a skill this value is the default, so without the reason field a future edit could drop the explicit declaration and silently lose the documented deliberate-opt-in intent"
  fi
  for sec in "## Pre-flight gate" "## Phase 1" "## Phase 2" "## Frames table" "## 3-axis scoring rubric" "## Isolation invariant"; do
    if ! /usr/bin/grep -qF "$sec" "$IDEATE_CMD"; then
      warn "ideate skill missing required section: $sec (PR2 contract; locks the 2-wave algorithm shape)"
    fi
  done
else
  warn "skills/ideate/SKILL.md missing — ideate port not landed"
fi
