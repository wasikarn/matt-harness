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
OWNER=""
REASON=""
TTL=3600

show_help() {
  cat <<'EOF'
Usage: lock-claim.sh --team="team-name" --type=task|file --resource="id" --owner="agent-name" --reason="..." [--ttl=3600]
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --team=*) TEAM="${1#*=}" ;;
    --type=*) TYPE="${1#*=}" ;;
    --resource=*) RESOURCE="${1#*=}" ;;
    --owner=*) OWNER="${1#*=}" ;;
    --reason=*) REASON="${1#*=}" ;;
    --ttl=*) TTL="${1#*=}" ;;
    --help) show_help; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; show_help >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$TEAM" ] || [ -z "$TYPE" ] || [ -z "$RESOURCE" ] || [ -z "$OWNER" ] || [ -z "$REASON" ]; then
  echo "ERROR: missing required argument" >&2
  show_help >&2
  exit 1
fi

if [ "$TYPE" != "task" ] && [ "$TYPE" != "file" ]; then
  echo "ERROR: --type must be task or file" >&2
  exit 1
fi

# Encode resource for directory name
if [ "$TYPE" = "file" ]; then
  ENCODED_RESOURCE=$(printf '%s' "$RESOURCE" | sed 's|/|--|g')
  DIR_NAME="file--${ENCODED_RESOURCE}"
else
  DIR_NAME="task-${RESOURCE}"
fi

LOCK_BASE="${HOME}/.claude/locks/${TEAM}"
LOCK_DIR="${LOCK_BASE}/${DIR_NAME}"
LOCK_FILE="${LOCK_DIR}/lock.json"
# P0: temp file outside LOCK_DIR so mkdir success + mv failure doesn't leave zombie dir
TMP_FILE="${LOCK_BASE}/${DIR_NAME}.tmp.$$"

_now_epoch() {
  date -u +%s
}

_iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

_epoch_from_iso() {
  python3 -c 'import datetime,sys; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00")).timestamp()))' "$1"
}

acquire_lock() {
  local status="claimed"
  mkdir -p "$LOCK_BASE" 2>/dev/null || true

  # P0: always remove the temp claim file on exit; the mv path turns it into
  # lock.json, so the rm -f is harmless after success.
  trap 'rm -f "$TMP_FILE"' EXIT

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    # P0: ERR trap removes zombie dir if mkdir succeeds but mv fails
    trap 'rm -f "$TMP_FILE"; rm -rf "$LOCK_DIR"' ERR
    status="claimed"
  else
    if [ -f "$LOCK_FILE" ]; then
      local expires_at owner_str reason_str
      expires_at=$(jq -r '.expires_at // empty' "$LOCK_FILE" 2>/dev/null) || expires_at=""
      owner_str=$(jq -r '.owner // empty' "$LOCK_FILE" 2>/dev/null) || owner_str="unknown"
      reason_str=$(jq -r '.reason // empty' "$LOCK_FILE" 2>/dev/null) || reason_str="unknown"

      if [ -n "$expires_at" ]; then
        local exp_epoch now_epoch
        exp_epoch=$(_epoch_from_iso "$expires_at")
        now_epoch=$(_now_epoch)
        if [ "$now_epoch" -gt "$exp_epoch" ]; then
          rm -rf "$LOCK_DIR"
          if mkdir "$LOCK_DIR" 2>/dev/null; then
            trap 'rm -f "$TMP_FILE"; rm -rf "$LOCK_DIR"' ERR
            status="claimed-stale"
          else
            echo "conflict: owner=$owner_str reason=$reason_str"
            exit 0
          fi
        else
          echo "conflict: owner=$owner_str reason=$reason_str"
          exit 0
        fi
      else
        rm -rf "$LOCK_DIR"
        if mkdir "$LOCK_DIR" 2>/dev/null; then
          trap 'rm -f "$TMP_FILE"; rm -rf "$LOCK_DIR"' ERR
          status="claimed-stolen"
        else
          echo "conflict: owner=$owner_str reason=$reason_str"
          exit 0
        fi
      fi
    else
      # Directory exists but lock.json is missing — another claimer is in-progress.
      # Do NOT steal; treat as conflict to preserve atomicity.
      echo "conflict: owner=unknown reason=unknown"
      exit 0
    fi
  fi

  local acquired_at expires_at agent_session
  acquired_at=$(_iso_now)
  expires_at=$(python3 -c 'import datetime, sys; d = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=int(sys.argv[1])); print(d.strftime("%Y-%m-%dT%H:%M:%SZ"))' "$TTL")
  agent_session="${CLAUDE_SESSION_ID:-no-sid}"

  # P0: build JSON with jq to prevent command injection via --owner/--reason
  jq -n \
    --arg owner "$OWNER" \
    --arg agent_session "$agent_session" \
    --arg acquired_at "$acquired_at" \
    --arg expires_at "$expires_at" \
    --arg lock_type "$TYPE" \
    --arg resource_id "$RESOURCE" \
    --arg reason "$REASON" \
    '{
      owner: $owner,
      agent_session: $agent_session,
      acquired_at: $acquired_at,
      expires_at: $expires_at,
      lock_type: $lock_type,
      resource_id: $resource_id,
      reason: $reason
    }' > "$TMP_FILE"

  mv "$TMP_FILE" "$LOCK_FILE"
  trap - ERR

  # P0: log only after successful mv to avoid inconsistent journal state on crash
  if [ "$status" = "claimed-stale" ]; then
    journal_append "lock-claim" "stale_lock_stolen" "{\"team\":\"$TEAM\",\"resource\":\"$RESOURCE\",\"old_owner\":\"$owner_str\"}" >/dev/null 2>&1 || true
  elif [ "$status" = "claimed-stolen" ]; then
    journal_append "lock-claim" "lock_stolen" "{\"team\":\"$TEAM\",\"resource\":\"$RESOURCE\",\"old_owner\":\"$owner_str\"}" >/dev/null 2>&1 || true
  fi
  journal_append "lock-claim" "lock_acquired" "{\"team\":\"$TEAM\",\"resource\":\"$RESOURCE\",\"owner\":\"$OWNER\",\"lock_type\":\"$TYPE\"}" >/dev/null 2>&1 || true
  echo "$status"
}

acquire_lock
