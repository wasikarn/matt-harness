#!/usr/bin/env bash
# acli-edit.sh — thin wrapper around acli-edit.py for safe Jira description edits.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --dry-run support: strip the flag from args, set DRY_RUN=true
DRY_RUN=false
new_args=()
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ]; then
    DRY_RUN=true
  else
    new_args+=("$arg")
  fi
done
set -- "${new_args[@]}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "usage: acli-edit.sh KEY (DESC.md | - | --remove-section \"H\" | --replace-section \"H\" NEW.md) [--dry-run]"
  exit 0
fi
if [ $# -lt 2 ]; then
  echo "usage: acli-edit.sh KEY (DESC.md | - | --remove-section \"H\" | --replace-section \"H\" NEW.md) [--dry-run]" >&2
  exit 1
fi

KEY="$1"
HEADING="" SRC=""
case "$2" in
  --remove-section)  MODE=remove;  HEADING="${3:?--remove-section needs a \"HEADING\"}" ;;
  --replace-section) MODE=replace; HEADING="${3:?--replace-section needs a \"HEADING\"}"; SRC="${4:?--replace-section needs NEW.md|-}" ;;
  *)                 MODE=append;  SRC="$2" ;;
esac

tmp_cur=$(mktemp) tmp_new=$(mktemp) tmp_payload=$(mktemp)
trap 'rm -f "$tmp_cur" "$tmp_new" "$tmp_payload"' EXIT

acli jira workitem view "$KEY" --fields description --json > "$tmp_cur"
[ "$MODE" != "remove" ] && python3 "$SCRIPT_DIR/md2adf.py" "$SRC" > "$tmp_new"

python3 "$SCRIPT_DIR/acli-edit.py" "$MODE" "$KEY" "$tmp_cur" "$tmp_payload" "$tmp_new" "$HEADING"

if [ "$DRY_RUN" = "true" ]; then
  echo "=== Dry run — merged payload for $KEY ===" >&2
  cat "$tmp_payload"
  exit 0
fi

acli jira workitem edit --from-json "$tmp_payload" --yes --json \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['results'][0]; print(r['status'], '-', r['message'])"
