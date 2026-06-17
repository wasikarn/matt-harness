#!/usr/bin/env python3
"""ideate-cli.py — standalone prompt assembler for kbg:ideate.

This is NOT a full LLM pipeline. It has no API key, no network calls, and no
Claude Code runtime. It is a deterministic prompt assembler that produces the
same Diverge prompts the kbg:ideate skill uses, so a user can run them outside a
Claude Code session (e.g. piped to a local model, a script, or a batch queue).

Usage:
    python3 scripts/ideate-cli.py \
        --problem "How should we cache search results?" \
        --context "A B2B SaaS search API." \
        --format json

    cat problem.txt | python3 scripts/ideate-cli.py --format markdown

Outputs:
    JSON array of 5 Diverge prompts (one per frame), each ready to be sent to
    an isolated LLM worker. Each prompt carries the isolation invariant: the
    problem, optional context, the frame label, the frame vantage, and a system
    instruction that forbids evaluation.

The frame list can be supplied explicitly with --frames, or the CLI can read the
same rotation state used by the SessionStart hook with --rotate.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import List, Optional


FRAME_CATALOG = {
    "hardware-eyes": "Think in latency, memory layout, and physical constraints. Re-ask as a hardware/firmware problem. What does the bus topology, the cache, the timing budget tell you?",
    "regulator": "Audit for compliance and failure modes. What must be provable, traceable, or refusable here?",
    "ten-year-old": "A curious 10-year-old who has never seen software. Naive but unencumbered approaches. Ignore convention.",
    "adversary": "Hostile competitor or attacker. Approaches that exploit, fail, or sabotage the obvious solution — then invert into ideas.",
    "biology": "Transplant a mechanism from biology — immune systems, neural plasticity, cell signaling, evolution, gut flora. Force-fit it.",
    "logistics": "Steal from logistics: queues, batching, just-in-time, hub-and-spoke, returns, last-mile. Apply literally.",
    "game-design": "Game designer. What are the loops, rewards, friction, save-states, speedrun tricks? Treat the user/system as a player.",
    "markets": "Treat the problem as a market. Buyers, sellers, market-makers. What does an auction, a futures contract, a clearing house look like here?",
    "inversion": "Ask the OPPOSITE question. If goal is X, brainstorm 'how would we guarantee NOT-X' — then negate each answer back.",
    "extreme-zero": "No money, no team, one hour. Crudest version that still does the load-bearing thing. Hacks, hardcoded values, manual loops welcome.",
    "extreme-infinite": "Infinite compute, infinite engineers, a decade. What is the maximalist version? What would only be possible at that scale?",
    "remove-assumption": "Name the thing everyone treats as fixed (framework, database, request/response model, network). Imagine it is gone. What is possible?",
    "speedrunner": "Find glitches, skips, out-of-bounds tricks, frame-perfect shortcuts. What is the abusive-but-legal path?",
    "ant-colony": "No central planner. Many dumb agents, local rules, pheromone trails. How does the problem solve itself emergently?",
    "ops-3am": "On-call engineer woken at 3am when this breaks. What design would let you not get paged? Runbook-shaped solution.",
}

WILD_FRAMES = {
    "hardware-eyes", "biology", "markets", "extreme-infinite",
    "remove-assumption", "speedrunner", "ant-colony",
}

DEFAULT_IDEAS_PER_FRAME = 6


def _rotate_frames(seed: int, count: int = 5) -> List[str]:
    """Deterministic frame picker matching hooks/session/ideate-rotate.sh."""
    frame_ids = list(FRAME_CATALOG.keys())
    h = (seed * 2654435761) % 2147483647
    picked: List[str] = []
    used = set()
    for i in range(count):
        idx = (h + i * 97) % len(frame_ids)
        while frame_ids[idx] in used:
            idx = (idx + 1) % len(frame_ids)
        used.add(frame_ids[idx])
        picked.append(frame_ids[idx])
    if not set(picked) & WILD_FRAMES:
        picked[-1] = list(WILD_FRAMES)[h % len(WILD_FRAMES)]
    return picked


def _load_rotation_state() -> Optional[int]:
    """Read the next rotation index from the SessionStart hook state file."""
    state_path = Path.home() / ".claude" / "state" / "ideate-rotation.json"
    if not state_path.exists():
        return None
    try:
        data = json.loads(state_path.read_text(encoding="utf-8"))
        return int(data.get("index", 0))
    except (ValueError, TypeError, OSError):
        return None


def build_diverge_prompt(problem: str, context: str, frame: str, ideas_per_frame: int) -> dict:
    if frame not in FRAME_CATALOG:
        raise ValueError(f"Unknown frame: {frame}")
    vantage = FRAME_CATALOG[frame]
    context_block = f"CONTEXT:\n{context}\n\n" if context.strip() else ""
    user_prompt = (
        f"PROBLEM:\n{problem}\n\n"
        f"{context_block}"
        f"FRAME — {frame}:\n{vantage}\n\n"
        f"Generate {ideas_per_frame} ideas under this frame.\n"
        "Output JSON array only. No prose before or after.\n"
        '[{"text": "...", "rationale": "..."}, ...]'
    )
    system_prompt = (
        "You are in DIVERGENT mode. You are a generator, not a critic. "
        f"Generate {ideas_per_frame} short distinct ideas under this frame. "
        "Each idea is one phrase or one sentence. Do not evaluate. Do not rank. "
        "Do not hedge. The first three obvious answers everyone would give are "
        "banned. Push past them into the awkward middle. "
        "Output a JSON array only. No prose before or after. "
        '[{"text": "...", "rationale": "..."}, ...]'
    )
    return {
        "frame": frame,
        "system_prompt": system_prompt,
        "user_prompt": user_prompt,
        "schema": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "rationale": {"type": "string"},
                },
                "required": ["text", "rationale"],
            },
        },
    }


def format_json(prompts: List[dict]) -> str:
    return json.dumps(prompts, indent=2, ensure_ascii=False)


def format_plain(prompts: List[dict]) -> str:
    lines: List[str] = []
    for p in prompts:
        lines.append(f"=== FRAME: {p['frame']} ===")
        lines.append("--- SYSTEM ---")
        lines.append(p["system_prompt"])
        lines.append("--- USER ---")
        lines.append(p["user_prompt"])
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def format_markdown(prompts: List[dict]) -> str:
    lines: List[str] = []
    for p in prompts:
        lines.append(f"## Frame: `{p['frame']}`")
        lines.append("")
        lines.append("### System prompt")
        lines.append("")
        lines.append("```")
        lines.append(p["system_prompt"])
        lines.append("```")
        lines.append("")
        lines.append("### User prompt")
        lines.append("")
        lines.append("```")
        lines.append(p["user_prompt"])
        lines.append("```")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Assemble kbg:ideate Diverge prompts for batch execution outside Claude Code."
    )
    parser.add_argument(
        "--problem", "-p",
        default=None,
        help="The ideation problem. If omitted, read from stdin.",
    )
    parser.add_argument(
        "--context", "-c",
        default="",
        help="Optional surrounding context for the problem.",
    )
    parser.add_argument(
        "--frames", "-f",
        default=None,
        help="Comma-separated frame IDs (default: auto-rotate via hook state).",
    )
    parser.add_argument(
        "--rotate", action="store_true",
        help="Use the same deterministic rotation as hooks/session/ideate-rotate.sh.",
    )
    parser.add_argument(
        "--ideas-per-frame", type=int, default=DEFAULT_IDEAS_PER_FRAME,
        help=f"Number of ideas each frame should generate (default: {DEFAULT_IDEAS_PER_FRAME}).",
    )
    parser.add_argument(
        "--format", choices=["json", "markdown", "plain"], default="markdown",
        help="Output format for the assembled prompts (default: markdown).",
    )
    args = parser.parse_args(argv)

    if args.problem is None:
        if sys.stdin.isatty():
            parser.print_help(sys.stderr)
            return 2
        args.problem = sys.stdin.read()

    problem = args.problem.strip()
    if not problem:
        print("ERROR: problem cannot be empty.", file=sys.stderr)
        return 2

    if args.frames:
        frames = [f.strip() for f in args.frames.split(",") if f.strip()]
        unknown = [f for f in frames if f not in FRAME_CATALOG]
        if unknown:
            print(f"ERROR: unknown frame(s): {', '.join(unknown)}", file=sys.stderr)
            return 2
    elif args.rotate:
        seed = _load_rotation_state() or 0
        frames = _rotate_frames(seed)
    else:
        # Default deterministic set matching the skill's original picker.
        frames = ["regulator", "ops-3am", "logistics", "adversary", "biology"]

    if len(frames) != 5:
        print("WARNING: ideate is calibrated for 5 frames; using a different count changes the cost/range trade-off.", file=sys.stderr)

    prompts = [build_diverge_prompt(problem, args.context, frame, args.ideas_per_frame) for frame in frames]

    if args.format == "json":
        print(format_json(prompts))
    elif args.format == "plain":
        print(format_plain(prompts))
    else:
        print(format_markdown(prompts))

    return 0


if __name__ == "__main__":
    sys.exit(main())
