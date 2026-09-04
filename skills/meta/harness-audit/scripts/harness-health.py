#!/usr/bin/env python3
# harness-health.py — read-only query surface over the live cost ledger.
# Part of `mh:harness-audit --health`; see skills/meta/harness-audit/SKILL.md for the contract.
# The cost-tracker Stop hook appends one row per session to costs.jsonl
# (see hooks/stop/cost-tracker.sh). Stdlib only, no subprocess, no LLM in the loop.
#
# The verdict + staleness lenses that previously read the governance journal and
# hooks/sensors.json were retired in the v0.6.0 cut reconciliation — both sources
# are gone. --health now surfaces the one live signal: per-session token cost.

import argparse
import datetime as dt
import json
import os
import re
import sys

DEFAULT_COSTS = os.path.expanduser("~/.local/share/kbg/metrics/costs.jsonl")
DEFAULT_SKILLS = os.path.expanduser("~/.local/share/kbg/metrics/skill-usage.jsonl")
# The plugin was renamed kbg -> mh; the live ledgers still carry thousands of
# pre-rename kbg:-prefixed rows inside any realistic lookback window. Admit
# both prefixes as "this fleet" when matching ledger rows to fleet surfaces
# (#136 fix 1) -- current plugin name is unioned in at call sites so a future
# rename doesn't need a code change here.
PLUGIN_ALIASES = {"mh", "kbg"}
# This file lives at <root>/skills/meta/harness-audit/scripts/harness-health.py —
# 4 parents up from its own containing dir reaches the fleet root, in both a
# dotfiles checkout and a flat repo checkout (the file's position relative to
# the fleet is fixed either way; see issue #136).
DEFAULT_ROOT = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "..", "..", ".."))

_NAME_RE = re.compile(r'^name:\s*(.+?)\s*$', re.MULTILINE)
_DMI_RE = re.compile(r'^disable-model-invocation:\s*true\b', re.MULTILINE)


def warn(msg):
    print(f"[harness-health] WARN: {msg}", file=sys.stderr)


