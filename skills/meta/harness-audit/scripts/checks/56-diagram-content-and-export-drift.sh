#!/usr/bin/env bash
# 56. Diagram content, export, and a11y drift — the check the 2026-08-28
# diagram overhaul's own plan-reviewer pass demanded. Originally three
# sub-checks; the anchor-list fact-drift sub-check (formerly A) was removed
# 2026-09-01 when its sole two anchor targets, mh-core-workflow.html and
# mh-hook-profile-stack.html, were deleted as dead diagram surface (sweep #3)
# — verified as their only consumer before removal. Two sub-checks remain:
#
#   A (WARN) Export-freshness, via git status rather than mtime, across BOTH
#     hops of the real chain (html source -> svg -> png). Raw mtime was the
#     plan's first idea but breaks on a fresh clone (checkout stamps every
#     file with the same time, destroying edit-order). git status is
#     stateless and clone-safe: a clean tree has nothing to check (skip, no
#     false positive); a dirty file with a clean downstream sibling means
#     the export step was skipped. The first cut of this check only walked
#     svg->png; a deep-audit pass (2026-08-28) found that gap empirically —
#     editing an .html source with no svg/png touch produced zero warnings,
#     even though .html is the actual authored source every diagram in this
#     repo starts from, making it the MORE likely place to forget the
#     export step, not the less likely one. Both hops are checked now.
#
#   B (WARN, graceful-skip) Wires diagram-design's own self_check.py and
#     verify-geometry.py over docs/diagrams/*.html — hero-diagram.html was
#     failing self_check.py on 4 a11y counts with
#     nothing catching it before this check existed. The plugin isn't
#     bundled with matt-harness (portability doctrine, CLAUDE.md's
#     Architecture section) — an info(), not a warn(), announces the skip
#     when it's absent, same tier check 50 uses for the mattpocock-skills
#     companion plugin being absent.
_is_mh=0
if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE_DIR/.claude-plugin/plugin.json" ]; then
  [ "$(jq -r '.name // empty' "$CLAUDE_DIR/.claude-plugin/plugin.json" 2>/dev/null)" = "mh" ] && _is_mh=1
fi

