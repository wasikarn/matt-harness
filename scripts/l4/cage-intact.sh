#!/usr/bin/env bash
# cage-intact.sh — the cage-completeness core (audit #43a/43b/43d), extracted as a
# standalone (design §5 R3) so both audit.sh #43 and the loop-guard's per-cycle
# --assert-cage-intacent call ONE implementation (no sync-seam — the anchor list
# lives here, once). Exits with the CRIT count (0 = clean). Gated on ADR 0003: a
# tree that does not declare L3 skips (exit 0), mirroring audit #43's gate. CRIT
# lines are prefixed "CRIT: " so audit.sh #43 can relay them through its own crit().
#
# Usage: bash cage-intact.sh <repo-root>
# Fail-closed for R3: a shell-out error or non-zero exit in the caller (the loop-
# guard precheck) is treated as a failed safety check → STOP the cycle.
set -uo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "CRIT: cage-intact: missing <repo-root> arg" >&2
  exit 2
fi
# Layout: dotfiles nests the harness under claude/; the kbg-harness plugin repo is
# flat (agents/, skills/, … at the root). Resolve CLAUDE_DIR to whichever holds
# the fleet so one script serves both checkouts (mirrors audit.sh line 27).
if [ -d "$REPO/claude" ]; then
  CLAUDE_DIR="$REPO/claude"
else
  CLAUDE_DIR="$REPO"
fi
ADR0003="$CLAUDE_DIR/docs/adr/0003-l3-bounded-autonomy.md"
CAGE="$CLAUDE_DIR/scripts/l3-cage.txt"

CRIT_COUNT=0
crit() { printf 'CRIT: %s\n' "$1"; CRIT_COUNT=$((CRIT_COUNT + 1)); }

# Not an L3-declaring tree (other plugin repos + audit fixtures) → skip, exit 0.
[ -f "$ADR0003" ] || exit 0

# 43a: cage file present + non-empty (after stripping comments/blanks).
if [ ! -f "$CAGE" ]; then
  crit "L3 cage missing: scripts/l3-cage.txt absent but ADR 0003 declares L3 (the loop would run uncaged — ADR 0003 §Three rails)"
elif [ -z "$(grep -vE '^[[:space:]]*(#|$)' "$CAGE")" ]; then
  crit "L3 cage empty: scripts/l3-cage.txt has no entries — a deny-by-default cage with nothing in it denies nothing (fail-closed expects entries)"
else
  # 43b: cage must cover the load-bearing anchors. _CAGE_ANCHORS is the SINGLE
  # source for the curated anchor set; 43b checks anchors⊆cage (directional), 43d
  # checks the L4 members are in BOTH surfaces (bidirectional). Add a path here AND
  # to scripts/l3-cage.txt in lockstep.
  _CAGE_ANCHORS="scripts/l3-cage.txt
scripts/l3-loop-guard.py
hooks/**
tests/hooks/runners/**
skills/harness-audit/scripts/audit.sh
skills/_lib/**
scripts/run-gauntlet.sh
eval/run-eval.py
scripts/evals/**
scripts/plan_linter/**
eval/datasets/**
eval/regressions/**
tests/evals/**
scripts/l4/**
.claude/settings.local.json
docs/adr/**
CLAUDE.md
METHODOLOGY.md
RTK.md
ACLI.md
DBGATE.md
CONTEXT.md
DOMAINS.md
.git/config
.git/hooks/**
git-hooks/**
.claude-plugin/plugin.json
.claude-plugin/marketplace.json"
  _missing=""
  while IFS= read -r _anchor; do
    [ -n "$_anchor" ] || continue
    grep -qxF "$_anchor" "$CAGE" || _missing="$_missing $_anchor"
  done <<<"$_CAGE_ANCHORS"
  [ -z "$_missing" ] || crit "L3 cage incomplete: scripts/l3-cage.txt is missing required safety anchor(s):$_missing (the loop could edit these to escape — ADR 0003 §Cage redesign)"
  # 43d: L4 cage↔anchor lockstep (design §5 F2/F3 blocker). #43b is directional
  # (anchors⊆cage), so a path added to the cage but missing from CAGE_ANCHORS passes
  # SILENTLY; the L4 anchors must appear in BOTH surfaces. Quoted to defeat globstar.
  for _a in 'eval/regressions/**' 'tests/evals/**' 'scripts/l4/**' '.claude/settings.local.json'; do
    _ic=0; _ia=0
    if grep -qxF "$_a" "$CAGE"; then _ic=1; fi
    if printf '%s\n' "$_CAGE_ANCHORS" | grep -qxF "$_a"; then _ia=1; fi
    [ "$_ic$_ia" = "11" ] || crit "L4 cage↔anchor drift: '$_a' in cage:$_ic / anchors:$_ia — must be in BOTH scripts/l3-cage.txt and the #43 CAGE_ANCHORS set (design §5 F2/F3; a one-sided add silently un-cages a path)"
  done
fi

exit $CRIT_COUNT