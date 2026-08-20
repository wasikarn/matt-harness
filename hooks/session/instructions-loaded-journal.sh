#!/usr/bin/env bash
# InstructionsLoaded: journal every CLAUDE.md / `.claude/rules/*.md` load to
# ~/.local/share/kbg/metrics/instructions-loaded.jsonl. This event has no
# decision control — Claude Code discards any stdout/JSON output it produces
# and uses it for observability only — so a log file is the only useful
# side effect. Exists to answer "did this file load, when, and why" with a
# deterministic record instead of forensic reconstruction after the fact.
#
# ponytail: unbounded append, same precedent as hooks/stop/cost-tracker.sh —
# rotate/trim manually if it grows large.
set -uo pipefail

payload=$(cat)

log_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$log_dir"

jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
  ts: $ts,
  session_id: (.session_id // "unknown"),
  cwd: (.cwd // "unknown"),
  file_path: (.file_path // "unknown"),
  memory_type: (.memory_type // "unknown"),
  load_reason: (.load_reason // "unknown"),
  globs: (.globs // null),
  trigger_file_path: (.trigger_file_path // null),
  parent_file_path: (.parent_file_path // null)
}' <<<"$payload" >>"$log_dir/instructions-loaded.jsonl" 2>/dev/null

exit 0
