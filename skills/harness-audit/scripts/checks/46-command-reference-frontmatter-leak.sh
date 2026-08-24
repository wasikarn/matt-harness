#!/usr/bin/env bash
# 46. Reference-file frontmatter leak (commands/ and skills/).
#
# A directory-form command (`commands/<name>/COMMAND.md` + a `references/`
# subfolder, e.g. `ship`/`ideate`) or a skill's `references/` subfolder
# (`incident`, `memory-lint`, `harness-audit`, etc.) is meant to keep its
# supporting files inert — read only via an explicit path pointer in the
# parent COMMAND.md/SKILL.md's prose, never invoked on their own. Confirmed
# via a live `claude -p "..." --debug-file <path>` capture (2026-07-20
# commands/deep-research pass): `commands/ship/references/classify.md` and
# `pre-ship-verify.md`, both carrying their own `name:`/`description:`
# frontmatter, loaded as fully independent skills
# (`kbg:ship:references:classify`, userFacingName="ship-classify") even
# though `/ship` only ever reads them by file path. `commands/ideate/
# references/frames.md` carries no frontmatter and correctly did NOT leak —
# proving the rule is precise: any `.md` under `commands/` (other than a
# command's own `COMMAND.md` entrypoint) that carries a `description:` in
# frontmatter becomes its own accidental command, regardless of directory
# nesting or author intent. Widened to `skills/*/references/*.md` 2026-08-17
# (deep-audit pass) after `skills/harness-audit/references/health.md` was
# found carrying the identical `name:`/`description:` shape, unguarded — the
# same failure mode, just under skills/ instead of commands/.
#
# WARN (not CRIT): a real but non-catastrophic namespace/token-budget leak —
# not the tamper-sensitive class checks 39/44 CRIT-guard.
shopt -s nullglob
_leak_candidates=("$CLAUDE_DIR"/commands/*/*.md "$CLAUDE_DIR"/commands/*/*/*.md "$CLAUDE_DIR"/skills/*/references/*.md)
shopt -u nullglob
for _f in "${_leak_candidates[@]}"; do
  [ -f "$_f" ] || continue
  case "$(basename "$_f")" in COMMAND.md|SKILL.md) continue ;; esac
  grep -q '^---' "$_f" || continue
  if [ -n "$(fm_get "$_f" "description" --block)" ]; then
    warn "reference file ${_f#"$CLAUDE_DIR"/} carries frontmatter with a description: — Claude Code loads it as an independent command/skill, not inert supporting material (strip the frontmatter, matching commands/ideate/references/frames.md's shape, or move the file outside commands/ or skills/)"
  fi
done
unset _f _leak_candidates
