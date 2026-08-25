#!/usr/bin/env bash
# 18. Bundled shell scripts pass syntax check
while IFS= read -r f; do
  if ! bash -n "$f" 2>/dev/null; then
    crit "bundled script '${f#$CLAUDE_DIR/}' has a shell syntax error"
  fi
done < <(find "$CLAUDE_DIR/skills" -name '*.sh' 2>/dev/null || true)

