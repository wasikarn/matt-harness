#!/usr/bin/env bash
# audit.sh — automated health check for the custom Claude Code ecosystem.
# Usage: bash audit.sh [<repo-root>] [--plugin-cache <path>]
# Exit code = number of findings (0 = clean).
set -euo pipefail
# Hooks moved into subdirs (gates/, advisory/, lifecycle/, …); the per-hook
# checks (#3/#11/#29) and the Fleet count must recurse, not glob top-level —
# else they silently scan 0 of ~36 real hooks (green-because-empty).
shopt -s globstar

# Parse args. Positional [<repo-root>] first; optional --plugin-cache <path>
# second. Keep backward-compat: a single arg is treated as repo-root (the old
# call shape `bash audit.sh <repo>` still works).
REPO_ROOT=""
PLUGIN_CACHE_ARG=""
STALENESS_ONLY=0
ONLY_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-cache) PLUGIN_CACHE_ARG="${2:-}"; shift 2 ;;
    --plugin-cache=*) PLUGIN_CACHE_ARG="${1#--plugin-cache=}"; shift ;;
    --staleness-only) STALENESS_ONLY=1; shift ;;
    --only) ONLY_ID="${2:-}"; shift 2 ;;
    --only=*) ONLY_ID="${1#--only=}"; shift ;;
    *) [ -z "$REPO_ROOT" ] && REPO_ROOT="$1"; shift ;;
  esac
done
REPO_ROOT="${REPO_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
# Layout: dotfiles nests the harness under claude/; the extracted kbg-harness
# plugin repo is flat (agents/, skills/, … at the root). Resolve CLAUDE_DIR to
# whichever holds the fleet so one audit.sh serves both checkouts.
if [ -d "$REPO_ROOT/claude" ]; then
  CLAUDE_DIR="$REPO_ROOT/claude"
else
  CLAUDE_DIR="$REPO_ROOT"
fi
SETTINGS="$CLAUDE_DIR/settings.json"
MEMORY_DIR="${REPO_ROOT//claude/}/.claude/projects/$(echo "$REPO_ROOT" | sed 's|/|_|g')/memory"

# AUDIT-1: --staleness-only flag — emit a JSON list of {name, last_fired,
# days_silent, fallback_role, ...} joined from hooks/sensors.json (Wave 1
# registry) and the governance evidence journal. Consumed by HOOK-1
# (Wave 2) at SessionStart to apply Q3 severity gating. Runs BEFORE the
# rest of the audit so the non-flag path is byte-identical: this block
# is the only difference vs upstream, and it early-exits when set.
# BASH_SOURCE-stable: REGISTRY resolves from the script's own location
# (line 53) so the path is correct whether the script runs from the
# source tree, the plugin cache, or with no <repo> arg. Degrades to `[]`
# if the registry is missing (the registry may be rolled back
# independently of this flag).
if [ "$STALENESS_ONLY" = "1" ]; then
  # The default $REPO_ROOT fallback (line 19: /../../../..) is 1 level
  # too high — it resolves to the *parent* of the kbg-harness repo when
  # no <repo> arg is given. The brief requires this flag to work with
  # OR without the optional <repo> argument, so we resolve the registry
  # via BASH_SOURCE instead of depending on $REPO_ROOT. This also keeps
  # the registry path correct in plugin-cache invocations (the script
  # is the same file regardless of where the cache copy lives).
  REGISTRY="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../hooks" && pwd)/sensors.json"
  if [ ! -f "$REGISTRY" ]; then
    echo "[]"
    exit 0
  fi
  # Honor the JOURNAL-SCHEMA.md test override (CLAUDE_JOURNAL_PATH). Same
  # convention journal_append() uses — keep the read side consistent.
  JOURNAL="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
  python3 - "$REGISTRY" "$JOURNAL" <<'PY' 2>/dev/null || echo "[]"
import datetime as dt, json, os, sys
registry_path, journal_path = sys.argv[1], sys.argv[2]
now = dt.datetime.now(dt.timezone.utc)
# Build name -> last_fired_iso from the journal. Hook basenames in the
# journal match the registry's `name` field (basename without .sh/.py
# extension; see JOURNAL-SCHEMA.md envelope: `hook` is the script id,
# not a path). A sensor that never journaled is `null` by design — the
# absence is the signal the notifier is built to detect.
last_fired = {}
if os.path.isfile(journal_path):
    with open(journal_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            h = d.get("hook")
            ts = d.get("ts")
            if not h or not ts:
                continue
            # Keep the maximum (latest) ts per hook. ts is ISO8601
            # string-comparable; no parsing needed for the max.
            if h not in last_fired or ts > last_fired[h]:
                last_fired[h] = ts
with open(registry_path, encoding="utf-8") as f:
    reg = json.load(f)
sensors = reg.get("sensors", [])
out = []
for s in sensors:
    name = s["name"]
    lf = last_fired.get(name)
    if lf is None:
        ds = None
    else:
        # days_silent = floor((now - last_fired) / 1 day). ISO8601
        # string sort order matches chronological order, but use
        # datetime subtraction for the day count to be safe across
        # fractional seconds and tz variants in the journal stream.
        try:
            lf_dt = dt.datetime.fromisoformat(lf.replace("Z", "+00:00"))
            ds = (now - lf_dt).days
        except ValueError:
            ds = None
    out.append({
        "name": name,
        "should_fire_when": s.get("should_fire_when"),
        "max_silent_days": s.get("max_silent_days"),
        "fallback_role": s.get("fallback_role"),
        "must_fire_in_session": s.get("must_fire_in_session", False),
        "enabled": s.get("enabled", True),
        "last_fired": lf,
        "days_silent": ds,
    })
# Stable order for the consumer (HOOK-1 hashes the stale set, see Q4 in
# docs/research/sensor-staleness-notifier-design.md). Sort by name.
out.sort(key=lambda e: e["name"])
print(json.dumps(out, separators=(",", ":")))
PY
  exit 0
fi

# AUDIT-2: --only <id> — run exactly ONE check by id (design §5 R3). The per-check
# runner the loop-guard's --assert-cage-intact shells every cycle to re-assert cage
# completeness cheaply. Supported ids: 43 (cage-completeness → scripts/l4/cage-
# intact.sh). Exits non-zero on CRIT, fail-closed. Extensible: add a case per id.
# Unsupported id → exit 2 (honest about what's supported, not a silent fallthrough).
if [ -n "$ONLY_ID" ]; then
  case "$ONLY_ID" in
    43)
      bash "$REPO_ROOT/scripts/l4/cage-intact.sh" "$REPO_ROOT"
      exit $?
      ;;
    *)
      echo "audit --only: unsupported id '$ONLY_ID' (supported: 43)" >&2
      exit 2
      ;;
  esac
