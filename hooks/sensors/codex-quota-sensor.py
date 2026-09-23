#!/usr/bin/env python3
"""PostToolUseFailure(Bash) sensor: on a Codex CLI command failing with a
usage-limit/rate-limit-shaped error, records the failure so the paired
codex-quota-advisory.py sensor can warn before the next Codex dispatch
instead of finding out mid-call again. Never blocks (always exit 0) --
advisory infrastructure only, same posture as failure-diagnose-nudge.py.

Real gap this closes: docs/reference/codex-integration-map.md and
memory's project_codex_usage_limit_hit_twice_2026_09_12.md both record the
Codex CLI's usage quota being exhausted multiple times across sessions with
no automated detection -- every hit was discovered reactively, mid-dispatch.
This sensor (and its paired advisory) doesn't recover Codex availability;
it only stops a doomed retry from spending a round-trip on a window that's
already known to be closed.

Persisted, not session-scoped: a quota retry window can span hours to
days, well past this session's lifetime, unlike failure-diagnose-nudge's
session-scoped nudge cap. State lives under ~/.cache/mh by default,
overridable via MH_CODEX_QUOTA_STATE_FILE (tests point this at a throwaway
path).

Deliberately loose match on the failure text ("usage limit", "rate limit",
"quota") rather than one exact string: the Codex CLI's exact wording is not
a documented contract, and a false positive here only costs one redundant
advisory line later, never a block.
"""
import json
import os
import re
import sys
import time

_CODEX_RE = re.compile(r"(^|[\s/\"'])codex([\s\"']|$)")
_QUOTA_RE = re.compile(r"usage\s*limit|rate\s*limit|quota", re.IGNORECASE)
_MAX_MESSAGE_LEN = 500


def default_state_path():
    return os.environ.get("MH_CODEX_QUOTA_STATE_FILE") or os.path.expanduser(
        "~/.cache/mh/codex-quota-state.json"
    )


def looks_like_codex_command(command):
    return bool(_CODEX_RE.search(command))


def looks_like_quota_failure(text):
    return bool(_QUOTA_RE.search(text))


def extract_command(data):
    ti = data.get("tool_input")
    if isinstance(ti, dict):
        cmd = ti.get("command")
        if isinstance(cmd, str):
            return cmd
    return ""


def record(state_path, message):
    try:
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        with open(state_path, "w") as f:
            json.dump({"recorded_at": int(time.time()), "message": message[:_MAX_MESSAGE_LEN]}, f)
    except OSError:
        pass  # fail-open: losing the record just means no advisory next time, never blocks


def main(argv):
    try:
        data = json.load(sys.stdin)
    except (ValueError, TypeError):
        return 0
    if not isinstance(data, dict):
        return 0
    if data.get("hook_event_name") != "PostToolUseFailure":
        return 0

    command = extract_command(data)
    if not command or not looks_like_codex_command(command):
        return 0

    error = data.get("error")
    if not isinstance(error, str) or not looks_like_quota_failure(error):
        return 0

    state_path = argv[1] if len(argv) > 1 else default_state_path()
    record(state_path, error)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
