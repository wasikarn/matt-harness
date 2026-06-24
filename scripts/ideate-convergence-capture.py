#!/usr/bin/env python3
"""ideate-convergence-capture.py — capture one convergence record per session.

The heavy half of hooks/session/ideate-convergence-capture.sh: parse the
session transcript for /ideate (and kbg:ideate) invocations, extract the
problem fingerprint, compute a local Ollama (all-minilm) embedding, score
same-day convergence against ~/.claude/state/ideate-embeddings.jsonl, and
append one JSONL row. Runs as a `nohup` background child of the SessionEnd
hook so the hook returns in <50ms and the Claude CLI never cancels it
(the failure mode fc27033 fixed for the sibling memory-capture hook;
convergence was only timeout-capped, not backgrounded, so it still recurred).

Advisory only. Never blocks. Never mutates the repo. Exits 0 on every path.
Losing the record to an immediate power-off is acceptable for advisory
convergence telemetry.

Stdlib-only (urllib for the local Ollama API). Mirrors the inline Python that
previously lived in the hook body, with the jq append folded in.

Usage:
    python3 scripts/ideate-convergence-capture.py \\
        --transcript <path> --session-id <id> \\
        [--embeddings-file <path>] [--ollama-host <url>] \\
        [--ollama-model <name>] [--ollama-timeout <sec>] \\
        [--threshold <float>]
"""

import argparse
import json
import math
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

SLASH_RE = re.compile(r"(?:^|[\s])/ideate\b", re.IGNORECASE)


def extract_text(content: Any) -> str:
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    parts.append(item.get("text", ""))
                elif item.get("type") == "tool_use":
                    continue
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    return str(content)


def event_content(ev: Any) -> Any:
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


def clean_problem(text: str) -> str:
    text = re.sub(r"\s+", " ", text)
    return text.strip()[:500]


def is_ideate_invocation(item: Any) -> bool:
    if not isinstance(item, dict):
        return False
    tool_name = item.get("tool_name") or item.get("name") or ""
    inp = item.get("input") or {}
    if tool_name == "Skill":
        return inp.get("skill") in ("ideate", "kbg:ideate")
    if tool_name == "Command":
        return inp.get("command") in ("ideate", "/ideate")
    return False


def iter_ideate_invocations(ev: dict) -> list:
    found = []
    if is_ideate_invocation(ev):
        found.append(ev)
    content = event_content(ev)
    if isinstance(content, list):
        for block in content:
            if is_ideate_invocation(block):
                found.append(block)
    return found


def parse_transcript(path: str):
    """Return (events_in_order, ideate_invocations)."""
    p = Path(path)
    if not p.exists():
        return [], []
    raw = p.read_text(encoding="utf-8", errors="replace")
    if not raw.strip():
        return [], []

    events: list = []
    invocations: list = []

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
        if "messages" in obj and isinstance(obj.get("messages"), list):
            for ev in obj["messages"]:
                if not isinstance(ev, dict):
                    continue
                events.append(ev)
                invocations.extend(iter_ideate_invocations(ev))
            break
        events.append(obj)
        invocations.extend(iter_ideate_invocations(obj))

    return events, invocations