if [ "$_is_mh" = "1" ]; then

  # ── Sub-check A: export freshness via git status, not mtime ──────────
  # A fresh clone has nothing dirty, so nothing to check there (clone-safe
  # by construction) — this only fires against a file actually edited in
  # THIS working tree, which is exactly the session where forgetting to
  # re-export is possible.
  if command -v git >/dev/null 2>&1 && git -C "$CLAUDE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Hop 1: html (authored source) -> svg. This is the hop that actually
    # matters most — every diagram in this repo is authored by editing the
    # .html first, so "edited html, forgot to re-export anything" is the
    # realistic failure, not just "re-exported svg, forgot png."
    for _html in "$CLAUDE_DIR"/docs/diagrams/*.html; do
      [ -f "$_html" ] || continue
      _html_status=$(git -C "$CLAUDE_DIR" status --porcelain -- "$_html" 2>/dev/null || true)
      [ -n "$_html_status" ] || continue
      # Not every .html here has its own svg export. Only assert freshness
      # when a sibling svg already exists.
      _svg="${_html%.html}.svg"
      [ -f "$_svg" ] || continue
      _svg_status=$(git -C "$CLAUDE_DIR" status --porcelain -- "$_svg" 2>/dev/null || true)
      if [ -z "$_svg_status" ]; then
        warn "diagram-drift check 56: ${_html#"$CLAUDE_DIR"/} changed but ${_svg#"$CLAUDE_DIR"/} wasn't re-exported in this working tree — the svg (and whatever png depends on it) is stale"
      fi
    done
    unset _html _html_status _svg _svg_status

    # Hop 2: svg (export) -> png (what README actually embeds).
    for _svg in "$CLAUDE_DIR"/docs/diagrams/*.svg; do
      [ -f "$_svg" ] || continue
      _svg_status=$(git -C "$CLAUDE_DIR" status --porcelain -- "$_svg" 2>/dev/null || true)
      [ -n "$_svg_status" ] || continue
      # Not every svg here ships a PNG sibling. Only assert freshness when a
      # PNG sibling already exists; a missing one isn't this check's
      # business to demand.
      _png="${_svg%.svg}.png"
      [ -f "$_png" ] || continue
      _png_status=$(git -C "$CLAUDE_DIR" status --porcelain -- "$_png" 2>/dev/null || true)
      if [ -z "$_png_status" ]; then
        warn "diagram-drift check 56: ${_svg#"$CLAUDE_DIR"/} changed but ${_png#"$CLAUDE_DIR"/} wasn't re-exported in this working tree — stale PNG likely shipping (README embeds the PNG, not the SVG)"
      fi
    done
    unset _svg _svg_status _png _png_status
  fi

  # ── Sub-check B: a11y/geometry, via the diagram-design plugin ────────
  # Not bundled with matt-harness (CLAUDE.md's Architecture section) —
  # graceful info-skip when absent, same tier check 50 uses for the
  # mattpocock-skills companion plugin.
  _DD_BASE="$HOME/.claude/plugins/cache/diagram-design/diagram-design"
  _DD_VER=""
  if [ -d "$_DD_BASE" ]; then
    _DD_VER=$(find "$_DD_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | sort -V | tail -1)
  fi
  _SELF_CHECK="$_DD_BASE/${_DD_VER:-x}/skills/diagram-design/scripts/self_check.py"
  _VERIFY_GEOM="$_DD_BASE/${_DD_VER:-x}/scripts/verify-geometry.py"
  if [ -n "$_DD_VER" ] && [ -f "$_SELF_CHECK" ] && [ -f "$_VERIFY_GEOM" ] && command -v python3 >/dev/null 2>&1; then
    for _f in "$CLAUDE_DIR"/docs/diagrams/*.html; do
      [ -f "$_f" ] || continue
      _out=$(python3 "$_SELF_CHECK" "$_f" 2>&1 || true)
      case "$_out" in
        OK*) : ;;
        *) warn "diagram-drift check 56: self_check.py failed on ${_f#"$CLAUDE_DIR"/} — $(printf '%s' "$_out" | tr '\n' ' ')" ;;
      esac
      # Extract the finding count and compare numerically — a bare
      # `*"0 finding"*` glob match is a false-negative trap: "10 finding(s)"
      # and "20 finding(s)" both contain the literal substring "0 finding",
      # so a real double-digit geometry failure would have silently passed
      # as clean. Found and fixed by deep-audit (2026-08-28).
      _out=$(python3 "$_VERIFY_GEOM" "$_f" 2>&1 || true)
      # `|| true` neutralises `set -e` propagation when neither grep matches
      # (verify-geometry.py output with no "N finding" text at all — e.g. it
      # raised instead) — same idiom as check 34's `triggers=$(... ) || true`,
      # same bug class as check 50:125, both confirmed by the 2026-08-30 sweep.
      _geom_count=$(printf '%s' "$_out" | grep -oE '[0-9]+ finding' | grep -oE '^[0-9]+' | head -1) || true
      if [ "${_geom_count:-}" != "0" ]; then
        warn "diagram-drift check 56: verify-geometry.py failed on ${_f#"$CLAUDE_DIR"/} — $(printf '%s' "$_out" | tr '\n' ' ')"
      fi
    done
    unset _f _out _geom_count
  else
    info "diagram-design plugin not found under ${_DD_BASE/#"$HOME"/\~} — a11y/geometry sub-check skipped for docs/diagrams (install the plugin to restore it)"
  fi
  unset _DD_BASE _DD_VER _SELF_CHECK _VERIFY_GEOM
fi
unset _is_mh
