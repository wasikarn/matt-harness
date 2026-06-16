#!/usr/bin/env python3
"""
orchestrate-dispatch.py — deterministic coordinator-as-code dispatcher.

Reads a workflow spec (JSON or YAML) describing stages, resolves the DAG
into a wave-by-wave execution plan, optionally runs the `command`-typed
stages, and prints a structured plan suitable for a downstream consumer
(`/team-build`, `claude -p` headless, or a human operator) to dispatch
agent-typed stages per the lead-coordinator doctrine (F8 in
`skills/orchestrate/SKILL.md`).

What this script IS
-------------------
- A deterministic DAG resolver: parallel / sequential / loop-until
  semantics rendered as ordered waves, with `depends_on` validated as
  acyclic and every stage reachable.
- A validator for the workflow-spec contract — schema check + cycle
  detection + reachability check.
- A runner for `command`-typed stages (subprocess with timeouts) so the
  trivial "run `make build` then `pytest`" pipeline is one-shot.
- A plan emitter: `--emit-plan` prints a machine-readable JSON of the
  resolved wave structure; the lead (or `/team-build`) reads it and
  dispatches `agent`-typed stages per the F9 spawn-prompt template.

What this script IS NOT
-----------------------
- NOT an LLM agent dispatcher. `agent`-typed stages are emitted as
  "would-spawn" lines; the actual `Agent()` call lives in the Claude
  session, not in this script. The autonomy invariant (ADR 0002) keeps
  harness-internal loops at L2/L3 with a human gate per iteration;
  putting the LLM dispatch inside this script would be a covert L4.
- NOT a replacement for `/team-build`. `/team-build` owns the lead-
  coordinator contract; this script owns the spec-rendering half of
  the coordination contract. A lead can ask this script "what would
  the wave structure look like for `ship-merge.yml`?" before dispatch.
- NOT a `claude -p` headless harness. The script doesn't talk to an
  LLM; the lead does. If you need headless agent dispatch, that's a
  separate project (and a separate ADR-0002 conversation).

The fan-out cap (F8.5, hard cap = 5 per wave) is enforced in this
script via `--max-per-wave` (default 5); a symmetric F8.4 advisory floor
(`--min-per-wave`, default 3) flags an under-parallelized AGENT fan-out.
Clamping happens BEFORE the wave list is printed, not after — the lead
sees the clamped structure, not a 44-item wall of doom. The cap is on the
resolved wave list, not
on the input spec; the spec can declare more stages if the DAG fans
out organically. Over-cap stages are emitted to
`.scratch/<slug>/deferred-<date>.md` and queued for a follow-up wave.

ADR 0002 alignment
------------------
This dispatcher is L2/L3: a deterministic coordinator the lead consults
on demand. It does NOT auto-spawn agents, does NOT loop unattended, and
does NOT cross the human gate. The `--execute` mode runs ONLY
`command`-typed stages, which are the deterministic validator/fix
phases of a chain; `agent`-typed stages still need a human/lead gate.

Usage
-----
    # Validate + print the resolved wave plan (default; safe):
    python scripts/orchestrate-dispatch.py examples/ship-merge.yml

    # Emit a machine-readable plan (for `/team-build` consumption):
    python scripts/orchestrate-dispatch.py examples/ship-merge.yml --emit-plan

    # Run all `command`-typed stages in order (the deterministic chain
    # half — build, lint, test). Agent stages are emitted as plans only.
    python scripts/orchestrate-dispatch.py examples/ship-merge.yml --execute

    # Clamp the wave size before printing (default 5 per F8.5):
    python scripts/orchestrate-dispatch.py examples/ship-merge.yml --max-per-wave 8

    # JSON input works too:
    python scripts/orchestrate-dispatch.py examples/ship-merge.json

Exit codes
----------
    0 — spec is valid; plan emitted (or all command stages exited 0)
    1 — one or more command stages FAILED (or schema error during
        dispatch; not the validation pass)
    2 — bad invocation (missing spec path, unreadable file, empty stages)
    3 — parse error (malformed YAML/JSON)
    4 — schema error (cycle detected, unreachable stage, bad stage type,
        bad `depends_on` reference, or `loop_until` missing required
        fields). Distinct from exit 1 so "schema broken" doesn't
        masquerade as "build broken" in CI.

Sub-modules
-----------
    _orchestrate_loader.py   — load_spec, SpecValidationError, validate_spec
    _orchestrate_planner.py  — resolve_waves, build_plan, print_plan_human
    _orchestrate_executor.py — execute_command_stage, run_execute
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Ensure the scripts/ directory is importable when invoked as a script
sys.path.insert(0, str(Path(__file__).parent))

from orchestrate.loader import load_spec, validate_spec, SpecValidationError
from orchestrate.planner import resolve_waves, build_plan, print_plan_human
from orchestrate.executor import run_execute, DEFAULT_TIMEOUT

DEFAULT_MAX_PER_WAVE = 5  # F8.5 hard cap — max teammates per wave (skills/orchestrate/SKILL.md)
DEFAULT_MIN_PER_WAVE = 3  # F8.4 advisory floor — below this an AGENT fan-out is under-parallelized


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Deterministic dispatcher for workflow specs (coordination-as-code).",
    )
    parser.add_argument("spec", help="Path to workflow spec (JSON or YAML).")
    parser.add_argument(
        "--emit-plan", action="store_true",
        help="Print a machine-readable JSON plan to stdout (for /team-build consumption).",
    )
    parser.add_argument(
        "--execute", action="store_true",
        help="Run command-typed stages in wave order. Agent stages are reported only.",
    )
    parser.add_argument(
        "--max-per-wave", type=int, default=DEFAULT_MAX_PER_WAVE,
        help=f"Hard cap on stages per emitted wave (F8.5). Default: {DEFAULT_MAX_PER_WAVE}.",
    )
    parser.add_argument(
        "--min-per-wave", type=int, default=DEFAULT_MIN_PER_WAVE,
        help=f"Advisory floor for agent fan-out (F8.4 under-parallelized). Default: {DEFAULT_MIN_PER_WAVE}.",
    )
    parser.add_argument(
        "--timeout", type=int, default=DEFAULT_TIMEOUT,
        help=f"Per-command timeout in seconds. Default: {DEFAULT_TIMEOUT}.",
    )
    args = parser.parse_args()

    spec_path = Path(args.spec).resolve()
    spec = load_spec(spec_path)

    try:
        stages = validate_spec(spec)
    except SpecValidationError as e:
        print(f"orchestrate-dispatch: spec validation failed: {e}", file=sys.stderr)
        return 4

    waves = resolve_waves(stages, max_per_wave=args.max_per_wave)
    plan = build_plan(
        {"name": spec["name"], "description": spec.get("description", ""), "stages": stages},
        waves,
        max_per_wave=args.max_per_wave,
        min_per_wave=args.min_per_wave,
    )

    if args.emit_plan:
        print(json.dumps(plan, indent=2))
        return 0

    if args.execute:
        rc = run_execute(plan, timeout=args.timeout)
        if rc != 0:
            print(
                f"\norchestrate-dispatch: {rc} command stage(s) failed",
                file=sys.stderr,
            )
        return rc

    return print_plan_human(plan, spec_path)


if __name__ == "__main__":
    sys.exit(main())