def compute_embedding(problem: str, host: str, model: str, timeout: float) -> Optional[list]:
    if not problem or not problem.strip():
        return None
    payload = json.dumps({"model": model, "prompt": problem}).encode("utf-8")
    req = urllib.request.Request(
        f"{host}/api/embeddings",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            emb = data.get("embedding")
            if isinstance(emb, list) and emb:
                return [float(x) for x in emb]
    except Exception:
        pass
    return None


def cosine_similarity(a: list, b: list) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def max_same_day_similarity(current: list, today: str, path: str) -> float:
    if not path or not current:
        return 0.0
    p = Path(path)
    if not p.exists():
        return 0.0
    max_sim = 0.0
    try:
        with p.open("r", encoding="utf-8", errors="replace") as fh:
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
                if rec.get("date") != today:
                    continue
                emb = rec.get("embedding")
                if not isinstance(emb, list) or not emb:
                    continue
                try:
                    emb = [float(x) for x in emb]
                except (TypeError, ValueError):
                    continue
                sim = cosine_similarity(current, emb)
                if sim > max_sim:
                    max_sim = sim
    except Exception:
        pass
    return max_sim


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Capture one kbg:ideate convergence record.")
    parser.add_argument("--transcript", required=True, help="Session transcript JSONL path.")
    parser.add_argument("--session-id", default="no-sid", help="Session id for the record.")
    parser.add_argument("--embeddings-file", default=str(Path.home() / ".claude" / "state" / "ideate-embeddings.jsonl"),
                        help="JSONL state file to append the record to.")
    parser.add_argument("--ollama-host", default=os.environ.get("KBG_IDEATE_OLLAMA_HOST", "http://localhost:11434").rstrip("/"))
    parser.add_argument("--ollama-model", default=os.environ.get("KBG_IDEATE_EMBEDDING_MODEL", "all-minilm:latest"))
    parser.add_argument("--ollama-timeout", type=float, default=float(os.environ.get("KBG_IDEATE_OLLAMA_TIMEOUT", "8") or 8))
    parser.add_argument("--threshold", type=float, default=float(os.environ.get("KBG_IDEATE_CONVERGENCE_THRESHOLD", "0.85") or 0.85))
    args = parser.parse_args(argv)

    transcript = args.transcript
    if not transcript or not Path(transcript).exists():
        return 0

    events, invocations_list = parse_transcript(transcript)
    slash_invocations = 0
    last_slash_msg: Optional[dict] = None
    for ev in events:
        if ev.get("type") == "user":
            text = extract_text(event_content(ev))
            if SLASH_RE.search(text):
                slash_invocations += 1
                last_slash_msg = ev

    invocations = len(invocations_list) + slash_invocations
    if invocations == 0:
        return 0  # no ideate calls -> write nothing, never create the file

    last_invocation = invocations_list[-1] if invocations_list else None
    problem = ""
    if last_invocation is not None:
        inp = last_invocation.get("input") or {}
        for key in ("args", "problem"):
            val = extract_text(inp.get(key))
            if val.strip():
                problem = val
                break
        if not problem.strip():
            inv_ts = last_invocation.get("timestamp") or ""
            for prev in reversed(events):
                if prev.get("type") != "user":
                    continue
                prev_ts = prev.get("timestamp") or ""
                if prev_ts and inv_ts and prev_ts > inv_ts:
                    continue
                candidate = extract_text(event_content(prev))
                if candidate.strip():
                    problem = candidate
                    break
    if not problem.strip() and last_slash_msg is not None:
        problem = extract_text(event_content(last_slash_msg))
    if not problem.strip():
        problem = "(no problem extracted)"
    problem = clean_problem(problem)

    embedding = compute_embedding(problem, args.ollama_host, args.ollama_model, args.ollama_timeout)
    status = "unknown"
    reason = "Ollama embedding endpoint not available"
    if embedding is not None:
        status = "ok"
        reason = "embedding computed"
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        max_sim = max_same_day_similarity(embedding, today, args.embeddings_file)
        if max_sim >= args.threshold:
            status = "warning"
            reason = f"max same-day cosine similarity {max_sim:.4f} >= threshold {args.threshold:.2f} — ideate runs may be converging"

    record = {
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "session_id": args.session_id,
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "problem": problem,
        "invocations": invocations,
        "embedding": embedding,
        "convergence_status": status,
        "convergence_reason": reason,
    }

    try:
        Path(args.embeddings_file).parent.mkdir(parents=True, exist_ok=True)
        with open(args.embeddings_file, "a", encoding="utf-8") as fh:
            # Compact separators (no whitespace) match the sibling budget hook's
            # jq output and the session_id grep the SessionEnd tests assert on.
            fh.write(json.dumps(record, separators=(",", ":"), default=lambda o: None if o is None else str(o)) + "\n")
    except Exception:
        # Advisory telemetry — never fail the (backgrounded) worker loudly.
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())