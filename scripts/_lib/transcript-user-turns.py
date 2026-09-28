"""transcript-user-turns.py -- print a Claude Code session transcript's own
human-typed turns, skipping tool-result turns.

A session .jsonl transcript represents both a human's typed prompt and every
tool result as a "user"-role event (tool_result blocks ride back to the API
as user-role content). Retyped as an ad hoc `python3 -c` filter in 21 past
matt-harness sessions (2026-09-28 session-history mining) instead of living
as a checked-in script. A "user" event counts as a real human turn only when
none of its content blocks are tool_result -- the JSONL format allows a
mixed turn in principle, and treating one as non-human on any tool_result
block errs toward under- rather than over-including tool noise.

Usage: python3 transcript-user-turns.py <path-to-session.jsonl>
Prints each human turn's text to stdout, separated by a "--- turn N ---"
marker line and a blank line.
"""
import json
import sys


def turn_text(content):
    """Return a user event's human-readable text, or "" if it is not a
    plain human turn (content is missing, empty, or carries a tool_result)."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
        return ""
    parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    return "\n".join(p for p in parts if p)


def human_turns(lines):
    """Yield each human turn's text, in order, from an iterable of raw
    JSONL lines."""
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict) or event.get("type") != "user":
            continue
        message = event.get("message")
        if not isinstance(message, dict):
            continue
        text = turn_text(message.get("content"))
        if text.strip():
            yield text


def _selftest():
    fixture = [
        json.dumps({"type": "user", "message": {"role": "user", "content": "hello"}}),
        json.dumps({"type": "user", "message": {"role": "user",
                    "content": [{"type": "tool_result", "content": "tool output"}]}}),
        json.dumps({"type": "assistant", "message": {"role": "assistant", "content": "ignored"}}),
        json.dumps({"type": "user", "message": {"role": "user",
                    "content": [{"type": "text", "text": "second prompt"}]}}),
        "",
        "not json",
        json.dumps({"type": "user", "message": {"role": "user", "content": "   "}}),
    ]
    turns = list(human_turns(fixture))
    assert turns == ["hello", "second prompt"], turns
    print("transcript-user-turns.py selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
        sys.exit(0)
    if len(sys.argv) != 2:
        print("usage: transcript-user-turns.py <path-to-session.jsonl>", file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[1], encoding="utf-8") as f:
        for n, text in enumerate(human_turns(f), start=1):
            print(f"--- turn {n} ---")
            print(text)
            print()
