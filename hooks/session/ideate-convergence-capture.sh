#!/bin/bash
# ideate-convergence-capture.sh — SessionEnd hook that detects convergence
# across /ideate (and legacy kbg:ideate) runs using local Ollama embeddings.
#
# Advisory only. Never blocks. Never mutates the repo. Appends one JSONL row
# per ideate run to ~/.claude/state/ideate-embeddings.jsonl.
#
# The hook reads the session transcript for ideate invocations, extracts the
# problem text and the rotated frames used, and stores an embedding vector
# (all-minilm via the local Ollama API) for the problem fingerprint. This is a
# pragmatic proxy for full idea-text embeddings: if the same problem is run
# repeatedly with similar frames, the embedding is similar and we flag
# convergence risk.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=ideate-convergence-capture
#
# Failure mode: silent. Always exit 0.

HOOK_ID="ideate-convergence-capture"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

STATE_DIR="${HOME}/.claude/state"
EMB_FILE="${STATE_DIR}/ideate-embeddings.jsonl"
mkdir -p "$STATE_DIR" || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID_VAL" ] || SESSION_ID_VAL="no-sid"

[ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ] && exit 0

# Everything that touches the transcript is done in a single Python pass:
# Claude Code transcripts are JSONL event streams (one JSON object per line),
# and Skill calls are often nested inside assistant message content arrays.
# The old jq-only filter assumed a single JSON object with a .messages[] array,
# which produced a multi-line zero string on real transcripts and broke both
# the early-exit guard and the final --argjson append.
KBG_IDEATE_OLLAMA_TIMEOUT="${KBG_IDEATE_OLLAMA_TIMEOUT:-8}"
PY_OUT=$(
  KBG_IDEATE_TRANSCRIPT="$TRANSCRIPT" \
  KBG_IDEATE_SESSION_ID="$SESSION_ID_VAL" \
  KBG_IDEATE_OLLAMA_HOST="${KBG_IDEATE_OLLAMA_HOST:-http://localhost:11434}" \
  KBG_IDEATE_EMBEDDING_MODEL="${KBG_IDEATE_EMBEDDING_MODEL:-all-minilm:latest}" \
  KBG_IDEATE_OLLAMA_TIMEOUT="$KBG_IDEATE_OLLAMA_TIMEOUT" \
  KBG_IDEATE_CONVERGENCE_THRESHOLD="${KBG_IDEATE_CONVERGENCE_THRESHOLD:-0.85}" \
  KBG_IDEATE_EMBEDDINGS_FILE="$EMB_FILE" \
  python3 - <<'PY' 2>/dev/null
import json
import math
import os
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

TRANSCRIPT = os.environ.get('KBG_IDEATE_TRANSCRIPT', '')
OLLAMA_HOST = os.environ.get('KBG_IDEATE_OLLAMA_HOST', 'http://localhost:11434').rstrip('/')
OLLAMA_MODEL = os.environ.get('KBG_IDEATE_EMBEDDING_MODEL', 'all-minilm:latest')
try:
    OLLAMA_TIMEOUT = float(os.environ.get('KBG_IDEATE_OLLAMA_TIMEOUT', '8'))
    if OLLAMA_TIMEOUT <= 0:
        OLLAMA_TIMEOUT = 8
except ValueError:
    OLLAMA_TIMEOUT = 8
THRESHOLD = os.environ.get('KBG_IDEATE_CONVERGENCE_THRESHOLD', '0.85')
try:
    THRESHOLD = float(THRESHOLD)
except ValueError:
    THRESHOLD = 0.85
EMB_FILE = os.environ.get('KBG_IDEATE_EMBEDDINGS_FILE', '')

SLASH_RE = re.compile(r'(?:^|[\s])/ideate\b', re.IGNORECASE)


def extract_text(content: Any) -> str:
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


def event_content(ev: Any) -> Any:
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


def clean_problem(text: str) -> str:
    text = re.sub(r'\s+', ' ', text)
    return text.strip()[:500]


def is_ideate_invocation(item: Any) -> bool:
    if not isinstance(item, dict):
        return False
    tool_name = item.get('tool_name') or item.get('name') or ''
    inp = item.get('input') or {}
    if tool_name == 'Skill':
        return inp.get('skill') in ('ideate', 'kbg:ideate')
    if tool_name == 'Command':
        return inp.get('command') in ('ideate', '/ideate')
    return False


def iter_ideate_invocations(ev: dict) -> list[dict]:
    """Return any ideate invocations carried by this event."""
    found = []
    if is_ideate_invocation(ev):
        found.append(ev)
    # Nested tool_use blocks inside assistant message content.
    content = event_content(ev)
    if isinstance(content, list):
        for block in content:
            if is_ideate_invocation(block):
                found.append(block)
    return found


def parse_transcript(path: str) -> tuple[list[dict], list[dict]]:
    """Return (events_in_order, ideate_invocations)."""
    p = Path(path)
    if not p.exists():
        return [], []
    raw = p.read_text(encoding='utf-8', errors='replace')
    if not raw.strip():
        return [], []

    events: list[dict] = []
    invocations: list[dict] = []

    # Prefer JSONL; fall back to legacy single-object .messages format.
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
        if 'messages' in obj and isinstance(obj.get('messages'), list):
            # Legacy format: the whole file is one object with a .messages array.
            for ev in obj['messages']:
                if not isinstance(ev, dict):
                    continue
                events.append(ev)
                invocations.extend(iter_ideate_invocations(ev))
            break
        events.append(obj)
        invocations.extend(iter_ideate_invocations(obj))

    return events, invocations


def compute_embedding(problem: str) -> Optional[list[float]]:
    if not problem or not problem.strip():
        return None
    payload = json.dumps({'model': OLLAMA_MODEL, 'prompt': problem}).encode('utf-8')
    req = urllib.request.Request(
        f'{OLLAMA_HOST}/api/embeddings',
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=OLLAMA_TIMEOUT) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            emb = data.get('embedding')
            if isinstance(emb, list) and emb:
                return [float(x) for x in emb]
    except Exception:
        pass
    return None


def cosine_similarity(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def max_same_day_similarity(current: list[float], today: str, path: str) -> float:
    if not path or not current:
        return 0.0
    p = Path(path)
    if not p.exists():
        return 0.0
    max_sim = 0.0
    with p.open('r', encoding='utf-8', errors='replace') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(rec, dict):
                continue
            if rec.get('date') != today:
                continue
            emb = rec.get('embedding')
            if not isinstance(emb, list) or not emb:
                continue
            try:
                emb = [float(x) for x in emb]
            except (TypeError, ValueError):
                continue
            sim = cosine_similarity(current, emb)
            if sim > max_sim:
                max_sim = sim
    return max_sim


def main() -> None:
    events, invocations_list = parse_transcript(TRANSCRIPT)
    slash_invocations = 0
    last_slash_msg: Optional[dict] = None

    for ev in events:
        if ev.get('type') == 'user':
            text = extract_text(event_content(ev))
            if SLASH_RE.search(text):
                slash_invocations += 1
                last_slash_msg = ev

    invocation_count = len(invocations_list)
    invocations = invocation_count + slash_invocations

    if invocations == 0:
        print(json.dumps({'invocations': 0, 'problem': '', 'embedding': None,
                          'status': 'ok', 'reason': 'no ideate calls in session'}))
        return

    # Problem extraction: prefer the most recent ideate invocation's explicit
    # argument, otherwise the nearest preceding user message.
    last_invocation = invocations_list[-1] if invocations_list else None
    problem = ''
    if last_invocation is not None:
        inp = last_invocation.get('input') or {}
        for key in ('args', 'problem'):
            val = extract_text(inp.get(key))
            if val.strip():
                problem = val
                break
        if not problem.strip():
            inv_ts = last_invocation.get('timestamp') or ''
            for prev in reversed(events):
                if prev.get('type') != 'user':
                    continue
                prev_ts = prev.get('timestamp') or ''
                if prev_ts and inv_ts and prev_ts > inv_ts:
                    continue
                candidate = extract_text(event_content(prev))
                if candidate.strip():
                    problem = candidate
                    break
    if not problem.strip() and last_slash_msg is not None:
        problem = extract_text(event_content(last_slash_msg))
    if not problem.strip():
        problem = '(no problem extracted)'
    problem = clean_problem(problem)

    embedding = compute_embedding(problem)
    status = 'unknown'
    reason = 'Ollama embedding endpoint not available'

    if embedding is not None:
        status = 'ok'
        reason = 'embedding computed'
        today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
        max_sim = max_same_day_similarity(embedding, today, EMB_FILE)
        if max_sim >= THRESHOLD:
            status = 'warning'
            reason = f'max same-day cosine similarity {max_sim:.4f} >= threshold {THRESHOLD:.2f} — ideate runs may be converging'

    print(json.dumps({
        'invocations': invocations,
        'problem': problem,
        'embedding': embedding,
        'status': status,
        'reason': reason,
    }, default=lambda o: None if o is None else str(o)))


if __name__ == '__main__':
    main()
PY
)

# If the Python helper failed to return valid JSON, fail silently.
if [ -z "$PY_OUT" ] || ! printf '%s' "$PY_OUT" | jq -e . >/dev/null 2>&1; then
    exit 0
fi

# Extract all fields from PY_OUT in a single jq pass (one fork instead of five).
# Each value is on its own line; IFS= read -r preserves it verbatim (no trimming).
# EMBEDDING uses tojson so null → "null" and arrays → compact JSON, matching jq -c.
{ IFS= read -r INVOCATIONS
  IFS= read -r PROBLEM
  IFS= read -r EMBEDDING
  IFS= read -r CONVERGENCE_STATUS
  IFS= read -r CONVERGENCE_REASON
} < <(printf '%s' "$PY_OUT" | jq -r '
    (.invocations // 0),
    (.problem // "(no problem extracted)"),
    (.embedding | tojson),
    (.status // "unknown"),
    (.reason // "")' 2>/dev/null)
[ "$INVOCATIONS" -eq 0 ] 2>/dev/null && exit 0

DATE=$(date -u +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -nc \
  --arg date "$DATE" \
  --arg session_id "$SESSION_ID_VAL" \
  --arg ts "$TIMESTAMP" \
  --arg problem "$PROBLEM" \
  --argjson invocations "$INVOCATIONS" \
  --argjson embedding "${EMBEDDING:-null}" \
  --arg status "$CONVERGENCE_STATUS" \
  --arg reason "$CONVERGENCE_REASON" \
  '{
    date: $date,
    session_id: $session_id,
    ts: $ts,
    problem: $problem,
    invocations: $invocations,
    embedding: $embedding,
    convergence_status: $status,
    convergence_reason: $reason
  }' >> "$EMB_FILE" 2>/dev/null || {
    echo "[$HOOK_ID] ERROR: failed to append convergence record to $EMB_FILE" >&2
}

exit 0
