#!/usr/bin/env python3
"""select-affected-fixtures.py — deterministic affected-eval selector.

Input:  git diff --cached --name-only (passed as --staged-files ...)
Output: JSON with pre_commit {datasets[], regressions[]}, pre_push_only[],
        fallback bool.

Mapping rules:
  skills/<name>/SKILL.md        -> eval/regressions/<name>*.json
                                  eval/datasets/<name>*.json
  commands/<name>.md            -> eval/regressions/<name>*.json
                                  eval/datasets/<name>*.json
  agents/<name>.md              -> eval/regressions/<name>*.json
                                  eval/datasets/<name>*.json
  hooks/<name>.sh               -> hooks/tests/test-critical-hooks.sh (pre_push_only)
  hooks/_lib.sh                 -> hooks/tests/test-critical-hooks.sh (pre_push_only)
  eval/regressions/<name>.json  -> itself
  eval/datasets/<name>.json     -> itself
  scripts/run-gauntlet.sh       -> fallback (all fixtures)
  .claude-plugin/*.json         -> fallback (all fixtures)
  eval/run-eval.py              -> fallback (grader changed)
  scripts/evals/run-acceptance.py -> fallback (grader changed)

Additionally, any regression fixture whose JSON text contains a staged
relative path is included, so fixtures that reference specific files
outside the naming pattern are not missed.
"""
import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
EVAL_DIR = REPO_ROOT / "eval"
REGRESSIONS_DIR = EVAL_DIR / "regressions"
DATASETS_DIR = EVAL_DIR / "datasets"
CRITICAL_HOOKS_SUITE = REPO_ROOT / "hooks" / "tests" / "test-critical-hooks.sh"


def glob_fixtures(component: str):
    """Return regression + dataset files whose basename starts with component."""
    regs = sorted(REGRESSIONS_DIR.glob(f"{component}*.json"))
    dss = sorted(DATASETS_DIR.glob(f"{component}*.json"))
    return regs, dss


def component_from_path(path: str):
    """Extract component name from skill / command / agent paths."""
    if path.startswith("skills/"):
        rest = path[len("skills/"):]
        return rest.split("/", 1)[0] if rest else None
    if path.startswith("commands/") or path.startswith("agents/"):
        # commands/foo.md -> foo
        rest = path[len(path.split("/", 1)[0]) + 1:]
        if rest and rest.endswith(".md"):
            return rest[:-3]
    return None


def scan_regression_refs(staged: set[str]):
    """Return regression fixtures whose JSON text contains a staged path."""
    hits = []
    for p in REGRESSIONS_DIR.glob("*.json"):
        try:
            text = p.read_text(encoding="utf-8")
        except Exception:
            continue
        for rel in staged:
            if rel in text:
                hits.append(p)
                break
    return hits


def dedupe(paths):
    seen, out = set(), []
    for p in paths:
        rp = str(p.relative_to(REPO_ROOT))
        if rp not in seen:
            seen.add(rp)
            out.append(p)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Select affected eval fixtures for staged changes"
    )
    parser.add_argument(
        "--staged-files", nargs="+", required=True,
        help="Repo-relative paths from git diff --cached --name-only"
    )
    parser.add_argument(
        "--format", choices=["json", "lines"], default="json",
        help="Output format"
    )
    args = parser.parse_args()

    staged = set(args.staged_files)
    regs, dss = [], []
    pre_push = []
    fallback = False

    for f in staged:
        if f.startswith(("skills/", "commands/", "agents/")):
            name = component_from_path(f)
            if name:
                r, d = glob_fixtures(name)
                regs.extend(r)
                dss.extend(d)
        elif f.startswith("hooks/") and f.endswith(".sh"):
            pre_push.append(CRITICAL_HOOKS_SUITE)
        elif f.startswith("eval/regressions/") and f.endswith(".json"):
            regs.append(REPO_ROOT / f)
        elif f.startswith("eval/datasets/") and f.endswith(".json"):
            dss.append(REPO_ROOT / f)
        elif f == "scripts/run-gauntlet.sh":
            fallback = True
        elif f.startswith(".claude-plugin/") and f.endswith(".json"):
            fallback = True
        elif f in ("eval/run-eval.py", "scripts/evals/run-acceptance.py"):
            # The grader itself changed; any fixture's meaning could shift.
            fallback = True

    if not fallback:
        for p in scan_regression_refs(staged):
            if p not in regs:
                regs.append(p)

    regs = dedupe(regs)
    dss = dedupe(dss)
    pre_push = dedupe(pre_push)

    if fallback:
        regs = sorted(REGRESSIONS_DIR.glob("*.json"))
        dss = sorted(DATASETS_DIR.glob("*.json"))

    output = {
        "pre_commit": {
            "regressions": [str(p.relative_to(REPO_ROOT)) for p in regs],
            "datasets": [str(p.relative_to(REPO_ROOT)) for p in dss],
        },
        "pre_push_only": [str(p.relative_to(REPO_ROOT)) for p in pre_push],
        "fallback": fallback,
    }

    if args.format == "lines":
        for section in (
            output["pre_commit"]["regressions"],
            output["pre_commit"]["datasets"],
            output["pre_push_only"],
        ):
            for line in section:
                print(line)
    else:
        print(json.dumps(output, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
