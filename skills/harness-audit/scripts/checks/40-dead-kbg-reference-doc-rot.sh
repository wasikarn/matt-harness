#!/usr/bin/env bash
# 40. Dead `kbg:<name>` reference doc-rot (a surface or doc names a `kbg:`
# skill/agent that does not exist in the fleet).
# `kbg:adr` and `kbg:article-mine` were fixed as dead cross-references once
# (v0.8.0) and had to be fixed AGAIN in v0.11.0 — proof a manual sweep alone
# doesn't hold once a surface is renamed/removed. `kbg:` is a distinctive,
# colon-prefixed token (verified: zero prose false-positives across a 30+-name
# repo-wide extraction) unlike bare scaffold words, so — unlike check 38's
# rule (b), which excludes bare words for exactly that collision risk — a
# general regex is safe here. Found by the 2026-07-01 deep-verification audit
# (Missing-Opportunity round). WARN, not CRIT — advisory, matching 37/38.
#
# docs/research/*.md is excluded on purpose (see check 37) — dated
# design/analysis snapshots correctly cite since-renamed surfaces as history.
#
# "former/formerly `kbg:X`" lines are also excluded — an established,
# legitimate convention in this repo for documenting a rename (found live in
# 3 files on first run of this check: skills/harness-audit, skills/incident,
# commands/ship). Same shape as check 37/38's own false-positive guards:
# don't nag on a clean, explicitly-historical pattern.
_known_kbg=$(mktemp)
{
  if [ -d "$CLAUDE_DIR/skills" ]; then
    for d in "$CLAUDE_DIR/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done
  fi
  if [ -d "$CLAUDE_DIR/agents" ]; then
    for f in "$CLAUDE_DIR/agents"/*.md; do [ -f "$f" ] && basename "$f" .md; done
  fi
  if [ -d "$CLAUDE_DIR/commands" ]; then
    for f in "$CLAUDE_DIR/commands"/*.md; do [ -f "$f" ] && basename "$f" .md; done
    for d in "$CLAUDE_DIR/commands"/*/; do [ -f "${d}COMMAND.md" ] && basename "$d"; done
  fi
} | sort -u > "$_known_kbg"
for _f in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/reference.md \
          "$CLAUDE_DIR"/commands/*.md "$CLAUDE_DIR"/commands/*/COMMAND.md \
          "$CLAUDE_DIR"/agents/*.md \
          "$CLAUDE_DIR"/docs/*.md "$CLAUDE_DIR"/docs/agents/*.md \
          "$CLAUDE_DIR"/docs/reference/*.md "$CLAUDE_DIR"/docs/skill-template/*.md \
          "$CLAUDE_DIR"/BOUNDARY.md; do
  [ -f "$_f" ] || continue
  while IFS= read -r _name; do
    [ -z "$_name" ] && continue
    grep -qx "$_name" "$_known_kbg" || \
      warn "dead kbg:-reference in ${_f#"$CLAUDE_DIR"/}: 'kbg:$_name' resolves to no skill/agent/command in the fleet (doc-rot)"
  done < <(grep -viE 'former' "$_f" 2>/dev/null | grep -hoE 'kbg:[a-zA-Z][a-zA-Z0-9_-]*' | sed 's/^kbg://' | sort -u)
done
rm -f "$_known_kbg"
unset _f _name _known_kbg
