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
import glob
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

PROJECTS_ROOT = Path.home() / ".claude" / "projects"
CMD_NAME_RE = re.compile(r"<command-name>\s*/?([\w:-]+)\s*</command-name>")
# Nudge content names its target as '/foo' (command) or 'foo' (skill).
NUDGE_TARGET_RE = re.compile(
    r"\[skill-nudge\] Heuristic match:.*?'/?([\w:-]+)'\s+(command|skill)", re.DOTALL
)


def parse_ts(event: dict):
    """Return a timezone-aware datetime from an event's timestamp, or None."""
    ts = event.get("timestamp")
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def content_to_text(content) -> str:
    """Flatten a message.content (str or list of blocks) to searchable text."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for c in content:
            if isinstance(c, dict):
                if c.get("type") == "text":
                    parts.append(c.get("text", ""))
                elif isinstance(c.get("content"), str):
                    parts.append(c["content"])
        return "\n".join(parts)
    return ""


def is_genuine_user_prompt(event: dict) -> bool:
    """True if this is a real user turn (typed prompt or slash), not a tool result."""
    if event.get("type") != "user":
        return False
    if event.get("toolUseResult") is not None:
        return False
    msg = event.get("message")
    if not isinstance(msg, dict):
        return False
    content = msg.get("content")
    if isinstance(content, list):
        # a tool_result echo is a user event but not a prompt
        if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            return False
    return True


def slash_names(event: dict) -> set:
    """Slash command names the user typed in this prompt (normalized, no slash)."""
    text = content_to_text(event.get("message", {}).get("content"))
    return {m.lower() for m in CMD_NAME_RE.findall(text)}


def nudge_target(event: dict):
    """If event is a skill-nudge injection, return (target_name, kind) else None."""
    att = event.get("attachment")
    if not isinstance(att, dict):
        return None
    if att.get("hookName") != "UserPromptSubmit":
        return None
    content = att.get("content", "")
    if "[skill-nudge] Heuristic match" not in content:
        return None
    m = NUDGE_TARGET_RE.search(content)
    if not m:
        return None
    return (m.group(1).lower(), m.group(2))  # (name, "command"|"skill")


def skill_invocations(event: dict):
    """Yield (skill_name, caller_type_or_None) for Skill tool_use blocks."""
    if event.get("type") != "assistant":
        return
    for c in event.get("message", {}).get("content", []) or []:
        if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "Skill":
            name = (c.get("input", {}) or {}).get("skill", "?")
            caller = c.get("caller")
            ctype = caller.get("type") if isinstance(caller, dict) else None
            yield (name.lower(), ctype)


def assistant_mentions(event: dict, target: str) -> bool:
    """True if assistant text/thinking in this event mentions /target or target."""
    if event.get("type") != "assistant":
        return False
    blob_parts = []
    for c in event.get("message", {}).get("content", []) or []:
        if isinstance(c, dict) and c.get("type") in ("text", "thinking"):
            blob_parts.append(c.get("text", "") or c.get("thinking", ""))
    blob = "\n".join(blob_parts).lower()
    return f"/{target}" in blob or target in blob


def normalize(name: str) -> str:
    """Strip plugin prefix and slash; lowercase. 'skill-creator:skill-creator'->'skill-creator'."""
    name = name.lstrip("/").lower()
    if ":" in name:
        name = name.split(":")[-1]
    return name


def _has_dmi(path: Path) -> bool:
    """True if frontmatter sets disable-model-invocation: true."""
    try:
        txt = path.read_text()
    except OSError:
        return False
    m = re.search(r"^---\n(.*?)\n---", txt, re.DOTALL)
    fm = m.group(1) if m else ""
    return bool(re.search(r"disable-model-invocation:\s*true", fm))


def load_custom_names(repo_root: Path):
    """Custom skills and commands from the repo, with disable-model-invocation flags.

    Excludes scaffolds (leading underscore). Returns:
      skills:   {name: dmi_bool}  — user-authored skills
      commands: {name: dmi_bool}  — user-authored commands (all dmi=True in practice)
    Skills with dmi=True (assert-presence, decommission) and every command can only
    be invoked manually, so they are excluded from the auto-rate denominator.
    """
    skills, commands = {}, {}
    sdir = repo_root / "claude" / "skills"
    if sdir.is_dir():
        for d in sdir.iterdir():
            if d.is_dir() and not d.name.startswith("_") and (d / "SKILL.md").exists():
                skills[d.name.lower()] = _has_dmi(d / "SKILL.md")
    cdir = repo_root / "claude" / "commands"
    if cdir.is_dir():
        for f in cdir.glob("*.md"):
            if not f.name.startswith("_"):
                commands[f.stem.lower()] = _has_dmi(f)
    return skills, commands


def iter_project_dirs(scope: str, projects: list):
    if projects:
        for p in projects:
            yield from glob.glob(str(PROJECTS_ROOT / p))
        return
    if scope == "all":
        yield from (str(d) for d in PROJECTS_ROOT.iterdir() if d.is_dir())
    elif scope == "kobig":
        # Named project dirs only. The trailing '-' deliberately excludes the
        # bare '-Users-kobig' home-default project (~2661 throwaway/misc
        # sessions). Verified 2026-05-30: that dir contributes ZERO custom-skill
        # invocations post-nudge, so kobig == all for the rate while scanning
        # ~10x fewer files. Use --scope all to re-confirm that holds.
        yield from (str(d) for d in PROJECTS_ROOT.glob("-Users-kobig-*") if d.is_dir())
    else:  # dotfiles
        yield str(PROJECTS_ROOT / "-Users-kobig-Codes-Personals-dotfiles")


def segment_turns(events: list):
    """Split an ordered event list into turns. Each turn = list of events starting
    at a genuine user prompt. Events before the first prompt are dropped."""
    turns, cur = [], None
    for ev in events:
        if is_genuine_user_prompt(ev):
            if cur is not None:
                turns.append(cur)
            cur = [ev]
        elif cur is not None:
            cur.append(ev)
    if cur is not None:
        turns.append(cur)
    return turns


def expansion_slash_skill(turn_start: dict, by_uuid: dict):
    """If this turn began as a command EXPANSION, return the normalized slash name.

    Typing `/X` emits two user events: a <command-name>/X marker (the MANUAL
    signal, its own n=1 turn) and the command's expanded body, whose parentUuid
    points back at the marker. The body looks like a fresh natural-language prompt,
    so a Skill tool_use that EXECUTES the command lands here and would be misread
    as AUTO — double-counting the one /X action as both manual and auto.
    Verified 2026-05-30 on /ship-merge and /acli (parentUuid == marker uuid).
    Returns the slash skill so the caller can suppress that auto count.
    """
    parent = by_uuid.get(turn_start.get("parentUuid"))
    if parent is None:
        return None
    names = slash_names(parent)
    return normalize(next(iter(names))) if names else None


def analyze(args):
    since = datetime.fromisoformat(args.since).replace(tzinfo=timezone.utc) if args.since else None
    until = datetime.fromisoformat(args.until).replace(tzinfo=timezone.utc) if args.until else None
    custom_skills, custom_commands = load_custom_names(args.repo_root)

    files = []
    for d in iter_project_dirs(args.scope, args.projects):
        files.extend(glob.glob(os.path.join(d, "*.jsonl")))

    # auto[name] = {main, sidechain, caller_direct}  (Skill tool_use events)
    auto = defaultdict(lambda: {"main": 0, "sidechain": 0, "caller_direct": 0})
    # manual[name] = count of /name slash events
    manual = Counter()
    # slash_exec[name] = Skill tool_use that merely executes a /name slash
    # (suppressed from auto to avoid double-counting; already in manual)
    slash_exec = Counter()
    nudge_events = []
    files_scanned = 0
    turns_total = 0
    # "active" = contributes a measured count (skill use, skill/command slash, or
    # nudge). Scope-invariant: empty home-dir sessions inflate scanned/total but
    # never active — so reporting active makes the kobig==all equivalence visible.
    files_active = 0
    turns_active = 0

    for fp in files:
        try:
            with open(fp) as fh:
                events = [json.loads(ln) for ln in fh if ln.strip()]
        except (OSError, json.JSONDecodeError):
            # tolerate a partially-corrupt file: re-parse line by line
            events = []
            try:
                for ln in open(fp):
                    try:
                        events.append(json.loads(ln))
                    except json.JSONDecodeError:
                        continue
            except OSError:
                continue
        files_scanned += 1
        by_uuid = {e.get("uuid"): e for e in events if isinstance(e, dict) and e.get("uuid")}
        file_active = False

        for turn in segment_turns(events):
            tts = parse_ts(turn[0])
            if since and (tts is None or tts < since):
                continue
            if until and (tts is None or tts >= until):
                continue
            turns_total += 1
            turn_active = False

            # MANUAL: one slash per user prompt that names a skill/command
            for s in slash_names(turn[0]):
                n = normalize(s)
                manual[n] += 1
                if n in custom_skills or n in custom_commands:
                    turn_active = True

            # If this turn is a command expansion, the slash that spawned it is
            # already a MANUAL event — suppress its execution Skill use from AUTO.
            exp_skill = expansion_slash_skill(turn[0], by_uuid)

            # AUTO: Skill tool_use events anywhere in the turn
            turn_invocations = []
            turn_nudges = []
            for ev in turn:
                nt = nudge_target(ev)
                if nt:
                    turn_nudges.append(nt)
                    # NB: nudges intentionally do NOT mark a turn active. Active =
                    # rate-relevant (auto/manual), which is scope-invariant. Nudge
                    # fires are scope-DEPENDENT (the hook fires in home-dir too).
                for name, ctype in skill_invocations(ev):
                    norm = normalize(name)
                    turn_invocations.append(norm)
                    turn_active = True
                    if ev.get("isSidechain"):
                        auto[norm]["sidechain"] += 1
                    elif norm == exp_skill:
                        slash_exec[norm] += 1  # double-count guard, not AUTO
                    else:
                        auto[norm]["main"] += 1
                        if ctype == "direct":
                            auto[norm]["caller_direct"] += 1

            if turn_active:
                turns_active += 1
                file_active = True

            # nudge efficacy (per-turn, this is the one real correlation)
            for target, kind in turn_nudges:
                ntarget = normalize(target)
                fired = ntarget in turn_invocations
                mentioned = any(assistant_mentions(ev, ntarget) for ev in turn)
                nudge_events.append({
                    "target": ntarget, "kind": kind,
                    "fired": fired, "mentioned": mentioned,
                    "sidechain": bool(turn[0].get("isSidechain")),
                })

        if file_active:
            files_active += 1

    return {
        "since": args.since, "until": args.until, "scope": args.scope,
        "projects": args.projects,
        "files_scanned": files_scanned, "turns_total": turns_total,
        "files_active": files_active, "turns_active": turns_active,
        "custom_skills": custom_skills,      # {name: dmi}
        "custom_commands": custom_commands,  # {name: dmi}
        "auto": {k: v for k, v in auto.items()},
        "manual": dict(manual),
        "slash_exec": dict(slash_exec),
        "nudges": nudge_events,
    }


def summarize(data: dict) -> str:
    skills = data["custom_skills"]      # {name: dmi}
    commands = data["custom_commands"]  # {name: dmi}
    auto = data["auto"]                 # {name: {main, sidechain, caller_direct}}
    manual = data["manual"]             # {name: count}

    def amain(name):
        return auto.get(name, {}).get("main", 0)

    def mcount(name):
        return manual.get(name, 0)

    # model-invocable custom skills (dmi=False) — the auto-rate denominator
    invocable = sorted(n for n, dmi in skills.items() if not dmi)
    dmi_skills = sorted(n for n, dmi in skills.items() if dmi)

    sum_auto = sum(amain(n) for n in invocable)
    sum_manual = sum(mcount(n) for n in invocable)
    n_total = sum_auto + sum_manual
    custom_rate = 100 * sum_auto / n_total if n_total else 0

    # overall across ALL skills seen (custom + plugin + builtin).
    # A slash counts as a skill-manual ONLY if the name can auto-fire — i.e. it
    # appears as a Skill tool_use somewhere, or is a model-invocable custom skill.
    # This excludes UI/client commands (/clear, /plugin, /compact, /config, ...)
    # which are slashes but never skills, and excludes dmi skills + commands
    # (reported separately as manual-only).
    nonauto_names = set(commands) | set(dmi_skills)
    skill_universe = set(auto) | set(invocable)
    all_auto = sum(v.get("main", 0) for v in auto.values())
    all_manual = sum(c for n, c in manual.items()
                     if n in skill_universe and n not in nonauto_names)
    all_total = all_auto + all_manual
    all_rate = 100 * all_auto / all_total if all_total else 0

    L = []
    L.append("# Skill Auto-Trigger Measurement")
    L.append("")
    L.append(f"**Window**: {data['since'] or 'BEGIN'} .. {data['until'] or 'NOW'}  |  "
             f"**Scope**: {data['scope']}{' ' + ' '.join(data['projects']) if data['projects'] else ''}")
    L.append(f"**Corpus**: {data['files_scanned']} transcripts scanned "
             f"({data.get('files_active', '?')} with rate-relevant activity), "
             f"{data['turns_total']} turns in window "
             f"({data.get('turns_active', '?')} active). "
             "Rate-active counts (auto/manual) are scope-invariant; "
             "scanned/total and nudge fires are not.")
    L.append(f"**Custom skills**: {len(skills)} ({len(invocable)} model-invocable, "
             f"{len(dmi_skills)} disable-model-invocation)")
    L.append("")
    L.append("AUTO = Skill tool_use (model invoked). MANUAL = /slash (user invoked). "
             "Disjoint event populations. auto-rate = auto / (auto + manual), main thread.")
    L.append("")
    L.append("## Headline")
    L.append("")
    L.append("| Metric | Auto | Manual | n | Auto-rate |")
    L.append("|--------|------|--------|---|-----------|")
    L.append(f"| Custom skills (model-invocable) | {sum_auto} | {sum_manual} | {n_total} | {custom_rate:.0f}% |")
    L.append(f"| All skills (incl. plugin/built-in) | {all_auto} | {all_manual} | {all_total} | {all_rate:.0f}% |")
    L.append("")

    # per-skill custom breakout
    L.append("## Custom model-invocable skill breakout (main thread)")
    L.append("")
    L.append("| Skill | auto | manual | auto-rate | caller=direct |")
    L.append("|-------|------|--------|-----------|---------------|")
    never = []
    for name in invocable:
        a, m = amain(name), mcount(name)
        if a + m == 0:
            never.append(name)
            continue
        r = 100 * a / (a + m) if (a + m) else 0
        cd = auto.get(name, {}).get("caller_direct", 0)
        L.append(f"| {name} | {a} | {m} | {r:.0f}% | {cd} |")
    L.append("")
    L.append(f"**Never invoked either way ({len(never)}/{len(invocable)})**: {', '.join(never) or '—'}")
    L.append("")

    # manual-only families (cannot auto-fire by design)
    L.append("## Manual-only (disable-model-invocation — excluded from auto-rate)")
    L.append("")
    L.append("| Name | kind | manual | auto (should be ~0) |")
    L.append("|------|------|--------|---------------------|")
    for name in dmi_skills:
        L.append(f"| {name} | skill(dmi) | {mcount(name)} | {amain(name)} |")
    for name in sorted(commands):
        m = mcount(name)
        a = amain(name)
        if m == 0 and a == 0:
            continue
        L.append(f"| {name} | command | {m} | {a} |")
    L.append("")

    # caller.type diagnostic (proves it is noise)
    direct_total = sum(v.get("caller_direct", 0) for v in auto.values())
    main_total = sum(v.get("main", 0) for v in auto.values())
    L.append("## caller.type diagnostic")
    L.append("")
    L.append(f"`caller=direct` on {direct_total}/{main_total} main-thread Skill tool_use events. "
             "It does NOT track auto/manual (same skill shows both) — kept only to "
             "document that the 2026-05-30 'caller unreliable' finding holds.")
    L.append("")

    # nudge efficacy
    nd = [n for n in data["nudges"] if not n["sidechain"]]
    L.append("## Nudge efficacy (main thread, per-turn)")
    L.append("")
    if not nd:
        L.append("No nudge injections in window.")
    else:
        by_target = defaultdict(lambda: {"n": 0, "fired": 0, "mentioned": 0, "kind": ""})
        for n in nd:
            t = by_target[n["target"]]
            t["n"] += 1
            t["fired"] += 1 if n["fired"] else 0
            t["mentioned"] += 1 if n["mentioned"] else 0
            t["kind"] = n["kind"]
        L.append("`fired` = named skill invoked same turn. `mentioned` = assistant "
                 "referenced it (commands cannot auto-fire, so mention is their success).")
        L.append("")
        L.append("> SCOPE NOTE: the skill-nudge hook fires globally, so nudge counts "
                 "are scope-DEPENDENT (kobig undercounts home-dir fires). Use "
                 "`--scope all` for the honest nudge action-rate; auto-rate above "
                 "stays scope-invariant either way.")
        L.append("")
        L.append("| Nudge target | kind | emitted | fired | mentioned | acted% |")
        L.append("|--------------|------|---------|-------|-----------|--------|")
        tot_n = tot_acted = 0
        for t in sorted(by_target):
            d = by_target[t]
            acted = max(d["fired"], d["mentioned"]) if d["kind"] == "command" else d["fired"]
            pct = 100 * acted / d["n"] if d["n"] else 0
            tot_n += d["n"]
            tot_acted += acted
            L.append(f"| {t} | {d['kind']} | {d['n']} | {d['fired']} | {d['mentioned']} | {pct:.0f}% |")
        L.append("")
        L.append(f"**Overall nudge action rate**: {tot_acted}/{tot_n} "
                 f"({100*tot_acted/tot_n if tot_n else 0:.0f}%)")
    L.append("")
    se = data.get("slash_exec", {})
    if se:
        L.append("## Double-count guard (slash-executions suppressed from AUTO)")
        L.append("")
        L.append("A `/X` whose command body re-invokes via the Skill tool would count")
        L.append("once as MANUAL (the slash) and once as AUTO (the execution). These")
        L.append("execution Skill-uses are detected via parentUuid and excluded from AUTO:")
        L.append("")
        L.append("| Skill | suppressed |")
        L.append("|-------|------------|")
        for name in sorted(se):
            L.append(f"| {name} | {se[name]} |")
        L.append("")
        L.append("Limitation: a slash that crosses a compaction boundary breaks the")
        L.append("parentUuid chain and may slip through (seen once for /ship-merge, dmi —")
        L.append("excluded from the auto-rate anyway).")
        L.append("")

    L.append("## Caveats")
    L.append("")
    L.append("- AUTO (Skill tool_use) and MANUAL (/slash) are independent event")
    L.append("  counts. They almost never co-occur — EXCEPT a /command whose body")
    L.append("  re-invokes via the Skill tool, which the double-count guard above")
    L.append("  suppresses from AUTO (already counted as manual).")
    L.append("- `mentioned` for command nudges is a weak proxy (assistant text may")
    L.append("  reference the command without recommending it). Treat as upper bound.")
    L.append("- Sidechain (subagent) invocations excluded from headline.")
    return "\n".join(L)


def main():
    p = argparse.ArgumentParser(description="Per-turn skill auto-trigger measurement")
    p.add_argument("--since", help="ISO date (UTC) lower bound on turn timestamp")
    p.add_argument("--until", help="ISO date (UTC) upper bound (exclusive)")
    p.add_argument("--scope", choices=["dotfiles", "kobig", "all"], default="kobig",
                   help="corpus preset (default: kobig — skills are global)")
    p.add_argument("--projects", nargs="*", default=[],
                   help="explicit project-dir globs (overrides --scope)")
    p.add_argument("--repo-root", type=Path,
                   default=Path(__file__).resolve().parents[2],
                   help="dotfiles repo root for custom skill/command enumeration")
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
