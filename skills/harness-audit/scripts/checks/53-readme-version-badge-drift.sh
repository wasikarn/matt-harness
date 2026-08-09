#!/usr/bin/env bash
# 53. README version-badge drift. The README's shields.io version badge is a
# 3rd copy of the version string alongside plugin.json/marketplace.json, and
# nothing checked it against them — confirmed missed twice in a row in this
# repo's own history (v0.68.234 then v0.68.235 both bumped the manifests but
# left the badge on v0.68.233; caught by a /kbg:deep-audit pass, not by any
# existing check). WARN, not CRIT — doc-rot degrades gracefully, same
# severity as check 48's fleet-count drift, which this mirrors structurally.
#
# Sync-seam: this is intentionally its own check, not folded into check 48 —
# 48's _check_triple asserts a *substring* match (the fleet-count string can
# sit inside a longer line), but the badge line IS the whole match target
# once the version number is stripped out, so a dedicated exact-prefix/suffix
# comparison reads clearer than forcing it through 48's substring shape.
#
# Repo-identity gate: mirrors check 48 — ships inside the plugin cache, so
# gate on this being a real kbg-harness checkout before reading CLAUDE_DIR
# paths that only make sense there.
_is_kbg=0
if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE_DIR/.claude-plugin/plugin.json" ]; then
  [ "$(jq -r '.name // empty' "$CLAUDE_DIR/.claude-plugin/plugin.json" 2>/dev/null)" = "kbg" ] && _is_kbg=1
fi

if [ "$_is_kbg" = "1" ] && command -v jq >/dev/null 2>&1; then
  _readme="$CLAUDE_DIR/README.md"
  _manifest_version=$(jq -r '.version // empty' "$CLAUDE_DIR/.claude-plugin/plugin.json" 2>/dev/null)
  if [ -n "$_manifest_version" ] && [ -f "$_readme" ]; then
    _badge_line=$(/usr/bin/grep -F 'img.shields.io/badge/version-' "$_readme" 2>/dev/null || true)
    if [ -z "$_badge_line" ]; then
      warn "readme version-badge check 53: no shields.io version badge found in README.md — location may have moved/been reworded"
    else
      case "$_badge_line" in
        *"badge/version-${_manifest_version}-"*) : ;;
        *) warn "README.md version badge is stale vs plugin.json ($_manifest_version) — bump the shields.io badge on or near the top of README.md" ;;
      esac
    fi
  fi
  unset _readme _manifest_version _badge_line
fi
unset _is_kbg
