#!/usr/bin/env python3
"""ideate-memory.py — capture, index, and search past kbg:ideate runs.

This script is the deterministic half of the ideate-memory feature. It:

1. Initializes a qmd collection at ~/.claude/state/ideate-memory/.
2. Captures ideate runs from a Claude Code session transcript and writes one
   markdown file per run.
3. Indexes the collection with qmd.
4. Searches past runs by semantic similarity and returns ranked results.

Usage:
    python3 scripts/ideate-memory.py init
    python3 scripts/ideate-memory.py capture --transcript PATH --session-id SID
    python3 scripts/ideate-memory.py index
    python3 scripts/ideate-memory.py search "caching strategy"
    python3 scripts/ideate-memory.py status

The SessionEnd hook hooks/session/ideate-memory-capture.sh calls the capture
subcommand. The /ideate-search command calls the search subcommand.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


STATE_DIR = Path.home() / ".claude" / "state" / "ideate-memory"
COLLECTION_NAME = "ideate-memory"


def _sha1(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def _extract_text(content: Any) -> str:
    """Flatten a message content field to plain text."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))
            elif isinstance(item, dict) and item.get("type") == "tool_use":
                # Skip embedded tool_use blocks inside assistant content arrays.
                continue
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    return str(content)


def _event_content(ev: Any) -> Any:
    """Return the content payload for a transcript event.

    Current vendor transcripts wrap the message payload in a nested `message`
    object; legacy transcripts stored content directly on the event.
    """
    if not isinstance(ev, dict):
        return None
    if "content" in ev:
        return ev["content"]
    msg = ev.get("message")
    if isinstance(msg, dict):
        return msg.get("content")
    return None


def _load_transcript(path: Path) -> tuple[list[dict], list[dict]]:
    """Return (messages, tool_uses) from a Claude Code transcript.

    Handles both JSONL (one event per line, the current vendor format) and the
    legacy single-JSON-object with a .messages array.
    """
    raw = path.read_text(encoding="utf-8")
    if not raw.strip():
        return [], []

    messages: list[dict] = []
    tool_uses: list[dict] = []

    # Try JSONL first.
    parsed_lines = 0
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        parsed_lines += 1
        if isinstance(obj, dict):
            if obj.get("type") in ("user", "assistant", "system"):
                messages.append(obj)
            elif obj.get("type") == "tool_use":
                tool_uses.append(obj)
            elif "messages" in obj and isinstance(obj["messages"], list):
                # Legacy single-object format; merge and stop further line parsing.
                messages.extend(obj["messages"])
                break

    if parsed_lines and (messages or tool_uses):
        # Normalize assistant tool_use blocks embedded in content arrays into
        # standalone tool_use rows so downstream logic can find them.
        for msg in messages:
            if msg.get("type") != "assistant":
                continue
            content = _event_content(msg)
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "tool_use":
                        tool_uses.append(item)
        return messages, tool_uses

    # Legacy single-JSON-object format.
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return [], []
    if isinstance(data, dict) and isinstance(data.get("messages"), list):
        messages = data["messages"]
        for msg in messages:
            if msg.get("type") == "assistant":
                content = _event_content(msg)
                if isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "tool_use":
                            tool_uses.append(item)
        return messages, tool_uses

    return [], []


def _is_ideate_skill_call(item: dict) -> bool:
    """Return True if item is a tool_use whose skill target is ideate."""
    if not isinstance(item, dict):
        return False
    tool_name = item.get("tool_name") or item.get("name") or ""
    if tool_name != "Skill":
        return False
    inp = item.get("input") or {}
    return inp.get("skill") in ("ideate", "kbg:ideate")


