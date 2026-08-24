#!/usr/bin/env bash
# audit.sh — automated health check for the custom Claude Code ecosystem.
# Usage: bash audit.sh [<repo-root>] [--plugin-cache <path>]
# Exit code = number of findings (0 = clean).
set -euo pipefail
# bash >= 4 required (#93): globstar (below) and five checks' `declare -A`
# are bash-4 features — on stock macOS bash 3.2 the run would otherwise die
# mid-audit with an unexplained rc=127. Refuse up front with the fix named.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "audit.sh: needs bash >= 4 (this is bash ${BASH_VERSION}); stock macOS ships 3.2 — brew install bash" >&2
  exit 1
fi
# Hooks moved into subdirs (gates/, advisory/, lifecycle/, …); the per-hook
# checks (#3/#11/#29) and the Fleet count must recurse, not glob top-level —
# else they silently scan 0 of ~36 real hooks (green-because-empty).
shopt -s globstar

# Parse args. Positional [<repo-root>] first; optional --plugin-cache <path>
# second. Keep backward-compat: a single arg is treated as repo-root (the old
# call shape `bash audit.sh <repo>` still works).
REPO_ROOT=""
PLUGIN_CACHE_ARG=""
ONLY_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-cache) PLUGIN_CACHE_ARG="${2:-}"; shift 2 ;;
    --plugin-cache=*) PLUGIN_CACHE_ARG="${1#--plugin-cache=}"; shift ;;
    --only) ONLY_ID="${2:-}"; shift 2 ;;
    --only=*) ONLY_ID="${1#--only=}"; shift ;;
    *) [ -z "$REPO_ROOT" ] && REPO_ROOT="$1"; shift ;;
  esac
done
REPO_ROOT="${REPO_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# Layout: dotfiles nests the harness under claude/; the extracted matt-harness
# plugin repo is flat (agents/, skills/, … at the root). Resolve CLAUDE_DIR to
# whichever holds the fleet so one audit.sh serves both checkouts.
if [ -d "$REPO_ROOT/claude" ]; then
  CLAUDE_DIR="$REPO_ROOT/claude"
else
  CLAUDE_DIR="$REPO_ROOT"
fi
# SETTINGS + MEMORY_DIR are read by sourced checks; shellcheck can't see across
# the sourced-files boundary and flags both as unused. Disable SC2034 here.
# shellcheck disable=SC2034
SETTINGS="$CLAUDE_DIR/settings.json"
# MEMORY_DIR is the per-project auto-memory dir Claude Code itself uses —
# keyed by git-repo path with "/" replaced by "-" (code.claude.com/docs/en/
# memory.md:358, confirmed 2026-08-20: "derived from the git repository").
# The prior formula here never resolved to a real path (stripped the literal
# substring "claude" out of REPO_ROOT, then keyed by "_" not "-"), so check 13
# (13-memory-index-drift.sh), the only consumer, silently read nothing every
# run.
# shellcheck disable=SC2034
MEMORY_DIR="$HOME/.claude/projects/${REPO_ROOT//\//-}/memory"

# AUDIT-2: --only <id> — run exactly ONE check by id against the resolved scope
# (so tests/skills/harness-audit/test-harness-audit.sh can prove a known-bad
# fixture makes the matching check fire — the maker-grades-own-work guard on
# the audit itself). Dispatch happens AFTER the check-fragment glob is built
# (below), where CLAUDE_DIR / fm_get / crit / warn are all in scope. Works for
# any check id that resolves to exactly one fragment (not a hardcoded
# allowlist) — used so far for 39 (recursive-improve disable-model-invocation
# flag — CRIT), 40 (dead kbg: doc-rot — WARN), 48 (fleet-count doc-rot — WARN).
# A miss (0 or >1 matches) → err_die (unsupported, not silent).

# Source the shared libraries.
# shellcheck source=../../../scripts/_lib/frontmatter-helpers.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/frontmatter-helpers.sh"
# shellcheck source=../../../scripts/_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/err.sh"