def load_rows(path):
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, raw in enumerate(f, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                yield json.loads(raw)
            except ValueError:
                warn(f"skipping malformed line {n} in {path}")


def filter_rows(rows, args):
    out = list(rows)
    if args.since is not None:
        cutoff = (dt.datetime.now(dt.timezone.utc)
                  - dt.timedelta(days=args.since)).isoformat(
            timespec="milliseconds").replace("+00:00", "Z")
        out = [r for r in out if r.get("timestamp", "") >= cutoff]
    if args.last is not None:
        out = out[-args.last:]
    return out


def render_cost(rows, costs_path):
    print(f"## Token usage (costs.jsonl)\nledger: {costs_path}\n")
    if not rows:
        print("0 rows — the cost-tracker Stop hook appends one per session")
        return
    print("| ts | session | model | input | output | cache_write | cache_read | est_cost_usd |")
    print("|---|---|---|---|---|---|---|---|")
    gin = gout = gcw = gcr = 0
    gcost = 0.0
    for r in rows:
        i, o, cw, cr = (r.get("input_tokens", 0), r.get("output_tokens", 0),
                        r.get("cache_write_tokens", 0), r.get("cache_read_tokens", 0))
        cost = r.get("estimated_cost_usd", 0.0)
        gin += i; gout += o; gcw += cw; gcr += cr
        gcost += cost if isinstance(cost, (int, float)) else 0.0
        sid = (r.get("session_id") or "?")[:8]
        print(f"| {r.get('timestamp','?')} | {sid} | {r.get('model','?')} | {i:,} | "
              f"{o:,} | {cw:,} | {cr:,} | {cost:.4f} |")
    print(f"\n**Σ across {len(rows)} session(s): input {gin:,} · output {gout:,} · "
          f"cache_write {gcw:,} · cache_read {gcr:,} · est_cost ${gcost:.4f}** "
          f"(rates are heuristic — see hooks/stop/cost-tracker.sh)")


def count_skill_usage(rows, now=None):
    # Shared by render_skill_usage and the dead-surface panel — same
    # (plugin, skill) -> (n7, n30) shape, don't fork this into two copies
    # that can drift (#136).
    #
    # timespec="seconds" (not "milliseconds") to match the writer's actual
    # on-disk format (date -u +%Y-%m-%dT%H:%M:%SZ has no fractional
    # seconds) -- the mismatch was harmless at day-granularity buckets but
    # was a real string-comparison inconsistency (#90 adversarial audit,
    # 2026-08-25).
    if now is None:
        now = dt.datetime.now(dt.timezone.utc)

    def cutoff(days):
        return (now - dt.timedelta(days=days)).isoformat(
            timespec="seconds").replace("+00:00", "Z")
    c7, c30 = cutoff(7), cutoff(30)
    counts = {}
    skipped = 0
    for r in rows:
        ts, skill, plugin = r.get("ts"), r.get("skill", "unknown"), r.get("plugin", "unknown")
        # load_rows() only catches JSON syntax errors; a syntactically valid
        # row with the WRONG type (ts as an int, etc.) reaches here and used
        # to crash the whole --health command with an uncaught TypeError on
        # the string comparison below (#90 adversarial audit, 2026-08-25,
        # reproduced live). Skip and warn instead, matching load_rows' own
        # malformed-line convention.
        if not isinstance(ts, str) or not isinstance(skill, str) or not isinstance(plugin, str):
            skipped += 1
            continue
        n7, n30 = counts.get((plugin, skill), (0, 0))
        if ts >= c30:
            n30 += 1
        if ts >= c7:
            n7 += 1
        counts[(plugin, skill)] = (n7, n30)
    return counts, skipped


def render_skill_usage(rows, skills_path):
    # Invocation counts only, split by plugin — no outcome/success field.
    # No reliable success signal exists for a Skill call (see
    # hooks/session/skill-usage-telemetry.sh's header); this is usage
    # evidence for the future matt-skill vs harness-skill overlap cull,
    # not a success-rate panel.
    print(f"\n## Skill usage (skill-usage.jsonl)\nledger: {skills_path}\n")
    if not rows:
        print("0 rows — the session:skill-usage-telemetry PostToolUse hook appends one per skill invocation")
        return
    counts, skipped = count_skill_usage(rows)
    if skipped:
        warn(f"skipped {skipped} skill-usage row(s) with a non-string ts/skill/plugin field")
    print("| plugin | skill | last 7d | last 30d |")
    print("|---|---|---|---|")
    for (plugin, skill), (n7, n30) in sorted(counts.items(), key=lambda kv: -kv[1][1]):
        if n30 == 0:
            continue
        print(f"| {plugin} | {skill} | {n7} | {n30} |")
    by_plugin_30 = {}
    for (plugin, _), (_, n30) in counts.items():
        by_plugin_30[plugin] = by_plugin_30.get(plugin, 0) + n30
    total7 = sum(n7 for n7, _ in counts.values())
    total30 = sum(n30 for _, n30 in counts.values())
    plugin_summary = ", ".join(f"{p}={n}" for p, n in
                                sorted(by_plugin_30.items(), key=lambda kv: -kv[1]) if n)
    print(f"\n**Σ last 7d: {total7} invocation(s) · last 30d: {total30} invocation(s)** "
          f"({plugin_summary or 'no plugin data'})")


def _frontmatter(path):
    # Simple line-regex over the leading ---...--- block, same stdlib-only
    # style as the rest of this repo's tooling — no PyYAML.
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError:
        return None
    if not content.startswith("---"):
        return None
    end = content.find("\n---", 3)
    return content[3:end] if end != -1 else None


def get_plugin_name(root):
    path = os.path.join(root, ".claude-plugin", "plugin.json")
    try:
        with open(path, encoding="utf-8") as f:
            name = json.load(f).get("name")
        if isinstance(name, str) and name:
            return name
    except (OSError, ValueError):
        pass
    warn(f"could not read plugin name from {path}, defaulting to 'mh'")
    return "mh"


def scan_skills(root):
    # Mirrors checks/01-fleet-count.sh: every SKILL.md under <root>/skills,
    # excluding a path segment starting with '_' and any '-workspace/'
    # segment. Yields (bare_name, manual_only).
    skills_dir = os.path.join(root, "skills")
    for dirpath, _dirnames, filenames in os.walk(skills_dir):
        if "SKILL.md" not in filenames:
            continue
        path = os.path.join(dirpath, "SKILL.md")
        if "/_" in path or "-workspace/" in path:
            continue
        fm = _frontmatter(path)
        if fm is None:
            continue
        m = _NAME_RE.search(fm)
        bare = m.group(1) if m else os.path.basename(dirpath)
        yield bare, bool(_DMI_RE.search(fm))


def scan_agents(root):
    # Mirrors checks/01-fleet-count.sh: every *.md directly under
    # <root>/agents (maxdepth 1). Namespaced form uses the filename stem,
    # matching real agent_type values in costs.jsonl (e.g. "mh:backend-architect").
    agents_dir = os.path.join(root, "agents")
    if not os.path.isdir(agents_dir):
        return []
    return sorted(
        fn[:-3] for fn in os.listdir(agents_dir)
        if fn.endswith(".md") and os.path.isfile(os.path.join(agents_dir, fn))
    )


def scan_skill_preloads(root):
    # A skill listed in an agent's `skills:` frontmatter is preloaded into
    # that agent's context directly -- it never goes through a model-issued
    # Skill tool call, so it can never appear in skill-usage.jsonl and is
    # always "dead" by invocation count alone (#136 fix 2). Map full skill
    # name -> [agent stem, ...] so the dead-surface panel can label it
    # instead of leaving the note empty.
    agents_dir = os.path.join(root, "agents")
    preloads = {}
    if not os.path.isdir(agents_dir):
        return preloads
    for fn in sorted(os.listdir(agents_dir)):
        path = os.path.join(agents_dir, fn)
        if not (fn.endswith(".md") and os.path.isfile(path)):
            continue
        fm = _frontmatter(path)
        if fm is None:
            continue
        in_list = False
        for line in fm.splitlines():
            if re.match(r'^skills:\s*$', line):
                in_list = True
                continue
            if not in_list:
                continue
            m = re.match(r'^\s*-\s*(\S+)\s*$', line)
            if m:
                preloads.setdefault(m.group(1), []).append(fn[:-3])
            else:
                in_list = False
    return preloads


def count_hooks(root):
    # Mirrors checks/01-fleet-count.sh: *.sh/*.py under <root>/hooks,
    # excluding __pycache__ paths and leading-underscore filenames. Total
    # count only — no per-hook invocation ledger exists (#136).
    hooks_dir = os.path.join(root, "hooks")
    count = 0
    for dirpath, _dirnames, filenames in os.walk(hooks_dir):
        if "__pycache__" in dirpath.split(os.sep):
            continue
        for fn in filenames:
            if fn.startswith("_"):
                continue
            if fn.endswith(".sh") or fn.endswith(".py"):
                count += 1
    return count


def compute_dead_surfaces(root, skill_rows, costs_path, skills_path):
    # Both ledger paths are checked with os.path.isfile before computing
    # anything for that surface type -- a missing ledger must never silently
    # read as "0 active rows" -> "every fleet surface is dead" (#136 fix 3).
    # This function is the single source of truth for both the markdown and
    # --json render paths (main() passes both through here), so neither can
    # bypass the check the other honors.
    plugin = get_plugin_name(root)
    aliases = PLUGIN_ALIASES | {plugin}

    skills_missing = not os.path.isfile(skills_path)
    dead_skills = None
    if not skills_missing:
        counts, _skipped = count_skill_usage(skill_rows)
        active_skills = set()
        for (p, skill_full), (_n7, n30) in counts.items():
            if p not in aliases or n30 <= 0:
                continue
            stem = skill_full.split(":", 1)[1] if ":" in skill_full else skill_full
            active_skills.add(f"{plugin}:{stem}")  # normalize pre-rename rows to current prefix
        preloads = scan_skill_preloads(root)
        rows = [(f"{plugin}:{bare}", manual_only, preloads.get(f"{plugin}:{bare}"))
                for bare, manual_only in scan_skills(root)
                if f"{plugin}:{bare}" not in active_skills]
        rows.sort(key=lambda t: t[0])
        dead_skills = rows

    costs_missing = not os.path.isfile(costs_path)
    dead_agents = None
    if not costs_missing:
        cutoff30 = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)).isoformat(
            timespec="milliseconds").replace("+00:00", "Z")
        active_agents = set()
        for r in load_rows(costs_path):  # unfiltered — own fixed 30d window, like the skill panel
            ts, agent_type = r.get("timestamp"), r.get("agent_type")
            if not (r.get("stream") == "subagent" and isinstance(agent_type, str)
                    and isinstance(ts, str) and ts >= cutoff30 and ":" in agent_type):
                continue
            a_prefix, a_stem = agent_type.split(":", 1)
            if a_prefix in aliases:
                active_agents.add(f"{plugin}:{a_stem}")  # normalize pre-rename rows too
        dead_agents = sorted(
            f"{plugin}:{stem}" for stem in scan_agents(root)
            if f"{plugin}:{stem}" not in active_agents)

    return {
        "root": root,
        "plugin": plugin,
        "dead_skills": (None if dead_skills is None else
                         [{"name": n, "manual_only": m, "preloaded_by": p} for n, m, p in dead_skills]),
        "skills_path": skills_path,
        "skills_source_missing": skills_missing,
        "dead_agents": None if dead_agents is None else [{"name": n} for n in dead_agents],
        "costs_path": costs_path,
        "costs_source_missing": costs_missing,
        "hooks": {"count": count_hooks(root), "source_missing": True},
    }