fi

# Source the shared libraries.
# shellcheck source=../../_lib/frontmatter-helpers.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../_lib/frontmatter-helpers.sh"
# shellcheck source=../../_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../_lib/err.sh"

# Fail loud (Rule 12): if the resolved root holds none of the fleet dirs, root
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
# plugin-delivered component as a false positive (62 CRITs on kbg-harness).
# --plugin-cache <path> overrides the default for testing (see tests/harness-audit/fixtures/).
# Resolve to the latest installed version of the kbg plugin in the cache,
# so a version bump (e.g. 0.1.0 -> 0.1.1 -> 0.1.2) doesn't silently disable
# F1 plugin-aware bypass. PLUGIN_CACHE_ARG still wins for explicit override.
if [ -z "$PLUGIN_CACHE_ARG" ]; then
  _KBG_CACHE_DIR="$HOME/.claude/plugins/cache/kobig/kbg"
  if [ -d "$_KBG_CACHE_DIR" ]; then
    _LATEST=$(ls -1 "$_KBG_CACHE_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
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
unset _KBG_CACHE_DIR _LATEST
PLUGIN_ACTIVE=0
if [ -d "$PLUGIN_CACHE/agents" ] || [ -d "$PLUGIN_CACHE/skills" ] || \
   [ -d "$PLUGIN_CACHE/commands" ] || [ -d "$PLUGIN_CACHE/hooks" ] || \
   [ -d "$PLUGIN_CACHE/output-styles" ]; then
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
    commands)      [ -f "$PLUGIN_CACHE/commands/$name.md" ] ;;
    hooks)         [ -f "$PLUGIN_CACHE/hooks/$name" ] ;;
    output-styles) [ -f "$PLUGIN_CACHE/output-styles/$name.md" ] ;;
    *) return 1 ;;
  esac
}

# Finding IDs reuse the per-tier counters (F<n>/W<n>/I<n>). The previous
# next_id() helper incremented its counter inside a $(...) command substitution
# (a subshell), so the parent counter never advanced and every finding rendered
# as F1/W1/I1. Folding the increment into the same assignment that already
# tracks the exit-code totals keeps IDs unique per tier with no subshell.
crit() { CRIT_COUNT=$((CRIT_COUNT + 1)); echo "  CRIT F${CRIT_COUNT}: $1"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo "  WARN W${WARN_COUNT}: $1"; }
info() { INFO_COUNT=$((INFO_COUNT + 1)); echo "  INFO I${INFO_COUNT}: $1"; }

# ── helpers (fm_get / fm_has / SKIP_SCAFFOLD_GLOB come from _lib/frontmatter-helpers.sh) ──

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

# ── checks (sourced in file order; sequence-named fragments preserve the
# original execution order — checks are NOT numerically sorted in the file
# (#31 follows #33), so glob-sourcing by 01..52 filename sort reproduces the
# original order exactly). Sourced via the script dir (not CWD) so the audit
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
for _cf in "${_checks[@]}"; do
  # shellcheck source=/dev/null
  . "$_cf"
done
unset _cf

# Split-integrity guard: exactly 52 fragments, each carrying one '# N.' header,
# numbers 1..52 each exactly once. Source scope == count scope == the SAME glob
# (checks/[0-9][0-9]-*.sh), so an unnumbered extra is neither sourced nor
# counted. Three assertions close the fail-OPEN holes a single equality check
# misses: a fragment with no header (files != headers), a duplicate number
# (total != unique), and a gap/loss (unique set != 1..52). Any = err_die.
_all_ids=$(grep -hoE '^# [0-9]+\. ' "${_checks[@]}" 2>/dev/null | grep -oE '[0-9]+' | sort -n)
_n_files=${#_checks[@]}
_n_total=$(printf '%s\n' "$_all_ids" | grep -c .)
_n_uniq=$(printf '%s\n' "$_all_ids" | sort -u | grep -c .)
_uniq_ids=$(printf '%s\n' "$_all_ids" | uniq | tr '\n' ' ')
_exp_ids=$(seq 1 52 | tr '\n' ' ')
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
TOTAL=$((CRIT_COUNT + WARN_COUNT))
echo ""
echo "Exit: $TOTAL"
exit $TOTAL
