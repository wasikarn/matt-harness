#!/usr/bin/env bash
# codex-state-path.sh: compute the paired codex@openai-codex plugin's
# per-workspace review-gate state.json path for a given repo root.
#
# Ported from the installed plugin's scripts/lib/state.mjs (v1.0.6), not a
# public contract -- there is no documented, versioned path for this file.
# slug = basename(realpath(root)) sanitized to [a-zA-Z0-9._-] (runs collapsed
# to a single "-", leading/trailing "-" stripped), falling back to
# "workspace" if that empties it. hash = first 16 hex chars of
# sha256(realpath(root)). Path = $MH_CODEX_DATA_DIR/state/<slug>-<hash>/state.json,
# where MH_CODEX_DATA_DIR defaults to Claude Code's own per-plugin data
# directory for codex@openai-codex (observed consistent across every
# installed plugin on this machine; not a Claude Code-documented env var,
# same status as the undocumented-but-real vars this repo already relies on).
# The env var exists so tests can point this at a throwaway directory instead
# of the real, shared, machine-global one -- see docs/reference/env-vars.md.
#
# Prints the path on stdout; returns non-zero (prints nothing) if root does
# not exist or no sha256 tool is available.
codex_state_path() {
  local root="$1" real base slug hash data_dir
  real=$(cd -P "$root" 2>/dev/null && pwd) || return 1
  base=$(basename "$real")
  slug=$(printf '%s' "$base" | LC_ALL=C sed -E 's/[^a-zA-Z0-9._-]+/-/g; s/^-+//; s/-+$//')
  [ -z "$slug" ] && slug="workspace"
  if command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$real" | shasum -a 256 | cut -c1-16)
  elif command -v sha256sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$real" | sha256sum | cut -c1-16)
  else
    return 1
  fi
  data_dir="${MH_CODEX_DATA_DIR:-$HOME/.claude/plugins/data/codex-openai-codex}"
  printf '%s/state/%s-%s/state.json' "$data_dir" "$slug" "$hash"
}
