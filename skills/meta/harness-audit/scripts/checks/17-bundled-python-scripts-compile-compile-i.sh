#!/usr/bin/env bash
# 17. Bundled Python scripts compile (compile() is in-memory — writes no .pyc)
while IFS= read -r f; do
  if ! python3 -c "import sys; compile(open(sys.argv[1]).read(), sys.argv[1], 'exec')" "$f" 2>/dev/null; then
    crit "bundled script '${f#$CLAUDE_DIR/}' has a Python syntax error"
  fi
done < <(find "$CLAUDE_DIR/skills" -name '*.py' -not -path '*__pycache__*' 2>/dev/null || true)

