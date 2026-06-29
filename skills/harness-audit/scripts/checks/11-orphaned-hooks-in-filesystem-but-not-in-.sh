#!/usr/bin/env bash
# 11. Orphaned hooks (in filesystem but not in settings.json)
if [ -f "$SETTINGS" ]; then
  for f in "$CLAUDE_DIR/hooks"/**/*; do
    [ -f "$f" ] || continue
    case "${f#"$CLAUDE_DIR"/hooks/}" in tests/*|*__pycache__*) continue;; esac
    hook_name=$(basename "$f")
    # Skip hook libraries (sourced by hooks, not registered as hooks themselves).
    # The _lib.sh prefix matches the existing project scaffold convention used
    # in skills/ and agents/; install.sh's hooks glob *.{sh,py} symlinks it so
    # hook scripts can `source "$(dirname "$0")/_lib.sh"` at runtime.
    # *.md = co-located docs (JOURNAL-SCHEMA.md) — not hooks, never in settings.
    # *.json = plugin hook registry (hooks/hooks.json), not a hook script.
    # *.bak = editor/backup residue (e.g. hooks.json.test.bak from a hook-test
    # session), not a real hook — matches the F1 skip pattern in #3.
    case "$hook_name" in _*.sh|_*.py|*.bak|*.md|*.json) continue;; esac
    # Wired = settings.json (symlink mode) OR hooks/hooks.json (plugin mode).
    if ! grep -q "$hook_name" "$SETTINGS" \
       && ! grep -q "$hook_name" "$CLAUDE_DIR/hooks/hooks.json" 2>/dev/null; then
      crit "hook '$hook_name' exists in hooks/ but not wired in settings.json or hooks.json"
    fi
  done
fi

