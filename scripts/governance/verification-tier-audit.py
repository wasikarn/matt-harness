#!/usr/bin/env python3
"""verification-tier-audit — retro-grade shipped features against the
verification_tier rubric.

For each feature it gathers evidence — a `.scratch/<feature>/verification-trail.md`
(authoritative if present), an `ACCEPTANCE.md`, eval files under a matching
`skills/<feature>/` (or `claude/skills/<feature>/` in dotfiles layout), and references in `tests/hooks/runners/` (or `claude/hooks/tests/` in dotfiles layout) — then assigns
one `verification_tier`:

    tdd-provenance | analyzer-pass | no-trail

`tdd-provenance` is assigned ONLY from an explicit declared `verification_tier`
line in the trail (the `red_green` shas are human-readable evidence, not a parsed
field) — it is never inferred from git (retro-detecting a red→green sequence is
unreliable, and a false "tdd-provenance" is worse than an honest "analyzer-pass").

Read-only. Exit 0 always (a grading report, not a gate). The journal is read via
governance-summary.py's `load_jsonl` (the single JSONL parser — no second parser),
surfaced as global context (verdict events are not feature-scopable; they carry
the journaler's hook-id, not a feature tag).

Usage:
    verification-tier-audit.py [--root DIR] [feature ...]
    # default features: accept-task critical-eval c1-journal
"""
import argparse
import importlib.util
import os
import re
import sys
from pathlib import Path

DEFAULT_FEATURES = ["accept-task", "critical-eval", "c1-journal"]
# A feature's slug may differ from its .scratch dir name.
SCRATCH_ALIAS = {"c1-journal": "c1-evidence-journal"}
VALID_TIERS = {"tdd-provenance", "analyzer-pass", "no-trail"}
JOURNAL_DEFAULT = os.path.join(os.path.expanduser("~"), ".claude", "governance-events.jsonl")


