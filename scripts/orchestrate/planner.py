"""_orchestrate_planner.py — wave resolution and plan emission for orchestrate-dispatch."""

from __future__ import annotations

from pathlib import Path
from typing import Any


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
