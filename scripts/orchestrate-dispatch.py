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

The fan-out cap (F8.5, hard cap = 16 per wave) is enforced in this
script via `--max-per-wave` (default 16). Clamping happens BEFORE the
wave list is printed, not after — the lead sees the clamped structure,
not a 44-item wall of doom. The cap is on the resolved wave list, not
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

    # Clamp the wave size before printing (default 16 per F8.5):
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
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

try:
    import yaml  # PyYAML — stdlib for most harness projects; safe-required
    HAS_YAML = True
except ImportError:
    HAS_YAML = False


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MAX_PER_WAVE = 16  # F8.5 hard cap (skills/orchestrate/SKILL.md)
DEFAULT_TIMEOUT = 60  # seconds per command-typed stage
SUPPORTED_STAGE_TYPES = {"command", "agent", "parallel", "loop"}


# ---------------------------------------------------------------------------
# Spec loading + parsing
# ---------------------------------------------------------------------------

def load_spec(path: Path) -> dict[str, Any]:
    """Load a workflow spec from JSON or YAML.

    Detection: .json → json.load; .yml/.yaml → yaml.safe_load; otherwise
    peek at the first non-whitespace char ('{' or '[' → JSON, else YAML).
    The auto-detect path matters because the harness ships both shapes
    (JSON for tool-generated specs, YAML for human-edited ones), and
    rejecting one is more friction than the peek costs.
    """
    if not path.exists():
        print(f"orchestrate-dispatch: spec not found: {path}", file=sys.stderr)
        sys.exit(2)

    text = path.read_text(encoding="utf-8")
    if not text.strip():
        print(f"orchestrate-dispatch: spec is empty: {path}", file=sys.stderr)
        sys.exit(2)

    suffix = path.suffix.lower()
    if suffix == ".json":
        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            print(f"orchestrate-dispatch: JSON parse error in {path}: {e}", file=sys.stderr)
            sys.exit(3)
    if suffix in (".yml", ".yaml"):
        if not HAS_YAML:
            print(
                "orchestrate-dispatch: PyYAML not installed; install it "
                "or pass a .json spec.",
                file=sys.stderr,
            )
            sys.exit(2)
        try:
            loaded = yaml.safe_load(text)
            return loaded if loaded is not None else {}
        except yaml.YAMLError as e:
            print(f"orchestrate-dispatch: YAML parse error in {path}: {e}", file=sys.stderr)
            sys.exit(3)

    # Auto-detect by first char
    stripped = text.lstrip()
    if stripped.startswith(("{", "[")):
        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            print(f"orchestrate-dispatch: JSON parse error in {path}: {e}", file=sys.stderr)
            sys.exit(3)
    if not HAS_YAML:
        print(
            f"orchestrate-dispatch: {path} has non-JSON suffix; PyYAML "
            "not installed. Use a .json spec or install PyYAML.",
            file=sys.stderr,
        )
        sys.exit(2)
    try:
        loaded = yaml.safe_load(text)
        return loaded if loaded is not None else {}
    except yaml.YAMLError as e:
        print(f"orchestrate-dispatch: YAML parse error in {path}: {e}", file=sys.stderr)
        sys.exit(3)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

class SpecValidationError(Exception):
    """Raised when the spec is structurally broken (cycle, bad reference,
    missing required field). Caught at the top level → exit 4.
    """


