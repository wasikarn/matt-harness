#!/usr/bin/env bash
# acli-set-desc.sh — REPLACE an issue's entire description from a Markdown file.
#
# md2adf.py DESC.md → {"issues":[KEY],"description":<ADF doc>} → edit --from-json.
# This OVERWRITES the whole body. For append / single-section edits that PRESERVE
# the original, use acli-edit.sh instead.
#
# Why it exists: create-bulk --from-json rejects rich-markdown descriptions, so the
# verified flow is bulk-create with short placeholders, then set the real body per
# ticket with this script (reference_acli_bulk_create_descriptions; TP-558..566).
#
# Usage:
#   bash acli-set-desc.sh KEY desc.md            # replace (asks acli to confirm via --yes)
#   bash acli-set-desc.sh KEY desc.md --dry-run  # render the new body, send nothing
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

KEY="${1:-}"
DESC="${2:-}"
DRY="${3:-}"
if [ -z "$KEY" ] || [ -z "$DESC" ]; then
  echo "usage: acli-set-desc.sh KEY desc.md [--dry-run]" >&2
  exit 2
fi
[ -f "$DESC" ] || { echo "acli-set-desc: no such file: $DESC" >&2; exit 1; }

# Bare ADF doc (no -s/-p/-t → md2adf prints just the description document).
ADF="$(python3 "$HERE/md2adf.py" "$DESC")"

if [ "$DRY" = "--dry-run" ]; then
  echo "⚠️  REPLACES the ENTIRE description of $KEY (use acli-edit.sh to append/section-edit)."
  echo "--- new description preview ---"
  printf '%s' "$ADF" | python3 "$HERE/adf2md.py"
  echo "--- (dry-run — nothing sent) ---"
  exit 0
fi

TMP="$(mktemp -t acli-set-desc.XXXXXX.json)"
trap 'rm -f "$TMP"' EXIT
# Pass KEY as argv[1] so shell meta-characters (especially single quotes) never
# reach a Python string literal. ADF arrives via stdin.
printf '%s' "$ADF" | python3 -c "import json,sys; print(json.dumps({'issues':[sys.argv[1]],'description':json.load(sys.stdin)}))" "$KEY" > "$TMP"
acli jira workitem edit --from-json "$TMP" --yes
