#!/usr/bin/env bash
# 30. disable-model-invocation must carry a documented reason (DETERMINISTIC).
# The flag is a per-surface judgment (CLAUDE.md selection criterion); a flag
# WITHOUT a recorded reason is an undocumented decision — and in practice the
# audit found these were often dir-of-origin residue ("all commands flagged")
# rather than a real per-surface call. This is a presence check (NOT a semantic
# judge): every `disable-model-invocation: true` surface must also carry a
# non-empty `disable-model-invocation-reason:`. It HAS teeth (any unreasoned flag
# WARNs and can fail) — unlike the prior reporter-shape heuristic it replaced,
# which matched zero real flagged surfaces (a Rule-9 test that could not fail).
# Appropriateness stays semantic + advisory (human review of the reasons); this
# check only enforces that the reason EXISTS, which is deterministic. WARN (not
# CRIT): a missing reason is a doc gap, not a safety regression — all 10
# disable-model-invocation carriers are CRIT-guarded against the flag itself
# disappearing by checks #36, #40, #45, #58-64.
#
# Frontmatter-scoped (fm_get), not a raw substring grep over the first 20
# lines — same hardening #36/#40/#45/#58-64 carry: `head -20 | grep -qF`
# false-negatives if the literal string appears anywhere in the first 20
# lines (e.g. inside `description:` prose) even when the real frontmatter
# key was stripped. Was the last of the four to still carry the old idiom
# (fixed 2026-08-30, alongside checks 58-64): a stripped flag whose
# description prose still contains the literal string would otherwise let
# this check's loop body run and WARN "missing reason" on a skill that no
# longer carries the flag at all — noise stacked on the CRIT the new checks
# already raise. fm_get matches `^key:` inside the real `---...---` block
# only, so this check now correctly stays silent once the flag is gone.
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  [ "$(fm_get "$f" disable-model-invocation)" = "true" ] || continue
  _nm=$(basename "$f" .md); case "$f" in */SKILL.md) _nm=$(basename "$(dirname "$f")") ;; esac
  if [ -z "$(fm_get "$f" "disable-model-invocation-reason" --block)" ]; then
    warn "'$_nm': disable-model-invocation: true without a 'disable-model-invocation-reason:' — record WHY this surface is user-only (per-surface, not blanket; CLAUDE.md selection criterion)"
  fi
done