def render_dead_surfaces(root, skill_rows, costs_path, skills_path):
    dead = compute_dead_surfaces(root, skill_rows, costs_path, skills_path)
    print(f"\n## Dead surfaces (0 logged invocations in last 30d)\nfleet root: {dead['root']}\n")
    print("Coverage note: counts model-issued Skill-tool calls and subagent Task "
          "invocations only. A skill preloaded via an agent's `skills:` frontmatter, "
          "invoked by a typed `/plugin:name` slash command, or run directly as a "
          "script leaves no row in either ledger and will show here even when it "
          "runs constantly.\n")

    ds, da = dead["dead_skills"], dead["dead_agents"]
    if ds is None:
        print(f"skills: source missing: {dead['skills_path']} — dead-skill list not computed")
    if da is None:
        print(f"agents: source missing: {dead['costs_path']} — dead-agent list not computed")

    ds_rows, da_rows = ds or [], da or []
    if ds is not None and da is not None and not ds_rows and not da_rows:
        print("0 dead skill(s), 0 dead agent(s) — every fleet surface was invoked in the last 30d")
    elif ds_rows or da_rows:
        print("| type | name | note |")
        print("|---|---|---|")
        for row in ds_rows:
            notes = []
            if row["manual_only"]:
                notes.append("manual-only (disable-model-invocation)")
            if row["preloaded_by"]:
                notes.append("preloaded-by: " + ", ".join(row["preloaded_by"]))
            print(f"| skill | {row['name']} | {'; '.join(notes)} |")
        for row in da_rows:
            print(f"| agent | {row['name']} | |")

    print(f"\nhooks: {dead['hooks']['count']} hook(s) in fleet — no invocation ledger exists, "
          f"source missing (see issue #136)")

    skills_summary = f"{len(ds_rows)} dead skill(s)" if ds is not None else "skills source missing"
    agents_summary = f"{len(da_rows)} dead agent(s)" if da is not None else "agents source missing"
    print(f"\n**{skills_summary} · {agents_summary}** — "
          f"INFO only: usage evidence for a future deletion sweep, never auto-deletes.")


