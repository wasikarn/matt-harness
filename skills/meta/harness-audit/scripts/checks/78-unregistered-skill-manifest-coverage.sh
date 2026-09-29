#!/usr/bin/env bash
# 78. Unregistered skill (GH #211). `.claude-plugin/plugin.json`'s `skills` array is additive to the
# default one-level `skills/<name>` scan, and this repo nests skills one level deeper
# (`skills/<bucket>/<name>`), so a skill loads only if a manifest entry covers its directory. A
# whole-bucket entry (`./skills/meta/`) covers every skill in it; a per-skill entry
# (`./skills/workflow/ideate/`) covers one. A new skill under a per-skill bucket with no entry
# never loads, and nothing else notices: check 02 goes silent once the cache holds the file, check 05
# accepts the bucket, check 75 only fires when a doc names `mh:<skill>`. Skills that are meant to
# stay unshipped are listed in MANIFEST_EXPECTED_EXCLUDED (audit.sh), shared with check 75.
_MANIFEST_JSON="$CLAUDE_DIR/.claude-plugin/plugin.json"
if [ -f "$_MANIFEST_JSON" ]; then
  _unregistered=$(python3 - "$CLAUDE_DIR" "$_MANIFEST_JSON" "${MANIFEST_EXPECTED_EXCLUDED:-}" <<'PYEOF'
import json, os, sys

claude_dir, manifest_path, allow = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
try:
    entries = json.load(open(manifest_path)).get("skills")
except Exception:
    sys.exit(0)
if not isinstance(entries, list):
    sys.exit(0)
prefixes = [e.lstrip("./").rstrip("/") for e in entries if isinstance(e, str)]
for root, dirs, files in os.walk(os.path.join(claude_dir, "skills")):
    dirs[:] = sorted(d for d in dirs if not d.startswith("_") and not d.endswith("-workspace"))
    if "SKILL.md" not in files:
        continue
    rel = os.path.relpath(root, claude_dir)
    if os.path.basename(rel) in allow:
        continue
    if not any(rel == p or rel.startswith(p + "/") for p in prefixes):
        print(rel)
PYEOF
)
  for _rel in $_unregistered; do
    crit "skill '$_rel' is not covered by any .claude-plugin/plugin.json skills entry, so it will never load; add \"./$_rel/\" (or its bucket) to the manifest, or list its name in MANIFEST_EXPECTED_EXCLUDED in audit.sh if it is meant to stay unshipped"
  done
  unset _unregistered _rel
fi
unset _MANIFEST_JSON
