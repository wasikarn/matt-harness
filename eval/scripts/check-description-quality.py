#!/usr/bin/env python3
"""Regression grader for kbg-harness surface description quality.

Scans agents/*.md, commands/*.md, and skills/*/SKILL.md for YAML frontmatter
and verifies the v0.2.97 description-quality contract:

  - description length <= 1024 characters
  - description contains a Thai trigger
  - description contains a positive trigger clause
  - description contains a negative scope clause
  - disable-model-invocation: true is paired with a non-empty reason

Output is one line per surface:

    PASS agents/foo.md
    FAIL commands/bar.md: missing Thai trigger; missing positive trigger clause

Followed by a RESULT summary block that run-eval.py matches against
description-quality success criteria.
"""

import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

SURFACE_GLOBS = [
    ("agents", "*.md"),
    ("commands", "*.md"),
    ("skills", "*/SKILL.md"),
]

THAI_RE = re.compile(r"[฀-๿]")

POSITIVE_CLAUSES = [
    "Use when",
    "Use this skill when",
    "Use PROACTIVELY when",
    "Use after",
    "Use before",
    "Trigger when",
    "Auto-loads when",
    "ALWAYS trigger",
    "ALWAYS run",
    "Trigger on",
    "Invoke when",
]

NEGATIVE_CLAUSES = [
    "Don't use for",
    "Do NOT use for",
    "Do not use for",
    "Never use for",
    "Avoid using for",
]


def parse_frontmatter(path: Path) -> tuple[dict | None, str]:
    """Return (frontmatter_dict, raw_frontmatter_text) or (None, error)."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return None, "missing frontmatter"

    # Find the closing --- after the opening one.
    end = text.find("\n---", 4)
    if end == -1:
        return None, "unterminated frontmatter"

    fm_text = text[3:end].strip("\n")
    try:
        data = yaml.safe_load(fm_text) or {}
    except yaml.YAMLError as e:
        return None, f"invalid YAML frontmatter: {e}"

    if not isinstance(data, dict):
        return None, "frontmatter is not a mapping"
    return data, fm_text


def check_surface(path: Path) -> tuple[str, list[str]]:
    """Return (relative_path, failure_reasons). Empty reasons == pass."""
    rel = str(path.relative_to(REPO_ROOT))
    fm, error = parse_frontmatter(path)
    if fm is None:
        return rel, [error]

    failures: list[str] = []
    description = fm.get("description")
    if description is None or description == "":
        failures.append("missing description")
        return rel, failures

    if not isinstance(description, str):
        failures.append("description is not a string")
        return rel, failures

    # a. Length
    if len(description) > 1024:
        failures.append(f"description length {len(description)} > 1024")

    # b. Thai trigger
    if not THAI_RE.search(description):
        failures.append("missing Thai trigger")

    # c. Positive trigger clause (case-insensitive)
    desc_lower = description.lower()
    if not any(clause.lower() in desc_lower for clause in POSITIVE_CLAUSES):
        failures.append("missing positive trigger clause")

    # d. Negative scope clause (case-insensitive)
    if not any(clause.lower() in desc_lower for clause in NEGATIVE_CLAUSES):
        failures.append("missing negative scope clause")

    # e. disable-model-invocation reason
    dmi = fm.get("disable-model-invocation")
    reason = fm.get("disable-model-invocation-reason")
    if dmi is True and (not reason or not str(reason).strip()):
        failures.append("disable-model-invocation: true without non-empty reason")

    return rel, failures


def collect_surfaces(repo_root: Path) -> list[Path]:
    """Find all surface files under the repo root."""
    surfaces: list[Path] = []
    for kind, pattern in SURFACE_GLOBS:
        for p in sorted((repo_root / kind).glob(pattern)):
            if p.is_file():
                surfaces.append(p)
    return surfaces


def main() -> int:
    repo_root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else REPO_ROOT
    surfaces = collect_surfaces(repo_root)

    if not surfaces:
        print("FAIL: no surfaces found", file=sys.stderr)
        return 2

    fail_counts = {
        "description-length": 0,
        "thai-trigger": 0,
        "positive-trigger": 0,
        "negative-scope": 0,
        "dmi-reason": 0,
        "other": 0,
    }
    overall_fail = 0

    for path in surfaces:
        rel, failures = check_surface(path)
        if failures:
            overall_fail += 1
            for f in failures:
                if "length" in f:
                    fail_counts["description-length"] += 1
                elif "Thai" in f:
                    fail_counts["thai-trigger"] += 1
                elif "positive" in f:
                    fail_counts["positive-trigger"] += 1
                elif "negative" in f or "scope" in f:
                    fail_counts["negative-scope"] += 1
                elif "disable-model-invocation" in f:
                    fail_counts["dmi-reason"] += 1
                else:
                    fail_counts["other"] += 1
            print(f"FAIL {rel}: {'; '.join(failures)}")
        else:
            print(f"PASS {rel}")

    total = len(surfaces)
    pass_count = total - overall_fail

    def status(category: str) -> str:
        return "PASS" if fail_counts[category] == 0 else "FAIL"

    print()
    print(f"RESULT: All surfaces have Thai triggers: {status('thai-trigger')}")
    print(f"RESULT: All descriptions are under 1024 characters: {status('description-length')}")
    print(f"RESULT: All surfaces have positive trigger clause: {status('positive-trigger')}")
    print(f"RESULT: All surfaces have negative scope clause: {status('negative-scope')}")
    print(f"RESULT: All disable-model-invocation flags have reasons: {status('dmi-reason')}")
    print(f"RESULT: Script exits 0: {'PASS' if overall_fail == 0 else 'FAIL'}")
    print(f"SUMMARY: {pass_count}/{total} surfaces passed")

    return 0 if overall_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