def _load_governance_reader():
    """Import load_jsonl from governance-summary.py (hyphenated filename → importlib).
    Reusing it is the 'no new journal parser' contract: one parse/fail-loud path."""
    path = Path(__file__).resolve().parent / "governance-summary.py"
    spec = importlib.util.spec_from_file_location("governance_summary", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load governance-summary.py from {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # main() is __main__-guarded — no side effects on import
    return mod.load_jsonl


def _read_trail_tier(scratch_dir):
    """Return the declared verification_tier from verification-trail.md, or None."""
    trail = scratch_dir / "verification-trail.md"
    if not trail.is_file():
        return None
    for line in trail.read_text(errors="replace").splitlines():
        m = re.match(r"^[\s\-]*verification_tier:\s*(\S+)", line)
        if m:
            return m.group(1)
    return None


def _has_eval_evidence(skill_dir, root):
    """True if a matching skill dir carries eval files (an analyzer-pass signal).

    Supports both the flat kbg-harness layout (evals live under
    tests/evals/skills/<feature>/) and the nested dotfiles layout
    (claude/skills/<feature>/evals/).
    """
    if not skill_dir.is_dir():
        return False
    name = skill_dir.name
    # New flat layout: evals moved out of auto-discovered component dirs.
    flat_evals = root / "tests" / "evals" / "skills" / name / "evals.json"
    if flat_evals.is_file():
        return True
    if (skill_dir / "evals").is_dir():
        return True
    return any("eval" in p.name.lower() for p in skill_dir.rglob("*") if p.is_file())


def _referenced_in_hook_tests(root, names):
    """True if any hook-test runner mentions one of the feature's names.

    Supports both the flat kbg-harness layout (tests/hooks/runners/) and the
    nested dotfiles layout (claude/hooks/tests/).
    """
    tests_dir = root / "tests" / "hooks" / "runners"
    if not tests_dir.is_dir():
        tests_dir = root / "claude" / "hooks" / "tests"
    if not tests_dir.is_dir():
        return False
    # Match both the hyphenated slug and its space form: test prose tends to write
    # "C1 evidence journal", not the dir name "c1-evidence-journal".
    needles = set()
    for n in names:
        if n:
            needles.add(n.lower())
            needles.add(n.lower().replace("-", " "))
    for p in tests_dir.rglob("*"):
        if not p.is_file():
            continue
        text = p.read_text(errors="replace").lower()
        if any(n in text for n in needles):
            return True
    return False


def grade(feature, root):
    """Gather evidence for one feature and assign (tier, source, evidence-notes)."""
    alias = SCRATCH_ALIAS.get(feature)
    scratch_names = [feature] + ([alias] if alias else [])
    scratch_dir = next(
        (root / ".scratch" / n for n in scratch_names if (root / ".scratch" / n).is_dir()),
        None,
    )
    skill_dir = root / "claude" / "skills" / feature

    notes = []
    declared = _read_trail_tier(scratch_dir) if scratch_dir else None
    if declared:
        notes.append(f"trail={declared}")
    if scratch_dir:
        notes.append(f"scratch={scratch_dir.name}")
        if (scratch_dir / "ACCEPTANCE.md").is_file():
            notes.append("ACCEPTANCE.md")
    evals = _has_eval_evidence(skill_dir, root)
    if evals:
        notes.append("evals")
    tref = _referenced_in_hook_tests(root, scratch_names)
    if tref:
        notes.append("hook-tests-ref")

    # Assignment: declared trail is authoritative; else infer from test/eval
    # evidence; else no-trail. tdd-provenance only ever comes from a trail.
    if declared in VALID_TIERS:
        tier, source = declared, "declared in verification-trail.md"
    elif declared:  # present but not a recognized value
        tier, source = "no-trail", f"trail tier {declared!r} not in rubric"
    elif evals or tref:
        tier, source = "analyzer-pass", "inferred: tests/evals present"
    else:
        tier, source = "no-trail", "no trail, no tests/evals found"
    return tier, source, ", ".join(notes) or "—"


def main():
    ap = argparse.ArgumentParser(description="retro-grade features against the verification_tier rubric")
    ap.add_argument("--root", default=os.getcwd(), help="repo root to scan (default: cwd)")
    ap.add_argument("--journal", default=JOURNAL_DEFAULT, help="governance journal path")
    ap.add_argument("features", nargs="*", default=DEFAULT_FEATURES, help="features to grade")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    features = args.features or DEFAULT_FEATURES

    print(f"=== verification-tier audit — {root} ===\n")
    print(f"{'feature':24} {'verification_tier':18} evidence")
    print(f"{'-'*24} {'-'*18} {'-'*40}")
    for feat in features:
        tier, source, notes = grade(feat, root)
        print(f"{feat:24} {tier:18} {notes}")
        print(f"{'':24} {'':18} ↳ {source}")

    # Journal context — reuse governance-summary.py's load_jsonl (no new parser).
    # Verdict events are NOT feature-scopable, so this is global corroboration only.
    try:
        load_jsonl = _load_governance_reader()
        evts, n_corrupt, existed = load_jsonl(args.journal)
        if existed:
            kinds = {}
            for e in evts:
                k = e.get("event", "?")
                kinds[k] = kinds.get(k, 0) + 1
            rf, vv = kinds.get("review_finding", 0), kinds.get("verification_verdict", 0)
            print(f"\njournal: {len(evts)} events ({rf} review_finding, {vv} verification_verdict)"
                  f"{f', {n_corrupt} corrupt' if n_corrupt else ''} — global, not feature-scoped")
        else:
            print("\njournal: none yet")
    except Exception as e:  # reader is best-effort context; never fail the grade
        print(f"\njournal: unreadable ({type(e).__name__}: {e})", file=sys.stderr)

    print("\nNote: tdd-provenance is only assigned from an explicit verification-trail.md "
          "red→green entry — never inferred from git history.")


if __name__ == "__main__":
    main()
