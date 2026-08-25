#!/usr/bin/env bash
# 37. Dead `mh:<name>` reference doc-rot (a surface or doc names an `mh:`
# skill/agent that does not exist in the fleet).
# `kbg:adr` and `kbg:article-mine` were fixed as dead cross-references once
# (v0.8.0) and had to be fixed AGAIN in v0.11.0 — proof a manual sweep alone
# doesn't hold once a surface is renamed/removed. Renamed from
# 37-dead-kbg-reference-doc-rot.sh at the `kbg`->`mh` namespace rename (T10
# #89) — the live invocation prefix is `mh:` now, so that is what this check
# watches for dead references against, going forward.
# Anchored, not a bare substring match: `kbg:` was long enough (4 chars incl.
# colon) to be a distinctive token with zero prose false-positives across a
# 30+-name repo-wide extraction, but `mh:` is only 2 letters — an unanchored
# `grep -oE 'mh:...'` would also match the tail of any longer token ending in
# those two letters immediately before a colon (e.g. a word or path segment
# ending "...mh:"). The `(^|[^a-zA-Z0-9_-])` alternation requires whatever
# precedes `mh:` to be start-of-line or a non-identifier character, so a
# same-line prefix like that can't produce a false match. Re-verified
# zero-false-positive on this repo's own corpus after the rename (2026-08-25).
# Found by the 2026-07-01 deep-verification audit (Missing-Opportunity
# round). WARN, not CRIT — advisory, matching 35.
#
# docs/research/*.md is excluded on purpose (see check 35) — dated
# design/analysis snapshots correctly cite since-renamed surfaces as history.
#
# "former/formerly `mh:X`" lines are also excluded — an established,
# legitimate convention in this repo for documenting a rename (found live in
# 3 files on first run of this check: skills/harness-audit, skills/incident,
# and the now-removed commands/ship). Same shape as check 35's own
# false-positive guards: don't nag on a clean, explicitly-historical pattern.
#
# Scan list widened 2026-08-17 (deep-audit pass) to include the
# `skills/*/references/*.md` and `commands/*/references/*.md` subfolder
# convention several skills/commands adopted for their oversized-file split
# — the prior list only covered `skills/*/reference.md` (singular,
# pre-dating that convention), so a dead `mh:` citation inside one of these
# subfolder files could have gone unseen with no functional signal.
# Set built once; lookups below are pure-bash array membership (was: one
# `grep -qx` re-scan of this list per referenced name).
declare -A _known_mh=()
while IFS= read -r _k; do [ -n "$_k" ] && _known_mh["$_k"]=1; done < <({
  if [ -d "$CLAUDE_DIR/skills" ]; then
    for d in "$CLAUDE_DIR/skills"/[!_]*/; do
      [ -d "$d" ] || continue
      case "$(basename "$d")" in *-workspace) continue ;; esac  # gitignored iterate-skill scratch dirs, not real skills
      basename "$d"
    done
  fi
  if [ -d "$CLAUDE_DIR/agents" ]; then
    for f in "$CLAUDE_DIR/agents"/*.md; do [ -f "$f" ] && basename "$f" .md; done
  fi
} | sort -u)
for _f in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/reference.md \
          "$CLAUDE_DIR"/skills/*/references/*.md \
          "$CLAUDE_DIR"/agents/*.md \
          "$CLAUDE_DIR"/docs/*.md "$CLAUDE_DIR"/docs/agents/*.md \
          "$CLAUDE_DIR"/docs/reference/*.md "$CLAUDE_DIR"/docs/skill-template/*.md \
          "$CLAUDE_DIR"/BOUNDARY.md; do
  [ -f "$_f" ] || continue
  while IFS= read -r _name; do
    [ -z "$_name" ] && continue
    [ -n "${_known_mh[$_name]:-}" ] || \
      warn "dead mh:-reference in ${_f#"$CLAUDE_DIR"/}: 'mh:$_name' resolves to no skill/agent/command in the fleet (doc-rot)"
  done < <(grep -viE 'former' "$_f" 2>/dev/null | grep -ohE '(^|[^a-zA-Z0-9_-])mh:[a-zA-Z][a-zA-Z0-9_-]*' | sed -E 's/^.*mh://' | sort -u)
done
unset _f _name _known_mh
