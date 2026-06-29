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
# CRIT): a missing reason is a doc gap, not a safety regression — the one
# safety-load-bearing flag (recursive-improve) is CRIT-guarded by #32.
for f in "$CLAUDE_DIR/commands"/*.md "$CLAUDE_DIR/skills"/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  head -20 "$f" | grep -qF 'disable-model-invocation: true' || continue
  _nm=$(basename "$f" .md); case "$f" in */SKILL.md) _nm=$(basename "$(dirname "$f")") ;; esac
  if [ -z "$(fm_get "$f" "disable-model-invocation-reason" --block)" ]; then
    warn "'$_nm': disable-model-invocation: true without a 'disable-model-invocation-reason:' — record WHY this surface is user-only (per-surface, not blanket; CLAUDE.md selection criterion)"
  fi
done

