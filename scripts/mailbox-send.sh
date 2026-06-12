#!/bin/bash
set -euo pipefail

# mailbox-send.sh — send a direct message, broadcast, or lead-only message.
# Usage: mailbox-send.sh --team="health-endpoint" --from="lead" --to="backend-engineer" --subject="..." --body="..." [--type=direct|broadcast|lead-only]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source _lib.sh for journal_append if available; otherwise provide a fallback.
if [ -f "$SCRIPT_DIR/../hooks/_lib.sh" ]; then
  # shellcheck source=../hooks/_lib.sh
  source "$SCRIPT_DIR/../hooks/_lib.sh"
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
Usage: $(basename "$0") --team="NAME" --from="SENDER" --to="RECIPIENT" --subject="SUBJECT" --body="BODY" [--type=direct|broadcast|lead-only]

  --team      Team context (directory under ~/.claude/mailbox/)
  --from      Sender agent identifier
  --to        Recipient agent identifier (or "broadcast")
  --subject   Message subject line
  --body      Message body text
  --type      Message type: direct (default), broadcast, lead-only
  --help      Show this usage message
EOF
}

# Parse arguments
TEAM=""
FROM=""
TO=""
SUBJECT=""
BODY=""
TYPE="direct"

for arg in "$@"; do
  case "$arg" in
    --help) usage; exit 0 ;;
    --team=*) TEAM="${arg#*=}" ;;
    --from=*) FROM="${arg#*=}" ;;
    --to=*) TO="${arg#*=}" ;;
    --subject=*) SUBJECT="${arg#*=}" ;;
    --body=*) BODY="${arg#*=}" ;;
    --type=*) TYPE="${arg#*=}" ;;
    *) echo "ERROR: unknown argument $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$TEAM" ] || [ -z "$FROM" ] || [ -z "$TO" ] || [ -z "$SUBJECT" ] || [ -z "$BODY" ]; then
  echo "ERROR: missing required argument" >&2
  usage >&2
  exit 1
fi

MAILBOX_BASE="${CLAUDE_MAILBOX_BASE:-$HOME/.claude/mailbox}"
TEAM_DIR="$MAILBOX_BASE/$TEAM"
TMP_DIR="$TEAM_DIR/.tmp"

mkdir -p "$TMP_DIR"

msg_id="$(date -u +%Y-%m-%dT%H-%M-%SZ)-$(python3 -c 'import uuid; print(uuid.uuid4().hex[:8])')"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

tmpfile="$TMP_DIR/${msg_id}.md"

# P0: construct file with printf to prevent command injection via --body='$(cmd)'
{
  printf '%s\n' '---'
  printf 'msg_id: "%s"\n' "$msg_id"
  printf 'ts: "%s"\n' "$ts"
  printf 'from: "%s"\n' "$FROM"
  printf 'to: "%s"\n' "$TO"
  printf 'type: "%s"\n' "$TYPE"
  printf 'subject: "%s"\n' "$SUBJECT"
  printf 'reply_to: ""\n'
  printf '%s\n' '---'
  printf '%s\n' "$BODY"
} > "$tmpfile"

# Determine destination based on type
case "$TYPE" in
  direct)
    DEST_DIR="$TEAM_DIR/inbox/$TO/unread"
    ;;
  broadcast)
    DEST_DIR="$TEAM_DIR/broadcast/unread"
    ;;
  lead-only)
    DEST_DIR="$TEAM_DIR/inbox/lead/unread"
    ;;
  *)
    echo "ERROR: unknown type '$TYPE'" >&2
    rm -f "$tmpfile"
    exit 1
    ;;
esac

mkdir -p "$DEST_DIR"

# Atomic move
case "$OSTYPE" in
  darwin*)
    # macOS mv lacks --no-clobber in the GNU sense; use test + mv
    if [ -e "$DEST_DIR/$(basename "$tmpfile")" ]; then
      echo "ERROR: destination file already exists" >&2
      rm -f "$tmpfile"
      exit 1
    fi
    mv "$tmpfile" "$DEST_DIR/"
    ;;
  *)
    mv --no-clobber "$tmpfile" "$DEST_DIR/" || {
      echo "ERROR: atomic move failed (file exists?)" >&2
      rm -f "$tmpfile"
      exit 1
    }
    ;;
esac

# Governance log
journal_append "mailbox-send" "message_sent" "{\"msg_id\":\"$msg_id\",\"team\":\"$TEAM\",\"from\":\"$FROM\",\"to\":\"$TO\",\"type\":\"$TYPE\",\"subject\":\"$SUBJECT\"}" >/dev/null || true

printf '%s\n' "$msg_id"
