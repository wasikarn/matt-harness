#!/usr/bin/env python3
"""memory-lint — health check + action mode for the file-based memory store.

Karpathy's llm-wiki "Lint" operation for our memory: catch broken cross-links,
orphaned facts, and index drift before they rot. Deterministic only — semantic
checks (contradictions, staleness) need an LLM pass, not this.

Usage:
  memory-lint.py [MEMORY_DIR]                     # default detector mode
  memory-lint.py [MEMORY_DIR] --auto-archive      # enter action mode (default: --dry-run)
  memory-lint.py [MEMORY_DIR] --auto-archive --dry-run
  memory-lint.py [MEMORY_DIR] --auto-archive --yes  # apply (no confirm prompt)
  memory-lint.py [MEMORY_DIR] --json              # machine-readable output

Detector checks (default mode):
  - dangling [[links]]   — target resolves to no memory (by filename stem or name: slug)
  - orphans              — a memory with no outbound and no inbound [[links]]
  - index drift          — MEMORY.md pointer ↔ file, both directions
  - load budget          — 200-line / 25KB cap on MEMORY.md
Exit code = finding count (0 = clean). Fails loud if MEMORY_DIR is missing.

Action mode (--auto-archive) — applies the A3 trim rubric (memory/project_memory_trim_session_2026_06_04.md):
  Class A — stale-superseded:   MEMORY.md pointer has **SUPERSEDED** marker + topic has 0 surviving inbound
  Class B — near-budget-collapse: pointer ≥250 chars + topic >5KB + pointer carries detail
  Class C — dangling-link-rewrite: surviving file has [[wikilink]] that resolves to nothing or to _archive/

All mutations use `mv` (never `rm`); confirm prompt is shown by default; --yes skips confirm.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import subprocess
import tempfile
import time

WIKILINK = re.compile(r"\[\[([^\]]+)\]\]")
NAME_RE = re.compile(r"(?m)^name:\s*(.+)$")
POINTER_RE = re.compile(r"\]\(([^)]+\.md)\)")  # markdown link ](file.md), not prose "(x.md)"
SUPERSEDED_RE = re.compile(r"\*\*SUPERSEDED[^*]*\*\*\s*by\s*\[\[([^\]]+)\]\]")
POINTER_LINE_RE = re.compile(r"^- \[[^\]]+\]\(([^)]+\.md)\)(.*)$", re.MULTILINE)

LINE_CAP = 200
BYTE_CAP = 25 * 1024
SUPERSEDED_ARCHIVE_DATE_FMT = "%Y-%m-%d"
STUB_TEMPLATE = "- [{}](_archive/{}/{}) — archived on-demand"
# The link target is the archived path so future grep/audit can find the file.
# `memory-lint` will report it as ORPHAN (no top-level wikilink inbound) but the
# markdown link itself resolves. Class A's whole point is "no surviving inbound"
# anyway — the user is explicitly saying "this entry is closed, browse on-demand."


def memory_dir(positional):
    if positional:
        return positional
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True).stdout.strip()
    if not root:
        sys.exit("FATAL: not in a git repo and no MEMORY_DIR given")
    enc = root.replace("/", "-")
    return os.path.join(os.path.expanduser("~/.claude/projects"), enc, "memory")


def link_target(raw):
    # Strip Obsidian alias "[[target|display]]" and a trailing .md.
    t = raw.split("|", 1)[0].strip()
    return t[:-3] if t.endswith(".md") else t


# ── Detector mode ─────────────────────────────────────────────────────────

def collect_state(d):
    """Build the shared data structures used by both detector and action modes."""
    files = [f for f in os.listdir(d) if f.endswith(".md") and f != "MEMORY.md"]
    if not files:
        sys.exit(f"FATAL: no memory files in {d}")

    stems = {f[:-3] for f in files}
    slugs, links_out = {}, {}
    for f in files:
        txt = open(os.path.join(d, f), encoding="utf-8").read()
        m = NAME_RE.search(txt)
        slugs[f] = m.group(1).strip() if m else None
        links_out[f] = [link_target(x) for x in WIKILINK.findall(txt)]

    slug_set = {v for v in slugs.values() if v}
    inbound = set()
    for f, targets in links_out.items():
        for t in targets:
            if t in stems or t in slug_set:
                inbound.add(t)

    index_path = os.path.join(d, "MEMORY.md")
    idx = ""
    referenced = set()
    if os.path.isfile(index_path):
        idx = open(index_path, encoding="utf-8").read()
        referenced = set(POINTER_RE.findall(idx))
    return {
        "d": d, "files": files, "stems": stems, "slugs": slugs, "slug_set": slug_set,
        "inbound": inbound, "links_out": links_out, "index_path": index_path,
        "idx": idx, "referenced": referenced,
    }


def detector_findings(state):
    findings = []
    files = state["files"]
    inbound = state["inbound"]
    links_out = state["links_out"]
    slugs = state["slugs"]
    referenced = state["referenced"]
    idx = state["idx"]
    idx_path = state["index_path"]

    # 1. dangling links
    for f, targets in links_out.items():
        for t in targets:
            if t not in state["stems"] and t not in state["slug_set"]:
                findings.append(f"DANGLING: {f} → [[{t}]] (no such memory)")

    if not os.path.isfile(idx_path):
        findings.append("MISSING: MEMORY.md index not found")
    else:
        # 2. orphans
        for f in files:
            has_out = bool(links_out[f])
            has_in = (f[:-3] in inbound) or (slugs[f] in inbound)
            if f in referenced and not has_out and not has_in:
                findings.append(f"ORPHAN: {f} (no [[links]] in or out)")

        # 3. index drift
        for f in files:
            if f not in referenced:
                findings.append(f"UNINDEXED: {f} not pointed to from MEMORY.md")
        for ref in sorted(referenced):
            if ref not in files:
                findings.append(f"STALE POINTER: MEMORY.md → ({ref}) but file missing")

        # 4. load budget
        idx_bytes, idx_lines = len(idx.encode("utf-8")), idx.count("\n") + 1
        pct = int(max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP) * 100)
        if idx_lines > LINE_CAP or idx_bytes > BYTE_CAP:
            findings.append(f"OVER-BUDGET: MEMORY.md {idx_lines}L/{idx_bytes}B exceeds the 200-line/25KB load cap — trailing index entries WON'T load; fold closed entries into a topic-file/ledger + archive (only MEMORY.md loads — splitting into multiple indexes won't help)")
        elif pct >= 80:
            findings.append(f"NEAR-BUDGET: MEMORY.md at {pct}% of the 200-line/25KB load cap ({idx_lines}L, {idx_bytes}B) — trim verbose pointers, or fold closed entries into a topic-file/ledger + archive (only MEMORY.md loads — don't split into multiple indexes)")

    total_links = sum(len(v) for v in links_out.values())
    linked_count = len([f for f in files if links_out[f] or f[:-3] in inbound or slugs[f] in inbound])
    return findings, total_links, linked_count


def run_detector(state, as_json):
    findings, total_links, linked_count = detector_findings(state)
    if as_json:
        print(json.dumps({
            "mode": "detector",
            "memory_dir": state["d"],
            "files": len(state["files"]),
            "links": total_links,
            "linked": linked_count,
            "findings": findings,
        }, indent=2))
        sys.exit(0 if not findings else len(findings))

    idx_bytes = len(state["idx"].encode("utf-8"))
    idx_lines = state["idx"].count("\n") + 1
    pct = int(max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP) * 100)
    print(f"=== memory-lint: {state['d']} ===")
    print(f"memories: {len(state['files'])} | links: {total_links} | "
          f"linked: {linked_count} | MEMORY.md: {pct}% of load cap | findings: {len(findings)}")
    print()
    for line in findings:
        print(f"  {line}")
    if not findings:
        print("  clean — no dangling links, orphans, or index drift")
    print(f"\nExit: {len(findings)}")
    sys.exit(len(findings))


# ── Action mode ───────────────────────────────────────────────────────────

def list_archive(d):
    """Return set of filename-stems living under _archive/ (recursively)."""
    archive_dir = os.path.join(d, "_archive")
    stems = set()
    if not os.path.isdir(archive_dir):
        return stems
    for root, _, fs in os.walk(archive_dir):
        for f in fs:
            if f.endswith(".md"):
                stems.add(f[:-3])
    return stems


def file_size(d, name):
    p = os.path.join(d, name)
    return os.path.getsize(p) if os.path.isfile(p) else 0


def read_file(d, name):
    return open(os.path.join(d, name), encoding="utf-8").read()


def short_hash(s, n=200):
    return hashlib.sha1(s[:n].encode("utf-8")).hexdigest()[:10]


def parse_pointer_line(line):
    """Extract (filename, link-text, rest-after-paren) from a `- [text](file.md) — tail` line."""
    m = re.match(r"^- \[([^\]]+)\]\(([^)]+\.md)\)(.*)$", line)
    if not m:
        return None
    return m.group(1), m.group(2), m.group(3)


def class_a_stale_superseded(state):
    """Class A: pointer contains **SUPERSEDED** marker + the file the pointer POINTS TO
    exists + has 0 surviving inbound [[wikilinks]] (i.e. the marker is the explicit
    supersession signal AND nothing else references the file).
    The supersedence-target `[[X]]` in the marker is recorded for downstream Class C
    rewrites only (it's the canonical successor, not the file to move)."""
    plan = []
    for line in state["idx"].splitlines():
        m = SUPERSEDED_RE.search(line)
        if not m:
            continue
        # The OLD topic = the file the markdown link points to on this line
        link_m = re.search(r"\]\(([^)]+\.md)\)", line)
        if not link_m:
            continue
        target_file = link_m.group(1)
        target_stem = target_file[:-3]
        if target_file not in state["files"]:
            continue
        # Must have 0 surviving inbound
        if target_stem in state["inbound"]:
            continue
        # Successor for downstream use
        successor = m.group(1).split("|", 1)[0].strip()
        successor = successor[:-3] if successor.endswith(".md") else successor
        plan.append({
            "action": "move",
            "from": target_file,
            "to_archive_subdir": time.strftime(SUPERSEDED_ARCHIVE_DATE_FMT),
            "old_pointer_line": line,
            "successor": successor,
            "pointer_rewrite": {
                "from": line,
                "to": None,  # filled in later
            },
        })
    return plan


def class_b_near_budget_collapse(state):
    """Class B: longest pointer-lines (>=250 chars) where topic is >5KB and pointer is >= 1.2x first paragraph."""
    plan = []
    if not state["idx"]:
        return plan
    # Match the 200L/25KB cap threshold
    idx_bytes = len(state["idx"].encode("utf-8"))
    idx_lines = state["idx"].count("\n") + 1
    pct = int(max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP) * 100)
    if pct < 80:
        return plan

    candidates = []
    for m in POINTER_LINE_RE.finditer(state["idx"]):
        fname = m.group(1)
        rest = m.group(2)
        full_line = m.group(0)
        if len(full_line) < 250:
            continue
        if fname not in state["files"]:
            continue
        topic_size = file_size(state["d"], fname)
        if topic_size <= 5 * 1024:
            continue
        # Proxy: pointer carries detail if full line >= 1.2x first-paragraph of topic
        topic_txt = read_file(state["d"], fname)
        first_para = topic_txt.split("\n\n", 1)[0] if topic_txt else ""
        if len(full_line) >= 1.2 * max(len(first_para), 1):
            candidates.append((len(full_line), fname, full_line, topic_size))

    candidates.sort(key=lambda x: -x[0])  # longest first
    for line_len, fname, full_line, topic_size in candidates:
        # Stub: ~80 chars
        stem = fname[:-3]
        stub = f"- [{stem}]({fname}) — see [[{stem}]] for full record"
        # supersedes: note in topic file
        plan.append({
            "action": "rewrite_pointer",
            "from": full_line,
            "to": stub,
            "from_chars": len(full_line),
            "to_chars": len(stub),
            "delta_bytes": len(stub.encode("utf-8")) - len(full_line.encode("utf-8")),
            "topic_file": fname,
        })
    return plan


