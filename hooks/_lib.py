#!/usr/bin/env python3
"""
_lib — shared protocol helpers for Claude Code hooks. The single Python
emission point for the governance evidence journal; mirrors _lib.sh:journal_append
byte-for-byte. Contract: claude/hooks/JOURNAL-SCHEMA.md.

Envelope literal stamped by journal_append():
  {id, ts, session, hook, event, source: "journal_append", fields}

Stdlib only. No pip deps. Importable by hooks (security-diff-review.py) and
scripts (review-pr-journal.py). The bash shim (_lib.sh:_journal_append_py)
calls into this module via `python3 -c 'import _lib; _lib.journal_append(...)'`
so config-change-log.sh:50-51 stays unchanged at the call site.
"""

import json
import os
import re
import sys
import uuid
from datetime import datetime, timezone

JOURNAL_DEFAULT = os.path.join(os.path.expanduser("~"), ".claude",
                               "governance-events.jsonl")
# Pinned — JOURNAL-SCHEMA.md § "source" enum. Do NOT change to a per-language
# literal (e.g. "journal_append_py"): the source enum is consumer-stable and
# governance-summary.py ingests "journal_append" regardless of which language
# emitted the line. The bash and python paths stamp the same value.
SOURCE = "journal_append"

# Deny-list regexes — the KEY regex is the bash `password|api_key|secret|token|credential`
# set. The VALUE regex is byte-for-byte equivalent to _lib.sh:151: it includes
# BOTH the keyword substring (so a value containing `password|secret|...` is
# redacted — matches bash behavior) AND the shape patterns (AKIA…, gh[pousr]_…,
# sk-…, xoxb…-…, PEM headers, `user:pass@host`). `re.I` is the equivalent of
# jq's `"i"` flag.
_KEY_DL = re.compile(r"password|api_key|secret|token|credential", re.I)
_VAL_DL = re.compile(
    r"password|api_key|secret|token|credential"
    r"|AKIA[0-9A-Z]{16}"
    r"|gh[pousr]_[A-Za-z0-9]{20,}"
    r"|sk-[A-Za-z0-9]{20,}"
    r"|xox[baprs]-[A-Za-z0-9-]{10,}"
    r"|-----BEGIN[A-Z ]*PRIVATE KEY"
    r"|[a-z][a-z0-9+.\-]*://[^/@\s]+:[^/@\s]+@",
    re.I,
)


def _now_ms() -> int:
    """Millisecond epoch — composes the journal `id`. Contract-equivalent to
    the bash `_now_ms` in _lib.sh (same value; the envelope is
    language-agnostic)."""
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def _redact(value, key=None, _depth=0, _truncated=None):
    """Redact a value whose KEY or string content matches a secret name/shape.
    Recurses dict + list, same surface as the _lib.sh jq walk at lines
    153-159. The KEY match is word-boundary-free (matches the bash jq's
    `test("password|api_key|secret|token|credential"; "i")`); the VALUE
    match is shape-only.

    `_depth` caps recursion at 64 — Python's `json` default is 1000 but a
    hostile or malformed `fields` payload (e.g. a self-referential nested
    dict loop, or a >100-deep array) would crash with RecursionError mid-
    emit and surface as rc=1 to the caller. 64 covers all reasonable JSON
    shapes (the JSON spec has no real-world use of nesting >32).

    `_truncated` is a one-element list used as a mutable carrier so the
    caller can detect whether the depth cap fired on this emit and emit
    a stderr warning. Module-level (default `None` = no carrier) is safe
    because the only caller path is single-threaded synchronous journal
    emit; a missing carrier just disables the warning (test path)."""
    if _truncated is not None and _depth > 64:
        _truncated[0] = True
        return "[depth-truncated]"
    if key is not None and _KEY_DL.search(str(key)):
        return "[redacted]"
    if isinstance(value, dict):
        return {k: _redact(v, k, _depth + 1, _truncated) for k, v in value.items()}
    if isinstance(value, list):
        return [_redact(v, None, _depth + 1, _truncated) for v in value]
    if isinstance(value, str) and _VAL_DL.search(value):
        return "[redacted]"
    return value


