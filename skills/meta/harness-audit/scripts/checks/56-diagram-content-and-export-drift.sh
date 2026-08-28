#!/usr/bin/env bash
# 56. Diagram content, export, and a11y drift — the check the 2026-08-28
# diagram overhaul's own plan-reviewer pass demanded, and which caught a real
# bug on its FIRST write: mh-hook-profile-stack.html's headline ("18 route
# through dispatch-single.sh") never matched its own drawn tier boxes
# (2 strict + 8 standard + 7 minimal = 17) — README.md said the same wrong
# 18 in prose two paragraphs above a bullet list that already had the right
# 7/8/2/1 breakdown. Fixed same commit as this check. Three sub-checks:
#
#   A (WARN) Anchor-list fact drift. Deliberately NOT a general "any N-shaped
#     string" scanner — check 44's own header names that exact design as
#     already tried and rejected (false-positives on every changelog entry
#     and dated origin note). Each anchor names a STABLE substring (never
#     containing the live number itself, or a value change couldn't be
#     detected) plus the exact numeral substring expected to sit near it,
#     re-derived from hooks.json / pretooluse-table.json / hooks/advisory/ —
#     never carried forward from README prose or an existing diagram, same
#     ground rule the diagrams themselves were redrawn under. Skill/agent/
#     bucket counts are already check 44's job — not duplicated here.
#     Tier semantics (the "volume knob, not severity" framing) is a prose
#     claim with no single canonical string, deliberately left to the plan's
#     own manual adversarial re-grep pass rather than mechanized here.
#
#   B (WARN) PNG-freshness, via git status rather than mtime. Raw mtime was
#     the plan's first idea but breaks on a fresh clone (checkout stamps
#     every file with the same time, destroying edit-order). git status is
#     stateless and clone-safe: a clean tree has nothing to check (skip, no
#     false positive); an svg that's dirty (modified or untracked) with a
#     clean sibling png means the export step was skipped — exactly the
#     failure Verification §2 in the plan named as "the likeliest way this
#     ships wrong."
#
#   C (WARN, graceful-skip) Wires diagram-design's own self_check.py and
#     verify-geometry.py over docs/diagrams/*.html + docs/promo/*.html —
#     hero-diagram.html was failing self_check.py on 4 a11y counts with
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

  # ── Sub-check A: anchor-list fact drift ──────────────────────────────
  _HOOK_REG_TOTAL=$(python3 -c "
import json
d = json.load(open('$CLAUDE_DIR/hooks/hooks.json'))
print(sum(len(m.get('hooks', [])) for ev in d.get('hooks', {}).values() for m in ev))
" 2>/dev/null || true)
  _GATE_RULES=$(python3 -c "
import json
print(len(json.load(open('$CLAUDE_DIR/hooks/pretooluse-table.json'))))
" 2>/dev/null || true)
  _TIER_COUNTS=$(python3 -c "
import json
d = json.load(open('$CLAUDE_DIR/hooks/hooks.json'))
c = {'strict': 0, 'standard': 0, 'minimal': 0, 'untiered': 0}
for ev, matchers in d.get('hooks', {}).items():
    for m in matchers:
        for h in m.get('hooks', []):
            args = h.get('args', [])
            tier = args[2] if len(args) > 2 else 'untiered'
            c[tier] = c.get(tier, 0) + 1
print(c['strict'], c['standard'], c['minimal'], c['untiered'])
" 2>/dev/null || true)
  _ADVISORY=$(safe_count find "$CLAUDE_DIR/hooks/advisory" -maxdepth 1 -name '*.sh' -type f)

  if [ -n "$_HOOK_REG_TOTAL" ] && [ -n "$_GATE_RULES" ] && [ -n "$_TIER_COUNTS" ]; then
    read -r _STRICT _STANDARD _MINIMAL _UNTIERED <<< "$_TIER_COUNTS"
    _HOOK_REG_TIERED=$((_STRICT + _STANDARD + _MINIMAL))

    # <file> <anchor, no live number in it> <expect substring> [grep -A lines]
    _check_anchor() {
      local f="$1" anchor="$2" expect="$3" ctx="${4:-0}" line
      if [ ! -f "$f" ]; then
        warn "diagram-drift check 56: tracked file not found: ${f#"$CLAUDE_DIR"/} — anchor list may be stale (file moved/deleted)"
        return 0
      fi
      line=$(/usr/bin/grep -A "$ctx" -F -- "$anchor" "$f" 2>/dev/null || true)
      if [ -z "$line" ]; then
        warn "diagram-drift check 56: anchor '$anchor' not found in ${f#"$CLAUDE_DIR"/} — anchor list may be stale (file moved/reworded)"
        return 0
      fi
      case "$line" in
        *"$expect"*) : ;;
        *) warn "diagram-drift in ${f#"$CLAUDE_DIR"/} near '$anchor' — live value is '$expect'" ;;
      esac
    }

    _num_word_cap() {
      case "$1" in
        1) echo One ;; 2) echo Two ;; 3) echo Three ;; 4) echo Four ;; 5) echo Five ;;
        6) echo Six ;; 7) echo Seven ;; 8) echo Eight ;; 9) echo Nine ;; 10) echo Ten ;;
        *) echo "" ;;
      esac
    }

    # hooks.json total (18)
    _check_anchor "$CLAUDE_DIR/README.md" "hook registrations across" "${_HOOK_REG_TOTAL} hook registrations across"
    _check_anchor "$CLAUDE_DIR/README.md" "in \`hooks/hooks.json\` (" "${_HOOK_REG_TOTAL} in \`hooks/hooks.json\` (${_MINIMAL} minimal / ${_STANDARD} standard / ${_STRICT} strict / ${_UNTIERED} untiered dispatcher entry)"
    _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-core-workflow.html" "hook registrations</text>" "${_HOOK_REG_TOTAL} hook registrations</text>"

    # hooks.json tiered subset routed through dispatch-single.sh (17)
    _check_anchor "$CLAUDE_DIR/README.md" "of those route through" "${_HOOK_REG_TIERED} of those route through"
    _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-hook-profile-stack.html" "REGISTRATIONS · hooks/dispatch-single.sh" "${_HOOK_REG_TIERED} REGISTRATIONS · hooks/dispatch-single.sh"

    # gate rules in pretooluse-table.json (11)
    _check_anchor "$CLAUDE_DIR/README.md" "hook that fans out to" "fans out to ${_GATE_RULES} gate rules"
    _check_anchor "$CLAUDE_DIR/README.md" "aren't part of this stack at all" "The ${_GATE_RULES} \`gate:*\`"
    _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-core-workflow.html" "fans out to" "fans out to ${_GATE_RULES} gate rules"
    _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-hook-profile-stack.html" "RULES · hooks/dispatch-pretooluse.sh" "${_GATE_RULES} RULES · hooks/dispatch-pretooluse.sh"

    # per-tier handler counts on the profile-stack diagram (2 strict / 8 standard / 7 minimal)
    _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-hook-profile-stack.html" "TIER: STRICT" "${_STRICT} handlers" 1
    _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-hook-profile-stack.html" "TIER: STANDARD" "${_STANDARD} handlers" 1
    _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-hook-profile-stack.html" "TIER: MINIMAL" "${_MINIMAL} handlers" 1

    # advisory sensor count — only ever spelled out in prose (7 -> "Seven")
    _advisory_word=$(_num_word_cap "$_ADVISORY")
    if [ -n "$_advisory_word" ]; then
      _check_anchor "$CLAUDE_DIR/docs/diagrams/mh-core-workflow.html" "advisory sensors journal after each tool call" "${_advisory_word} advisory sensors journal after each tool call"
    else
      warn "diagram-drift check 56: advisory sensor count ($_ADVISORY) has no word-form mapping — verify docs/diagrams/mh-core-workflow.html's desc by hand"
    fi

    unset -f _check_anchor _num_word_cap
    unset _STRICT _STANDARD _MINIMAL _UNTIERED _HOOK_REG_TIERED _advisory_word
  else
    warn "diagram-drift check 56: could not derive live hook/gate counts from hooks.json or pretooluse-table.json (parse failure) — sub-check A skipped"
  fi
  unset _HOOK_REG_TOTAL _GATE_RULES _TIER_COUNTS _ADVISORY

  # ── Sub-check B: PNG freshness via git status, not mtime ─────────────
  # A fresh clone has nothing dirty, so nothing to check there (clone-safe
  # by construction) — this only fires against an svg actually edited in
  # THIS working tree, which is exactly the session where forgetting to
  # re-export is possible.
  if command -v git >/dev/null 2>&1 && git -C "$CLAUDE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for _svg in "$CLAUDE_DIR"/docs/diagrams/*.svg "$CLAUDE_DIR"/docs/promo/*.svg; do
      [ -f "$_svg" ] || continue
      _svg_status=$(git -C "$CLAUDE_DIR" status --porcelain -- "$_svg" 2>/dev/null || true)
      [ -n "$_svg_status" ] || continue
      # Not every svg here ships a PNG sibling — docs/promo/hero-diagram.svg
      # is embedded directly via <object> in selling-points.html, never a
      # PNG. Only assert freshness when a PNG sibling already exists; a
      # missing one isn't this check's business to demand.
      _png="${_svg%.svg}.png"
      [ -f "$_png" ] || continue
      _png_status=$(git -C "$CLAUDE_DIR" status --porcelain -- "$_png" 2>/dev/null || true)
      if [ -z "$_png_status" ]; then
        warn "diagram-drift check 56: ${_svg#"$CLAUDE_DIR"/} changed but ${_png#"$CLAUDE_DIR"/} wasn't re-exported in this working tree — stale PNG likely shipping (README embeds the PNG, not the SVG)"
      fi
    done
    unset _svg _svg_status _png _png_status
  fi

  # ── Sub-check C: a11y/geometry, via the diagram-design plugin ────────
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
    for _f in "$CLAUDE_DIR"/docs/diagrams/*.html "$CLAUDE_DIR"/docs/promo/*.html; do
      [ -f "$_f" ] || continue
      # docs/promo/selling-points.html is a sell sheet, not a diagram — the
      # plan that built this check documented its self_check.py findings
      # (an <object> embed, no accessible SVG of its own) as out of scope by
      # design, not a defect. Warning on it forever would be exactly the
      # permanent-noise WARN floor check 44's own header warns against.
      case "$_f" in
        */docs/promo/selling-points.html) continue ;;
      esac
      _out=$(python3 "$_SELF_CHECK" "$_f" 2>&1 || true)
      case "$_out" in
        OK*) : ;;
        *) warn "diagram-drift check 56: self_check.py failed on ${_f#"$CLAUDE_DIR"/} — $(printf '%s' "$_out" | tr '\n' ' ')" ;;
      esac
      _out=$(python3 "$_VERIFY_GEOM" "$_f" 2>&1 || true)
      case "$_out" in
        *"0 finding"*) : ;;
        *) warn "diagram-drift check 56: verify-geometry.py failed on ${_f#"$CLAUDE_DIR"/} — $(printf '%s' "$_out" | tr '\n' ' ')" ;;
      esac
    done
    unset _f _out
  else
    info "diagram-design plugin not found under ${_DD_BASE/#"$HOME"/\~} — a11y/geometry sub-check skipped for docs/diagrams and docs/promo (install the plugin to restore it)"
  fi
  unset _DD_BASE _DD_VER _SELF_CHECK _VERIFY_GEOM
fi
unset _is_mh
