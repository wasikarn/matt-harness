#!/usr/bin/env bash
# 13. Memory index drift
# Process substitution (not a pipe) keeps the loop in the current shell so
# crit() increments propagate — a `grep | while` runs in a subshell and the
# count would be lost (the CRIT line prints but the exit code under-reports).
MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"
if [ -f "$MEMORY_INDEX" ]; then
  while IFS= read -r memf; do
    mem_path="$MEMORY_DIR/$memf"
    if [ ! -f "$mem_path" ]; then
      crit "memory references '$memf' but file missing"
    fi
  done < <(grep -oE '\([^)]+\.md\)' "$MEMORY_INDEX" | tr -d '()' | sort -u || true)
fi

