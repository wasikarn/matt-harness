#!/bin/bash
set -euo pipefail

# NOTE: This script expects --team, --type, --resource, and --owner.
#       hooks/lifecycle/task-lifecycle.sh lines 250-254 call it with --plan-dir and --task-id,
#       which is a dead-code mismatch; the caller should align with the interface above.

# Source _lib.sh for journal_append; provide no-op fallback if unavailable.
_LIB="$(cd "$(dirname "$0")" && pwd)/../../hooks/_lib.sh"
if [ -f "$_LIB" ]; then
  # shellcheck source=../hooks/_lib.sh
  source "$_LIB" 2>/dev/null || true
fi
if ! command -v journal_append >/dev/null 2>&1; then
  journal_append() { :; }
fi

TEAM=""
TYPE=""
RESOURCE=""
OWNER=""

show_help() {
  cat <<'EOF'
Usage: lock-release.sh --team="team-name" --type=task|file --resource="id" --owner="agent-name"
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --team=*) TEAM="${1#*=}" ;;
    --type=*) TYPE="${1#*=}" ;;
    --resource=*) RESOURCE="${1#*=}" ;;
    --owner=*) OWNER="${1#*=}" ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; show_help >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$TEAM" ] || [ -z "$TYPE" ] || [ -z "$RESOURCE" ] || [ -z "$OWNER" ]; then
  echo "ERROR: missing required argument" >&2
  show_help >&2
  exit 1
fi

if [ "$TYPE" = "file" ]; then
  ENCODED_RESOURCE=$(printf '%s' "$RESOURCE" | sed 's|/|--|g')
  DIR_NAME="file--${ENCODED_RESOURCE}"
else
  DIR_NAME="task-${RESOURCE}"
fi

LOCK_DIR="${HOME}/.claude/locks/${TEAM}/${DIR_NAME}"
LOCK_FILE="${LOCK_DIR}/lock.json"

if [ ! -d "$LOCK_DIR" ]; then
  echo "released-absent"
  exit 0
fi

if [ -f "$LOCK_FILE" ]; then
  current_owner=$(jq -r '.owner // empty' "$LOCK_FILE" 2>/dev/null) || current_owner="unknown"
  if [ "$current_owner" != "$OWNER" ]; then
    echo "release-denied"
    exit 0
  fi
else
  echo "release-denied"
  exit 0
fi

rm -rf "$LOCK_DIR"
journal_append "lock-release" "lock_released" "{\"team\":\"$TEAM\",\"resource\":\"$RESOURCE\",\"owner\":\"$OWNER\"}" >/dev/null 2>&1 || true
echo "released"