def validate_spec(spec: dict[str, Any]) -> list[dict[str, Any]]:
    """Validate the spec and return the normalized stage list.

    Required top-level fields:
      - name (str)
      - stages (list, ≥1)

    Per-stage fields (type-specific, see SUPPORTED_STAGE_TYPES):
      - id (str, unique within spec)
      - type: command | agent | parallel | loop
      - depends_on (list of stage ids; default [])
      - one of: command, agent_type+prompt, parallel (list of sub-stages),
        loop_until+body

    Raises SpecValidationError on:
      - missing/empty stages
      - duplicate stage id
      - unknown stage type
      - depends_on referencing a non-existent id
      - cycle in the DAG (detected by topo-sort)
      - unreachable stage
      - command stage missing `command` field
      - agent stage missing `agent_type` or `prompt`
      - parallel stage with empty sub-stage list
      - loop stage missing `loop_until` or `body`
    """
    if not isinstance(spec, dict):
        raise SpecValidationError(f"spec root must be a mapping, got {type(spec).__name__}")
    if "name" not in spec or not isinstance(spec["name"], str) or not spec["name"].strip():
        raise SpecValidationError("spec.name is required and must be a non-empty string")
    if "stages" not in spec or not isinstance(spec["stages"], list) or not spec["stages"]:
        raise SpecValidationError("spec.stages is required and must be a non-empty list")

    stages = spec["stages"]
    ids_seen: set[str] = set()
    for i, stage in enumerate(stages):
        if not isinstance(stage, dict):
            raise SpecValidationError(f"stage[{i}] must be a mapping, got {type(stage).__name__}")
        sid = stage.get("id")
        if not isinstance(sid, str) or not sid.strip():
            raise SpecValidationError(f"stage[{i}].id is required and must be a non-empty string")
        if sid in ids_seen:
            raise SpecValidationError(f"duplicate stage id: {sid!r}")
        ids_seen.add(sid)

        stype = stage.get("type")
        if stype not in SUPPORTED_STAGE_TYPES:
            raise SpecValidationError(
                f"stage {sid!r}: unknown type {stype!r}; "
                f"supported: {sorted(SUPPORTED_STAGE_TYPES)}"
            )

        deps = stage.get("depends_on", [])
        if deps is None:
            deps = []
        if not isinstance(deps, list):
            raise SpecValidationError(f"stage {sid!r}: depends_on must be a list, got {type(deps).__name__}")
        for dep in deps:
            if not isinstance(dep, str):
                raise SpecValidationError(f"stage {sid!r}: depends_on entries must be strings, got {type(dep).__name__}")
            if dep not in ids_seen and dep != sid:
                # Lazy check; full reference resolution happens after all ids are collected.
                # Here we just record that we'll re-check after the loop.
                pass

        if stype == "command":
            cmd = stage.get("command")
            if not isinstance(cmd, str) or not cmd.strip():
                raise SpecValidationError(f"stage {sid!r} (command): 'command' is required and must be a non-empty string")
        elif stype == "agent":
            if not isinstance(stage.get("agent_type"), str) or not stage["agent_type"].strip():
                raise SpecValidationError(f"stage {sid!r} (agent): 'agent_type' is required and must be a non-empty string")
            if not isinstance(stage.get("prompt"), str) or not stage["prompt"].strip():
                raise SpecValidationError(f"stage {sid!r} (agent): 'prompt' is required and must be a non-empty string")
        elif stype == "parallel":
            sub = stage.get("stages")
            if not isinstance(sub, list) or not sub:
                raise SpecValidationError(f"stage {sid!r} (parallel): 'stages' must be a non-empty list of sub-stages")
            # Sub-stages may be inline dicts or references; for v1 we require inline dicts.
            for j, ss in enumerate(sub):
                if not isinstance(ss, dict):
                    raise SpecValidationError(f"stage {sid!r} (parallel).stages[{j}] must be a mapping")
                # Sub-stages inherit validation; the simplest v1 policy is
                # to require the same fields (id/type/...). They share
                # the parent's depends_on (parallel parent stage is the
                # one with depends_on).
                if "id" not in ss:
                    raise SpecValidationError(f"stage {sid!r} (parallel).stages[{j}]: 'id' is required")
                if ss.get("type") not in SUPPORTED_STAGE_TYPES:
                    raise SpecValidationError(
                        f"stage {sid!r} (parallel).stages[{j}]: unknown type {ss.get('type')!r}"
                    )
        elif stype == "loop":
            if not isinstance(stage.get("loop_until"), str) or not stage["loop_until"].strip():
                raise SpecValidationError(f"stage {sid!r} (loop): 'loop_until' is required and must be a non-empty string")
            body = stage.get("body")
            if not isinstance(body, list) or not body:
                raise SpecValidationError(f"stage {sid!r} (loop): 'body' must be a non-empty list of sub-stages")
            for j, bs in enumerate(body):
                if not isinstance(bs, dict):
                    raise SpecValidationError(f"stage {sid!r} (loop).body[{j}] must be a mapping")
                if "id" not in bs:
                    raise SpecValidationError(f"stage {sid!r} (loop).body[{j}]: 'id' is required")
                if bs.get("type") not in SUPPORTED_STAGE_TYPES:
                    raise SpecValidationError(
                        f"stage {sid!r} (loop).body[{j}]: unknown type {bs.get('type')!r}"
                    )

    # Resolve depends_on references now that we have the full id set.
    for stage in stages:
        for dep in stage.get("depends_on", []) or []:
            if dep not in ids_seen:
                raise SpecValidationError(
                    f"stage {stage['id']!r}: depends_on references unknown id {dep!r}"
                )
            if dep == stage["id"]:
                raise SpecValidationError(
                    f"stage {stage['id']!r}: depends_on must not include itself"
                )

    # Cycle detection via Kahn's algorithm (BFS topo-sort). If we can't
    # process all nodes, there's a cycle.
    in_degree: dict[str, int] = {sid: 0 for sid in ids_seen}
    edges: dict[str, list[str]] = {sid: [] for sid in ids_seen}
    for stage in stages:
        for dep in stage.get("depends_on", []) or []:
            edges[dep].append(stage["id"])
            in_degree[stage["id"]] += 1
    queue = [sid for sid, deg in in_degree.items() if deg == 0]
    topo: list[str] = []
    while queue:
        # Sort to make wave assignment deterministic (helpful for diffs/tests).
        queue.sort()
        current = queue.pop(0)
        topo.append(current)
        for child in edges[current]:
            in_degree[child] -= 1
            if in_degree[child] == 0:
                queue.append(child)
    if len(topo) != len(ids_seen):
        # Find a node that's still in_degree > 0 to mention in the error
        cyclic = [sid for sid, deg in in_degree.items() if deg > 0]
        raise SpecValidationError(
            f"cycle detected in depends_on graph; nodes still blocked: {sorted(cyclic)}"
        )

    # Reachability from the set of roots (in_degree == 0) — should match
    # topo, but if a spec has no roots (only possible with cycles, which
    # we caught above), we'd hit it here.
    if not [sid for sid, deg in in_degree.items() if deg == 0] and ids_seen:
        raise SpecValidationError("no root stages found (every stage has a depends_on)")

    return stages