def class_c_dangling_link_rewrite(state):
    """Class C: surviving top-level file has a [[wikilink]] that resolves to nothing,
    OR to a target in _archive/ where the source has a known supersedence target."""
    plan = []
    archive_stems = list_archive(state["d"])
    # Build index of (stem → first non-section line of MEMORY.md that mentions it as pointer)
    # for "known supersedence target" hint.
    super_targets = {}  # archived_stem -> superseded-by target
    for line in state["idx"].splitlines():
        m = SUPERSEDED_RE.search(line)
        if not m:
            continue
        # Find filename in same line
        pm = re.search(r"\]\(([^)]+\.md)\)", line)
        if not pm:
            continue
        old_fname = pm.group(1)
        old_stem = old_fname[:-3]
        if old_stem in archive_stems:
            super_targets[old_stem] = m.group(1).split("|", 1)[0].strip()

    for f, targets in state["links_out"].items():
        # Only look at surviving top-level files
        if f not in state["files"]:
            continue
        for t in targets:
            if t in state["stems"] or t in state["slug_set"]:
                continue
            # Dangling: target resolves to nothing
            if t not in archive_stems:
                # No clear ledger — record as a candidate; agent decides rewrite target
                # Default rewrite target = external-evals-ledger if it exists, else no-op flag
                ledger = "project_external_evals_ledger"
                if ledger in state["stems"]:
                    new_target = ledger
                else:
                    # Pick any surviving ledger; if none, mark as manual
                    ledgers = [s for s in sorted(state["stems"])
                               if "ledger" in s and s in state["files"]]
                    new_target = ledgers[0] if ledgers else None
                plan.append({
                    "action": "rewrite_wikilink",
                    "file": f,
                    "old": f"[[{t}]]",
                    "new": f"[[{new_target}]]" if new_target else None,
                    "reason": "dangling-target",
                })
            else:
                # Archived target — find replacement
                replacement = super_targets.get(t)
                if replacement and replacement in state["stems"]:
                    plan.append({
                        "action": "rewrite_wikilink",
                        "file": f,
                        "old": f"[[{t}]]",
                        "new": f"[[{replacement}]]",
                        "reason": "archived-with-supersedence",
                    })
                else:
                    # Archived but no clear supersedence — point to nearest ledger
                    ledger = "project_external_evals_ledger"
                    if ledger in state["stems"]:
                        new_target = ledger
                    else:
                        ledgers = [s for s in sorted(state["stems"])
                                   if "ledger" in s and s in state["files"]]
                        new_target = ledgers[0] if ledgers else None
                    plan.append({
                        "action": "rewrite_wikilink",
                        "file": f,
                        "old": f"[[{t}]]",
                        "new": f"[[{new_target}]]" if new_target else None,
                        "reason": "archived-no-supersedence",
                    })
    return plan


