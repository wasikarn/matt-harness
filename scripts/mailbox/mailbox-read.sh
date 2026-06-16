#!/bin/bash
set -euo pipefail

# mailbox-read.sh — mark a message as read.
# Usage: mailbox-read.sh --team="NAME" --agent="AGENT" --msg-id="ID"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source _lib.sh for journal_append if available; otherwise fallback.
if [ -f "$SCRIPT_DIR/../../hooks/_lib.sh" ]; then
  # shellcheck source=../hooks/_lib.sh
  source "$SCRIPT_DIR/../../hooks/_lib.sh"
else
  journal_append() {
    local hook_id="$1" event="$2" fields_json="$3"
    local journal="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
    mkdir -p "$(dirname "$journal")" 2>/dev/null || true
    local ms iso rand
    ms="$(date -u +%s)000"
    read -r iso rand <<<"$(python3 -c 'import uuid,datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]+"Z", uuid.uuid4().hex[:8])')"
    printf '{"id":"%s-%s-%s","ts":"%s","session":"no-sid","hook":"%s","event":"%s","source":"journal_append","fields":%s}\n' \
      "$ms" "$hook_id" "$rand" "$iso" "$hook_id" "$event" "$fields_json" >> "$journal"
  }
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --team="NAME" --agent="AGENT" --msg-id="MSG_ID"

  --team    Team context
  --agent   Agent identifier
  --msg-id  Message ID to mark as read
  --help    Show this usage message
EOF
}

TEAM=""
AGENT=""
MSG_ID=""

for arg in "$@"; do
  case "$arg" in
    --help) usage; exit 0 ;;
    --team=*) TEAM="${arg#*=}" ;;
    --agent=*) AGENT="${arg#*=}" ;;
    --msg-id=*) MSG_ID="${arg#*=}" ;;
    *) echo "ERROR: unknown argument $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$TEAM" ] || [ -z "$AGENT" ] || [ -z "$MSG_ID" ]; then
  echo "ERROR: --team, --agent, and --msg-id are required" >&2
  usage >&2
  exit 1
fi

MAILBOX_BASE="${CLAUDE_MAILBOX_BASE:-$HOME/.claude/mailbox}"
TEAM_DIR="$MAILBOX_BASE/$TEAM"

unread_direct="$TEAM_DIR/inbox/$AGENT/unread/${MSG_ID}.md"
unread_broadcast="$TEAM_DIR/broadcast/unread/${MSG_ID}.md"

if [ -f "$unread_direct" ]; then
  read_dir="$TEAM_DIR/inbox/$AGENT/read"
  mkdir -p "$read_dir"
  mv "$unread_direct" "$read_dir/${MSG_ID}.md"
elif [ -f "$unread_broadcast" ]; then
  receipt_dir="$TEAM_DIR/broadcast/read-receipts/$AGENT"
  mkdir -p "$receipt_dir"
  touch "$receipt_dir/$MSG_ID"
else
  echo "ERROR: message not found in unread (direct or broadcast)" >&2
  exit 1
fi

# Governance log
journal_append "mailbox-read" "message_read" "{\"team\":\"$TEAM\",\"agent\":\"$AGENT\",\"msg_id\":\"$MSG_ID\"}" >/dev/null || true