def _find_ideate_runs(messages: list[dict], tool_uses: list[dict]) -> list[dict]:
    """Find ideate tool_use events and the assistant response that follows each."""
    # Build a unified timeline of candidate skill calls, keyed by a stable order.
    skill_calls: list[tuple[int, dict]] = []
    seen_ids: set[str] = set()

    def _seen_id(item: dict) -> str:
        return item.get("uuid") or item.get("id") or json.dumps(item, sort_keys=True, default=str)

    for item in tool_uses:
        if _is_ideate_skill_call(item):
            sid = _seen_id(item)
            if sid not in seen_ids:
                seen_ids.add(sid)
                skill_calls.append((len(skill_calls), item))

    for i, msg in enumerate(messages):
        if _is_ideate_skill_call(msg):
            sid = _seen_id(msg)
            if sid not in seen_ids:
                seen_ids.add(sid)
                skill_calls.append((len(skill_calls), msg))

    # Sort by timestamp when available so the "most recent" heuristic in the hook
    # stays stable even if embedded tool_use blocks appear before standalone lines.
    def _ts(item: dict) -> str:
        return item.get("timestamp") or ""

    skill_calls.sort(key=lambda pair: (_ts(pair[1]), pair[0]))

    runs = []
    for raw_idx, msg in skill_calls:
        # Locate this call in the messages timeline for nearest-neighbour lookup.
        idx = None
        for i, m in enumerate(messages):
            if m is msg:
                idx = i
                break
        if idx is None:
            # Nested tool_use blocks extracted from assistant content share the
            # same object reference as the block inside the parent message.
            for i, m in enumerate(messages):
                if m.get("type") != "assistant":
                    continue
                content = _event_content(m)
                if isinstance(content, list):
                    for block in content:
                        if block is msg:
                            idx = i
                            break
                if idx is not None:
                    break
        if idx is None:
            idx = raw_idx

        inp = msg.get("input") or {}
        problem_arg = _extract_text(inp.get("args") or "")
        if not problem_arg.strip():
            problem_arg = _extract_text(inp.get("problem") or "")

        # Find the user message that triggered this ideate call.
        problem = problem_arg
        ts = msg.get("timestamp", "")
        if not problem.strip():
            for prev in reversed(messages[:idx]):
                if prev.get("type") == "user":
                    prev_ts = prev.get("timestamp", "")
                    if prev_ts and ts and prev_ts > ts:
                        break
                    candidate = _extract_text(_event_content(prev))
                    if candidate.strip():
                        problem = candidate
                        break

        # Find the first assistant message after this tool_use that has actual
        # text output (skip assistant messages that are only tool_use wrappers).
        output = ""
        for nxt in messages[idx + 1 :]:
            nxt_type = nxt.get("type")
            if nxt_type == "assistant":
                candidate = _extract_text(_event_content(nxt))
                if candidate.strip():
                    output = candidate
                    break
                # Empty assistant message (likely a tool_use wrapper): keep looking.
            if nxt_type == "user":
                # Stop if the user speaks before the assistant answers.
                break

        runs.append(
            {
                "problem": problem.strip(),
                "output": output.strip(),
                "timestamp": ts,
                "frames": [],  # Could be populated later if we infer them from context.
            }
        )
    return runs


def _clean_filename(text: str) -> str:
    """Make a filesystem-safe slug from a problem text."""
    slug = re.sub(r"[^a-zA-Z0-9฀-๿ _-]", "", text)
    slug = re.sub(r"\s+", "_", slug).strip("_")
    return slug[:60]