def atomic_write(path, content):
    """Write file atomically: stage at temp path, fsync, os.replace."""
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".memory-lint.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def apply_action_plan(state, plan):
    """Execute the plan: Class A moves, B/C rewrites. Returns (bytes_saved, applied_summary)."""
    applied = {"A": [], "B": [], "C": []}
    bytes_saved = 0
    d = state["d"]
    idx = state["idx"]
    new_idx = idx

    # Class A — moves + pointer stub rewrites
    archive_date = time.strftime(SUPERSEDED_ARCHIVE_DATE_FMT)
    archive_dir = os.path.join(d, "_archive", archive_date)
    for entry in plan["A"]:
        src = os.path.join(d, entry["from"])
        dst = os.path.join(archive_dir, entry["from"])
        os.makedirs(archive_dir, exist_ok=True)
        if os.path.exists(dst):
            # Skip if already archived at this date; record as a no-op
            applied["A"].append({"action": "move", "from": entry["from"], "to": dst, "skipped": "already-archived"})
            # Still rewrite the pointer
        else:
            try:
                shutil.move(src, dst)
                applied["A"].append({"action": "move", "from": entry["from"], "to": dst})
            except OSError:
                os.rename(src, dst)
                applied["A"].append({"action": "move", "from": entry["from"], "to": dst})
        # Rewrite pointer line to stub
        old_line = entry["old_pointer_line"]
        stem = entry["from"][:-3]
        new_line = STUB_TEMPLATE.format(stem, archive_date, entry["from"])
        if old_line in new_idx:
            new_idx = new_idx.replace(old_line, new_line)
            bytes_saved += len(old_line.encode("utf-8")) - len(new_line.encode("utf-8"))
        entry["pointer_rewrite"]["to"] = new_line

    # Class B — pointer rewrites
    for entry in plan["B"]:
        old_line = entry["from"]
        new_line = entry["to"]
        if old_line in new_idx:
            new_idx = new_idx.replace(old_line, new_line)
            bytes_saved += entry["delta_bytes"]
            applied["B"].append({"action": "rewrite_pointer", "from": old_line, "to": new_line})
        # Add a 1-line supersedes: note at top of topic file
        topic_path = os.path.join(d, entry["topic_file"])
        try:
            topic_txt = open(topic_path, encoding="utf-8").read()
            supersedes_line = f"\n<!-- memory-lint: pointer collapsed {time.strftime('%Y-%m-%d')} (A3 trim) — see MEMORY.md -->\n"
            if supersedes_line.strip() not in topic_txt:
                atomic_write(topic_path, topic_txt + supersedes_line)
        except OSError:
            pass

    # Class C — wikilink rewrites inside surviving files
    for entry in plan["C"]:
        if not entry.get("new"):
            continue  # manual resolution needed
        path = os.path.join(d, entry["file"])
        try:
            txt = open(path, encoding="utf-8").read()
        except OSError:
            continue
        if entry["old"] in txt:
            new_txt = txt.replace(entry["old"], entry["new"])
            bytes_saved += len(entry["old"].encode("utf-8")) - len(entry["new"].encode("utf-8"))
            applied["C"].append({"action": "rewrite_wikilink", "from": entry["old"], "to": entry["new"], "file": entry["file"]})
            atomic_write(path, new_txt)

    # Atomic MEMORY.md write (only if changed)
    if new_idx != idx:
        atomic_write(state["index_path"], new_idx)

    return bytes_saved, applied


