# 6. Frontmatter completeness — commands
for f in "$CLAUDE_DIR/commands"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if ! grep -q '^---' "$f"; then
    crit "command '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "command '$name' missing description: in frontmatter"
  fi
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    crit "command '$name' missing name: in frontmatter"
  fi
  # NOTE: a `type: command` frontmatter requirement was retired 2026-06-16 — it
  # was self-referential (the field existed only to satisfy this check; nothing
  # functional read it, it is not in the official slash-command schema, and the
  # commands/ directory already determines command-ness). See CLAUDE.md
  # "disable-model-invocation — selection criterion" note.
done

