#!/usr/bin/env bash
# 32. Reasoning-models index drift — the unified 39-model table in
# docs/reference/reasoning-models.md must list one row for every vendored
# thinking-*/SKILL.md directory under docs/reference/thinking-skills/skills/.
# A mismatch means a model was added/removed/renamed without updating the catalog.
# Mapping rule: upstream keeps the same hyphen-separated tokens, but moves a
# trailing `-thinking` to the front as the `thinking-` prefix. So
# `systems-thinking` → `thinking-systems`, while `feedback-loops` simply becomes
# `thinking-feedback-loops`.
RM_INDEX="$CLAUDE_DIR/docs/reference/reasoning-models.md"
RM_SKILLS_DIR="$CLAUDE_DIR/docs/reference/thinking-skills/skills"
if [ -f "$RM_INDEX" ] && [ -d "$RM_SKILLS_DIR" ]; then
  _rm_drift=$(python3 - "$RM_INDEX" "$RM_SKILLS_DIR" <<'PY'
import os, re, sys
index_path, skills_dir = sys.argv[1:3]

in_index = False
rows = set()
with open(index_path) as fh:
    for line in fh:
        if line.startswith('## Unified 39-model index'):
            in_index = True
            continue
        if not in_index:
            continue
        # Stop parsing when we leave the index section; downstream tables are
        # commentary/mapping tables, not part of the 39-model catalog.
        if line.startswith('## '):
            in_index = False
            continue
        if not line.startswith('|') or line.lstrip().startswith('|--') or ' Model ' in line:
            continue
        row = line.split('|')[1].strip().lower()
        # Skip the separator row and any malformed entries.
        if not row or row.startswith('---') or not re.fullmatch(r'[a-z0-9\-]+', row):
            continue
        rows.add(row)

dirs = {entry for entry in os.listdir(skills_dir)
        if os.path.isdir(os.path.join(skills_dir, entry)) and entry.startswith('thinking-')}

def row_to_dir(row):
    if row.endswith('-thinking'):
        return 'thinking-' + row[:-9]
    return 'thinking-' + row

missing_dirs = sorted(row_to_dir(r) for r in rows if row_to_dir(r) not in dirs)
orphan_dirs = sorted(d for d in dirs
                     if (d[len('thinking-'):] not in rows)
                     and ((d[len('thinking-'):] + '-thinking') not in rows))
if missing_dirs or orphan_dirs:
    msg = []
    if missing_dirs:
        msg.append(f"catalog rows with no vendored dir: {missing_dirs}")
    if orphan_dirs:
        msg.append(f"vendored dirs with no catalog row: {orphan_dirs}")
    print('; '.join(msg))
PY
)
  if [ -n "${_rm_drift:-}" ]; then
    warn "reasoning-models index drift — $_rm_drift"
  fi
else
  warn "reasoning-models reference docs missing from plugin cache: $RM_INDEX or $RM_SKILLS_DIR"
fi

