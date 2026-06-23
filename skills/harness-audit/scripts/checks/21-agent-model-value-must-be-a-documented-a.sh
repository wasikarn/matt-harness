# 21. Agent model value — must be a documented alias or a full claude-* model ID.
# code.claude.com/docs/en/model-config: aliases sonnet|opus|haiku|fable|inherit,
# or a full ID (claude-opus-4-8, claude-sonnet-4-6, ...). model is optional
# (defaults to inherit), so a missing field is fine — only a present-but-bogus
# value warns.
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  model=$(fm_get "$f" "model" --block)
  [ -n "$model" ] || continue
  case "$model" in
    sonnet|opus|haiku|fable|inherit) ;;
    claude-*) ;;
    *) warn "agent '$name' model='$model' is not an alias (sonnet|opus|haiku|fable|inherit) or a claude-* ID" ;;
  esac
done

