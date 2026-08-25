#!/usr/bin/env bash
# 44. Fleet-count doc-rot at named locations (skills/agents pair — "commands"
# dropped from the triple 2026-08-25, #112, since commands/ retired for good).
# A hand-maintained fleet-count string ("19-agent fleet", "11/19", "1/19", etc.) has gone stale 6 separate
# times in this repo's history, each caught by a different ad-hoc mechanism
# (a proxy smoke test, a real agent dispatch, a manual grep sweep) rather than
# a systemic check — see CHANGELOG v0.68.0. This is deliberately an EXPLICIT
# location list, not a general "any N-agent-shaped string" scanner: a general
# regex fires on every changelog entry and dated origin note (confirmed
# false-positive pattern from 3 sweeps during this check's own design). WARN,
# not CRIT — doc-rot degrades gracefully, it is not irrecoverable.
#
# Sync-seam: the 2 full-triple anchors below mirror the sed targets in
# skills/inventory/scripts/sync-fleet-counts.sh — an edit to one location list
# should prompt a check of the other. `sync-fleet-counts.sh` auto-fixes any
# WARN from a _check_triple location; the 2 _check_agent_count (prose-only)
# locations are check-only, no auto-write (see plan rationale, CHANGELOG v0.68.0).
# The two .claude-plugin manifests were dropped 2026-08-22: their description
# was rewritten as a feature-oriented text with no counts (deliberate — counts
# drift), so the anchors went permanently stale; reword-not-track, same as the
# prose spots below.
# docs/onboarding.md was deliberately NOT added as a 5th location — its mention
# is one narrative sentence, not a structured manifest, and reads worse forced
# into the "N skills · M agents · P commands" template; deleted to prose instead
# (matches the reword-not-track doctrine for the other prose spots below).
#
# Repo-identity gate: CLAUDE_DIR resolves to whichever checkout audit.sh runs
# against (dotfiles-nested vs. this flat plugin repo), and this check ships
# inside the plugin cache. A file that EXISTS in another valid context
# without ever carrying the anchor would false-WARN at anyone not running
# matt-harness — so gate the whole fragment on this being the real
# matt-harness checkout.
_is_mh=0
if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE_DIR/.claude-plugin/plugin.json" ]; then
  [ "$(jq -r '.name // empty' "$CLAUDE_DIR/.claude-plugin/plugin.json" 2>/dev/null)" = "mh" ] && _is_mh=1
fi

if [ "$_is_mh" = "1" ]; then
  # Live counts — duplicates check-01's methodology directly (3 short finds);
  # not worth a shared lib for this size, matching the sync script's own copy.
  _LIVE_SKILLS=$(safe_count find "$CLAUDE_DIR/skills" -name SKILL.md -not -path '*/_*' -not -path '*-workspace/*')
  _LIVE_AGENTS=$(safe_count find "$CLAUDE_DIR/agents" -maxdepth 1 -name '*.md' -type f)
  _EXPECT_TRIPLE="${_LIVE_SKILLS} skills · ${_LIVE_AGENTS} agents"

  # <file> <anchor> — full "N skills · M agents · P commands" match. `--`
  # before the pattern: some anchors below start with '-' ("-agent fleet"),
  # which grep would otherwise parse as an option.
  _check_triple() {
    local f="$1" anchor="$2" line
    if [ ! -f "$f" ]; then
      warn "fleet-count check 44: tracked file not found: ${f#"$CLAUDE_DIR"/} — location list may be stale (file moved/deleted)"
      return 0
    fi
    line=$(/usr/bin/grep -F -- "$anchor" "$f" 2>/dev/null || true)
    if [ -z "$line" ]; then
      warn "fleet-count check 44: anchor '$anchor' not found in ${f#"$CLAUDE_DIR"/} — location list may be stale (file moved/reworded)"
      return 0
    fi
    case "$line" in
      *"$_EXPECT_TRIPLE"*) : ;;
      *) warn "fleet-count drift in ${f#"$CLAUDE_DIR"/} near '$anchor' — live fleet is '$_EXPECT_TRIPLE'. Run skills/inventory/scripts/sync-fleet-counts.sh to fix." ;;
    esac
  }

  # <file> <anchor> — bare "N-agent" match, for prose that only states the
  # agent count (not the full skills/agents/commands triple).
  _check_agent_count() {
    local f="$1" anchor="$2" line
    if [ ! -f "$f" ]; then
      warn "fleet-count check 44: tracked file not found: ${f#"$CLAUDE_DIR"/} — location list may be stale (file moved/deleted)"
      return 0
    fi
    line=$(/usr/bin/grep -F -- "$anchor" "$f" 2>/dev/null || true)
    if [ -z "$line" ]; then
      warn "fleet-count check 44: anchor '$anchor' not found in ${f#"$CLAUDE_DIR"/} — location list may be stale (file moved/reworded)"
      return 0
    fi
    case "$line" in
      *"${_LIVE_AGENTS}-agent"*) : ;;
      *) warn "agent-count drift in ${f#"$CLAUDE_DIR"/} near '$anchor' — live agent count is $_LIVE_AGENTS" ;;
    esac
  }

  _check_triple "$CLAUDE_DIR/README.md" "real current fleet:"
  _check_triple "$CLAUDE_DIR/README.md" "| kbg-native |"
  _check_agent_count "$CLAUDE_DIR/skills/workflow/orchestrate/reference.md" "-agent survivor set"
  _check_agent_count "$CLAUDE_DIR/docs/agent-voice-extension.md" "-agent fleet"

  unset -f _check_triple _check_agent_count
  unset _LIVE_SKILLS _LIVE_AGENTS _EXPECT_TRIPLE
fi
unset _is_mh
