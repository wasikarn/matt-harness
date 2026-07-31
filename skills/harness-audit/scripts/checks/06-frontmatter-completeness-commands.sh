#!/usr/bin/env bash
# 6. Frontmatter completeness — commands
# Per code.claude.com/docs/en/skills (custom commands were merged into the
# skills frontmatter schema; slash-commands redirects there): `name:` IS a
# documented, valid field in the schema that governs `.claude/commands/`
# files too — it just isn't what determines the invoked command name there.
# For a file under `.claude/commands/`, the command name always comes from
# the file name (without extension), regardless of `name:`. Warn-only for
# missing name: (preserves audit visibility without blocking on a field
# that doesn't affect invocation for this file location).
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

