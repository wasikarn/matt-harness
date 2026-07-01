#!/usr/bin/env bash
# 3. Symlink integrity — hooks (recurse: hooks live in gates/, advisory/, …)
# globstar with set -e exits if the directory is empty and the pattern expands
# literally to itself; use find so empty/minimal fixtures don't kill the audit.
if [ -d "$CLAUDE_DIR/hooks" ]; then
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
    # OR present in the kbg@kobig plugin cache (delivery model is plugin-enable,
    # not symlink-farm — see #2/#3b for the equivalent pattern on skills/agents/…).
    if grep -q "$name" "$CLAUDE_DIR/hooks/hooks.json" 2>/dev/null \
       && ! grep -q "$name" "$SETTINGS" 2>/dev/null; then continue; fi
    if is_plugin_delivered hooks "$name"; then continue; fi
    if [ ! -L "$HOME/.claude/hooks/$name" ]; then
      crit "hook '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
    fi
  done < <(find "$CLAUDE_DIR/hooks" -type f -not -path '*__pycache__*' -print0 2>/dev/null || true)
fi

# 3b. Symlink integrity — agents and commands.
# Regression guard: 14 agents (and at least one command) were committed to the
# repo but never symlinked into ~/.claude/, so Claude Code could not load them.
# No check caught it because symlink integrity covered only skills and hooks.
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  if [ ! -L "$HOME/.claude/agents/$name" ] && ! is_plugin_delivered agents "${name%.md}"; then
    crit "agent '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done
for f in "$CLAUDE_DIR/commands"/*.md "$CLAUDE_DIR/commands"/*/COMMAND.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  # A nested commands/<dir>/COMMAND.md loads by its parent dir name, not "COMMAND".
  case "$f" in */COMMAND.md) name="$(basename "$(dirname "$f")").md" ;; esac
  if [ ! -L "$HOME/.claude/commands/$name" ] && ! is_plugin_delivered commands "${name%.md}"; then
    crit "command '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done

# 3c. Symlink integrity — output-styles.
# Output styles ship as .md files in claude/output-styles/ and must symlink
# to ~/.claude/output-styles/<name>.md so Claude Code can apply them via
# /output-style. Same regression class as §3b (committed but not loadable).
for f in "$CLAUDE_DIR/output-styles"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  if [ ! -L "$HOME/.claude/output-styles/$name" ] && ! is_plugin_delivered output-styles "${name%.md}"; then
    crit "output-style '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done