def _write_run(date: str, session_id: str, run: dict) -> Optional[Path]:
    """Write one ideate run as a markdown file in the state directory."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    problem = run.get("problem") or "(no problem)"
    problem_slug = _clean_filename(problem)
    problem_hash = _sha1(problem)
    session_part = _sha1(session_id)[:8]
    filename = f"{date}_{session_part}_{problem_slug}_{problem_hash}.md"
    # Collapse collisions by appending a counter.
    path = STATE_DIR / filename
    counter = 1
    stem = path.stem
    while path.exists():
        path = STATE_DIR / f"{stem}_{counter}.md"
        counter += 1

    frames_yaml = ""
    if run.get("frames"):
        frames_yaml = "frames:\n" + "".join(f"  - {f}\n" for f in run["frames"])

    frontmatter = {
        "problem": problem,
        "date": date,
        "session_id": session_id,
        "timestamp": run.get("timestamp", ""),
    }
    if run.get("frames"):
        frontmatter["frames"] = run["frames"]

    body = run.get("output") or "(no output captured)"
    # Ensure the problem is also in the body so qmd indexes it.
    full_body = f"## Problem\n\n{problem}\n\n## Output\n\n{body}"

    content = (
        "---\n"
        + json.dumps(frontmatter, indent=2, ensure_ascii=False)
        + "\n---\n\n"
        + full_body
        + "\n"
    )

    path.write_text(content, encoding="utf-8")
    return path


def _qmd_available() -> bool:
    return shutil.which("qmd") is not None


def _qmd(args: list[str], check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["qmd", *args],
        capture_output=True,
        text=True,
        check=check,
    )


def cmd_init(_argv: Any) -> int:
    """Create the state directory and qmd collection."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"State directory: {STATE_DIR}")

    if not _qmd_available():
        print("[WARN] qmd not found — collection will be created on first search.")
        return 0

    # Check if collection already exists with the right path.
    result = _qmd(["collection", "list"])
    existing = result.stdout + result.stderr
    if COLLECTION_NAME in existing:
        show = _qmd(["collection", "show", COLLECTION_NAME])
        if str(STATE_DIR) in show.stdout or str(STATE_DIR) in show.stderr:
            print(f"qmd collection already exists and points to {STATE_DIR}")
            return 0
        print(f"[WARN] qmd collection '{COLLECTION_NAME}' exists but points elsewhere.")
        print(f"        Remove it with: qmd collection remove {COLLECTION_NAME}")
        print(f"        Then recreate with: qmd collection add {COLLECTION_NAME} {STATE_DIR.name}/")
        return 1

    # qmd resolves collection paths relative to the cwd at creation time, so run
    # the add command from the state parent directory with a relative path.
    parent_dir = STATE_DIR.parent
    rel_path = f"{STATE_DIR.name}/"
    result = subprocess.run(
        ["qmd", "collection", "add", COLLECTION_NAME, rel_path],
        capture_output=True,
        text=True,
        cwd=str(parent_dir),
    )
    if result.returncode != 0:
        print(f"[ERROR] failed to create qmd collection: {result.stderr}", file=sys.stderr)
        return 1
    print(f"Created qmd collection: {COLLECTION_NAME} -> {STATE_DIR}")
    return 0


def cmd_capture(args: argparse.Namespace) -> int:
    """Read a transcript and persist any ideate runs found."""
    transcript_path = Path(args.transcript)
    if not transcript_path.exists():
        print(f"[WARN] transcript not found: {transcript_path}", file=sys.stderr)
        return 0

    messages, tool_uses = _load_transcript(transcript_path)
    if not messages and not tool_uses:
        return 0

    runs = _find_ideate_runs(messages, tool_uses)
    if not runs:
        return 0

    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    written = 0
    for run in runs:
        if not run["problem"] and not run["output"]:
            continue
        path = _write_run(date, args.session_id, run)
        if path:
            written += 1
            print(f"[ideate-memory] captured {path.name}")

    if written:
        print(f"[ideate-memory] captured {written} run(s)")
    return 0


def cmd_index(_args: argparse.Namespace) -> int:
    """Update and embed the qmd collection."""
    if not _qmd_available():
        print("[ERROR] qmd not found", file=sys.stderr)
        return 1

    update = _qmd(["update", COLLECTION_NAME])
    if update.returncode != 0:
        print(f"[WARN] qmd update: {update.stderr}", file=sys.stderr)

    embed = _qmd(["embed", COLLECTION_NAME])
    if embed.returncode != 0:
        print(f"[WARN] qmd embed: {embed.stderr}", file=sys.stderr)

    return 0


