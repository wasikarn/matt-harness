#!/usr/bin/env bash
# 19. Bundled JSON files parse
while IFS= read -r f; do
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    crit "bundled JSON '${f#$CLAUDE_DIR/}' is invalid"
  fi
done < <(find "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks" -name '*.json' 2>/dev/null || true)

