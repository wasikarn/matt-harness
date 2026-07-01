#!/usr/bin/env bash
# 6. Frontmatter completeness — commands
# Per code.claude.com/docs/en/slash-commands: a command file under
# `.claude/commands/<name>.md` derives its command name from the file name
# (without extension). `name:` frontmatter is NOT part of the slash-command
# schema — it's a plugin-root `SKILL.md` construct. Warn-only for missing name:
# (preserves audit visibility without blocking on a field the schema doesn't
# require).
for f in "$CLAUDE_DIR/commands"/*.md "$CLAUDE_DIR/commands"/*/COMMAND.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  case "$f" in */COMMAND.md) name=$(basename "$(dirname "$f")") ;; esac
  if ! grep -q '^---' "$f"; then
    crit "command '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "command '$name' missing description: in frontmatter"
  fi
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    warn "command '$name' missing name: in frontmatter (optional — command name derives from filename per slash-commands docs)"
  fi
  # NOTE: a `type: command` frontmatter requirement was retired 2026-06-16 — it
  # was self-referential (the field existed only to satisfy this check; nothing
  # functional read it, it is not in the official slash-command schema, and the
  # commands/ directory already determines command-ness). See CLAUDE.md
  # "disable-model-invocation — selection criterion" note.
done

