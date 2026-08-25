#!/usr/bin/env bash
# 46. Skill cited in slash form (should be `mh:<name>`, never `/<name>`).
# docs/skill-authoring-conventions.md's "Suggested next step footers" section
# (referenced, not duplicated, from CLAUDE.md's Skill authoring doctrine —
# confirmed 2026-08-20 no such section lives in CLAUDE.md itself) documents
# this exact bug shipping TWICE before a manual survey caught it (v0.35.0: `commands/pr.md`,
# `diagnosing-bugs/SKILL.md`) — and it noted check 37 structurally can't see
# it, since check 37's regex only fires on the `mh:` token to begin with. A
# skill mis-cited as `` `/name` `` reads as a real command to anyone following
# the doc; the doctrine ("Skills are ALWAYS cited `mh:`-form") is stated but
# nothing enforced it. Found a THIRD live instance while building this check
# (`commands/post-mortem.md`, citing `` `/incident` `` — `incident` is
# skill-only, no command counterpart) — fixed alongside this guard.
#
# Scope: only backtick-wrapped, bare `` `/name` `` spans (nothing else inside
# the backticks) — excludes file paths (`` `/Users/...` ``) and doc paths
# (`` `/orchestrate/SKILL.md` ``), which have more content before the closing
# backtick. `name` must match a known skill — the former dual check against a
# `commands/` namespace was dropped 2026-08-25 (#112): commands/ retired for
# good, so every `name` match is a skill by construction now. "former/removed" lines are excluded,
# mirroring checks 35/37's guard for legitimate historical references (a
# skill can share a name with a command retired long ago — confirmed live:
# docs/reference/hook-lifecycle-contracts.md's "the removed `/learn` command").
# WARN, not CRIT — advisory, matching 35/37 (the old check 38 covering the
# same class was retired 2026-08-25, ticket 87).
# Sets built once; lookups below are pure-bash array membership (was: two
# `grep -qx` re-scans per cited name).
declare -A _known_skills50=()
if [ -d "$CLAUDE_DIR/skills" ]; then
  while IFS= read -r _k; do [ -n "$_k" ] && _known_skills50["$_k"]=1; done < <(
    for d in "$CLAUDE_DIR/skills"/[!_]*/; do
      [ -d "$d" ] || continue
      case "$(basename "$d")" in *-workspace) continue ;; esac  # gitignored iterate-skill scratch dirs, not real skills
      basename "$d"
    done | sort -u)
fi
for _f in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/reference.md \
          "$CLAUDE_DIR"/agents/*.md \
          "$CLAUDE_DIR"/docs/*.md "$CLAUDE_DIR"/docs/agents/*.md \
          "$CLAUDE_DIR"/docs/reference/*.md "$CLAUDE_DIR"/docs/skill-template/*.md \
          "$CLAUDE_DIR"/BOUNDARY.md; do
  [ -f "$_f" ] || continue
  while IFS= read -r _name; do
    [ -z "$_name" ] && continue
    [ -n "${_known_skills50[$_name]:-}" ] || continue
    warn "skill cited in slash form in ${_f#"$CLAUDE_DIR"/}: '/$_name' should be 'mh:$_name' — '$_name' is a skill, not a command (doc-rot, misleads readers)"
  done < <(grep -viE 'former|removed' "$_f" 2>/dev/null | grep -hoE '`/[a-zA-Z][a-zA-Z0-9_-]*`' | tr -d '`/' | sort -u)
done
unset _f _name _known_skills50
