#!/usr/bin/env bash
# 1. Fleet count
AGENTS=$(safe_count find "$CLAUDE_DIR/agents" -maxdepth 1 -name '*.md' -type f)
SKILLS=$(safe_count find "$CLAUDE_DIR/skills" -maxdepth 1 -type d -not -name '_*' -not -name 'skills')
COMMANDS=$(safe_count find "$CLAUDE_DIR/commands" -maxdepth 1 -name '*.md' -type f)
HOOKS=$(safe_count find "$CLAUDE_DIR/hooks" -type f \( -name '*.sh' -o -name '*.py' \) -not -path '*__pycache__*' -not -name '_*')
OUTPUT_STYLES=$(safe_count find "$CLAUDE_DIR/output-styles" -maxdepth 1 -name '*.md' -type f)
THEMES=$(safe_count find "$CLAUDE_DIR/themes" -maxdepth 1 -name '*.json' -type f)
echo "Fleet: ${AGENTS:-0} agents, ${SKILLS:-0} skills, ${COMMANDS:-0} commands, ${HOOKS:-0} hooks, ${OUTPUT_STYLES:-0} output-styles, ${THEMES:-0} themes"
# Header context, NOT a finding: a plugin cache always exists for the owner who
# dogfoods the plugin, so this fires every run and is never actionable. An
# always-on non-actionable "finding" is noise in the findings channel — print it
# as a context line alongside Root:/Fleet: instead (keeps 0C/0W/0I honest).
if [ "$PLUGIN_ACTIVE" -eq 1 ]; then
  echo "Plugin cache: $PLUGIN_CACHE (F1 treats plugin-delivered components as loadable)"
fi
echo ""

