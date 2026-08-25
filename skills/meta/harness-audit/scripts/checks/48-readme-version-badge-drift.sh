#!/usr/bin/env bash
# 48. README version-badge drift. The README's shields.io version badge is a
# 3rd copy of the version string alongside plugin.json/marketplace.json, and
# nothing checked it against them — confirmed missed twice in a row in this
# repo's own history (v0.68.234 then v0.68.235 both bumped the manifests but
# left the badge on v0.68.233; caught by a /kbg:deep-audit pass, not by any
# existing check). WARN, not CRIT — doc-rot degrades gracefully, same
# severity as check 44's fleet-count drift, which this mirrors structurally.
#
# Sync-seam: this is intentionally its own check, not folded into check 44 —
# 44's _check_triple asserts a *substring* match (the fleet-count string can
# sit inside a longer line), but the badge line IS the whole match target
# once the version number is stripped out, so a dedicated exact-prefix/suffix
# comparison reads clearer than forcing it through 44's substring shape.
#
# Repo-identity gate: mirrors check 44 — ships inside the plugin cache, so
# gate on this being a real matt-harness checkout before reading CLAUDE_DIR
# paths that only make sense there.
_is_mh=0
if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE_DIR/.claude-plugin/plugin.json" ]; then
  [ "$(jq -r '.name // empty' "$CLAUDE_DIR/.claude-plugin/plugin.json" 2>/dev/null)" = "mh" ] && _is_mh=1
fi

if [ "$_is_mh" = "1" ] && command -v jq >/dev/null 2>&1; then
  _readme="$CLAUDE_DIR/README.md"
  _manifest_version=$(jq -r '.version // empty' "$CLAUDE_DIR/.claude-plugin/plugin.json" 2>/dev/null)
  if [ -n "$_manifest_version" ] && [ -f "$_readme" ]; then
    # 2026-08-26: README switched to a shields.io *dynamic* JSON badge that
    # reads plugin.json's version off the develop branch at render time —
    # there is no third copy of the version string to drift any more. Accept
    # that as the fixed state; keep the static-badge comparison as the
    # fallback so a future revert to a hand-written badge is still checked.
    _dyn_line=$(/usr/bin/grep -F 'img.shields.io/badge/dynamic/json' "$_readme" 2>/dev/null || true)
    if [ -n "$_dyn_line" ] && printf '%s' "$_dyn_line" | /usr/bin/grep -qF 'plugin.json' && printf '%s' "$_dyn_line" | /usr/bin/grep -qF 'label=version'; then
      : # self-updating badge sourced from plugin.json — nothing to drift
    else
      _badge_line=$(/usr/bin/grep -F 'img.shields.io/badge/version-' "$_readme" 2>/dev/null || true)
      if [ -z "$_badge_line" ]; then
        warn "readme version-badge check 48: no shields.io version badge (static or dynamic-json) found in README.md — location may have moved/been reworded"
      else
        case "$_badge_line" in
          *"badge/version-${_manifest_version}-"*) : ;;
          *) warn "README.md version badge is stale vs plugin.json ($_manifest_version) — bump the shields.io badge on or near the top of README.md" ;;
        esac
      fi
    fi
  fi
  unset _readme _manifest_version _badge_line _dyn_line
fi
unset _is_mh
