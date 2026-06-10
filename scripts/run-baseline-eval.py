#!/usr/bin/env python3
"""Run baseline eval for a skill: with_skill vs without_skill comparison.

Usage:
    python3 run-baseline-eval.py <skill-path> [--iterations N] [--model MODEL]

Example:
    python3 run-baseline-eval.py ~/dotfiles/claude/skills/clarify-first --iterations 1

Prerequisites:
    - The skill must have evals/evals.json with at least one eval case.
    - claude CLI must be available and authenticated.
    - Skill must be discoverable via ~/.claude/skills/ symlink (handled by install.sh).

What it does:
    1. Reads evals/evals.json from the skill directory.
    2. For each eval, spawns TWO claude -p runs in parallel:
       a) with_skill  — skill discoverable normally
       b) without_skill — skill temporarily unlinked from ~/.claude/skills/
    3. Saves raw outputs to <skill-name>-baseline-workspace/iteration-1/eval-<id>/
    4. Generates benchmark.json and benchmark.md with timing + token comparison.
    5. Restores skill symlink.

Caveats:
    - This measures trigger + output, not assertion grading. Add assertions
      manually or use skill-creator's grader agent for full scoring.
    - Token counts are approximate (from claude -p stream-json metadata).
    - without_skill may still trigger other skills; this is intentional — we
      compare against "natural Claude behavior" not "empty context".
"""

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def find_skill_symlink(skill_name: str) -> Path | None:
    """Find the skill symlink in ~/.claude/skills/."""
    link = Path.home() / ".claude" / "skills" / skill_name
    if link.exists() or link.is_symlink():
        return link
    return None


def run_claude_prompt(prompt: str, project_root: Path, model: str | None = None, timeout: int = 300) -> dict:
    """Run claude -p and return parsed output + metadata."""
    cmd = [
        "claude", "-p", prompt,
        "--output-format", "stream-json",
    ]
    if model:
        cmd.extend(["--model", model])

    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

    start = time.time()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=project_root,
            env=env,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"output": "", "error": "timeout", "duration_seconds": timeout, "tokens": 0}

    duration = time.time() - start

    # Try to extract token count from final metadata event in stream-json
    tokens = 0
    for line in result.stdout.strip().splitlines():
        try:
            event = json.loads(line)
            if event.get("type") == "result":
                tokens = event.get("message", {}).get("usage", {}).get("output_tokens", 0)
                tokens += event.get("message", {}).get("usage", {}).get("input_tokens", 0)
        except json.JSONDecodeError:
            continue

    return {
        "output": result.stdout + result.stderr,
        "error": result.returncode != 0,
        "duration_seconds": round(duration, 1),
        "tokens": tokens,
    }


