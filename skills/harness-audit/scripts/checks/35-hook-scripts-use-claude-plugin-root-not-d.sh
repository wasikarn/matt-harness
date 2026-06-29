#!/usr/bin/env bash
# 35. Hook scripts/commands use CLAUDE_PLUGIN_ROOT, never CLAUDE_PLUGIN_DIR.
# CLAUDE_PLUGIN_DIR is NOT a real Claude Code variable (docs:
# code.claude.com/docs/en/hooks "Reference scripts by path" — the documented
# variable is CLAUDE_PLUGIN_ROOT, the plugin install dir, set for all source
# types incl. directory marketplaces). CLAUDE_PLUGIN_DIR is undefined and
# expands empty, so `bash "${CLAUDE_PLUGIN_DIR}/hooks/..."` collapses to
# `bash /hooks/...` and the ENTIRE hook fleet silently fails — gates, advisory
# sensors, doctrine bootstrap all off, with no CRIT surfacing. This is an
# enforcement-gate bypass class: a one-token typo disables every deny-gate.
# Regression guard for the 2026-06-29 fix.
# Scope: hooks/ only (commands in hooks.json + every hook script). The check
# itself lives under skills/ and contains the literal search term, so scanning
# the whole repo would self-match — hooks/ is both the complete bug surface
# and self-match-free.
if [ -d "$CLAUDE_DIR/hooks" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    file=${line%%:*}; rest=${line#*:}; lineno=${rest%%:*}
    crit "hook '${file#"$CLAUDE_DIR"/}:${lineno}' references CLAUDE_PLUGIN_DIR (not a real CC variable — use CLAUDE_PLUGIN_ROOT; expands empty and silently disables the whole hook fleet)"
  done < <(grep -rn 'CLAUDE_PLUGIN_DIR' "$CLAUDE_DIR/hooks" \
            --include='*.sh' --include='*.py' --include='*.json' \
            --exclude-dir=tests --exclude-dir=__pycache__ 2>/dev/null || true)
fi