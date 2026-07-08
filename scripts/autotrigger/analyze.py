"""analyze() and summarize() for measure-autotrigger."""

import glob
import json
import os
from collections import Counter, defaultdict
from datetime import datetime, timezone

from .events import (
    assistant_mentions,
    expansion_slash_skill,
    iter_project_dirs,
    load_custom_names,
    normalize,
    nudge_target,
    parse_ts,
    segment_turns,
    skill_invocations,
    slash_names,
)


def analyze(args):
    since = datetime.fromisoformat(args.since).replace(tzinfo=timezone.utc) if args.since else None
    until = datetime.fromisoformat(args.until).replace(tzinfo=timezone.utc) if args.until else None
    custom_skills, custom_commands = load_custom_names(
        args.repo_root, use_plugin_cache_fallback=args.use_plugin_cache_fallback)

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
