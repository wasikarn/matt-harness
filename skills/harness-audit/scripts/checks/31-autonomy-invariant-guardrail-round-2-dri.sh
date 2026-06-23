# 32. Autonomy invariant guardrail — round-2 drill-down (2026-06-12),
# surface-closure 2026-06-16. ADR 0002 names FIVE load-bearing surfaces for the
# invariant; before this closure only surface 3 (the `disable-model-invocation:
# true` frontmatter on recursive-improve) was guarded — and even that silently
# passed when the skill file was deleted (delete the skill -> the guard no-ops
# -> the invariant is unprotected with no flag raised). Surfaces 1/2/4 (the
# prose homes in CONTEXT.md, METHODOLOGY.md, harness-decay-cadence.md) had no
# check at all and could be reworded or removed silently.
#
# Trigger: a repo DECLARES the invariant iff docs/adr/0002-autonomy-invariant.md
# exists. When it does, the self-binding skill must EXIST (not merely match-when-
# present) and every doc surface must keep its load-bearing phrase. When ADR 0002
# is absent (other plugin repos, the audit fixtures) the whole block is skipped —
# the invariant is THIS repo's, not a universal plugin requirement.
#
# Phrase matches are exact (grep -qF) on a single contiguous line, each the most
# invariant-specific wording on its surface, so a careless reword trips the gate.
# If this check fires on a real repo the invariant has regressed and the harness
# is one model-version from self-rewriting — CRIT, not WARN.
#
# Two triggers, deliberately split: surface 3 (the frontmatter flag) is checked
# whenever the skill is PRESENT — this preserves the original guard for any repo
# carrying the skill, regardless of ADR. The deleted-skill hole and the doc
# surfaces 1/2/4 are checked only when the repo DECLARES the invariant (ADR 0002
# present), because absence-as-regression and the prose homes are meaningful
# only for this harness, not every plugin repo that happens to vendor the skill.
RI_SKILL="$CLAUDE_DIR/skills/recursive-improve/SKILL.md"
ADR0002="$CLAUDE_DIR/docs/adr/0002-autonomy-invariant.md"
if [ -f "$RI_SKILL" ]; then
  # Surface 3: present skill must carry the flag in its FRONTMATTER. Read it via
  # fm_get (which parses ONLY the `---` block) rather than the old `head -20 |
  # grep -qF` — the exact phrase "disable-model-invocation: true" also appears in
  # the skill's PROSE (the autonomy-invariant paragraph + the L3 note), so both a
  # line-window grep AND a naive grep-anywhere could pass with the real frontmatter
  # flag deleted. fm_get is frontmatter-anchored AND line-count-independent (a
  # docstring rewrite that pushes the flag past line 20 can no longer break it).
  if [ "$(fm_get "$RI_SKILL" "disable-model-invocation" --block | tr -d ' ')" != "true" ]; then
    crit "skills/recursive-improve/SKILL.md: missing 'disable-model-invocation: true' in frontmatter (autonomy invariant regressed — see CONTEXT.md §Invariants + ADR 0002)"
  fi
elif [ -f "$ADR0002" ]; then
  # Deleted-skill hole: ADR declares the invariant but the self-binding skill is
  # gone — deleting it silently no-opped the old guard. That deletion IS the regression.
  crit "autonomy invariant: ADR 0002 present but skills/recursive-improve/SKILL.md is MISSING — deleting the self-binding skill no-ops the guard (ADR 0002 surface 3)"
fi
if [ -f "$ADR0002" ]; then
  # Surfaces 1/2/4: each doc surface must exist and keep its load-bearing phrase.
  while IFS='|' read -r _label _rel _phrase; do
    [ -n "$_label" ] || continue
    _f="$CLAUDE_DIR/$_rel"
    if [ ! -f "$_f" ]; then
      crit "autonomy invariant: ADR 0002 present but $_rel is MISSING ($_label — ADR 0002)"
    elif ! grep -qF "$_phrase" "$_f"; then
      crit "autonomy invariant: $_rel dropped its load-bearing phrase \"$_phrase\" ($_label — ADR 0002)"
    fi
  done <<'AUTONOMY_SURFACES'
surface 1 CONTEXT §Invariants|CONTEXT.md|unattended self-repair loop
surface 2 METHODOLOGY Rule 4|METHODOLOGY.md|every loop terminates at a human gate
surface 4 decay-cadence|docs/harness-decay-cadence.md|autonomous self-rewriter
AUTONOMY_SURFACES
fi
# 32b (additive, design §8 + #32): the caged, flag-gated launcher is the ONLY
# sanctioned self-start. The recursive-improve frontmatter assertion above is
# UNCHANGED + keeps firing — the OS scheduler (launchd), not the model, self-starts
# the launcher, so disable-model-invocation: true is NOT contradicted. This leg ADDS:
# (a) scripts/l4/launch.sh exists + reads the caged scheduler.conf + honors the
# kill-file; (b) no unsanctioned self-start primitive (CronCreate / crontab) lurks in
# hooks/ or scripts/ outside scripts/l4/**. Gated on ADR 0004 (L4 machinery).
_ADR0004_32="$CLAUDE_DIR/docs/adr/0004-l4-autonomy.md"
if [ -f "$_ADR0004_32" ]; then
  _LAUNCH="$CLAUDE_DIR/scripts/l4/launch.sh"
  if [ ! -f "$_LAUNCH" ]; then
    crit "autonomy invariant (#32b): scripts/l4/launch.sh missing — the caged, flag-gated self-launch launcher is absent (design §8, ADR 0004 #1)"
  else
    _lsrc=$(grep -vE '^[[:space:]]*#' "$_LAUNCH" 2>/dev/null)
    printf '%s\n' "$_lsrc" | grep -qF 'scheduler.conf' || crit "autonomy invariant (#32b): launch.sh does not read the caged scheduler.conf (design §8 — config only from the cage)"
    printf '%s\n' "$_lsrc" | grep -qF 'KILLFILE' || crit "autonomy invariant (#32b): launch.sh does not honor the kill-file (design §8 kill-switch)"
  fi
  _strays=$(grep -rnE 'CronCreate|crontab' "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/scripts" 2>/dev/null \
            | grep -vE 'scripts/l4/|:.*#|\.pyc' || true)
  if [ -n "$_strays" ]; then
    crit "autonomy invariant (#32b): unsanctioned self-start primitive (CronCreate/crontab) outside scripts/l4/ — the caged launcher is the sole sanctioned self-start (design §8): $_strays"
  fi
fi

