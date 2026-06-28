#!/usr/bin/env bash
# Lifecycle: log compaction events to ~/.local/share/kbg/compaction-log.txt
set -uo pipefail

log_file="$HOME/.local/share/kbg/compaction-log.txt"
mkdir -p "$(dirname "$log_file")"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] compaction triggered" >> "$log_file"
exit 0