def print_plan(state, plan, estimated_impact):
    idx_bytes = len(state["idx"].encode("utf-8"))
    idx_lines = state["idx"].count("\n") + 1
    pct_now = int(max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP) * 100)
    new_bytes = max(idx_bytes + estimated_impact, 0)
    pct_after = int(new_bytes / BYTE_CAP * 100)

    print(f"=== memory-lint --auto-archive --dry-run: {state['d']} ===")
    print()
    print(f"Class A (stale-superseded): {len(plan['A'])} files")
    for e in plan["A"]:
        print(f"  [move] {e['from']} → _archive/{e['to_archive_subdir']}/")
    if plan["A"]:
        print(f"  [rewrite] {len(plan['A'])} MEMORY.md pointer(s) → stub")
    print()
    print(f"Class B (near-budget-collapse): {len(plan['B'])} pointer(s)")
    for e in plan["B"]:
        print(f"  [rewrite] MEMORY.md: {e['topic_file']} ({e['from_chars']} → {e['to_chars']} chars, {e['delta_bytes']:+d}B)")
    print()
    print(f"Class C (dangling-link-rewrite): {len(plan['C'])}")
    for e in plan["C"]:
        if e.get("new"):
            print(f"  [rewrite] {e['file']}: {e['old']} → {e['new']} ({e['reason']})")
        else:
            print(f"  [manual] {e['file']}: {e['old']} (no ledger target found; needs human resolution)")
    print()
    print(f"Estimated impact: {estimated_impact:+d}B ({estimated_impact/1024:+.1f}KB)")
    print(f"  MEMORY.md {idx_bytes}B → {new_bytes}B ({pct_now}% → {pct_after}% of {BYTE_CAP}B cap)")


