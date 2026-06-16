#!/usr/bin/env python3
"""Measure skill auto-trigger rate from Claude Code transcripts.

Replaces the 2026-05-30 line-window prototype. The 2026-05-30 session proved the
correct measurement model by probing real transcripts:

  AUTO   = a Skill tool_use event (the model decided to invoke the skill).
  MANUAL = a `<command-name>/NAME</command-name>` user event (user typed /NAME).

These are DISJOINT event populations that never share a turn — typing a slash
executes the skill body WITHOUT emitting a Skill tool_use (verified: cooccur=0
for every skill). So auto/manual is NOT a per-turn correlation; it is two
independent counts:  auto-rate(skill) = auto / (auto + manual).

Two probe findings that killed the prototype's method:
  1. `caller.type` is noise. It read absent at the EVENT level in the prototype
     (always "<none>"), and inside the tool_use block it is "direct" or absent in
     a way that does NOT track auto/manual — the same skill (acli) shows both.
     Kept only as a diagnostic column.
  2. Slash and Skill tool_use are different events in different turns, so the
     6-line/per-turn correlation the prototype used could never match them.

Denominator rule: auto-rate is only meaningful for skills the model CAN invoke.
Skills/commands with `disable-model-invocation: true` (assert-presence,
decommission, and all claude/commands/*) can only be manual — they are reported
separately, never counted as auto-trigger failures.

Per-turn segmentation survives for ONE thing: nudge efficacy. A skill-nudge
(UserPromptSubmit attachment) and the model's response to it land in the same
turn, so that correlation is real.

Ground-truth signals (see probes in 2026-05-30 session):
  - Skill invocation: assistant event, content block {type:tool_use, name:Skill,
    input:{skill:NAME}}, optional nested caller:{type:"direct"}, isSidechain.
  - MANUAL marker: a genuine user turn whose content has
    <command-name>/NAME</command-name> (user typed the slash).
  - Nudge injection: a separate event with
    attachment:{hookName:"UserPromptSubmit", content:"[skill-nudge] Heuristic
    match: ... '/NAME' command|skill ..."}.

Usage:
    python3 measure-autotrigger.py [--since YYYY-MM-DD] [--until YYYY-MM-DD]
        [--projects GLOB ...] [--scope dotfiles|kobig|all]
        [--repo-root PATH] [--out DIR] [--json]

Windows for the 06-01 re-measure (run BOTH with identical method — fix #1):
    # pre-nudge baseline (nudge deployed 2026-05-25)
    measure-autotrigger.py --since 2026-05-13 --until 2026-05-25 --scope kobig
    # post-nudge re-measure
    measure-autotrigger.py --since 2026-05-25 --scope kobig

Scope presets (fix #3):
    dotfiles  only -Users-kobig-Codes-Personals-dotfiles (this repo's sessions)
    kobig     all -Users-kobig-* project dirs (skills are global -> fire there)
    all       every project dir under ~/.claude/projects

Output is descriptive, not a verdict. Caveats are printed inline. The decision
gate lives in the re-measure plan memo, not here.
"""

import argparse
import json
import sys
from pathlib import Path

# Ensure the scripts/ directory is importable when invoked as a script
sys.path.insert(0, str(Path(__file__).parent))

from autotrigger.analyze import analyze, summarize


def main():
    p = argparse.ArgumentParser(description="Per-turn skill auto-trigger measurement")
    p.add_argument("--since", help="ISO date (UTC) lower bound on turn timestamp")
    p.add_argument("--until", help="ISO date (UTC) upper bound (exclusive)")
    p.add_argument("--scope", choices=["dotfiles", "kobig", "all"], default="kobig",
                   help="corpus preset (default: kobig — skills are global)")
    p.add_argument("--projects", nargs="*", default=[],
                   help="explicit project-dir globs (overrides --scope)")
    p.add_argument("--repo-root", type=Path,
                   default=Path(__file__).resolve().parents[1],
                   help="dotfiles repo root for custom skill/command enumeration")
    p.add_argument("--use-plugin-cache-fallback", action="store_true",
                   help="if --repo-root has no claude/{skills,commands}/ (post-cutover "
                        "kbg-harness layout), walk ~/.claude/plugins/cache/kobig/kbg/ "
                        "for the latest version. Avoids the /tmp symlink workaround.")
    p.add_argument("--out", type=Path, help="write report dir (md + json) here")
    p.add_argument("--json", action="store_true", help="print raw json to stdout")
    args = p.parse_args()

    data = analyze(args)
    if args.json:
        print(json.dumps(data, indent=2))
        return
    report = summarize(data)
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        tag = f"{args.scope}_{args.since or 'begin'}_{args.until or 'now'}".replace("-", "")
        (args.out / f"autotrigger_{tag}.md").write_text(report)
        (args.out / f"autotrigger_{tag}.json").write_text(json.dumps(data, indent=2))
        print(f"Wrote {args.out}/autotrigger_{tag}.md", file=sys.stderr)
    print(report)


if __name__ == "__main__":
    main()