def run_single_eval(
    eval_item: dict,
    skill_name: str,
    skill_path: Path,
    project_root: Path,
    output_dir: Path,
    model: str | None,
    timeout: int,
) -> dict:
    """Run one eval: with_skill and without_skill."""
    eval_id = eval_item.get("id", 0)
    eval_name = eval_item.get("eval_name", f"eval-{eval_id}")
    prompt = eval_item["prompt"]

    eval_dir = output_dir / f"eval-{eval_id}-{eval_name}"
    with_dir = eval_dir / "with_skill"
    without_dir = eval_dir / "without_skill"
    with_dir.mkdir(parents=True, exist_ok=True)
    without_dir.mkdir(parents=True, exist_ok=True)

    # Save eval metadata
    (eval_dir / "eval_metadata.json").write_text(json.dumps(eval_item, indent=2))

    # Find skill symlink
    skill_link = find_skill_symlink(skill_name)
    skill_backup = None

    results = {}

    # --- with_skill run ---
    print(f"  [{eval_name}] Running WITH skill...", file=sys.stderr)
    with_result = run_claude_prompt(prompt, project_root, model, timeout)
    (with_dir / "output.txt").write_text(with_result["output"])
    (with_dir / "timing.json").write_text(json.dumps({
        "duration_ms": int(with_result["duration_seconds"] * 1000),
        "total_tokens": with_result["tokens"],
    }, indent=2))
    results["with_skill"] = with_result

    # --- without_skill run ---
    # Temporarily remove skill symlink so claude -p cannot discover it
    if skill_link:
        skill_backup = skill_link.with_suffix(f".backup-{uuid.uuid4().hex[:8]}")
        skill_link.rename(skill_backup)
        print(f"  [{eval_name}] Temporarily unlinked skill for baseline run", file=sys.stderr)

    print(f"  [{eval_name}] Running WITHOUT skill...", file=sys.stderr)
    without_result = run_claude_prompt(prompt, project_root, model, timeout)
    (without_dir / "output.txt").write_text(without_result["output"])
    (without_dir / "timing.json").write_text(json.dumps({
        "duration_ms": int(without_result["duration_seconds"] * 1000),
        "total_tokens": without_result["tokens"],
    }, indent=2))
    results["without_skill"] = without_result

    # Restore symlink
    if skill_backup and skill_backup.exists():
        skill_backup.rename(skill_link)
        print(f"  [{eval_name}] Restored skill symlink", file=sys.stderr)

    return {
        "eval_id": eval_id,
        "eval_name": eval_name,
        "with_skill": with_result,
        "without_skill": without_result,
    }


def generate_benchmark(results: list[dict], skill_name: str, skill_path: Path, model: str | None) -> dict:
    """Generate benchmark.json structure."""
    runs = []
    for r in results:
        for config in ("with_skill", "without_skill"):
            data = r[config]
            runs.append({
                "eval_id": r["eval_id"],
                "eval_name": r["eval_name"],
                "configuration": config,
                "duration_seconds": data["duration_seconds"],
                "tokens": data["tokens"],
                "error": data["error"],
            })

    # Compute summaries
    configs = {"with_skill": [], "without_skill": []}
    for r in results:
        for config in ("with_skill", "without_skill"):
            configs[config].append(r[config])

    def stats(values: list[float]) -> dict:
        if not values:
            return {"mean": 0, "stddev": 0, "min": 0, "max": 0}
        n = len(values)
        mean = sum(values) / n
        if n > 1:
            variance = sum((x - mean) ** 2 for x in values) / (n - 1)
            stddev = variance ** 0.5
        else:
            stddev = 0
        return {"mean": round(mean, 1), "stddev": round(stddev, 1), "min": round(min(values), 1), "max": round(max(values), 1)}

    with_times = [r["with_skill"]["duration_seconds"] for r in results]
    without_times = [r["without_skill"]["duration_seconds"] for r in results]
    with_tokens = [r["with_skill"]["tokens"] for r in results]
    without_tokens = [r["without_skill"]["tokens"] for r in results]

    return {
        "metadata": {
            "skill_name": skill_name,
            "skill_path": str(skill_path),
            "executor_model": model or "default",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "evals_run": [r["eval_id"] for r in results],
            "runs_per_configuration": 1,
        },
        "runs": runs,
        "run_summary": {
            "with_skill": {
                "time_seconds": stats(with_times),
                "tokens": stats(with_tokens),
            },
            "without_skill": {
                "time_seconds": stats(without_times),
                "tokens": stats(without_tokens),
            },
            "delta": {
                "time_seconds": f"{stats(with_times)['mean'] - stats(without_times)['mean']:+.1f}",
                "tokens": f"{stats(with_tokens)['mean'] - stats(without_tokens)['mean']:+.0f}",
            },
        },
        "notes": [
            "This is a timing/token baseline. Add assertion grading for full quality comparison.",
            "See agentskills.io/skill-creation/evaluating-skills for grading methodology.",
        ],
    }


