#!/usr/bin/env python3
"""merge-review-reports.py — deterministic merge of parallel validator reports.

Consumes the JSON reports emitted by the review-pr.yml validator fan-out:
  - security.json       → {findings: [{file, line, severity, owasp}]}
  - coverage.json       → {untested_paths: [...], risk_rating: int}
  - errors.json         → {findings: [{file, line, severity, pattern}]}
  - comments.json       → {stale: [{file, line, comment}]}

Emits a single merged-report.json with the 4-step merge structure required by
the review-pr.yml `merge-reports` stage:
  1. Reports         — raw per-lens findings keyed by lens id.
  2. Conflict Resolution — surface disagreements with file:line citations.
  3. Priority Ranking — P0/P1/P2 by blast-radius.
  4. Action Plan     — concrete file:line edits with owner column.

The script is intentionally deterministic: it merges, de-dups, ranks, and
formats; it does NOT call an LLM. Autonomy invariant (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model): leave
judgment calls (e.g., whether a conflict is real) to the lead agent.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


REPORT_FILES = {
    "security": "security.json",
    "coverage": "coverage.json",
    "errors": "errors.json",
    "comments": "comments.json",
}

SEVERITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "high": 0, "medium": 1, "low": 2}


def load_reports(directory: Path) -> dict[str, dict]:
    reports: dict[str, dict] = {}
    for lens, filename in REPORT_FILES.items():
        path = directory / filename
        if path.exists():
            try:
                reports[lens] = json.loads(path.read_text())
            except json.JSONDecodeError as e:
                print(f"[WARN] Could not parse {path}: {e}", file=sys.stderr)
                reports[lens] = {}
        else:
            print(f"[WARN] Missing report: {path}", file=sys.stderr)
            reports[lens] = {}
    return reports


def flatten_findings(reports: dict[str, dict]) -> list[dict]:
    flat: list[dict] = []

    def add(lens: str, items: list[dict], kind: str) -> None:
        for item in items:
            finding = dict(item)
            finding["lens"] = lens
            finding["kind"] = kind
            flat.append(finding)

    security = reports.get("security", {})
    add("security", security.get("findings", []), "security")

    errors = reports.get("errors", {})
    add("errors", errors.get("findings", []), "error")

    comments = reports.get("comments", {})
    add("comments", comments.get("stale", []), "comment")

    coverage = reports.get("coverage", {})
    for path in coverage.get("untested_paths", []):
        flat.append({
            "file": path.get("file", path) if isinstance(path, dict) else path,
            "line": path.get("line", 0) if isinstance(path, dict) else 0,
            "severity": "P1",
            "lens": "coverage",
            "kind": "coverage",
            "risk_rating": coverage.get("risk_rating", 0),
        })

    return flat


def key_for(finding: dict) -> str:
    return f"{finding.get('file', '')}:{finding.get('line', 0)}"


def resolve_conflicts(findings: list[dict]) -> dict[str, list[dict]]:
    by_key: dict[str, list[dict]] = defaultdict(list)
    for f in findings:
        by_key[key_for(f)].append(f)

    conflicts = []
    merged = []
    for k, items in by_key.items():
        lenses = {i["lens"] for i in items}
        if len(items) > 1 and len(lenses) > 1:
            conflicts.append({
                "location": k,
                "lenses": sorted(lenses),
                "findings": items,
                "note": "Multiple lenses flagged this location; lead must confirm whether findings are duplicates or distinct issues.",
            })
        merged.extend(items)

    return {"merged": merged, "conflicts": conflicts}


def rank_priority(merged: list[dict]) -> dict[str, list[dict]]:
    def severity_of(f: dict) -> str:
        sev = str(f.get("severity", "P2")).strip().lower()
        if sev in {"high", "critical"}:
            return "P0"
        if sev in {"medium"}:
            return "P1"
        return "P2"

    buckets = {"P0": [], "P1": [], "P2": []}
    for f in merged:
        buckets[severity_of(f)].append(f)

    for bucket in buckets.values():
        bucket.sort(key=lambda f: (f.get("file", ""), f.get("line", 0)))

    return buckets


def build_action_plan(buckets: dict[str, list[dict]]) -> list[dict]:
    plan = []
    for priority in ("P0", "P1", "P2"):
        for f in buckets[priority]:
            plan.append({
                "priority": priority,
                "location": key_for(f),
                "file": f.get("file", ""),
                "line": f.get("line", 0),
                "lens": f.get("lens", ""),
                "kind": f.get("kind", ""),
                "severity": f.get("severity", ""),
                "owner": "backend-engineer" if f.get("kind") in {"security", "error", "coverage"} else "code-reviewer",
                "action": f"Review and fix {f.get('kind', 'issue')} flagged by {f.get('lens', 'unknown')} lens.",
            })
    return plan


def merge_reports(input_dir: Path) -> dict:
    reports = load_reports(input_dir)
    findings = flatten_findings(reports)
    conflicts = resolve_conflicts(findings)
    buckets = rank_priority(conflicts["merged"])
    action_plan = build_action_plan(buckets)

    return {
        "Reports": reports,
        "Conflict_Resolution": conflicts["conflicts"],
        "Priority_Ranking": buckets,
        "Action_Plan": action_plan,
        "meta": {
            "total_findings": len(findings),
            "conflict_count": len(conflicts["conflicts"]),
            "p0_count": len(buckets["P0"]),
            "p1_count": len(buckets["P1"]),
            "p2_count": len(buckets["P2"]),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge parallel validator reports into a ranked action plan."
    )
    parser.add_argument(
        "input_dir",
        type=Path,
        help="Directory containing security.json, coverage.json, errors.json, comments.json",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=None,
        help="Output path (default: <input_dir>/merged-report.json)",
    )
    args = parser.parse_args(argv)

    if not args.input_dir.is_dir():
        print(f"ERROR: {args.input_dir} is not a directory", file=sys.stderr)
        return 2

    merged = merge_reports(args.input_dir)
    output_path = args.output or (args.input_dir / "merged-report.json")
    output_path.write_text(json.dumps(merged, indent=2) + "\n")
    print(f"Merged report written to {output_path}")
    print(
        f"4-step merge complete: "
        f"{merged['meta']['total_findings']} findings, "
        f"{merged['meta']['conflict_count']} conflicts, "
        f"P0={merged['meta']['p0_count']} P1={merged['meta']['p1_count']} P2={merged['meta']['p2_count']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
