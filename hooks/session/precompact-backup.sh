#!/bin/bash
#
# PreCompact backup hook — async transcript archive before context compaction.
# Trigger: matcher manual|auto on PreCompact event, async: true.
#
# Reads JSON payload from stdin (PreCompact event) but primarily uses
# CLAUDE_TRANSCRIPT_PATH to locate the transcript.
#
# Keeps last 20 backups; older ones are pruned.
#
# METHODOLOGY alignment:
#   - Rule 2 (Simplicity): cp + ls + prune; no external dependencies.
#   - Rule 12 (Fail loud): non-zero exit surfaces stderr.
#

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
BACKUP_DIR="${CLAUDE_DIR}/backups"
mkdir -p "$BACKUP_DIR"

TRANSCRIPT="${CLAUDE_TRANSCRIPT_PATH:-}"
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

TS=$(date +%Y%m%d-%H%M%S)
BACKUP="${BACKUP_DIR}/transcript-${TS}.jsonl"

cp "$TRANSCRIPT" "$BACKUP"

# Prune old backups — keep last 20 (portable; no GNU xargs -r)
cd "$BACKUP_DIR"
ls -t transcript-*.jsonl 2>/dev/null | tail -n +21 | while IFS= read -r f; do
  rm -f "$f"
done

exit 0
