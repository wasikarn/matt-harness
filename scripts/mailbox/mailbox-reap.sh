#!/bin/bash
set -euo pipefail

# mailbox-reap.sh — cleanup old messages.
# Usage: mailbox-reap.sh --team="NAME" [--unread-days=7] [--archive-days=30]

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
Usage: $(basename "$0") --team="NAME" [--unread-days=7] [--archive-days=30]

  --team          Team context
  --unread-days   Remove unread messages older than N days (default 7)
  --archive-days  Remove archived messages older than N days (default 30)
  --help          Show this usage message
EOF
}

TEAM=""
UNREAD_DAYS=7
ARCHIVE_DAYS=30

for arg in "$@"; do
  case "$arg" in
    --help) usage; exit 0 ;;
    --team=*) TEAM="${arg#*=}" ;;
    --unread-days=*) UNREAD_DAYS="${arg#*=}" ;;
    --archive-days=*) ARCHIVE_DAYS="${arg#*=}" ;;
    *) echo "ERROR: unknown argument $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$TEAM" ]; then
  echo "ERROR: --team is required" >&2
  usage >&2
  exit 1
fi

MAILBOX_BASE="${CLAUDE_MAILBOX_BASE:-$HOME/.claude/mailbox}"
TEAM_DIR="$MAILBOX_BASE/$TEAM"

# Cross-platform ISO8601 to epoch seconds
iso_to_epoch() {
  local iso="$1"
  # Try GNU date first, then BSD date
  if date -d "$iso" +%s >/dev/null 2>&1; then
    date -d "$iso" +%s
  else
    date -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s
  fi
}

# Compute cutoffs
now_epoch=$(date -u +%s)
unread_cutoff=$(( now_epoch - UNREAD_DAYS * 86400 ))
archive_cutoff=$(( now_epoch - ARCHIVE_DAYS * 86400 ))

# Extract ts: field from a message file
extract_ts() {
  local f="$1"
  sed -n '/^---$/,/^---$/p' "$f" | grep '^ts:' | head -n1 | sed 's/^ts:[[:space:]]*//;s/^"//;s/"$//'
}

reap_count=0

# Reap old unread messages across all agents
if [ -d "$TEAM_DIR/inbox" ]; then
  for agent_dir in "$TEAM_DIR/inbox"/*; do
    [ -d "$agent_dir/unread" ] || continue
    for f in "$agent_dir/unread"/*.md; do
      [ -e "$f" ] || continue
      ts=$(extract_ts "$f")
      if [ -z "$ts" ]; then
        continue
      fi
      ts_epoch=$(iso_to_epoch "$ts")
      # P0: guard against empty ts_epoch to avoid bash arithmetic crash
      if [ -n "$ts_epoch" ] && [ "$ts_epoch" -lt "$unread_cutoff" ]; then
        msg_id=$(basename "$f" .md)
        rm -f "$f"
        journal_append "mailbox-reap" "reaped_unread" "{\"team\":\"$TEAM\",\"msg_id\":\"$msg_id\",\"ts\":\"$ts\",\"reason\":\"unread_age\",\"days_threshold\":$UNREAD_DAYS}" >/dev/null || true
        reap_count=$((reap_count + 1))
      fi
    done
  done
fi

# Reap old archived messages across all agents
if [ -d "$TEAM_DIR/inbox" ]; then
  for agent_dir in "$TEAM_DIR/inbox"/*; do
    [ -d "$agent_dir/archive" ] || continue
    for f in "$agent_dir/archive"/*.md; do
      [ -e "$f" ] || continue
      ts=$(extract_ts "$f")
      if [ -z "$ts" ]; then
        continue
      fi
      ts_epoch=$(iso_to_epoch "$ts")
      # P0: guard against empty ts_epoch to avoid bash arithmetic crash
      if [ -n "$ts_epoch" ] && [ "$ts_epoch" -lt "$archive_cutoff" ]; then
        msg_id=$(basename "$f" .md)
        rm -f "$f"
        journal_append "mailbox-reap" "reaped_archive" "{\"team\":\"$TEAM\",\"msg_id\":\"$msg_id\",\"ts\":\"$ts\",\"reason\":\"archive_age\",\"days_threshold\":$ARCHIVE_DAYS}" >/dev/null || true
        reap_count=$((reap_count + 1))
      fi
    done
  done
fi

printf '%s\n' "$reap_count"
