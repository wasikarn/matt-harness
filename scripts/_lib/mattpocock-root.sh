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
#      NOT depend on .claude-plugin/plugin.json's declared skill list —
#      check 51 already has to tolerate that manifest being absent or
#      malformed (its own "manifest format drifted" fail-closed path), so
#      making the *resolver* depend on it too would tie cache-completeness
#      to manifest-parsing correctness, two separable concerns.
resolve_mattpocock_root() {
  MATT_ROOT=""
  MATT_VER=""
  local base ver
  base="${MH_MATT_CACHE:-$HOME/.claude/plugins/cache/mattpocock/mattpocock-skills}"
  [ -d "$base" ] || return 1
  ver=$(find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | sort -V | tail -1)
  [ -n "$ver" ] || return 1
  [ -n "$(find "$base/$ver/skills" -name SKILL.md -print -quit 2>/dev/null)" ] || return 1
  # MATT_ROOT/MATT_VER are read by callers after sourcing this file; the
  # linter can't see across that boundary (same precedent as audit.sh's own
  # PLUGIN_ACTIVE/SETTINGS/MEMORY_DIR disables).
  # shellcheck disable=SC2034
  MATT_ROOT="$base/$ver"
  # shellcheck disable=SC2034
  MATT_VER="$ver"
  return 0
}
