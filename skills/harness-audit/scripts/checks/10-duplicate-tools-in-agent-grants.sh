# 10. Duplicate tools in agent grants
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  tools=$(fm_get "$f" "tools" --block)
  if [ -n "$tools" ]; then
    dups=$(echo "$tools" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | uniq -d)
    if [ -n "$dups" ]; then
      warn "agent '$name' duplicate tools: $dups"
    fi
  fi
done

