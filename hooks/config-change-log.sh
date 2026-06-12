#!/bin/bash
# ConfigChange logger — append-only audit trail when external processes
# (or /config writes, IDE saves, plugin updates) modify configuration
# files. Forensic answer to "why/when did X change?". Never blocks.
#
# Per vendor docs, matcher values: user_settings, project_settings,
# local_settings, policy_settings, skills. We register against all of
# them via empty matcher.
#
# Log: ~/.claude/config-change.log (TSV: ts \t session \t source \t path)
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=config-change-log

HOOK_ID="config-change-log"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

SRC=$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null)
FILE=$(printf '%s' "$INPUT" | jq -r '.file_path // .file // "unknown"' 2>/dev/null)

# Dedup by content hash. ConfigChange re-fires on touch/symlink-rebuild even when
# content is unchanged (matcher="" covers all skills/commands/settings). An
# install.sh re-run on 2026-05-26/27 touched ~2.8K files → 20K spurious lines
# (settings.json logged 670× though its mtime never moved). Log only real content
# changes: skip when the file's hash equals the last one we logged for that path.
if [ "$FILE" != "unknown" ] && [ -f "$FILE" ]; then
  HASHES="$HOME/.claude/.config-change-hashes"
  # P1: sha256sum is GNU; shasum is BSD/macOS. Try both for portability.
  if command -v sha256sum >/dev/null 2>&1; then
    NEWHASH=$(sha256sum "$FILE" 2>/dev/null | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    NEWHASH=$(shasum -a 256 "$FILE" 2>/dev/null | awk '{print $1}')
  else
    NEWHASH=""
  fi
  OLDHASH=$(awk -F'\t' -v p="$FILE" '$2==p{h=$1} END{print h}' "$HASHES" 2>/dev/null || true)
  if [ -n "$NEWHASH" ] && [ "$NEWHASH" = "$OLDHASH" ]; then exit 0; fi
  if [ -n "$NEWHASH" ]; then
    # P1: use mktemp for atomic update instead of predictable $HASHES.tmp
    HASH_TMP=$(mktemp "$(dirname "$HASHES")/.config-change-hashes.XXXXXX")
    { awk -F'\t' -v p="$FILE" '$2!=p' "$HASHES" 2>/dev/null || true; printf '%s\t%s\n' "$NEWHASH" "$FILE"; } > "$HASH_TMP" && mv "$HASH_TMP" "$HASHES"
  fi
fi

# ConfigChange fires on a different event than PreToolUse; preserve the
# manual TSV signature (ts \t session \t source \t path) and the mkdir
# ordering the dedup step relies on.
LOG="$HOME/.claude/config-change.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\t%s\t%s\t%s\n' "$TS" "$SID" "$SRC" "$FILE" >> "$LOG"

# Dual-write the same event into the structured evidence journal (JSONL). The
# governance digest dedups TSV+JSONL on (hook, ts_second, path) — JSONL wins —
# so this counts once during migration. Fields built via jq so a path with
# quotes/backslashes can't corrupt the envelope. See claude/hooks/JOURNAL-SCHEMA.md.
# Routes through the Python module (single emission point) — _journal_append_py
# is a 1-call-per-emit shim in _lib.sh:185. The shim's source="journal_append"
# is consumer-stable (governance-summary.py ingests regardless of which language
# emitted the line). See _lib.py for the lockstep envelope literal.
_journal_append_py "config-change-log" "config_change" \
  "$(jq -nc --arg path "$FILE" --arg source "$SRC" '{path: $path, source: $source}')"

# Propagate journal-write failure to Claude Code's PostToolUse matcher. The
# journal shim exits non-zero on jq-missing, redaction failure, or I/O error
# (see _lib.sh:124-183); an unconditional `exit 0` here would mask the failure
# as a clean hook run and the config_change event would silently disappear from
# the evidence journal. Rule 12: fail loud.
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
exit 0
