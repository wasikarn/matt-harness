#!/usr/bin/env bash
# audit.sh: health check for the mh plugin surfaces (agents/skills/hooks).
# Usage: bash audit.sh [<repo-root>] [--plugin-cache <path>] [--only <id>]
# Exit code = CRIT count (0 = clean). WARN/INFO never change the exit code.
set -euo pipefail
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "audit.sh: needs bash >= 4 (this is bash ${BASH_VERSION}); brew install bash" >&2
  exit 1
fi
# Hooks live in subdirs (gates/, session/, stop/); per-hook checks recurse.
shopt -s globstar

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
REPO_ROOT="${REPO_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
# dotfiles nests the fleet under claude/; the plugin repo is flat.
if [ -d "$REPO_ROOT/claude" ]; then
  CLAUDE_DIR="$REPO_ROOT/claude"
else
  CLAUDE_DIR="$REPO_ROOT"
fi
# Read by sourced checks; shellcheck cannot see across the source boundary.
# shellcheck disable=SC2034
SETTINGS="$CLAUDE_DIR/settings.json"

_LIB="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../scripts/_lib"
# shellcheck source=../../../../scripts/_lib/frontmatter-helpers.sh
. "$_LIB/frontmatter-helpers.sh"
# shellcheck source=../../../../scripts/_lib/codex-state-path.sh
. "$_LIB/codex-state-path.sh"
# shellcheck source=../../../../scripts/_lib/err.sh
. "$_LIB/err.sh"

if [ ! -d "$CLAUDE_DIR/agents" ] && [ ! -d "$CLAUDE_DIR/skills" ] && \
   [ ! -d "$CLAUDE_DIR/hooks" ]; then
  err_die "no harness fleet (agents/skills/hooks) under: $CLAUDE_DIR; pass the repo root explicitly: bash audit.sh <repo-root>"
fi

CRIT_COUNT=0
WARN_COUNT=0
INFO_COUNT=0

# Upstream-tracked skill installs (~/.agents/.skill-lock.json) are never
# symlink-checked: editing them would drift their content hash.
LOCK_FILE="$HOME/.agents/.skill-lock.json"
LOCKED_SKILLS=()
if [ -f "$LOCK_FILE" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r s; do LOCKED_SKILLS+=("$s"); done < <(jq -r '.skills | keys[]' "$LOCK_FILE")
fi

# Plugin delivery: Claude Code loads mh from ~/.claude/plugins/cache/<marketplace>/mh/<version>/,
# no symlink into ~/.claude/. Resolve the highest installed version across every
# marketplace dir (a marketplace rename must not turn every component into a CRIT).
# MH_CACHE_DIR overrides the cache root; --plugin-cache wins over both.
if [ -z "$PLUGIN_CACHE_ARG" ]; then
  if [ -n "${MH_CACHE_DIR:-}" ]; then
    _MH_CACHE_ROOTS="$MH_CACHE_DIR"
  else
    # Trailing `:` keeps the substitution's exit status 0 when no cache exists.
    _MH_CACHE_ROOTS=$(
      for _d in "$HOME"/.claude/plugins/cache/*/mh; do
        [ -d "$_d" ] || continue
        echo "$_d"
      done
      :
    )
  fi
  _BEST=$(for _root in $_MH_CACHE_ROOTS; do
    for _entry in "$_root"/*/; do
      [ -d "$_entry" ] || continue
      _ver=$(basename "$_entry")
      _norm="${_ver#v}"
      [[ "$_norm" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      printf '%s %s\n' "$_norm" "$_root/$_ver"
    done
  done | sort -V | tail -1)
  if [ -n "$_BEST" ]; then
    PLUGIN_CACHE="${_BEST#* }"
  else
    PLUGIN_CACHE="${MH_CACHE_DIR:-$HOME/.claude/plugins/cache/mh}/0.1.0"
  fi
else
  PLUGIN_CACHE="$PLUGIN_CACHE_ARG"
fi
unset _MH_CACHE_ROOTS _BEST _ver _entry _norm _root _d
# shellcheck disable=SC2034
PLUGIN_ACTIVE=0
if [ -d "$PLUGIN_CACHE/agents" ] || [ -d "$PLUGIN_CACHE/skills" ] || \
   [ -d "$PLUGIN_CACHE/hooks" ]; then
  # shellcheck disable=SC2034
  PLUGIN_ACTIVE=1
fi
# is_plugin_delivered <kind> <name>: 0 if the component exists in the plugin cache.
is_plugin_delivered() {
  local kind="$1"
  local name="$2"
  local _d
  case "$kind" in
    skills)
      [ -f "$PLUGIN_CACHE/skills/$name/SKILL.md" ] && return 0
      _d="$(find "$PLUGIN_CACHE/skills" -mindepth 2 -maxdepth 2 -type d -name "$name" 2>/dev/null | head -1)"
      [ -n "$_d" ] && [ -f "$_d/SKILL.md" ]
      ;;
    agents)        [ -f "$PLUGIN_CACHE/agents/$name.md" ] ;;
    hooks)         [ -f "$PLUGIN_CACHE/hooks/$name" ] ;;
    *) return 1 ;;
  esac
}

