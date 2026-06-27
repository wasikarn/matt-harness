#!/bin/bash
# ideate-budget-capture.sh — SessionEnd hook that counts /ideate (and legacy
# kbg:ideate) invocations from the session transcript and appends one JSONL row
# per calendar day to ~/.claude/state/ideate-usage.jsonl. The companion
# SessionStart hook ideate-rotate.sh reads that file and warns when the daily
# threshold is crossed.
#
# This is advisory-only feedback (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model / CLAUDE.md §"LLM-judge circularity").
# It never blocks SessionEnd and never emits a permissionDecision.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=ideate-budget-capture
#
# Failure mode: silent. Always exit 0.

HOOK_ID="ideate-budget-capture"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

STATE_DIR="${HOME}/.claude/state"
USAGE_FILE="${STATE_DIR}/ideate-usage.jsonl"
mkdir -p "$STATE_DIR" || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID_VAL" ] || SESSION_ID_VAL="no-sid"

# No transcript path = nothing to count (normal for very short sessions).
[ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ] && exit 0

# Count invocations of the ideate skill. Vendor tool spans for Skill use are
# nested inside assistant message content arrays in JSONL transcripts; the old
# jq-only filter assumed a single JSON object with a .messages[] array and
# silently counted zero on real transcripts.
INVOCATIONS=$(
  KBG_IDEATE_TRANSCRIPT="$TRANSCRIPT" \
  python3 - <<'PY' 2>/dev/null
import json
import os
import re
from pathlib import Path

TRANSCRIPT = os.environ.get('KBG_IDEATE_TRANSCRIPT', '')
SLASH_RE = re.compile(r'(?:^|[\s])/ideate\b', re.IGNORECASE)


def extract_text(content):
    if content is None:
        return ''
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    parts.append(item.get('text', ''))
                elif item.get('type') == 'tool_use':
                    continue
            elif isinstance(item, str):
                parts.append(item)
        return '\n'.join(parts)
    return str(content)


def event_content(ev):
    """Return the content payload for a transcript event.

    Current vendor transcripts wrap the message payload in a nested `message`
    object; legacy transcripts stored content directly on the event.
    """
    if not isinstance(ev, dict):
        return None
    if 'content' in ev:
        return ev['content']
    msg = ev.get('message')
    if isinstance(msg, dict):
        return msg.get('content')
    return None


def is_ideate_invocation(item):
    if not isinstance(item, dict):
        return False
    tool_name = item.get('tool_name') or item.get('name') or ''
    inp = item.get('input') or {}
    if tool_name == 'Skill':
        return inp.get('skill') in ('ideate', 'kbg:ideate')
    if tool_name == 'Command':
        return inp.get('command') in ('ideate', '/ideate')
    return False


def iter_ideate_invocations(ev):
    found = []
    if is_ideate_invocation(ev):
        found.append(ev)
    content = event_content(ev)
    if isinstance(content, list):
        for block in content:
            if is_ideate_invocation(block):
                found.append(block)
    return found


p = Path(TRANSCRIPT)
if not p.exists():
    print(0)
    raise SystemExit(0)

raw = p.read_text(encoding='utf-8', errors='replace')
if not raw.strip():
    print(0)
    raise SystemExit(0)

invocations = 0
for line in raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not isinstance(obj, dict):
        continue

    # Legacy single-object format with a .messages array.
    if 'messages' in obj and isinstance(obj.get('messages'), list):
        for ev in obj['messages']:
            if not isinstance(ev, dict):
                continue
            invocations += len(iter_ideate_invocations(ev))
            if ev.get('type') == 'user' and SLASH_RE.search(extract_text(event_content(ev))):
                invocations += 1
        break

    invocations += len(iter_ideate_invocations(obj))
    if obj.get('type') == 'user' and SLASH_RE.search(extract_text(event_content(obj))):
        invocations += 1

print(invocations)
PY
)

[ -n "$INVOCATIONS" ] || INVOCATIONS=0
[ "$INVOCATIONS" -eq 0 ] 2>/dev/null && exit 0

DATE=$(date -u +%Y-%m-%d)

# Append the count. Collapse multiple invocations in the same session into one
# row keyed by session+date so a long ideate loop does not bloat the file, while
# still preserving per-session observability. A later jq aggregation sums them.
if ! jq -nc \
  --arg date "$DATE" \
  --arg session_id "$SESSION_ID_VAL" \
  --argjson invocations "$INVOCATIONS" \
  '{date: $date, session_id: $session_id, invocations: $invocations}' >> "$USAGE_FILE" 2>/dev/null; then
  echo "[$HOOK_ID] ERROR: failed to append ideate usage to $USAGE_FILE" >&2
fi

exit 0
