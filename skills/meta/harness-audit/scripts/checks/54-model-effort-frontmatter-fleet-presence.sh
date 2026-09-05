#!/usr/bin/env bash
# 54. Fleet model:/effort: frontmatter — every surface entrypoint carries both keys.
#
# Convention: docs/reference/skill-authoring-conventions.md "Explicit model: + effort: on
# every surface (fleet convention, v0.68.430)" — all agents/*.md and
# skills/*/SKILL.md ship with explicit model: and
# effort:. This check enforces presence + value sanity, deliberately NOT the
# per-surface tier map: tiers are a judgment call that legitimately changes
# with a version bump, and freezing them here would turn every retier into a
# two-file edit for zero drift-catch value.
#
#   - either key missing               -> WARN (a new/edited surface dropped the convention)
#   - effort not low|medium|high|xhigh|max -> WARN
#   - skill/command model != inherit   -> WARN unless the surface runs context: fork
#     (a concrete pin on a main-thread surface switches the session model for the
#     REST OF THE TURN — official skills.md frontmatter reference)
#
# Agent model VALUES are check 21's job — only presence is checked here.
# skills/*/references/*.md fragments stay unstamped by design (check 42 owns
# the reference-file frontmatter class).
#
# WARN (not CRIT): convention drift, not the tamper-sensitive class 36/40/45 guard.
shopt -s nullglob
_me_files=("$CLAUDE_DIR"/agents/*.md "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/*/SKILL.md)
shopt -u nullglob
for _f in "${_me_files[@]}"; do
  [ -f "$_f" ] || continue
  _rel="${_f#"$CLAUDE_DIR"/}"
  _model=$(fm_get "$_f" "model" --block)
  _effort=$(fm_get "$_f" "effort" --block)
  [ -n "$_model" ] || warn "surface $_rel missing explicit model: frontmatter (fleet convention v0.68.430 — every surface carries model: + effort:)"
  if [ -z "$_effort" ]; then
    warn "surface $_rel missing explicit effort: frontmatter (fleet convention v0.68.430 — every surface carries model: + effort:)"
  else
    case "$_effort" in
      low|medium|high|xhigh|max) ;;
      *) warn "surface $_rel effort='$_effort' is not a documented tier (low|medium|high|xhigh|max)" ;;
    esac
  fi
  case "$_rel" in
    agents/*) ;; # value validation for agents is check 21's job
    *)
      if [ -n "$_model" ] && [ "$_model" != "inherit" ] && [ "$(fm_get "$_f" "context" --block)" != "fork" ]; then
        warn "skill/command $_rel pins model: '$_model' on a main-thread surface — that switches the session model for the rest of the turn; use model: inherit (or context: fork if the pin is deliberate)"
      fi
      ;;
  esac
done
unset _f _rel _model _effort _me_files
