#!/usr/bin/env bash
# codex-state-path.sh: compute the paired codex@openai-codex plugin's
# per-workspace review-gate state.json path for a given repo root.
#
# Ported from the installed plugin's scripts/lib/state.mjs (v1.0.6), not a
# public contract -- there is no documented, versioned path for this file.
# The <slug>-<hash> naming itself is shared with scripts/_lib/fragments-state.sh
# -- see scripts/_lib/slug-hash.sh for that derivation.
# Path = $MH_CODEX_DATA_DIR/state/<slug>-<hash>/state.json, where
# MH_CODEX_DATA_DIR defaults to Claude Code's own per-plugin data directory
# for codex@openai-codex (observed consistent across every installed plugin
# on this machine; not a Claude Code-documented env var, same status as the
# undocumented-but-real vars this repo already relies on). The env var
# exists so tests can point this at a throwaway directory instead of the
# real, shared, machine-global one -- see docs/reference/env-vars.md.
#
# Prints the path on stdout; returns non-zero (prints nothing) if root does
# not exist or no sha256 tool is available.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/slug-hash.sh"

codex_state_path() {
  local root="$1" slughash data_dir
  slughash=$(slug_hash "$root") || return 1
  data_dir="${MH_CODEX_DATA_DIR:-$HOME/.claude/plugins/data/codex-openai-codex}"
  printf '%s/state/%s/state.json' "$data_dir" "$slughash"
}
