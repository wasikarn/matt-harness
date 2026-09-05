#!/usr/bin/env bash
# 3. Symlink integrity — hooks (recurse: hooks live in gates/, session/, stop/)
# globstar with set -e exits if the directory is empty and the pattern expands
# literally to itself; use find so empty/minimal fixtures don't kill the audit.
#
# CI-safety (see check 02's identical guard for the full reasoning — same
# 76-CRIT-under-isolated-$HOME reproduction, 2026-08-28 adversarial plan
# review). $HOME/.claude/hooks existing at all distinguishes symlink-mode
# (per-component CRIT stays real) from a clean checkout with neither
# delivery mechanism configured (one aggregated WARN instead).
HOOKS_LOADABILITY_UNVERIFIABLE=0
if [ "${PLUGIN_ACTIVE:-0}" -eq 0 ] && [ ! -d "$HOME/.claude/hooks" ]; then
  HOOKS_LOADABILITY_UNVERIFIABLE=1
  warn "no plugin cache and no ~/.claude/hooks symlink farm present — hook loadability unverified in this environment (expected on a clean CI checkout; not a per-hook finding)"
fi
if [ "$HOOKS_LOADABILITY_UNVERIFIABLE" -eq 0 ] && [ -d "$CLAUDE_DIR/hooks" ]; then
  while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    case "${f#"$CLAUDE_DIR"/hooks/}" in tests/*|*__pycache__*) continue;; esac
    name=$(basename "$f")
    # Skip hook libraries (sourced by hooks, not registered as hooks themselves).
    # install.sh's *.{sh,py} glob WILL symlink these so hooks can `source` them
    # at runtime via `$(dirname "$0")/_lib.sh` — but the audit shouldn't expect
    # them in settings.json. Mirrors the _* scaffold rule used in skills/.
    # *.md = co-located docs (JOURNAL-SCHEMA.md, the evidence-journal contract) —
    # not registrable hooks; install.sh's {sh,py} glob never symlinks them.
    # *.json = plugin hook registry (hooks/hooks.json), not a hook script.
    # *.bak = editor/backup residue (e.g. hooks.json.test.bak from a hook-test
    # session), not a real hook — should not be symlinked and not in F1.
    case "$name" in _*.sh|_*.py|*.md|*.json|*.bak) continue;; esac
    # Plugin-mode hooks are wired in hooks/hooks.json and resolved at runtime via
    # ${CLAUDE_PLUGIN_ROOT}; they are intentionally NOT symlinked into ~/.claude.
    # Distinguishing mark: present in hooks.json but absent from settings.json,
    # OR present in the mh@wasikarn plugin cache (delivery model is plugin-enable,
    # not symlink-farm — see #2/#3b for the equivalent pattern on skills/agents/…).
    if grep -q "$name" "$CLAUDE_DIR/hooks/hooks.json" 2>/dev/null \
       && ! grep -q "$name" "$SETTINGS" 2>/dev/null; then continue; fi
    # Transitive wiring: see hook_wired_transitively() in audit.sh, shared with check 11.
    hook_wired_transitively "$name" && continue
    if is_plugin_delivered hooks "$name"; then continue; fi
    if [ ! -L "$HOME/.claude/hooks/$name" ]; then
      crit "hook '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
    fi
  done < <(find "$CLAUDE_DIR/hooks" -type f -not -path '*__pycache__*' -print0 2>/dev/null || true)
fi

# 3b. Symlink integrity — agents.
# Regression guard: 14 agents (and, historically, at least one command — see
# CLAUDE.md) were committed to the repo but never symlinked into ~/.claude/,
# so Claude Code could not load them. No check caught it because symlink
# integrity covered only skills and hooks. (The commands/ loop that used to
# live here was dropped 2026-08-25, #112 — commands/ retired as a surface
# type entirely, every command converted to a skill.)
# CI-safety: same guard shape as check 02/the hooks loop above.
if [ "${PLUGIN_ACTIVE:-0}" -eq 0 ] && [ ! -d "$HOME/.claude/agents" ]; then
  warn "no plugin cache and no ~/.claude/agents symlink farm present — agent loadability unverified in this environment (expected on a clean CI checkout; not a per-agent finding)"
else
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  if [ ! -L "$HOME/.claude/agents/$name" ] && ! is_plugin_delivered agents "${name%.md}"; then
    crit "agent '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done
fi
