#!/bin/bash
set -euo pipefail

# Source _lib.sh for journal_append; provide no-op fallback if unavailable.
_LIB="$(cd "$(dirname "$0")" && pwd)/../hooks/_lib.sh"
if [ -f "$_LIB" ]; then
  # shellcheck source=../hooks/_lib.sh
  source "$_LIB" 2>/dev/null || true
fi
if ! command -v journal_append >/dev/null 2>&1; then
  journal_append() { :; }
fi

TEAM=""
DRY_RUN=0

show_help() {
  cat <<'EOF'
Usage: lock-reap.sh --team="team-name" [--dry-run]
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --team=*) TEAM="${1#*=}" ;;
    --dry-run) DRY_RUN=1 ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; show_help >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$TEAM" ]; then
  echo "ERROR: missing required argument --team" >&2
  show_help >&2
  exit 1
fi

_epoch_from_iso() {
  python3 -c 'import datetime,sys; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "$1"
}

_now_epoch() {
  date -u +%s
}

LOCK_BASE="${HOME}/.claude/locks/${TEAM}"

if [ ! -d "$LOCK_BASE" ]; then
  echo "No locks found for team $TEAM"
  exit 0
fi

BROKEN=0
for lock_json in "$LOCK_BASE"/*/lock.json; do
  [ -f "$lock_json" ] || continue
  expires_at=$(jq -r '.expires_at // empty' "$lock_json" 2>/dev/null) || expires_at=""
  if [ -z "$expires_at" ]; then
    expires_at="1970-01-01T00:00:00Z"
  fi
  exp_epoch=$(_epoch_from_iso "$expires_at")
  now_epoch=$(_now_epoch)
  if [ "$now_epoch" -gt "$exp_epoch" ]; then
    dir_name=$(basename "$(dirname "$lock_json")")
    resource_id=$(jq -r '.resource_id // empty' "$lock_json" 2>/dev/null) || resource_id="$dir_name"
    echo "BROKEN: $dir_name (resource=$resource_id expired=$expires_at)"
    BROKEN=$((BROKEN + 1))
    if [ "$DRY_RUN" -eq 0 ]; then
      journal_append "lock-reap" "stale_lock_broken" "{\"team\":\"$TEAM\",\"resource\":\"$resource_id\",\"expired_at\":\"$expires_at\"}" >/dev/null 2>&1 || true
      rm -rf "$(dirname "$lock_json")"
    fi
  fi
done

if [ "$BROKEN" -eq 0 ]; then
  echo "No stale locks found"
fi
