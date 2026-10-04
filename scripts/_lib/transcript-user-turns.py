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

A third non-human case: an async task's completion callback (a dispatched
Agent or a backgrounded Bash command) rides back as plain-string "user"
content starting with "<task-notification>", not a tool_result block
(hooks/stop/cost-tracker.sh's jq filter uses the same
startswith("<task-notification>") check to recognize it). A fourth and
fifth: `isMeta` events (skill bodies, local-command output, system
reminders -- skills/meta/learn/SKILL.md's own transcript filter treats
this the same way) and `isCompactSummary` events (a compaction's own
re-stated prior turns, which would otherwise double-print). Other wrapper
shapes (`<local-command-stdout>`, `<bash-stdout>`, `<bash-input>`,
"[Request interrupted...]") are not filtered here -- out of scope until a
caller actually needs them excluded.

A turn must also carry nonblank text: a blank string, an empty text block,
or an image-only turn is dropped. `message.role` is not checked -- the event's
own `"type": "user"` already says it. (skills/meta/learn/SKILL.md carried its
own inline filter until #413; it differed on exactly those two points, pinned
in tests/scripts/test-transcript-user-turns.sh.)

Usage: python3 transcript-user-turns.py [--json] <path-to-session.jsonl>
Prints each human turn's text to stdout, separated by a "--- turn N ---"
marker line and a blank line. With --json, prints one JSON object per turn
per line instead: {"turn", "uuid", "timestamp", "text"}.
"""
import json
import sys


def turn_text(content):
    """Return a user event's human-readable text, or "" if it is not a
    plain human turn (content is missing, empty, carries a tool_result, or
    is a task-notification callback)."""
    if isinstance(content, str):
        return "" if content.startswith("<task-notification>") else content
    if not isinstance(content, list):
        return ""
    if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
        return ""
    parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    return "\n".join(p for p in parts if p)


def human_turns(lines):
    """Yield each human turn's text, in order, from an iterable of raw
    JSONL lines."""
    for _event, text in human_turn_events(lines):
        yield text


def human_turn_events(lines):
    """Yield (event, text) for each human turn, in order."""
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
        if event.get("isMeta") or event.get("isCompactSummary"):
            continue
        message = event.get("message")
        if not isinstance(message, dict):
            continue
        text = turn_text(message.get("content"))
        if text.strip():
            yield event, text


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
        json.dumps({"type": "user", "message": {"role": "user",
                    "content": "<task-notification>\n<task-id>aaa</task-id>\n<status>completed</status>\n</task-notification>"}}),
        json.dumps({"type": "user", "isMeta": True, "message": {"role": "user",
                    "content": "Base directory for this skill: /path/to/skill"}}),
        json.dumps({"type": "user", "isCompactSummary": True, "message": {"role": "user",
                    "content": "This session is being continued from a previous conversation..."}}),
    ]
    turns = list(human_turns(fixture))
    assert turns == ["hello", "second prompt"], turns
    print("transcript-user-turns.py selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
        sys.exit(0)
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = len(args) != len(sys.argv) - 1
    if len(args) != 1:
        print("usage: transcript-user-turns.py [--json] <path-to-session.jsonl>", file=sys.stderr)
        sys.exit(1)
    with open(args[0], encoding="utf-8") as f:
        for n, (event, text) in enumerate(human_turn_events(f), start=1):
            if as_json:
                print(json.dumps({"turn": n, "uuid": event.get("uuid"),
                                  "timestamp": event.get("timestamp"), "text": text},
                                 ensure_ascii=False))
                continue
            print(f"--- turn {n} ---")
            print(text)
            print()