# Fail loud: if the resolved root holds none of the fleet dirs, root
# resolution failed — error out instead of a false-clean "0 artifacts" pass. A
# post-extraction dotfiles root legitimately has only hooks/; that still counts.
if [ ! -d "$CLAUDE_DIR/agents" ] && [ ! -d "$CLAUDE_DIR/skills" ] && \
   [ ! -d "$CLAUDE_DIR/commands" ] && [ ! -d "$CLAUDE_DIR/hooks" ]; then
  err_die "no harness fleet (agents/skills/commands/hooks) under: $CLAUDE_DIR — pass the repo root explicitly: bash audit.sh <repo-root>"
fi

CRIT_COUNT=0
WARN_COUNT=0
INFO_COUNT=0

# Locked skills = upstream-tracked installs in ~/.agents/.skill-lock.json
# (Matt Pocock, gstack, ECC, etc. — agent system installs + pins by content
# hash). Editing them in either ~/.claude/skills/<name> or ~/.agents/skills/<name>
# would drift the hash and corrupt the install. Symlink F1 is therefore
# silenced for these names. SSOT record: memory `project_skill_lock_ssot`.
LOCK_FILE="$HOME/.agents/.skill-lock.json"
LOCKED_SKILLS=()
if [ -f "$LOCK_FILE" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r s; do LOCKED_SKILLS+=("$s"); done < <(jq -r '.skills | keys[]' "$LOCK_FILE")
fi

# Plugin delivery (kbg-cutover 2026-06-11). The kbg@kobig plugin installs
# agents/skills/commands/hooks/output-styles into the user-scope plugin cache
# (default ~/.claude/plugins/cache/kobig/kbg/<version>/) and Claude Code loads
# them from there at runtime — NO symlink into ~/.claude/ is created. Without
# this awareness, F1 ("not symlinked to ~/.claude/…") fires on every
# plugin-delivered component as a false positive (62 CRITs on matt-harness).
# --plugin-cache <path> overrides the default for testing (see tests/skills/harness-audit/known-bad/).
# Resolve to the latest installed version of the kbg plugin in the cache,
# so a version bump (e.g. 0.1.0 -> 0.1.1 -> 0.1.2) doesn't silently disable
# F1 plugin-aware bypass. PLUGIN_CACHE_ARG still wins for explicit override.
if [ -z "$PLUGIN_CACHE_ARG" ]; then
  # KBG_CACHE_DIR (docs/reference/env-vars.md) overrides the versionless cache
  # ROOT; the highest-semver subdir is still picked below. --plugin-cache (a
  # full versioned path) wins over both. Wired 2026-08-24 (#93) — the knob was
  # documented but never read.
  _KBG_CACHE_DIR="${KBG_CACHE_DIR:-$HOME/.claude/plugins/cache/kobig/kbg}"
  if [ -d "$_KBG_CACHE_DIR" ]; then
    # Glob + for-loop (avoiding SC2010 ls|grep). Picks the highest semver of any
    # subdirectory matching X.Y.Z or vX.Y.Z, so a version bump (0.1.0 -> 0.1.1
    # -> 0.1.2) never silently disables F1 plugin-aware bypass. The `v` prefix
    # matches what `claude plugin install` writes to the cache.
    _LATEST=$(for _entry in "$_KBG_CACHE_DIR"/*/; do
      [ -d "$_entry" ] || continue
      _ver=$(basename "$_entry")
      _norm="${_ver#v}"   # strip optional 'v' prefix for comparison
      [[ "$_norm" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      echo "$_ver"
    done | sort -V | tail -1)
    if [ -n "$_LATEST" ]; then
      PLUGIN_CACHE="$_KBG_CACHE_DIR/$_LATEST"
    else
      PLUGIN_CACHE="${_KBG_CACHE_DIR}/0.1.0"  # fallback for empty/missing cache
    fi
  else
    PLUGIN_CACHE="${_KBG_CACHE_DIR}/0.1.0"  # fallback when no cache dir
  fi
else
  PLUGIN_CACHE="$PLUGIN_CACHE_ARG"
fi
unset _KBG_CACHE_DIR _LATEST _ver _entry _norm
# PLUGIN_ACTIVE is read by checks 02 / 03 via the shared audit scope; shellcheck
# can't see across the sourced check files, so disable SC2034 here.
# shellcheck disable=SC2034
PLUGIN_ACTIVE=0
if [ -d "$PLUGIN_CACHE/agents" ] || [ -d "$PLUGIN_CACHE/skills" ] || \
   [ -d "$PLUGIN_CACHE/commands" ] || [ -d "$PLUGIN_CACHE/hooks" ] || \
   [ -d "$PLUGIN_CACHE/output-styles" ]; then
  # SC2034: PLUGIN_ACTIVE is reassigned here but read by sourced checks.
  # shellcheck disable=SC2034
  PLUGIN_ACTIVE=1
fi
# is_plugin_delivered <kind> <name> — returns 0 if a component named <name>
# of kind <kind> (skills|agents|commands|hooks|output-styles) is present in
# the plugin cache. Kinds map to cache subdirs: skills/<name>/SKILL.md,
# agents/<name>.md, commands/<name>.md, hooks/<name>, output-styles/<name>.md.
# Skills: a skill is a directory containing SKILL.md, so test the dir+file.
# Hooks: a hook is a single file (.sh or .py), so test the file directly.
# Agents/commands/output-styles: a single .md file.
is_plugin_delivered() {
  local kind="$1"
  local name="$2"
  case "$kind" in
    skills)        [ -f "$PLUGIN_CACHE/skills/$name/SKILL.md" ] ;;
    agents)        [ -f "$PLUGIN_CACHE/agents/$name.md" ] ;;
    commands)      [ -f "$PLUGIN_CACHE/commands/$name.md" ] || [ -f "$PLUGIN_CACHE/commands/$name/COMMAND.md" ] ;;
    hooks)         [ -f "$PLUGIN_CACHE/hooks/$name" ] ;;
    output-styles) [ -f "$PLUGIN_CACHE/output-styles/$name.md" ] ;;
    *) return 1 ;;
  esac
}

# hook_wired_transitively <hook-basename> — true if <hook-basename> is invoked
# through a small dispatch script hooks.json names instead of the hook file
# itself (e.g. worktree-guard-dispatch.sh execs worktree-guard.py). Shared by
# checks 03 and 11 (2026-08-19: a deep-audit found the two had each hand-copied
# this logic, drifting apart, and both versions had a real false-negative —
# the extraction swept hooks.json's free-text `description` fields too, not
# just real command/args values, so an unrelated referenced script whose own
# TEXT happened to mention the hook's name — even in a comment — counted as
# "wired". Falsified empirically: a genuinely unwired worktree-guard.py was
# reported clean via a comment mention in atlassian-mcp-gate.sh).
# Fix: scope extraction to hooks.json's actual command/args values via jq
# (falls back to the old text-sweep if jq is unavailable), and strip comment
# text from the referenced file before matching so a prose mention doesn't
# count as an invocation.
hook_wired_transitively() {
  local name="$1" hooks_json="$CLAUDE_DIR/hooks/hooks.json" ref_file
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r ref_file; do
      [ -n "$ref_file" ] && [ -f "$ref_file" ] || continue
      sed 's/#.*$//' "$ref_file" 2>/dev/null | grep -qF "$name" && return 0
    done < <(jq -r '
        .hooks | to_entries[]? | .value[]? | .hooks[]? |
        ([.command // empty] + (.args // [])) | .[] | select(type=="string")
      ' "$hooks_json" 2>/dev/null \
        | grep -E '\.(sh|py)$' \
        | sed "s|\${CLAUDE_PLUGIN_ROOT}|$CLAUDE_DIR|g; s|\$CLAUDE_PLUGIN_ROOT\b|$CLAUDE_DIR|g" \
        | sort -u)
  else
    while IFS= read -r ref_file; do
      [ -n "$ref_file" ] && [ -f "$ref_file" ] || continue
      sed 's/#.*$//' "$ref_file" 2>/dev/null | grep -qF "$name" && return 0
    done < <(grep -oE '[A-Za-z0-9_./${}-]+\.(sh|py)' "$hooks_json" 2>/dev/null \
        | sed "s|\${CLAUDE_PLUGIN_ROOT}|$CLAUDE_DIR|g; s|\$CLAUDE_PLUGIN_ROOT\b|$CLAUDE_DIR|g" \
        | sort -u)
  fi
  return 1
}

# Finding IDs reuse the per-tier counters (F<n>/W<n>/I<n>). The previous
# next_id() helper incremented its counter inside a $(...) command substitution
# (a subshell), so the parent counter never advanced and every finding rendered
# as F1/W1/I1. Folding the increment into the same assignment that already
# tracks the exit-code totals keeps IDs unique per tier with no subshell.
crit() { CRIT_COUNT=$((CRIT_COUNT + 1)); echo "  CRIT F${CRIT_COUNT}: $1"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo "  WARN W${WARN_COUNT}: $1"; }
info() { INFO_COUNT=$((INFO_COUNT + 1)); echo "  INFO I${INFO_COUNT}: $1"; }

# ── helpers (fm_get / fm_has come from scripts/_lib/frontmatter-helpers.sh) ──

# Run a find-like command and return its match count; if the starting directory
# is missing (find exits 1) we still get "0" instead of tripping set -e/pipefail.
safe_count() {
  local n
  n=$({ "$@" 2>/dev/null || true; } | wc -l | tr -d ' ')
  printf '%s' "$n"
}

# ── main ─────────────────────────────────────────────────────────────

echo "=== Skill Audit Report ==="
echo "Root: $REPO_ROOT"

# ── checks (sourced in filename-glob order; fragments are numbered 1..56 with
# filename prefix == '# N.' header, so glob-sorting by 01..56 sources them in
# numeric order). Sourced via the script dir (not CWD) so the audit
# runs correctly from any CWD, matching the _lib sourcing above. Fail-closed
# guard below catches any lost/dup fragment BEFORE the summary prints a
# false-clean result. ─────────────────────────────────────────────────────
_AUDIT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# NOTE: do NOT capture `shopt -p nullglob` into a var — `shopt -p <opt>` returns
# non-zero when the option is OFF (the default), and under `set -e` that
# command-substitution exit kills the audit. nullglob is OFF at audit start
# (only globstar is set at the top), so restore to OFF explicitly after the glob.
shopt -s nullglob
_checks=("$_AUDIT_DIR"/checks/[0-9][0-9]-*.sh)
shopt -u nullglob
[ "${#_checks[@]}" -gt 0 ] || err_die "audit: no check fragments in $_AUDIT_DIR/checks/ — split is broken (fail-closed, not fail-open)"

# --only <id>: source exactly ONE check fragment against the resolved scope
# and exit (skipping the full loop + the 56-fragment integrity guard, which
# only applies to a full run). err_die on no/ambiguous match.
if [ -n "$ONLY_ID" ]; then
  _padded=$(printf '%02d' "$ONLY_ID" 2>/dev/null || printf '%s' "$ONLY_ID")
  _only=()
  for _cf in "${_checks[@]}"; do
    _bn=$(basename "$_cf")
    case "$_bn" in
      "${ONLY_ID}"-*.sh|"${_padded}"-*.sh) _only+=("$_cf") ;;
    esac
  done
  case "${#_only[@]}" in
    0) err_die "audit --only: id '$ONLY_ID' matched no check fragment" ;;
    1) ;;
    *) err_die "audit --only: id '$ONLY_ID' matched ${#_only[@]} fragments (need exactly 1)" ;;
  esac
  # shellcheck source=/dev/null
  . "${_only[0]}"
  echo ""
  echo "=== Summary (--only $ONLY_ID) ==="
  echo "Critical: $CRIT_COUNT"
  echo "Warnings: $WARN_COUNT"
  echo "Info:     $INFO_COUNT"
  if [ "$CRIT_COUNT" -gt 0 ]; then exit "$CRIT_COUNT"; fi
  exit 0
fi

# ── frontmatter cache build (perf, 2026-07-03) ────────────────────────
# Pre-compute the common keys (name/description/tools, --block) for every fleet
# surface ONCE here in the main shell. Sourced checks call fm_get inside $(...)
# subshells, which inherit _FM_CACHE (declared in frontmatter-helpers.sh) by
# fork-copy and hit instead of re-spawning awk per file per key (~460 redundant
# awk spawns/run -> one build pass). fm_get falls back to awk on a miss, so any
# key not pre-cached still works. Modest win: awk is ~0.7ms/spawn here (not the
# 3-5ms a cold python3 is), so this cuts ~0.4s off the audit, not the 1.5-2.5s
# earlier estimated (corrected 2026-07-03 after profiling). Gauntlet long-pole
# is THIS audit (~8.4s, pre-commit AND pre-push), NOT shellcheck (~0.9s) —
# measured 2026-07-03 after v0.31.0. The 8.4s is distributed across the sourced
# checks (heaviest ~1s each: doc-rot, boundary-drift, description-length,
# doctrine-conformance, refs-resolve); no single runaway to cut surgically.
# The only further lever is a structural shared-fleet-manifest refactor
# touching the fragment integrity guard — declined at current stakes (low
# commit-frequency repo; risk to a safety-closed guard > seconds saved).
# >/dev/null suppresses stdout; the write to _FM_CACHE persists because this
# runs in the main shell, not a $(...) subshell.
for _fmf in "$CLAUDE_DIR"/skills/[!_]*/SKILL.md "$CLAUDE_DIR"/agents/*.md \
            "$CLAUDE_DIR"/commands/*.md "$CLAUDE_DIR"/commands/[!_]*/COMMAND.md; do
  [ -f "$_fmf" ] || continue
  fm_get "$_fmf" name --block >/dev/null
  fm_get "$_fmf" description --block >/dev/null
  fm_get "$_fmf" tools --block >/dev/null
done
unset _fmf

for _cf in "${_checks[@]}"; do
  # shellcheck source=/dev/null
  . "$_cf"
done
unset _cf

# Split-integrity guard: exactly 56 fragments, each carrying one '# N.' header,
# numbers 1..56 each exactly once. Source scope == count scope == the SAME glob
# (checks/[0-9][0-9]-*.sh), so an unnumbered extra is neither sourced nor
# counted. Three assertions close the fail-OPEN holes a single equality check
# misses: a fragment with no header (files != headers), a duplicate number
# (total != unique), and a gap/loss (unique set != 1..56). Any = err_die.
_all_ids=$(grep -hoE '^# [0-9]+\. ' "${_checks[@]}" 2>/dev/null | grep -oE '[0-9]+' | sort -n)
_n_files=${#_checks[@]}
_n_total=$(printf '%s\n' "$_all_ids" | grep -c .)
_n_uniq=$(printf '%s\n' "$_all_ids" | sort -u | grep -c .)
_uniq_ids=$(printf '%s\n' "$_all_ids" | uniq | tr '\n' ' ')
_exp_ids=$(seq 1 56 | tr '\n' ' ')
[ "$_n_files" = "$_n_total" ] || err_die "audit: check-fragment header mismatch — $_n_files files sourced but $_n_total '# N.' headers (a fragment lacks a header or carries >1) — fail-closed"
[ "$_n_total" = "$_n_uniq" ] || err_die "audit: duplicate check-fragment number (total=$_n_total unique=$_n_uniq) — a number is duplicated, not exactly-once — fail-closed"
[ "$_uniq_ids" = "$_exp_ids" ] || err_die "audit: check-fragment integrity broken — set [$_uniq_ids] != expected [$_exp_ids]; a fragment was lost or a gap appeared — fail-closed"
unset _all_ids _uniq_ids _exp_ids _n_files _n_total _n_uniq _checks _AUDIT_DIR

# ── summary ──────────────────────────────────────────────────────────

echo ""
echo "=== Summary ==="
echo "Critical: $CRIT_COUNT"
echo "Warnings: $WARN_COUNT"
echo "Info:     $INFO_COUNT"
echo ""
echo "Exit: $CRIT_COUNT"
# Exit policy: CRITs are blocking (nonzero), WARNs are informational (zero).
# This matches the gauntlet's blocking gate (CRITs only) and the in-CC sensor
# visibility (WARNs print to stderr so editors still see them). The pre-push
# gauntlet reports the full count via its own summary; it does NOT depend on
# the audit's exit code to know the count.
if [ "$CRIT_COUNT" -gt 0 ]; then
  exit "$CRIT_COUNT"
fi
exit 0
