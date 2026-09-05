#!/usr/bin/env python3
"""memory-lint — health check + action mode for the file-based memory store.

Karpathy's llm-wiki "Lint" operation for our memory: catch broken cross-links,
orphaned facts, and index drift before they rot. Deterministic only.

Usage:
  memory-lint.py [MEMORY_DIR]                     # default detector mode
  memory-lint.py [MEMORY_DIR] --auto-archive      # enter action mode (default: --dry-run)
  memory-lint.py [MEMORY_DIR] --auto-archive --dry-run
  memory-lint.py [MEMORY_DIR] --auto-archive --yes  # apply (no confirm prompt)
  memory-lint.py [MEMORY_DIR] --json              # machine-readable output

Detector checks (default mode):
  - dangling links       — [[wikilink]] or same-store markdown [text](file.md) target
                            resolves to no memory (by filename stem or name: slug);
                            suggests a close-name match (difflib, cutoff 0.6) if one exists.
                            Code-span-masked first (backtick prose quoting link syntax as
                            an example isn't a real cross-reference); a markdown target
                            containing "/" is treated as an external-repo citation, not a
                            same-store link, since memories live flat.
  - orphans               — a memory with no outbound and no inbound links (either syntax)
  - index drift           — MEMORY.md pointer ↔ file, both directions; UNINDEXED only
                            fires for a file that is also unreachable via [[links]]
  - load budget           — 200-line / 25KB cap on MEMORY.md
Exit code = finding count (0 = clean). Fails loud if MEMORY_DIR is missing.

Action mode (--auto-archive) — applies the A3 trim rubric (memory/project_memory_trim_session_2026_06_04.md):
  Class A — stale-superseded:   MEMORY.md pointer has **SUPERSEDED** marker + topic has 0 surviving inbound
  Class B — near-budget-collapse: pointer ≥250 chars + topic >5KB + pointer carries detail
  Class C — dangling-link-rewrite: surviving file has [[wikilink]] that resolves to nothing or to _archive/
  Class D — count-fold: fallback valve for A/B/C = 0 candidates but index still >=80% of cap
                         (this store's actual growth shape: many small terse entries, not a
                         few verbose outliers — confirmed empirically 2026-08-07, A/B found 0
                         candidates at 84% of cap). Deindexes (never deletes) the OLDEST pointer
                         lines by topic-file mtime, any type, until back under 65% of cap.
                         Reachability-guarded (2026-09-01): a candidate is skipped if deindexing
                         it would drop it (or anything only reachable through it) out of the
                         store's reachable set.

All mutations use `mv` (never `rm`) or deindex-only (Class D); confirm prompt is shown by
default; --yes skips confirm.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

WIKILINK = re.compile(r"\[\[([^\]]+)\]\]")
NAME_RE = re.compile(r"(?m)^name:\s*(.+)$")
POINTER_RE = re.compile(r"\]\(([^)]+\.md)\)")  # markdown link ](file.md), not prose "(x.md)"
FENCED_CODE_RE = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
SUPERSEDED_RE = re.compile(r"\*\*SUPERSEDED[^*]*\*\*\s*by\s*\[\[([^\]]+)\]\]")
POINTER_LINE_RE = re.compile(r"^- \[[^\]]+\]\(([^)]+\.md)\)(.*)$", re.MULTILINE)

LINE_CAP = 200
BYTE_CAP = 25 * 1024
FOLD_TRIGGER_PCT = 0.80  # matches the existing NEAR-BUDGET trigger (class_b uses the same cut)
FOLD_TARGET_PCT = 0.65   # Class D folds until back under this fraction of the caps
SUPERSEDED_ARCHIVE_DATE_FMT = "%Y-%m-%d"
STUB_TEMPLATE = "- [{}](_archive/{}/{}) — archived on-demand"
# The link target is the archived path so future grep/audit can find the file.
# `memory-lint` will report it as ORPHAN (no top-level wikilink inbound) but the
# markdown link itself resolves. Class A's whole point is "no surviving inbound"
# anyway — the user is explicitly saying "this entry is closed, browse on-demand."


def _auto_memory_directory_setting():
    # memory.md:362 — `autoMemoryDirectory` in settings.json overrides the
    # whole storage location. Read from any scope; project scope wins over
    # user scope, matching Claude Code's own most-specific-wins precedence
    # (same simplification harness-audit check 43 already makes — full
    # local/policy/--settings scopes aren't relevant to this CLI's own usage).
    for path in (
        os.path.join(".claude", "settings.local.json"),
        os.path.join(".claude", "settings.json"),
        os.path.expanduser("~/.claude/settings.json"),
    ):
        try:
            with open(path) as f:
                value = json.load(f).get("autoMemoryDirectory")
        except (OSError, json.JSONDecodeError):
            continue
        if value:
            return value
    return None


def memory_dir(positional):
    if positional:
        return positional
    auto_dir = _auto_memory_directory_setting()
    if auto_dir:
        return os.path.expanduser(auto_dir)
    # Match Claude Code's own auto-memory keying, not raw cwd: the official
    # doc (code.claude.com/docs/en/memory.md:358, confirmed 2026-08-20) states
    # the <project> path is "derived from the git repository, so all worktrees
    # and subdirectories within the same repo share one auto memory directory."
    # A prior version of this function keyed by raw os.getcwd() instead,
    # reasoning it had to "agree with skills/meta/learn/scripts/find-transcript.sh"
    # — but that script keys *session transcripts*, a separate CC mechanism
    # with its own cwd-based rule per the same doc; the two were wrongly
    # assumed to need one shared convention. Falls back to raw cwd outside a
    # git repo, matching the doc's "Outside a git repo, the project root is
    # used instead."
    # CLAUDE_CODE_PROJECT_DIR_NAME (env-vars.md:326, requires CC v2.1.234+,
    # corrected 2026-08-20) overrides the <project> name component, but only
    # "together with CLAUDE_CONFIG_DIR" — Claude Code "ignores this variable
    # when CLAUDE_CONFIG_DIR is unset". Honoring it alone (the prior bug here)
    # points memory-lint at a directory Claude Code itself isn't using.
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    projects_root = os.path.expanduser(config_dir) if config_dir else os.path.expanduser("~/.claude")
    projects_root = os.path.join(projects_root, "projects")
    project_dir_name = os.environ.get("CLAUDE_CODE_PROJECT_DIR_NAME")
    if config_dir and project_dir_name:
        enc = project_dir_name
    else:
        try:
            root = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True, text=True, check=True,
            ).stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            root = os.getcwd()
        enc = root.replace("/", "-")
    return os.path.join(projects_root, enc, "memory")


FRONTMATTER_BLOCK_RE = re.compile(r"\A---\n.*?\n---\n?", re.DOTALL)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def measured_index(idx):
    """Byte/line count of MEMORY.md the way Claude Code's own load-budget check
    measures it: YAML frontmatter and block-level HTML comments stripped before
    counting (code.claude.com/docs/en/memory.md:394, confirmed 2026-08-20).
    MEMORY.md carries no frontmatter today, so that half is a no-op in
    practice — kept for correctness if that ever changes, and so a maintainer
    wrapping a trimmed section in `<!-- -->` (Tier 3, official-docs audit
    2026-08-20) doesn't get double-counted against the cap that move exists to
    relieve."""
    stripped = FRONTMATTER_BLOCK_RE.sub("", idx, count=1)
    stripped = HTML_COMMENT_RE.sub("", stripped)
    return len(stripped.encode("utf-8")), stripped.count("\n") + 1


def link_target(raw):
    # Strip Obsidian alias "[[target|display]]" and a trailing .md.
    t = raw.split("|", 1)[0].strip()
    return t[:-3] if t.endswith(".md") else t


def strip_code_spans(text):
    """Mask fenced/inline code spans before link-scanning body text.

    A memory can legitimately quote link syntax as an example (prose describing
    another repo's `[[link]]` or `[x](y.md)` bug), not a real cross-reference.
    Confirmed live in this store twice: a backtick-wrapped `[[branching-model]]`
    and a backtick-wrapped `[reference.md](reference.md)` describing a fix made
    in a different repo. Length-preserving space substitution keeps offsets
    stable for any future line-based tooling.
    """
    text = FENCED_CODE_RE.sub(lambda m: " " * len(m.group(0)), text)
    return INLINE_CODE_RE.sub(lambda m: " " * len(m.group(0)), text)


def md_link_target(raw):
    """Markdown-link target → bare stem, or None if not a same-store cross-reference.

    This store's memories live flat (no subdirectories except _archive/), so a
    target containing "/" is a path into another repo (e.g. a doc cited as
    prose), not a same-store link — treating it as one would misfire DANGLING
    on legitimate external citations.
    """
    if "/" in raw:
        return None
    return raw[:-3] if raw.endswith(".md") else raw


# ── Detector mode ─────────────────────────────────────────────────────────

def compute_reachable(files, slugs, links_out, referenced):
    """Stems reachable from `referenced` roots via outbound [[links]]/pointers —
    the same BFS detector_findings' UNINDEXED check uses, factored out so
    class_d_count_fold can reuse it as a safety filter (2026-09-01 deep-audit:
    the original Class D picked deindex candidates by mtime alone with no
    reachability check, so on the real store it proposed 17/24 candidates that
    would have recreated the exact UNINDEXED finding this whole tool exists to
    relieve pressure on)."""
    target_stem = {f[:-3]: f[:-3] for f in files}
    for f in files:
        s = slugs[f]
        if s and s not in target_stem:
            target_stem[s] = f[:-3]
    reachable = {ref[:-3] for ref in referenced if ref in files}
    frontier = list(reachable)
    while frontier:
        cur = frontier.pop()
        for t in links_out.get(cur + ".md", []):
            r = target_stem.get(t)
            if r is not None and r not in reachable:
                reachable.add(r)
                frontier.append(r)
    return reachable


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
        scan_txt = strip_code_spans(txt)
        wiki_targets = [link_target(x) for x in WIKILINK.findall(scan_txt)]
        md_targets = [t for t in (md_link_target(x) for x in POINTER_RE.findall(scan_txt)) if t]
        links_out[f] = wiki_targets + md_targets

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
    candidates = state["stems"] | state["slug_set"]
    for f, targets in links_out.items():
        for t in targets:
            if t not in state["stems"] and t not in state["slug_set"]:
                match = difflib.get_close_matches(t, candidates, n=1, cutoff=0.6)
                hint = f" — did you mean [[{match[0]}]]?" if match else ""
                findings.append(f"DANGLING: {f} → {t} (no such memory){hint}")

    if not os.path.isfile(idx_path):
        findings.append("MISSING: MEMORY.md index not found")
    else:
        # 2. orphans
        for f in files:
            has_out = bool(links_out[f])
            has_in = (f[:-3] in inbound) or (slugs[f] in inbound)
            if f in referenced and not has_out and not has_in:
                findings.append(f"ORPHAN: {f} (no links in or out)")

        # 3. index drift — UNINDEXED is reachability-aware: a file with no
        # MEMORY.md pointer but reachable from an indexed root through
        # [[links]] is the fold rule's documented Context layer (Index →
        # Context → Detail, per MEMORY.md's own header), not rot. Only a file
        # that is unindexed AND unreachable from the index fires.
        reachable = compute_reachable(files, slugs, links_out, referenced)
        for f in files:
            if f not in referenced and f[:-3] not in reachable:
                findings.append(f"UNINDEXED: {f} not pointed to from MEMORY.md and not [[link]]-reachable from any indexed memory")
        for ref in sorted(referenced):
            if ref not in files:
                findings.append(f"STALE POINTER: MEMORY.md → ({ref}) but file missing")

        # 4. load budget
        idx_bytes, idx_lines = measured_index(idx)
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

    idx_bytes, idx_lines = measured_index(state["idx"])
    pct = int(max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP) * 100)
    print(f"=== memory-lint: {state['d']} ===")
    print(f"memories: {len(state['files'])} | links: {total_links} | "
          f"linked: {linked_count} | MEMORY.md: {pct}% of load cap | "
          f"findings: {len(findings)}")
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
        link_m = POINTER_RE.search(line)
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
        })
    return plan


def class_b_near_budget_collapse(state):
    """Class B: longest pointer-lines (>=250 chars) where topic is >5KB and pointer is >= 1.2x first paragraph."""
    plan = []
    if not state["idx"]:
        return plan
    # Match the 200L/25KB cap threshold
    idx_bytes, idx_lines = measured_index(state["idx"])
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


def _pick_ledger_target(state):
    """Default rewrite target for a link with no clear resolution: the
    external-evals ledger if it survives, else any surviving file with
    'ledger' in its stem, else None (caller falls back to manual)."""
    ledger = "project_external_evals_ledger"
    if ledger in state["stems"]:
        return ledger
    ledgers = [s for s in sorted(state["stems"])
               if "ledger" in s and s in state["files"]]
    return ledgers[0] if ledgers else None


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
        pm = POINTER_RE.search(line)
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
                new_target = _pick_ledger_target(state)
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
                    new_target = _pick_ledger_target(state)
                    plan.append({
                        "action": "rewrite_wikilink",
                        "file": f,
                        "old": f"[[{t}]]",
                        "new": f"[[{new_target}]]" if new_target else None,
                        "reason": "archived-no-supersedence",
                    })
    return plan


def class_d_count_fold(state, exclude_files):
    """Class D: pure count-pressure fallback valve. Only produces entries when the
    index is still >= FOLD_TRIGGER_PCT of cap — A/B/C's per-entry heuristics don't
    catch pure entry-count accumulation (many small terse pointer lines, no single
    verbose outlier to collapse). Deindexes (never deletes) the OLDEST pointer
    lines by topic-file mtime, any type, until back under FOLD_TARGET_PCT of cap —
    but only candidates that stay reachable afterward (compute_reachable, same BFS
    the UNINDEXED detector uses): a candidate whose deindex would drop it, or
    anything only reachable through it, out of the reachable set is skipped, not
    proposed. Without this guard the mtime-only pick has no way to tell a file with
    an alternate [[link]] path back to the index apart from one with none — found
    2026-09-01 via deep-audit: 17 of 24 real candidates on this store had zero
    alternate path and would have recreated the exact UNINDEXED finding this valve
    exists to relieve pressure on. exclude_files = filenames already claimed by
    plan A/B, so nothing double-counts. Self-contained byte accounting — does not
    participate in the shared estimated_impact sum used by A/B/C, which mixes
    savings-sign conventions across classes; D reports its own delta separately."""
    plan = []
    idx_bytes, idx_lines = measured_index(state["idx"])
    pct = max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP)
    if pct < FOLD_TRIGGER_PCT:
        return plan

    target_bytes = int(BYTE_CAP * FOLD_TARGET_PCT)
    target_lines = int(LINE_CAP * FOLD_TARGET_PCT)
    if idx_bytes <= target_bytes and idx_lines <= target_lines:
        return plan

    candidates = []
    for m in POINTER_LINE_RE.finditer(state["idx"]):
        fname = m.group(1)
        full_line = m.group(0)
        if fname in exclude_files or fname not in state["files"]:
            continue
        try:
            mtime = os.path.getmtime(os.path.join(state["d"], fname))
        except OSError:
            continue
        candidates.append((mtime, fname, full_line))
    candidates.sort(key=lambda c: c[0])  # oldest first

    # Safety invariant: nothing reachable today may become unreachable. Checked
    # cumulatively against the ORIGINAL full baseline as each candidate is
    # tentatively accepted, so an interaction between two accepted candidates
    # (one only reachable through the other) is caught too, not just each in
    # isolation.
    still_referenced = set(state["referenced"])
    baseline_reachable = compute_reachable(state["files"], state["slugs"], state["links_out"], still_referenced)

    remaining_bytes = idx_bytes
    remaining_lines = idx_lines
    for _mtime, fname, full_line in candidates:
        if remaining_bytes <= target_bytes and remaining_lines <= target_lines:
            break
        trial_referenced = still_referenced - {fname}
        trial_reachable = compute_reachable(state["files"], state["slugs"], state["links_out"], trial_referenced)
        if trial_reachable != baseline_reachable:
            continue  # would orphan fname (or something only reachable through it) — skip, don't propose
        still_referenced = trial_referenced
        remaining_bytes -= len(full_line.encode("utf-8")) + 1  # +1 for the newline
        remaining_lines -= 1
        plan.append({"action": "deindex", "file": fname, "old_pointer_line": full_line})
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
    """Execute the plan: Class A moves, B/C rewrites, D deindexes. Returns (bytes_saved, applied_summary)."""
    applied = {"A": [], "B": [], "C": [], "D": []}
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

    # Class D — pure deindex (remove pointer line only, backing file untouched)
    for entry in plan.get("D", []):
        old_line = entry["old_pointer_line"]
        if old_line + "\n" in new_idx:
            new_idx = new_idx.replace(old_line + "\n", "", 1)
            bytes_saved += len(old_line.encode("utf-8")) + 1
            applied["D"].append({"action": "deindex", "file": entry["file"]})
        elif old_line in new_idx:
            new_idx = new_idx.replace(old_line, "", 1)
            bytes_saved += len(old_line.encode("utf-8"))
            applied["D"].append({"action": "deindex", "file": entry["file"]})

    # Atomic MEMORY.md write (only if changed)
    if new_idx != idx:
        atomic_write(state["index_path"], new_idx)

    return bytes_saved, applied


def print_plan(state, plan, estimated_impact):
    idx_bytes, idx_lines = measured_index(state["idx"])
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
    plan_d = plan.get("D", [])
    d_bytes_saved = sum(len(e["old_pointer_line"].encode("utf-8")) + 1 for e in plan_d)
    print(f"Class D (count-fold): {len(plan_d)} pointer(s)")
    for e in plan_d:
        print(f"  [deindex] {e['file']} (backing file kept, just unindexed — still in git history + qmd)")
    if plan_d:
        print(f"  Class D savings (reported separately — not mixed into the estimate below): -{d_bytes_saved}B")
    print()
    print(f"Estimated impact (A+B+C only): {estimated_impact:+d}B ({estimated_impact/1024:+.1f}KB)")
    print(f"  MEMORY.md {idx_bytes}B → {new_bytes}B ({pct_now}% → {pct_after}% of {BYTE_CAP}B cap, before Class D)")


def run_action_mode(state, args):
    # Build plan
    plan_a = class_a_stale_superseded(state)
    plan_b = class_b_near_budget_collapse(state)
    plan_c = class_c_dangling_link_rewrite(state)
    exclude_files = {e["from"] for e in plan_a} | {e["topic_file"] for e in plan_b}
    plan_d = class_d_count_fold(state, exclude_files)
    plan = {"A": plan_a, "B": plan_b, "C": plan_c, "D": plan_d}
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
        d_list = [{"action": "deindex", "file": e["file"]} for e in plan_d]
        out = {
            "mode": "auto-archive-dry-run" if dry_run else "auto-archive-apply",
            "memory_dir": state["d"],
            "classes": {
                "A_stale_superseded": a_list,
                "B_near_budget_collapse": b_list,
                "C_dangling_link_rewrite": c_list,
                "D_count_fold": d_list,
            },
            "estimated_impact_bytes": estimated_impact,
            "estimated_impact_bytes_note": "A+B+C only — Class D reported separately",
            "d_count_fold_bytes_saved": sum(len(e["old_pointer_line"].encode("utf-8")) + 1 for e in plan_d),
            "apply_command": "memory-lint.py --auto-archive --yes",
        }
        print(json.dumps(out, indent=2))
        return 0  # JSON mode is informational; exit 0 regardless of dry_run

    print_plan(state, plan, estimated_impact)

    if not any(plan.values()):
        print()
        print("No actions proposed — store is clean (within action-mode heuristics).")
        if not apply_now:
            print("  (re-run with --yes to exit cleanly without re-checking)")
        return 0

    # An explicit --dry-run is a hard stop: print the plan and exit, never apply
    # or prompt. --dry-run wins over --yes (safety-flag precedence) — otherwise
    # `--auto-archive --dry-run --yes` silently applied, defeating the preview
    # SKILL.md documents --dry-run for. The default (bare --auto-archive) keeps
    # the prompt below; --yes alone still applies directly (dry_run is False).
    if args.dry_run:
        return 0

    if dry_run and not apply_now:
        print()
        print("Apply? [y/N] (use --yes to skip)")
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
        print(f"  D: {len(applied['D'])} pointer(s) deindexed (backing files kept)")
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
                    help="Skip y/N confirm and apply mutations (an explicit --dry-run overrides this)")
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