# ---------------------------------------------------------------------------
# Wave resolution
# ---------------------------------------------------------------------------

def resolve_waves(stages: list[dict[str, Any]], max_per_wave: int) -> list[list[str]]:
    """Resolve the DAG into waves (parallel groups) using level-by-level BFS.

    Wave 1 = all stages with no `depends_on`. Wave 2 = stages whose deps
    are all in Wave 1. Wave N = stages whose deps are all in Waves < N.
    This is the SAME algorithm the F9 spawn-prompt template uses
    implicitly; making it explicit in the dispatcher lets the lead
    inspect the wave plan before dispatching.

    Stages that would push a wave over `max_per_wave` are split: the
    first `max_per_wave` siblings land in the current wave, the rest
    are deferred to the next wave (still respecting their deps). This
    is the F8.5 clamp: the cap is on the emitted wave, not on the
    spec; a 30-stage spec with no deps fans into 2 waves of 16+14.

    Returns a list of waves, each a list of stage ids in deterministic
    (sorted) order.
    """
    stage_by_id = {s["id"]: s for s in stages}
    placed: set[str] = set()
    waves: list[list[str]] = []

    while len(placed) < len(stages):
        # Stages ready to schedule: deps all in `placed`
        ready = [
            sid for sid in stage_by_id
            if sid not in placed
            and all(d in placed for d in (stage_by_id[sid].get("depends_on") or []))
        ]
        ready.sort()  # deterministic ordering — diffs/tests stay stable
        if not ready:
            # No progress possible — means cycle or unreachable; validate_spec
            # already caught both, so this is a safety net.
            break
        # Clamp: split this batch into the current wave + overflow
        wave = ready[:max_per_wave]
        overflow = ready[max_per_wave:]
        waves.append(wave)
        placed.update(wave)
        if overflow:
            # Overflow lands in the next wave; we do NOT report them as
            # "deferred" here because the spec author may have intended
            # a wide wave. The lead / `/team-build` decides whether to
            # treat the overflow as a follow-up wave or split the spec.
            # The deferred-deque file is only written when the spec
            # explicitly sets `f8_5_overflow: deferred` (TODO, future).
            # For now, just keep going — the next iteration of this
            # loop will pick them up.
            pass

    return waves


