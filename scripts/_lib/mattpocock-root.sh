#!/usr/bin/env bash
# mattpocock-root.sh — shared resolver for the installed mattpocock-skills
# plugin's cache root. Single source of truth for the session bootstrap
# preflight (hooks/session/doctrine-bootstrap.sh) and the integration-refs
# audit check (skills/harness-audit/scripts/checks/51-mattpocock-integration-refs.sh)
# (#92/T13) — both previously duplicated ad-hoc versions of this lookup,
# one of which (doctrine-bootstrap.sh) only checked the parent cache
# directory's existence with no version resolution or completeness check.
#
# resolve_mattpocock_root: sets MATT_ROOT (the resolved version dir, e.g.
# .../mattpocock-skills/1.2.3) and MATT_VER (the bare version string) on
# success; both empty and return 1 on failure (not installed, or installed
# but half-extracted).
#
# Resolution order:
#   1. MH_MATT_CACHE env override (else the real cache path).
#   2. Highest-semver version subdirectory under that root (`sort -V`).
#   3. Completeness probe: at least one real SKILL.md must exist somewhere
#      under that version's skills/ tree (depth-agnostic — matches check
#      51's own precedent, since upstream's pending flatten-skills-tree
#      branch removes bucket nesting entirely). Rejects a half-extracted
#      install (top-level dirs landed, the skill payload didn't) that a
#      bare `-d .../skills` directory test would miss. Deliberately does
#      NOT *require* .claude-plugin/plugin.json's declared skill list —
#      check 51 already has to tolerate that manifest being absent or
#      malformed (its own "manifest format drifted" fail-closed path), so
#      requiring it here too would tie cache-completeness to manifest-
#      parsing correctness for every caller, including check 51's own
#      manifest-less fixtures.
#   4. When a manifest IS present and declares a nonzero skill count,
#      cross-check it: at least half the declared skills must actually
#      have landed. Closes a real gap found by an independent adversarial
#      audit (2026-08-25): a near-total extraction failure that leaves ONE
#      stray SKILL.md behind would otherwise still pass step 3's bare
#      ">=1" probe and be reported "installed and complete" by
#      doctrine-bootstrap.sh every session — exactly the silent dead-end
#      that preflight exists to prevent, and check 51's own per-reference
#      dead-ref check only catches it during a harness-audit run INSIDE
#      this repo, not in every other project session that has the plugin
#      enabled. No manifest (or one that fails to parse) -> step 3 alone
#      stands, unchanged; existing manifest-less fixtures are unaffected.
resolve_mattpocock_root() {
  MATT_ROOT=""
  MATT_VER=""
  local base ver found_count manifest declared_count
  base="${MH_MATT_CACHE:-$HOME/.claude/plugins/cache/mattpocock/mattpocock-skills}"
  [ -d "$base" ] || return 1
  ver=$(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | sort -V | tail -1)
  [ -n "$ver" ] || return 1
  found_count=$(find "$base/$ver/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  [ "${found_count:-0}" -gt 0 ] || return 1
  manifest="$base/$ver/.claude-plugin/plugin.json"
  if [ -f "$manifest" ]; then
    declared_count=$(grep -oE '"(\./)?skills/[^"]+"' "$manifest" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${declared_count:-0}" -gt 0 ] && [ "$found_count" -lt $(( (declared_count + 1) / 2 )) ]; then
      return 1
    fi
  fi
  # MATT_ROOT/MATT_VER are read by callers after sourcing this file; the
  # linter can't see across that boundary (same precedent as audit.sh's own
  # PLUGIN_ACTIVE/SETTINGS/MEMORY_DIR disables).
  # shellcheck disable=SC2034
  MATT_ROOT="$base/$ver"
  # shellcheck disable=SC2034
  MATT_VER="$ver"
  return 0
}
