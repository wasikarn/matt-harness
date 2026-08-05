#!/usr/bin/env bash
# 50. Skill cited in slash form (should be `kbg:<name>`, never `/<name>`).
# CLAUDE.md's "Suggested next step footers" section documents this exact bug
# shipping TWICE before a manual survey caught it (v0.35.0: `commands/pr.md`,
# `diagnosing-bugs/SKILL.md`) — and it noted check 40 structurally can't see
# it, since check 40's regex only fires on the `kbg:` token to begin with. A
# skill mis-cited as `` `/name` `` reads as a real command to anyone following
# the doc; the doctrine ("Skills are ALWAYS cited `kbg:`-form") is stated but
# nothing enforced it. Found a THIRD live instance while building this check
# (`commands/post-mortem.md`, citing `` `/incident` `` — `incident` is
# skill-only, no command counterpart) — fixed alongside this guard.
#
# Scope: only backtick-wrapped, bare `` `/name` `` spans (nothing else inside
# the backticks) — excludes file paths (`` `/Users/...` ``) and doc paths
# (`` `/orchestrate/SKILL.md` ``), which have more content before the closing
# backtick. `name` must match a known skill AND NOT also be a known command —
# skill/command namespaces don't currently overlap, but the dual check keeps
# this correct if that ever changes. "former/removed" lines are excluded,
# mirroring check 40/37/38's guard for legitimate historical references (a
# skill can share a name with a command retired long ago — confirmed live:
# docs/reference/hook-lifecycle-contracts.md's "the removed `/learn` command").
# WARN, not CRIT — advisory, matching 37/38/40.
# Sets built once; lookups below are pure-bash array membership (was: two
# `grep -qx` re-scans per cited name).
declare -A _known_skills50=()
if [ -d "$CLAUDE_DIR/skills" ]; then
  while IFS= read -r _k; do [ -n "$_k" ] && _known_skills50["$_k"]=1; done < <(
    for d in "$CLAUDE_DIR/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done | sort -u)
fi
declare -A _known_commands50=()
while IFS= read -r _k; do [ -n "$_k" ] && _known_commands50["$_k"]=1; done < <({
  if [ -d "$CLAUDE_DIR/commands" ]; then
    for f in "$CLAUDE_DIR/commands"/*.md; do [ -f "$f" ] && basename "$f" .md; done
    for d in "$CLAUDE_DIR/commands"/*/; do [ -f "${d}COMMAND.md" ] && basename "$d"; done
  fi
} | sort -u)
for _f in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/reference.md \
          "$CLAUDE_DIR"/commands/*.md "$CLAUDE_DIR"/commands/*/COMMAND.md \
          "$CLAUDE_DIR"/agents/*.md \
          "$CLAUDE_DIR"/docs/*.md "$CLAUDE_DIR"/docs/agents/*.md \
          "$CLAUDE_DIR"/docs/reference/*.md "$CLAUDE_DIR"/docs/skill-template/*.md \
          "$CLAUDE_DIR"/BOUNDARY.md; do
  [ -f "$_f" ] || continue
  while IFS= read -r _name; do
    [ -z "$_name" ] && continue
    [ -n "${_known_skills50[$_name]:-}" ] || continue
    [ -n "${_known_commands50[$_name]:-}" ] && continue
    warn "skill cited in slash form in ${_f#"$CLAUDE_DIR"/}: '/$_name' should be 'kbg:$_name' — '$_name' is a skill, not a command (doc-rot, misleads readers)"
  done < <(grep -viE 'former|removed' "$_f" 2>/dev/null | grep -hoE '`/[a-zA-Z][a-zA-Z0-9_-]*`' | tr -d '`/' | sort -u)
done
unset _f _name _known_skills50 _known_commands50
