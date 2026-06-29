# 32. Autonomy invariant guardrail — round-2 drill-down (2026-06-12),
# surface-closure 2026-06-16. the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model names FIVE load-bearing surfaces for the
# invariant; before this closure only surface 3 (the `disable-model-invocation:
# true` frontmatter on recursive-improve) was guarded — and even that silently
# passed when the skill file was deleted (delete the skill -> the guard no-ops
# -> the invariant is unprotected with no flag raised). Surfaces 1/2/4 (the
# prose homes in CONTEXT.md, METHODOLOGY.md, harness-decay-cadence.md) had no
# check at all and could be reworded or removed silently.
#
# RETIRED 2026-06-25 — surfaces 1/2/4 + the deleted-skill-hole leg + the #32b
# CLAUDE.md §The operating model (was L4 self-launch, retired) leg retired (CLAUDE.md §The operating model (current) supersedes 0002/0003/0004/0005; the autonomy
# machinery is deleted in Batch 2). The ADRs are append-only, so the ADR-gated
# legs are no-op'd DIRECTLY here rather than relying on ADR absence.
#
# KEPT LIVE — surface 3 (the recursive-improve frontmatter
# `disable-model-invocation: true` CRIT): the self-binding skill keeps the flag,
# so this guard keeps passing. It is checked whenever the skill is PRESENT,
# regardless of ADR — the frontmatter flag is the one code-level guard that
# survives the autonomy machinery deletion. fm_get parses ONLY the `---` block
# so a docstring rewrite pushing the flag past line 20 cannot break it, and the
# exact phrase appearing in the prose cannot false-pass it.
RI_SKILL="$CLAUDE_DIR/skills/recursive-improve/SKILL.md"
if [ -f "$RI_SKILL" ]; then
  if [ "$(fm_get "$RI_SKILL" "disable-model-invocation" --block | tr -d ' ')" != "true" ]; then
    crit "skills/recursive-improve/SKILL.md: missing 'disable-model-invocation: true' in frontmatter (autonomy invariant regressed — see CONTEXT.md §Invariants + the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model)"
  fi
fi
info "audit #32: RETIRED 2026-06-25 — surfaces 1/2/4 + deleted-skill-hole + #32b CLAUDE.md §The operating model (was L4 self-launch, retired) legs retired (CLAUDE.md §The operating model (current) supersedes 0002/0003/0004/0005); surface 3 stays live" 2>/dev/null || true