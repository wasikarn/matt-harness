#!/usr/bin/env python3
"""memory-lint — health check for the file-based memory store.

Karpathy's llm-wiki "Lint" operation for our memory: catch broken cross-links,
orphaned facts, and index drift before they rot. Deterministic only — semantic
checks (contradictions, staleness) need an LLM pass, not this.

Usage:
  memory-lint.py [MEMORY_DIR]      # default: this repo's ~/.claude/projects/<enc>/memory

Checks:
  - dangling [[links]]   — target resolves to no memory (by filename stem or name: slug)
  - orphans              — a memory with no outbound and no inbound [[links]]
  - index drift          — MEMORY.md pointer ↔ file, both directions
Exit code = finding count (0 = clean). Fails loud if MEMORY_DIR is missing.
"""
import os
import re
import sys
import subprocess

WIKILINK = re.compile(r"\[\[([^\]]+)\]\]")
NAME_RE = re.compile(r"(?m)^name:\s*(.+)$")
POINTER_RE = re.compile(r"\]\(([^)]+\.md)\)")  # markdown link ](file.md), not prose "(x.md)"


def memory_dir():
    if len(sys.argv) > 1:
        return sys.argv[1]
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


def main():
    d = memory_dir()
    if not os.path.isdir(d):
        sys.exit(f"FATAL: memory dir not found: {d}")

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
    findings = []

    # 1. dangling links + collect inbound
    inbound = set()
    for f, targets in links_out.items():
        for t in targets:
            if t in stems or t in slug_set:
                inbound.add(t)
            else:
                findings.append(f"DANGLING: {f} → [[{t}]] (no such memory)")

    # Read index early — needed for orphan + drift checks
    index_path = os.path.join(d, "MEMORY.md")
    referenced = set()
    idx = ""
    pct = 0
    if os.path.isfile(index_path):
        idx = open(index_path, encoding="utf-8").read()
        referenced = set(POINTER_RE.findall(idx))
    else:
        findings.append("MISSING: MEMORY.md index not found")

    # 2. orphans (indexed in MEMORY.md but no wikilinks in or out)
    for f in files:
        has_out = bool(links_out[f])
        has_in = (f[:-3] in inbound) or (slugs[f] in inbound)
        if f in referenced and not has_out and not has_in:
            findings.append(f"ORPHAN: {f} (no [[links]] in or out)")

    # 3. index drift, both directions
    if idx:
        for f in files:                                   # file → pointer
            if f not in referenced:
                findings.append(f"UNINDEXED: {f} not pointed to from MEMORY.md")
        for ref in sorted(referenced):                    # pointer → file
            if ref not in files:
                findings.append(f"STALE POINTER: MEMORY.md → ({ref}) but file missing")
        # 4. load budget — only the first 200 lines OR 25KB of MEMORY.md (whichever
        # first) load into a session; entries past that silently never load.
        LINE_CAP, BYTE_CAP = 200, 25 * 1024
        idx_bytes, idx_lines = len(idx.encode("utf-8")), idx.count("\n") + 1
        pct = int(max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP) * 100)
        if idx_lines > LINE_CAP or idx_bytes > BYTE_CAP:
            findings.append(f"OVER-BUDGET: MEMORY.md {idx_lines}L/{idx_bytes}B exceeds the 200-line/25KB load cap — trailing index entries WON'T load; fold closed entries into a topic-file/ledger + archive (only MEMORY.md loads — splitting into multiple indexes won't help)")
        elif pct >= 80:
            findings.append(f"NEAR-BUDGET: MEMORY.md at {pct}% of the 200-line/25KB load cap ({idx_lines}L, {idx_bytes}B) — trim verbose pointers, or fold closed entries into a topic-file/ledger + archive (only MEMORY.md loads — don't split into multiple indexes)")

    # report
    total_links = sum(len(v) for v in links_out.values())
    print(f"=== memory-lint: {d} ===")
    print(f"memories: {len(files)} | links: {total_links} | "
          f"linked: {len([f for f in files if links_out[f] or f[:-3] in inbound or slugs[f] in inbound])} | "
          f"MEMORY.md: {pct}% of load cap | findings: {len(findings)}")
    print()
    for line in findings:
        print(f"  {line}")
    if not findings:
        print("  clean — no dangling links, orphans, or index drift")
    print(f"\nExit: {len(findings)}")
    sys.exit(len(findings))


if __name__ == "__main__":
    main()