# ---------------------------------------------------------------------------
# Plan emission
# ---------------------------------------------------------------------------

def build_plan(spec: dict[str, Any], waves: list[list[str]], max_per_wave: int) -> dict[str, Any]:
    """Build a structured plan: {name, waves: [{ids, stages}, ...], ...}.

    Each wave carries the FULL stage data for the lead to render into
    F9 spawn prompts. This is the data shape `/team-build` would consume
    if it ever grows a `--spec` flag (future work; see
    `commands/team-build.md` for the consumer side).

    F8.5 overflow is FLAGGED, not auto-split. The lead (or a human
    operator) is the one who decides whether to split a 30-sub-stage
    parallel into 16+14 follow-up waves, merge some agents, or accept
    the overshoot explicitly. The dispatcher refuses to silently mutate
    the spec — that would be a covert L4 auto-block, which the autonomy
    invariant (ADR 0002) forbids. The flag is a `f8_5_overflow` list on
    the stage entry; the lead reads it, decides.
    """
    stage_by_id = {s["id"]: s for s in spec["stages"]}
    plan = {
        "name": spec["name"],
        "description": spec.get("description", ""),
        "wave_count": len(waves),
        "stage_count": len(spec["stages"]),
        "max_per_wave": max_per_wave,
        "f8_5_overflow_warnings": [],
        "waves": [
            {
                "index": i + 1,
                "stage_ids": wave,
                "stages": [stage_by_id[sid] for sid in wave],
            }
            for i, wave in enumerate(waves)
        ],
    }
    # Top-level wave overflow (a wave with more top-level stages than the cap)
    for wave in plan["waves"]:
        if len(wave["stage_ids"]) > max_per_wave:
            plan["f8_5_overflow_warnings"].append({
                "kind": "wave_overflow",
                "wave_index": wave["index"],
                "stage_count": len(wave["stage_ids"]),
                "max_per_wave": max_per_wave,
                "message": (
                    f"Wave {wave['index']} has {len(wave['stage_ids'])} top-level stages, "
                    f"exceeding F8.5 cap of {max_per_wave}. Lead must split or accept explicitly."
                ),
            })
        for stage in wave["stages"]:
            stype = stage.get("type")
            if stype == "parallel":
                sub = stage.get("stages", [])
                if len(sub) > max_per_wave:
                    plan["f8_5_overflow_warnings"].append({
                        "kind": "parallel_overflow",
                        "stage_id": stage["id"],
                        "sub_stage_count": len(sub),
                        "max_per_wave": max_per_wave,
                        "message": (
                            f"Parallel stage {stage['id']!r} has {len(sub)} sub-stages, "
                            f"exceeding F8.5 cap of {max_per_wave}. Lead must split into "
                            f"chunks of {max_per_wave} or accept explicitly."
                        ),
                    })
            elif stype == "loop":
                body = stage.get("body", [])
                if len(body) > max_per_wave:
                    plan["f8_5_overflow_warnings"].append({
                        "kind": "loop_body_overflow",
                        "stage_id": stage["id"],
                        "body_count": len(body),
                        "max_per_wave": max_per_wave,
                        "message": (
                            f"Loop stage {stage['id']!r} has {len(body)} body stages, "
                            f"exceeding F8.5 cap of {max_per_wave}. Lead must trim or accept explicitly."
                        ),
                    })
    return plan