def generate_benchmark_md(benchmark: dict) -> str:
    """Generate human-readable benchmark.md."""
    meta = benchmark["metadata"]
    summary = benchmark["run_summary"]
    runs = benchmark["runs"]

    lines = [
        f"# Skill Baseline Benchmark: {meta['skill_name']}",
        "",
        f"**Model**: {meta['executor_model']}",
        f"**Date**: {meta['timestamp']}",
        f"**Skill path**: {meta['skill_path']}",
        "",
        "## Summary",
        "",
        "| Metric | with_skill | without_skill | Delta |",
        "|--------|------------|---------------|-------|",
    ]

    for metric in ("time_seconds", "tokens"):
        w = summary["with_skill"][metric]
        wo = summary["without_skill"][metric]
        delta = summary["delta"][metric]
        label = "Time (s)" if metric == "time_seconds" else "Tokens"
        lines.append(f"| {label} | {w['mean']} ± {w['stddev']} | {wo['mean']} ± {wo['stddev']} | {delta} |")

    lines.extend([
        "",
        "## Per-Eval Results",
        "",
        "| Eval | Config | Duration | Tokens | Error |",
        "|------|--------|----------|--------|-------|",
    ])

    for run in runs:
        err = "✗" if run["error"] else "✓"
        lines.append(
            f"| {run['eval_name']} | {run['configuration']} | {run['duration_seconds']}s | {run['tokens']} | {err} |"
        )

    lines.extend([
        "",
        "## Notes",
        "",
    ])
    for note in benchmark["notes"]:
        lines.append(f"- {note}")

    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Run baseline eval: with_skill vs without_skill")
    parser.add_argument("skill_path", type=Path, help="Path to skill directory containing evals/evals.json")
    parser.add_argument("--iterations", type=int, default=1, help="Number of iterations (default: 1)")
    parser.add_argument("--model", default=None, help="Claude model to use (e.g., claude-sonnet-4-6)")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout per run in seconds (default: 300)")
    parser.add_argument("--workers", type=int, default=2, help="Parallel workers (default: 2)")
    args = parser.parse_args()

    skill_path = args.skill_path.resolve()
    evals_file = skill_path / "evals" / "evals.json"
    if not evals_file.exists():
        print(f"Error: No evals/evals.json found at {skill_path}", file=sys.stderr)
        sys.exit(1)

    evals_data = json.loads(evals_file.read_text())
    skill_name = evals_data.get("skill_name", skill_path.name)
    evals = evals_data.get("evals", [])
    if not evals:
        print("Error: evals.json has no eval cases.", file=sys.stderr)
        sys.exit(1)

    project_root = Path.cwd()
    workspace = Path(f"{skill_name}-baseline-workspace")
    workspace.mkdir(exist_ok=True)

    for iteration in range(1, args.iterations + 1):
        iter_dir = workspace / f"iteration-{iteration}"
        iter_dir.mkdir(exist_ok=True)
        print(f"\n=== Iteration {iteration}/{args.iterations} ===", file=sys.stderr)

        results = []
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = {
                executor.submit(
                    run_single_eval,
                    ev,
                    skill_name,
                    skill_path,
                    project_root,
                    iter_dir,
                    args.model,
                    args.timeout,
                ): ev
                for ev in evals
            }
            for future in as_completed(futures):
                ev = futures[future]
                try:
                    result = future.result()
                    results.append(result)
                    print(f"  ✓ {result['eval_name']} done", file=sys.stderr)
                except Exception as e:
                    print(f"  ✗ {ev.get('eval_name', ev.get('id'))} failed: {e}", file=sys.stderr)

        # Generate benchmark
        benchmark = generate_benchmark(results, skill_name, skill_path, args.model)
        benchmark_path = iter_dir / "benchmark.json"
        benchmark_path.write_text(json.dumps(benchmark, indent=2))
        print(f"\nBenchmark JSON: {benchmark_path}", file=sys.stderr)

        md_path = iter_dir / "benchmark.md"
        md_path.write_text(generate_benchmark_md(benchmark))
        print(f"Benchmark MD:   {md_path}", file=sys.stderr)

    print(f"\nDone. Workspace: {workspace.resolve()}", file=sys.stderr)


if __name__ == "__main__":
    main()
