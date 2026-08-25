#!/usr/bin/env bash
# 4. Frontmatter completeness — agents
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if ! grep -q '^---' "$f"; then
    crit "agent '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    crit "agent '$name' missing name: in frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "agent '$name' missing description: in frontmatter"
  fi
  # bucket: groups BOUNDARY.md's Agents table (inventory-boundary.sh, v5).
  # Missing it degrades the index (falls into "unbucketed"), doesn't break
  # loading — WARN, not CRIT. Same convention as check 05's skill version.
  if [ -z "$(fm_get "$f" "bucket")" ]; then
    warn "agent '$name' missing bucket: in frontmatter"
  fi
  # "Daisy" placeholder — exclude audit skill which documents this check — specific Anthropic upstream pattern
  if [ "$name" != "harness-audit" ] && grep -qi 'Daisy\|\\bdaisy\\b' "$f"; then
    warn "agent '$name' contains upstream 'Daisy' placeholder"
  fi
done

# 4b. Frontmatter completeness — output-styles.
# Output styles are loadable via /output-style <name>; missing frontmatter
# means the style is registered but not selectable. Symlink check (#3c)
# catches missing-symlink; this catches malformed-symlink.
for f in "$CLAUDE_DIR/output-styles"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  if ! grep -q '^---' "$f"; then
    crit "output-style '$name' missing frontmatter"
  fi
  if [ -z "$(fm_get "$f" "name" --block)" ]; then
    crit "output-style '$name' missing name: in frontmatter"
  fi
  if [ -z "$(fm_get "$f" "description" --block)" ]; then
    crit "output-style '$name' missing description: in frontmatter"
  fi
  # "Daisy" placeholder — same upstream pattern as agents/skills
  if grep -qi 'Daisy\|\\bdaisy\\b' "$f"; then
    warn "output-style '$name' contains upstream 'Daisy' placeholder"
  fi
done

