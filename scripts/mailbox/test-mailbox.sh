#!/bin/bash
set -euo pipefail

# Integration test for mailbox system.
# Uses CLAUDE_MAILBOX_BASE to isolate from the real ~/.claude/mailbox.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(mktemp -d /tmp/mailbox-test-base-XXXXXX)"
TEAM_NAME="test-team"
JOURNAL="${BASE_DIR}/governance-events.jsonl"

cleanup() {
  rm -rf "$BASE_DIR"
}
trap cleanup EXIT

export CLAUDE_MAILBOX_BASE="$BASE_DIR"
export CLAUDE_JOURNAL_PATH="$JOURNAL"

# Helper: run a mailbox script with --team pointing at our temp team
run() {
  local script="$1"
  shift
  "$SCRIPT_DIR/$script" --team="$TEAM_NAME" "$@"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

echo "=== Test 1: send direct message ==="
run mailbox-send.sh --from="lead" --to="backend-engineer" --subject="API contract change" --body="Please review the new schema."
# Verify file landed in inbox
msg_file=$(find "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/unread" -name "*.md" | head -n1)
[ -n "$msg_file" ] || fail "send did not create unread message file"
msg_id=$(basename "$msg_file" .md)
grep -q "subject: \"API contract change\"" "$msg_file" || fail "frontmatter subject missing"
grep -q "from: \"lead\"" "$msg_file" || fail "frontmatter from missing"
grep -q "to: \"backend-engineer\"" "$msg_file" || fail "frontmatter to missing"
grep -q "Please review the new schema." "$msg_file" || fail "body missing"
echo "PASS: send"

echo "=== Test 2: poll for unread ==="
poll_out=$(run mailbox-poll.sh --agent="backend-engineer")
echo "$poll_out"
echo "$poll_out" | grep -q "$msg_id" || fail "poll did not find direct message"
echo "PASS: poll"

echo "=== Test 3: read message ==="
msg_id=$(basename "$msg_file" .md)
run mailbox-read.sh --agent="backend-engineer" --msg-id="$msg_id"
[ -f "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/read/${msg_id}.md" ] || fail "read did not move to read/"
[ ! -f "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/unread/${msg_id}.md" ] || fail "read left file in unread/"
echo "PASS: read"

echo "=== Test 4: archive message ==="
run mailbox-archive.sh --agent="backend-engineer" --msg-id="$msg_id"
[ -f "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/archive/${msg_id}.md" ] || fail "archive did not move to archive/"
[ ! -f "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/read/${msg_id}.md" ] || fail "archive left file in read/"
echo "PASS: archive"

echo "=== Test 5: broadcast send + poll + read ==="
run mailbox-send.sh --from="lead" --to="broadcast" --subject="Stand-up" --body="10:00 daily" --type="broadcast"
bc_file=$(find "$BASE_DIR/$TEAM_NAME/broadcast/unread" -name "*.md" | head -n1)
[ -n "$bc_file" ] || fail "broadcast send did not create file"
bc_id=$(basename "$bc_file" .md)
# Poll as another agent
poll_bc=$(run mailbox-poll.sh --agent="frontend-engineer")
echo "$poll_bc" | grep -q "$bc_id" || fail "poll did not show broadcast"
# Read as frontend-engineer
run mailbox-read.sh --agent="frontend-engineer" --msg-id="$bc_id"
[ -f "$BASE_DIR/$TEAM_NAME/broadcast/read-receipts/frontend-engineer/$bc_id" ] || fail "broadcast read-receipt missing"
# Poll again — should NOT show (already read)
poll_bc2=$(run mailbox-poll.sh --agent="frontend-engineer")
if echo "$poll_bc2" | grep -q "$bc_id"; then
  fail "poll still showed read broadcast"
fi
echo "PASS: broadcast round-trip"

echo "=== Test 6: reap old messages ==="
# Forge an old unread message (8 days ago)
old_ts="$(date -u -d '8 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-8d +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/unread"
cat > "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/unread/old-unread.md" <<EOF
---
msg_id: "old-unread"
ts: "$old_ts"
from: "lead"
to: "backend-engineer"
type: "direct"
subject: "stale"
reply_to: ""
---
old body
EOF
run mailbox-reap.sh --unread-days=7 --archive-days=30
[ ! -f "$BASE_DIR/$TEAM_NAME/inbox/backend-engineer/unread/old-unread.md" ] || fail "reap did not remove old unread"
echo "PASS: reap"

echo "=== Test 7: --help on all scripts ==="
for s in mailbox-send.sh mailbox-poll.sh mailbox-read.sh mailbox-archive.sh mailbox-reap.sh; do
  out=$(run "$s" --help) || fail "$s --help exited non-zero"
  echo "$out" | grep -qi "usage" || fail "$s --help missing usage"
done
echo "PASS: --help"

echo ""
echo "All tests passed."
