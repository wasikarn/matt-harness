"""_orchestrate_loader.py — spec loading and validation for orchestrate-dispatch."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # PyYAML — stdlib for most harness projects; safe-required
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

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