# hook_wired_transitively <basename>: true if a script hooks.json names invokes
# <basename> (comment text stripped so a prose mention does not count). Shared by
# checks 03 and 11.
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
        | grep -oE '[^[:space:]"]+\.(sh|py)' \
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

# Counters increment in the same shell as the echo (no $(...) subshell) so IDs stay unique.
crit() { CRIT_COUNT=$((CRIT_COUNT + 1)); echo "  CRIT F${CRIT_COUNT}: $1"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo "  WARN W${WARN_COUNT}: $1"; }
info() { INFO_COUNT=$((INFO_COUNT + 1)); echo "  INFO I${INFO_COUNT}: $1"; }

# Count matches of a find-like command; a missing start dir yields 0, not a set -e trip.
safe_count() {
  local n
  n=$({ "$@" 2>/dev/null || true; } | wc -l | tr -d ' ')
  printf '%s' "$n"
}

echo "=== Skill Audit Report ==="
echo "Root: $REPO_ROOT"

# Checks are sourced from the script dir in filename order; each fragment's
# filename prefix == its '# N.' header. The integrity guard below fails closed
# on a lost, duplicated, or headerless fragment.
_AUDIT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
shopt -s nullglob
_checks=("$_AUDIT_DIR"/checks/[0-9][0-9]-*.sh)
shopt -u nullglob
[ "${#_checks[@]}" -gt 0 ] || err_die "audit: no check fragments in $_AUDIT_DIR/checks/ (fail-closed)"

# --only <id>: source exactly one fragment and exit; the integrity guard is skipped.
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

# Warm the frontmatter cache once in the main shell; sourced checks' $(...)
# subshells inherit it instead of re-spawning awk per file per key.
for _fmf in "$CLAUDE_DIR"/skills/[!_]*/[!_]*/SKILL.md "$CLAUDE_DIR"/agents/*.md; do
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

# Split-integrity guard: the kept check set is explicit (v1.0.0 rebuild);
# retired numbers are never reused, so a deliberate retirement edits this list.
_all_ids=$(grep -hoE '^# [0-9]+\. ' "${_checks[@]}" 2>/dev/null | grep -oE '[0-9]+' | sort -n)
_n_files=${#_checks[@]}
_n_total=$(printf '%s\n' "$_all_ids" | grep -c .)
_n_uniq=$(printf '%s\n' "$_all_ids" | sort -u | grep -c .)
_uniq_ids=$(printf '%s\n' "$_all_ids" | uniq | tr '\n' ' ')
_exp_ids="2 3 4 5 7 8 9 10 11 17 18 19 20 21 22 23 24 28 29 32 33 35 41 42 43 54 70 71 "
[ "$_n_files" = "$_n_total" ] || err_die "audit: check-fragment header mismatch: $_n_files files sourced but $_n_total '# N.' headers (fail-closed)"
[ "$_n_total" = "$_n_uniq" ] || err_die "audit: duplicate check-fragment number (total=$_n_total unique=$_n_uniq) (fail-closed)"
[ "$_uniq_ids" = "$_exp_ids" ] || err_die "audit: check-fragment set [$_uniq_ids] != expected [$_exp_ids]; a fragment was lost or a gap appeared (fail-closed)"
unset _all_ids _uniq_ids _exp_ids _n_files _n_total _n_uniq _checks _AUDIT_DIR

echo ""
echo "=== Summary ==="
echo "Critical: $CRIT_COUNT"
echo "Warnings: $WARN_COUNT"
echo "Info:     $INFO_COUNT"
echo ""
echo "Exit: $CRIT_COUNT"
if [ "$CRIT_COUNT" -gt 0 ]; then
  exit "$CRIT_COUNT"
fi
exit 0
