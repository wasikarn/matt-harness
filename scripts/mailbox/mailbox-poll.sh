#!/bin/bash
set -euo pipefail

# mailbox-poll.sh — poll for unread messages (direct + broadcast).
# Usage: mailbox-poll.sh --team="NAME" --agent="AGENT"

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
Usage: $(basename "$0") --team="NAME" --agent="AGENT"

  --team   Team context
  --agent  Agent identifier to poll for
  --help   Show this usage message
EOF
}

TEAM=""
AGENT=""

for arg in "$@"; do
  case "$arg" in
    --help) usage; exit 0 ;;
    --team=*) TEAM="${arg#*=}" ;;
    --agent=*) AGENT="${arg#*=}" ;;
    *) echo "ERROR: unknown argument $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$TEAM" ] || [ -z "$AGENT" ]; then
  echo "ERROR: --team and --agent are required" >&2
  usage >&2
  exit 1
fi

MAILBOX_BASE="${CLAUDE_MAILBOX_BASE:-$HOME/.claude/mailbox}"
TEAM_DIR="$MAILBOX_BASE/$TEAM"

# Parse a message file and emit msg_id, from, subject, type (tab-separated).
# Capture the YAML frontmatter block once and extract 4 fields from it, instead
# of re-reading the file 4 times. Behavior-identical: output is the same 4 TSV
# fields in the same order with the same stripping rules.
parse_msg() {
  local f="$1"
  local msg_id from subject type frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/p' "$f")
  msg_id=$(printf '%s\n' "$frontmatter" | grep '^msg_id:' | head -n1 | sed 's/^msg_id:[[:space:]]*//;s/^"//;s/"$//')
  from=$(printf '%s\n' "$frontmatter" | grep '^from:' | head -n1 | sed 's/^from:[[:space:]]*//;s/^"//;s/"$//')
  subject=$(printf '%s\n' "$frontmatter" | grep '^subject:' | head -n1 | sed 's/^subject:[[:space:]]*//;s/^"//;s/"$//')
  type=$(printf '%s\n' "$frontmatter" | grep '^type:' | head -n1 | sed 's/^type:[[:space:]]*//;s/^"//;s/"$//')
  printf '%s\t%s\t%s\t%s\n' "$msg_id" "$from" "$subject" "$type"
}

# Direct unread
if [ -d "$TEAM_DIR/inbox/$AGENT/unread" ]; then
  for f in "$TEAM_DIR/inbox/$AGENT/unread"/*.md; do
    [ -e "$f" ] || continue
    parse_msg "$f"
  done
fi

# Broadcast unread minus read receipts
if [ -d "$TEAM_DIR/broadcast/unread" ]; then
  for f in "$TEAM_DIR/broadcast/unread"/*.md; do
    [ -e "$f" ] || continue
    msg_id=$(basename "$f" .md)
    if [ -e "$TEAM_DIR/broadcast/read-receipts/$AGENT/$msg_id" ]; then
      continue
    fi
    parse_msg "$f"
  done
fi

# Governance log (lightweight — just that we polled)
journal_append "mailbox-poll" "polled" "{\"team\":\"$TEAM\",\"agent\":\"$AGENT\"}" >/dev/null || true