def _normalize_fields(fields_json, hook_id):
    """Coerce `fields_json` to a dict, exiting 2 on any non-recoverable
    shape. Both union arms (str, dict) funnel through this single exit
    point so the caller can't accidentally bypass redaction or the id mint.

    Accepts:
      - str: parsed via json.loads (the bash-caller contract)
      - dict: passed through (the python-caller convenience)
    Rejects (exit 2): list, scalar, None, malformed str. The bash path
    lets jq discard these silently; the python path fails loud per Rule 12.
    """
    if isinstance(fields_json, str):
        try:
            parsed = json.loads(fields_json)
        except json.JSONDecodeError as e:
            print(f"[{hook_id}] ERROR: fields_json is not valid JSON ({e}); "
                  f"refusing to drop the event silently", file=sys.stderr)
            sys.exit(2)
    elif isinstance(fields_json, dict):
        parsed = fields_json
    else:
        print(f"[{hook_id}] ERROR: fields_json must be str or dict, got "
              f"{type(fields_json).__name__}; refusing to drop the event "
              f"silently", file=sys.stderr)
        sys.exit(2)
    if not isinstance(parsed, dict):
        print(f"[{hook_id}] ERROR: fields_json must decode to an object, "
              f"got {type(parsed).__name__}; refusing to drop the event "
              f"silently", file=sys.stderr)
        sys.exit(2)
    return parsed


def journal_append(hook_id, event, fields_json):
    """Append one nested-envelope event to the governance journal. Returns
    the minted id on stdout (Phase II linkage contract — callers capture
    the id and reference it as a later event's `subject_id`).

    Exit codes: 0 success; 2 fail-loud (malformed fields_json, I/O error,
    redaction overflow). Mirrors _lib.sh:journal_append exit codes 0/2.

    `fields_json` may be a JSON string (the bash-caller contract, see
    _lib.sh:124) OR a Python dict (the python-caller convenience). Both
    are accepted; the dict form skips the json.loads round-trip."""
    fields = _normalize_fields(fields_json, hook_id)
    # F5: detect depth-truncation during redaction so we can warn on stderr.
    # A silent data-loss fallback is still a silent failure — the operator
    # needs to know that an event was lossy-compressed by the journaler.
    _trunc = [False]
    redacted = _redact(fields, _truncated=_trunc)
    if _trunc[0]:
        print(f"[{hook_id}] WARNING: redaction depth-capped at 64 for "
              f"event={event!r}; some fields replaced with "
              f"'[depth-truncated]'", file=sys.stderr)

    ms = _now_ms()
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    rid = f"{ms}-{hook_id}-{uuid.uuid4().hex[:8]}"

    journal = os.environ.get("CLAUDE_JOURNAL_PATH") or JOURNAL_DEFAULT
    parent = os.path.dirname(journal)
    try:
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(journal, "a", encoding="utf-8") as f:
            # `separators=(",", ":")` matches the bash path's `jq -nc` byte
            # shape (no whitespace after `,` or `:`). Lockstep invariant:
            # both _lib.sh and _lib.py stamp the same envelope literal so a
            # downstream `grep '"event":"review_finding"'` works against
            # either path.
            #
            # CR-7 (2026-06-09 review): `allow_nan=False` rejects `NaN` and
            # `Infinity` with `ValueError`. Without it, `json.dumps` happily
            # writes the literals `NaN` / `Infinity` — invalid JSON that
            # downstream `jq -c .` reads as `null` (NaN) or a real number
            # (Infinity), silently corrupting the journal. The bash path
            # rejects NaN at the `jq --argjson` step with rc=1, so this
            # closes a lockstep-invariant break.
            f.write(json.dumps({
                "id": rid,
                "ts": ts,
                "session": os.environ.get("CLAUDE_SESSION_ID", "no-sid"),
                "hook": hook_id,
                "event": event,
                "source": SOURCE,
                "fields": redacted,
            }, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n")
    # F1: TypeError arms the dict-passing contract — `json.dumps` raises on
    # non-serializable values (set, datetime, custom class). The str arm
    # catches the same class of error at `_normalize_fields:json.loads`;
    # the dict arm MUST raise the same exit-2 with the same named stderr.
    # F6: include journal path + event so the operator can debug without
    # `set -x`. "File exists" (when parent is a file) and "Permission
    # denied" are now distinguishable in the message.
    # CR-7: ValueError catches the `allow_nan=False` rejection of NaN/Inf
    # — reuses the same stderr pattern (path + event + error type) so the
    # operator sees the same shape regardless of which I/O arm fired.
    except (OSError, PermissionError, TypeError, ValueError) as e:
        print(f"[{hook_id}] ERROR: journal write failed for event={event!r} "
              f"path={journal!r} ({type(e).__name__}: {e}) — refusing to "
              f"drop the event silently", file=sys.stderr)
        sys.exit(2)

    print(rid)
    return rid