def _parse_qmd_json_output(stdout: str) -> list[dict]:
    """Extract the JSON array from qmd query stdout, ignoring progress lines."""
    # qmd emits spinner/progress lines before the JSON payload. The last
    # JSON-like block in stdout is the result array.
    start = stdout.rfind("[")
    if start == -1:
        return []
    # Find the matching closing bracket from the end to handle nested brackets.
    end = stdout.rfind("]")
    if end == -1 or end < start:
        return []
    try:
        return json.loads(stdout[start : end + 1])
    except json.JSONDecodeError:
        return []


def _extract_frontmatter(body: str) -> dict:
    """Parse JSON frontmatter from a captured ideate markdown file body."""
    if not body.startswith("---"):
        return {}
    end = body.find("\n---", 3)
    if end == -1:
        return {}
    try:
        return json.loads(body[3:end].strip())
    except json.JSONDecodeError:
        return {}


def _format_search_result(rank: int, result: dict) -> str:
    """Render one qmd result as a concise ideate-memory entry."""
    body = result.get("body") or result.get("snippet") or ""
    meta = _extract_frontmatter(body)
    problem = meta.get("problem") or "(unknown problem)"
    date = meta.get("date") or ""
    session_id = meta.get("session_id") or ""
    score = result.get("score")
    score_str = f" ({int(score * 100)}%)" if isinstance(score, (int, float)) else ""

    lines = [f"{rank}. {problem}{score_str}"]
    if date:
        lines.append(f"    date: {date}")
    if session_id:
        lines.append(f"    session: {session_id}")

    # One-line gist from the output body: first non-empty line after ## Output.
    gist = ""
    in_output = False
    for line in body.splitlines():
        if line.startswith("## Output"):
            in_output = True
            continue
        if in_output and line.strip() and not line.startswith("#"):
            gist = line.strip()
            break
    if gist:
        lines.append(f"    gist: {gist}")

    return "\n".join(lines)


def cmd_search(args: argparse.Namespace) -> int:
    """Search past ideate runs by semantic similarity."""
    if not _qmd_available():
        print("[ERROR] qmd not found — cannot search.", file=sys.stderr)
        return 1

    # Ensure collection exists and is indexed.
    init_rc = cmd_init(args)
    if init_rc != 0:
        return init_rc

    index_rc = cmd_index(args)
    if index_rc != 0:
        return index_rc

    query = args.query
    if not query.strip():
        print("ERROR: query cannot be empty.", file=sys.stderr)
        return 2

    result = _qmd(
        ["query", "-c", COLLECTION_NAME, "-n", "10", "--format", "json", "--full", query],
        check=False,
    )
    if result.returncode != 0:
        print(f"[ERROR] qmd query failed: {result.stderr}", file=sys.stderr)
        return 1

    results = _parse_qmd_json_output(result.stdout)
    if not results:
        print("No matching ideate runs found.")
        return 0

    print(f"## ideate memory search results (n={len(results)})")
    print(f"collection: {COLLECTION_NAME}\n")
    for rank, item in enumerate(results, 1):
        print(_format_search_result(rank, item))
        print()
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    """Show how many ideate runs have been captured."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(STATE_DIR.glob("*.md"))
    print(f"Captured ideate runs: {len(files)}")
    print(f"State directory: {STATE_DIR}")
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Capture, index, and search past kbg:ideate runs."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("init", help="Create the state directory and qmd collection.")

    p_capture = sub.add_parser("capture", help="Capture ideate runs from a transcript.")
    p_capture.add_argument("--transcript", required=True, help="Path to session transcript JSON.")
    p_capture.add_argument("--session-id", default="no-sid", help="Session identifier.")

    sub.add_parser("index", help="Update and embed the qmd collection.")

    p_search = sub.add_parser("search", help="Search past ideate runs.")
    p_search.add_argument("query", help="Search query.")

    sub.add_parser("status", help="Show capture count.")

    args = parser.parse_args(argv)

    if args.command == "init":
        return cmd_init(args)
    if args.command == "capture":
        return cmd_capture(args)
    if args.command == "index":
        return cmd_index(args)
    if args.command == "search":
        return cmd_search(args)
    if args.command == "status":
        return cmd_status(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