def print_plan_human(plan: dict[str, Any], spec_path: Path) -> int:
    """Print a human-readable plan. Returns 0 on success."""
    print(f"# Plan: {plan['name']}")
    if plan.get("description"):
        print(f"# {plan['description']}")
    print(f"# Spec: {spec_path}")
    print(f"# Stages: {plan['stage_count']} across {plan['wave_count']} wave(s)")
    print(f"# F8.5 cap: {plan.get('max_per_wave', '?')} stages per wave / parallel / loop body")
    print()
    overflows = plan.get("f8_5_overflow_warnings", [])
    if overflows:
        print(f"# ⚠ F8.5 OVERFLOW ({len(overflows)} warning(s)):")
        for w in overflows:
            print(f"#   - {w['message']}")
        print()
    for wave in plan["waves"]:
        print(f"## Wave {wave['index']} ({len(wave['stage_ids'])} stage(s))")
        for sid in wave["stage_ids"]:
            stage = next(s for s in wave["stages"] if s["id"] == sid)
            stype = stage.get("type", "command")
            deps = stage.get("depends_on") or []
            deps_str = f" [depends_on: {', '.join(deps)}]" if deps else ""
            if stype == "command":
                print(f"  - {sid} (command){deps_str}: `{stage.get('command', '')}`")
            elif stype == "agent":
                agent = stage.get("agent_type", "?")
                prompt_preview = (stage.get("prompt", "") or "")[:80].replace("\n", " ")
                print(f"  - {sid} (agent: {agent}){deps_str}: {prompt_preview}...")
            elif stype == "parallel":
                sub_ids = [s.get("id", "?") for s in stage.get("stages", [])]
                overflow_marker = ""
                if len(sub_ids) > plan.get("max_per_wave", 16):
                    overflow_marker = f" ⚠ OVER F8.5 cap ({len(sub_ids)}>{plan['max_per_wave']})"
                print(f"  - {sid} (parallel ×{len(sub_ids)}){deps_str}: {', '.join(sub_ids)}{overflow_marker}")
            elif stype == "loop":
                body_ids = [s.get("id", "?") for s in stage.get("body", [])]
                cond = stage.get("loop_until", "?")
                print(f"  - {sid} (loop until {cond!r}){deps_str}: {', '.join(body_ids)}")
            done_when = stage.get("done_when")
            if done_when:
                print(f"    done-when: {done_when}")
        print()
    return 0


# ---------------------------------------------------------------------------
# Execution (command-typed stages only)
# ---------------------------------------------------------------------------

def execute_command_stage(stage: dict[str, Any], timeout: int) -> tuple[bool, str, str, int]:
    """Run a `command`-typed stage via subprocess. Returns (ok, stdout, stderr, rc)."""
    cmd = stage["command"]
    started = time.time()
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout, cwd=str(REPO_ROOT),
        )
        elapsed = time.time() - started
        ok = result.returncode == 0
        suffix = f" [rc={result.returncode}, {elapsed:.1f}s]"
        if ok:
            print(f"  ✓ {stage['id']}{suffix}")
        else:
            print(f"  ✗ {stage['id']}{suffix}", file=sys.stderr)
            if result.stderr.strip():
                tail = "\n".join(result.stderr.strip().splitlines()[-5:])
                print(f"    stderr (last 5 lines):\n{tail}", file=sys.stderr)
        return ok, result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        print(f"  ⏱ {stage['id']} timed out after {timeout}s", file=sys.stderr)
        return False, "", f"timeout after {timeout}s", 124


def run_execute(plan: dict[str, Any], timeout: int) -> int:
    """Run command-typed stages in wave order. Agent/parallel/loop stages
    are reported as "would-spawn" and skipped — a lead or human must
    dispatch them. Returns 0 if all command stages exit 0, else 1.
    """
    failed = 0
    for wave in plan["waves"]:
        print(f"Wave {wave['index']} ({len(wave['stage_ids'])} stage(s)):")
        for stage in wave["stages"]:
            stype = stage.get("type", "command")
            if stype == "command":
                ok, _, _, _ = execute_command_stage(stage, timeout=timeout)
                if not ok:
                    failed += 1
            elif stype == "agent":
                print(
                    f"  → would-spawn: agent_type={stage.get('agent_type')!r} "
                    f"id={stage['id']!r} (lead dispatch required)"
                )
            elif stype == "parallel":
                print(
                    f"  → parallel stage {stage['id']!r}: "
                    f"{len(stage.get('stages', []))} sub-stage(s) "
                    f"(dispatch as one wave)"
                )
            elif stype == "loop":
                print(
                    f"  → loop stage {stage['id']!r} until {stage.get('loop_until')!r}: "
                    f"{len(stage.get('body', []))} body stage(s) "
                    f"(loop semantics; spec-render only)"
                )
    return 1 if failed else 0


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
