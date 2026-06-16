#!/bin/bash
set -euo pipefail

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

show_help() {
  cat <<'EOF'
Usage: lock-query.sh --team="team-name" --type=task|file --resource="id"
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --team=*) TEAM="${1#*=}" ;;
    --type=*) TYPE="${1#*=}" ;;
    --resource=*) RESOURCE="${1#*=}" ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; show_help >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$TEAM" ] || [ -z "$TYPE" ] || [ -z "$RESOURCE" ]; then
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

if [ -d "$LOCK_DIR" ] && [ -f "$LOCK_FILE" ]; then
  jq -c '{status: "locked", meta: .}' "$LOCK_FILE"
else
  echo '{"status":"free","meta":{}}'
fi