def main():
    ap = argparse.ArgumentParser(prog="harness-health",
        description="Read-only query surface over the live cost ledger (costs.jsonl).")
    ap.add_argument("--last", type=int, default=None, help="last N sessions (after other filters)")
    ap.add_argument("--since", type=float, default=None, help="sessions newer than N days")
    ap.add_argument("--costs", default=DEFAULT_COSTS, help="path to costs.jsonl ledger")
    ap.add_argument("--skills", default=DEFAULT_SKILLS, help="path to skill-usage.jsonl ledger")
    ap.add_argument("--root", default=DEFAULT_ROOT,
                    help="fleet root for the dead-surface panel (skills/, agents/, hooks/, .claude-plugin/)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    if len(sys.argv) == 1:  # no CLI flags → print help + exit 0
        ap.print_help(); return 0
    args = ap.parse_args()

    rows = list(filter_rows(load_rows(args.costs), args))
    skill_rows = list(load_rows(args.skills))  # unfiltered — panel is its own fixed 7d/30d windows
    if args.json:
        print(json.dumps({"ledger": args.costs, "sessions": rows,
                           "skills_ledger": args.skills, "skill_usage": skill_rows,
                           "dead_surfaces": compute_dead_surfaces(args.root, skill_rows, args.costs, args.skills)},
                          indent=2, default=str))
        return 0
    exit_code = 0
    if not rows and not os.path.isfile(args.costs):
        print(f"ERROR: cost ledger not found: {args.costs}", file=sys.stderr)
        exit_code = 1  # cost panel specifically can't be served — other panels below still can
    else:
        render_cost(rows, args.costs)
    render_skill_usage(skill_rows, args.skills)
    render_dead_surfaces(args.root, skill_rows, args.costs, args.skills)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())