def run_action_mode(state, args):
    # Build plan
    plan_a = class_a_stale_superseded(state)
    plan_b = class_b_near_budget_collapse(state)
    plan_c = class_c_dangling_link_rewrite(state)
    plan = {"A": plan_a, "B": plan_b, "C": plan_c}
    estimated_impact = (
        sum(len(e["old_pointer_line"]) - len(STUB_TEMPLATE.format(e["from"][:-3], e["to_archive_subdir"], e["from"])) for e in plan_a)
        + sum(e["delta_bytes"] for e in plan_b)
        + sum(len(e["old"]) - len(e["new"]) for e in plan_c if e.get("new"))
    )

    dry_run = args.dry_run or not args.yes  # default ON
    apply_now = args.yes and not args.dry_run

    if args.json:
        a_list = []
        for e in plan_a:
            a_list.append({
                "action": "move",
                "from": e["from"],
                "to": f"_archive/{e['to_archive_subdir']}/{e['from']}",
                "pointer_rewrite": {
                    "from": e["old_pointer_line"],
                    "to": STUB_TEMPLATE.format(e["from"][:-3], e["to_archive_subdir"], e["from"]),
                },
            })
        b_list = []
        for e in plan_b:
            b_list.append({
                "action": "rewrite_pointer",
                "from": e["from"],
                "to": e["to"],
                "delta_bytes": e["delta_bytes"],
                "topic_file": e["topic_file"],
            })
        c_list = []
        for e in plan_c:
            c_list.append({
                "action": "rewrite_wikilink",
                "file": e["file"],
                "old": e["old"],
                "new": e.get("new"),
                "reason": e.get("reason"),
            })
        out = {
            "mode": "auto-archive-dry-run" if dry_run else "auto-archive-apply",
            "memory_dir": state["d"],
            "classes": {
                "A_stale_superseded": a_list,
                "B_near_budget_collapse": b_list,
                "C_dangling_link_rewrite": c_list,
            },
            "estimated_impact_bytes": estimated_impact,
            "apply_command": "memory-lint.py --auto-archive --yes",
        }
        print(json.dumps(out, indent=2))
        return 0 if dry_run else 0  # JSON mode is informational; exit 0

    print_plan(state, plan, estimated_impact)

    if not any(plan.values()):
        print()
        print("No actions proposed — store is clean (within action-mode heuristics).")
        if not apply_now:
            print("  (re-run with --yes to exit cleanly without re-checking)")
        return 0

    if dry_run and not apply_now:
        print()
        print("Apply? [y/N] (use --yes to skip)")
        if args.yes:
            apply_now = True
        else:
            try:
                ans = input("> ").strip().lower()
            except EOFError:
                ans = "n"
            apply_now = ans in ("y", "yes")

    if apply_now:
        # Concurrent-edit guard: compare mtime + first-200-chars hash of MEMORY.md
        idx_path = state["index_path"]
        mtime_before = os.path.getmtime(idx_path)
        hash_before = short_hash(state["idx"], 200)
        time.sleep(0.05)  # allow in-flight writes to land
        idx_now = open(idx_path, encoding="utf-8").read()
        mtime_now = os.path.getmtime(idx_path)
        hash_now = short_hash(idx_now, 200)
        if (mtime_now != mtime_before) or (hash_now != hash_before):
            print()
            print("ERROR: MEMORY.md was modified since lint scan (mtime/hash drift).")
            print("  Re-run lint to refresh state, then re-apply.")
            return 2

        bytes_saved, applied = apply_action_plan(state, plan)
        print()
        print(f"=== Applied ===")
        print(f"  A: {len(applied['A'])} file(s) moved to _archive/")
        print(f"  B: {len(applied['B'])} pointer(s) collapsed")
        print(f"  C: {len(applied['C'])} wikilink(s) rewritten")
        print(f"  Net: {bytes_saved:+d}B saved on MEMORY.md")
    return 0


# ── Entry point ───────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="memory-lint: detector + action mode")
    ap.add_argument("memory_dir", nargs="?", help="Memory store path (default: auto-derive from cwd)")
    ap.add_argument("--auto-archive", action="store_true",
                    help="Enter action mode (default: --dry-run ON, prints plan)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print plan, do not mutate (default ON with --auto-archive)")
    ap.add_argument("--yes", action="store_true",
                    help="Skip y/N confirm and apply mutations (implies --no-dry-run)")
    ap.add_argument("--json", action="store_true", help="Machine-readable output")
    args = ap.parse_args()

    d = memory_dir(args.memory_dir)
    if not os.path.isdir(d):
        sys.exit(f"FATAL: memory dir not found: {d}")
    state = collect_state(d)

    if args.auto_archive:
        sys.exit(run_action_mode(state, args))
    else:
        run_detector(state, args.json)


if __name__ == "__main__":
    main()
