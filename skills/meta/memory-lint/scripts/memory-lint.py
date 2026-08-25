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
  memory-lint.py [MEMORY_DIR] --classify-unindexed  # fold-vs-forgotten triage, see below
  memory-lint.py [MEMORY_DIR] --find-patterns       # recurrence clusters (shared [[link]] referents)

Detector checks (default mode):
  - dangling links       — [[wikilink]] or same-store markdown [text](file.md) target
                            resolves to no memory (by filename stem or name: slug);
                            suggests a close-name match (difflib, cutoff 0.6) if one exists.
                            Code-span-masked first (backtick prose quoting link syntax as
                            an example isn't a real cross-reference); a markdown target
                            containing "/" is treated as an external-repo citation, not a
                            same-store link, since memories live flat.
  - orphans               — a memory with no outbound and no inbound links (either syntax)
  - index drift           — MEMORY.md pointer ↔ file, both directions
  - load budget           — 200-line / 25KB cap on MEMORY.md
Exit code = finding count (0 = clean). Fails loud if MEMORY_DIR is missing.

Staleness (advisory, printed separately — does NOT count toward exit code):
  - a memory file's mtime is the only durable signal this store has for "when was
    this claim last touched" (no per-memory last-verified field exists or is worth
    the migration cost — see skills/meta/memory-lint/SKILL.md). A file untouched past
    --stale-days is surfaced for a human to re-check, not treated as a defect —
    an old memory can still be true. Files already marked **SUPERSEDED** in
    MEMORY.md are excluded (already flagged through a different signal).

Fold-vs-forgotten triage (--classify-unindexed, manual, read-only):
  UNINDEXED (a file with no MEMORY.md pointer) is two different states wearing one label: an
  authoring oversight, or the fold rule's own documented correct end-state ("stop indexing it,
  don't delete it"). Blind-appending every UNINDEXED file back into MEMORY.md would silently
  undo real prior fold decisions. This mode classifies instead of fixing, using git history on
  MEMORY.md (see docs/research/claude-mem-architecture-study-2026-08-07.md, Adopt-1 — the first
  draft of this feature proposed the blind-append version and was caught by adversarial review
  before shipping):
    folded-confirmed        — a real `](file.md)` pointer link to this file was removed by a
                               commit to MEMORY.md (single-pass diff scan across MEMORY.md's
                               whole history, not `git log -S<filename>` substring search —
                               -S matches a bare filename MENTION in unrelated prose too, which
                               would misclassify an edit to that prose as a fold; see
                               _git_fold_commits()'s own docstring). NOT a candidate to re-add.
    never-indexed            — file is absent from the tree at the memory dir's first commit
                               (its whole life is inside tracked history) and no fold commit was
                               found — a real candidate to add. Tree membership at that commit,
                               not mtime — mtime resets on every edit and would misclassify a
                               fixed pre-baseline file back to "never-indexed" the next time
                               anyone touches it.
    ambiguous-pre-baseline   — file is present in the tree at the memory dir's first commit, so
                               it predates tracking; git has no opinion either way (a pre-baseline
                               fold looks identical to "never indexed" from git alone). Needs a
                               human to read the content.
    no-git-history           — the memory dir isn't a git repo (or has 0 commits) — same
                               ambiguity as ambiguous-pre-baseline, for every file, always.
    git-query-failed         — the dir IS a git repo, but a git call failed mid-scan (lock
                               contention, timeout, corrupted history) — can't safely tell fold
                               vs. forgotten, needs a manual read same as the two buckets above.
  All 3 real git calls (one log -p over MEMORY.md's history, one first-commit lookup, one
  tree-membership check) run exactly once per --classify-unindexed invocation, fixed regardless
  of UNINDEXED count — not once per file (measured: 744ms -> ~85ms on this store, v0.68.229).
  Never auto-appends anything to MEMORY.md — output is a classified list for a human to triage.

Action mode (--auto-archive) — applies the A3 trim rubric (memory/project_memory_trim_session_2026_06_04.md):
  Class A — stale-superseded:   MEMORY.md pointer has **SUPERSEDED** marker + topic has 0 surviving inbound
  Class B — near-budget-collapse: pointer ≥250 chars + topic >5KB + pointer carries detail
  Class C — dangling-link-rewrite: surviving file has [[wikilink]] that resolves to nothing or to _archive/
  Class D — count-fold: fallback valve for A/B/C = 0 candidates but index still >=80% of cap
                         (this store's actual growth shape: many small terse entries, not a
                         few verbose outliers — confirmed empirically 2026-08-07, A/B found 0
                         candidates at 84% of cap). Deindexes (never deletes) the OLDEST pointer
                         lines by topic-file mtime, any type, until back under 65% of cap. Not
                         type-restricted — project-only would have covered ~half the bytes a
                         real fold needed; the existing dry-run/--yes confirm gate is the review
                         point, not a type filter.

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
from datetime import datetime

WIKILINK = re.compile(r"\[\[([^\]]+)\]\]")
NAME_RE = re.compile(r"(?m)^name:\s*(.+)$")
POINTER_RE = re.compile(r"\]\(([^)]+\.md)\)")  # markdown link ](file.md), not prose "(x.md)"
FENCED_CODE_RE = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
SUPERSEDED_RE = re.compile(r"\*\*SUPERSEDED[^*]*\*\*\s*by\s*\[\[([^\]]+)\]\]")
POINTER_LINE_RE = re.compile(r"^- \[[^\]]+\]\(([^)]+\.md)\)(.*)$", re.MULTILINE)
TYPE_RE = re.compile(r"(?m)^\s*type:\s*(\w+)")
DESCRIPTION_RE = re.compile(r'(?m)^description:\s*"?(.*?)"?\s*$')
WHY_RE = re.compile(r"\*\*Why:\*\*")
HOW_RE = re.compile(r"\*\*How to apply:\*\*")
TEMPLATE_SCOPED_TYPES = ("feedback", "project")
STOPWORDS = {
    "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "is", "was",
    "are", "be", "this", "that", "with", "by", "from", "as", "it", "its",
    "not", "never", "always", "but", "if", "when", "than", "then", "so",
}

LINE_CAP = 200
BYTE_CAP = 25 * 1024
STALE_DAYS_DEFAULT = 90
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

    context_layer = 0

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
        # Context → Detail, per MEMORY.md's own header), not rot — counted
        # as context_layer (advisory), never a finding. Only a file that is
        # unindexed AND unreachable from the index fires.
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
        for f in files:
            if f not in referenced:
                if f[:-3] in reachable:
                    context_layer += 1
                else:
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
    return findings, total_links, linked_count, context_layer


def superseded_stems(state):
    """Filenames whose MEMORY.md pointer line already carries a **SUPERSEDED** marker —
    excluded from staleness since they're already flagged through a different signal."""
    stems = set()
    for line in state["idx"].splitlines():
        if not SUPERSEDED_RE.search(line):
            continue
        m = POINTER_RE.search(line)
        if m:
            stems.add(m.group(1)[:-3])
    return stems


MODIFIED_FIELD_RE = re.compile(r"(?m)^modified:\s*(\S+)")


def _modified_timestamp(text):
    """Parse the native `modified:` frontmatter field Claude Code itself writes
    (v2.1.214+, code.claude.com/docs/en/memory.md:404, confirmed 2026-08-20) —
    stamped whenever CC writes to a memory file that already has frontmatter.
    Returns a unix timestamp, or None if the field is absent or unparseable."""
    m = MODIFIED_FIELD_RE.search(text)
    if not m:
        return None
    try:
        return datetime.fromisoformat(m.group(1).strip().replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def staleness_findings(state, stale_days):
    """Staleness — advisory only, never counted toward exit code.

    Prefers the native `modified:` frontmatter timestamp when present, falling
    back to filesystem mtime when it isn't. mtime alone is a weaker signal than
    it looks for this store specifically: the store is a git repo that gets
    cloned across machines by design (memory `memory-store-autopush-hook-
    intentional`), and a checkout resets mtimes to checkout time regardless of
    when a memory was actually last touched — so mtime can measure a git
    operation instead of an edit. `modified:` doesn't have that failure mode.
    Still advisory either way: an old memory isn't wrong by default, just
    worth a human glance, and there's no per-memory last-verified field
    distinct from last-touched (adding one means migrating every existing
    file — not worth it for a lint-surface add-on).
    """
    now = time.time()
    skip = superseded_stems(state)
    stale = []
    for f in sorted(state["files"]):
        if f[:-3] in skip:
            continue
        path = os.path.join(state["d"], f)
        try:
            text = open(path, encoding="utf-8").read()
        except OSError:
            continue
        ts = _modified_timestamp(text)
        if ts is None:
            try:
                ts = os.path.getmtime(path)
            except OSError:
                continue
        age_days = int((now - ts) / 86400)
        if age_days >= stale_days:
            stale.append({"file": f, "age_days": age_days})
    stale.sort(key=lambda x: -x["age_days"])
    return stale


def template_compliance_findings(state):
    """Advisory only, always computed, never counted toward exit code — same
    tier as staleness_findings above.

    feedback/project memories are documented (this SKILL.md's own authoring
    format) to carry **Why:** and **How to apply:** — the two fields that
    separate a fact/skill (judge by utility, not size) from a raw log line.
    Missing them doesn't make a memory wrong, just undercooked; this surfaces
    a count + the worst offenders (neither field present) for a human to fix
    opportunistically. Deliberately never gates: a presence-only check has
    twice trained authors to paste filler elsewhere in this fleet (retired
    `type: command`; near-miss on `disable-model-invocation-reason`) —
    visibility is the whole point here, not enforcement.
    """
    d = state["d"]
    scoped_total = 0
    missing_why = missing_how = 0
    missing_both = []
    for f in sorted(state["files"]):
        txt = open(os.path.join(d, f), encoding="utf-8").read()
        frontmatter = txt.split("---", 2)[1] if txt.startswith("---") else ""
        m = TYPE_RE.search(frontmatter)
        if not m or m.group(1) not in TEMPLATE_SCOPED_TYPES:
            continue
        scoped_total += 1
        has_why, has_how = bool(WHY_RE.search(txt)), bool(HOW_RE.search(txt))
        if not has_why:
            missing_why += 1
        if not has_how:
            missing_how += 1
        if not has_why and not has_how:
            missing_both.append(f)
    return {
        "scoped_total": scoped_total,
        "missing_why": missing_why,
        "missing_how": missing_how,
        "missing_both": missing_both,
    }


def _tokenize(text):
    return {w for w in re.findall(r"[a-z0-9]+", text.lower())
            if w not in STOPWORDS and len(w) > 2}


def contradiction_candidates(state, min_overlap):
    """Deterministic candidate-pair pre-filter for --find-contradictions.

    NEVER auto-resolves — only surfaces candidates for a human (or a
    separately-invoked, adversarial LLM pass) to review. An extraction
    pipeline that both writes facts and unilaterally invalidates them is a
    maker-grades-itself failure (see
    docs/research/agent-memory-engineering-2026-08-07.md Part 2). This is a
    one-off, run-by-hand tool, not a scheduled job — a heuristic pre-filter
    over a handful of notes will both over- and under-match, which is exactly
    why it stays manual until a hand-run proves the signal is real.

    Signal: same `type:` frontmatter AND filename+description token-overlap
    ratio >= min_overlap. A shared outbound [[link]] is reported alongside a
    qualifying pair as context, never as an independent trigger — the first
    real hand-run against this store (2026-08-07) found "shares at least one
    link" alone produces 296 near-useless candidates on a 178-file store
    (most driven by both memories citing one common well-known prior finding,
    e.g. verify-adversarially-before-nothing), while token-overlap alone at
    the same threshold gives 4. That's the evidence this threshold and
    signal choice are built on, not a guess.
    """
    d = state["d"]
    files = sorted(state["files"])
    meta = {}
    for f in files:
        txt = open(os.path.join(d, f), encoding="utf-8").read()
        frontmatter = txt.split("---", 2)[1] if txt.startswith("---") else ""
        tm = TYPE_RE.search(frontmatter)
        dm = DESCRIPTION_RE.search(frontmatter)
        meta[f] = {
            "type": tm.group(1) if tm else None,
            "tokens": _tokenize(f[:-3].replace("-", " ") + " " + (dm.group(1) if dm else "")),
            "links": set(state["links_out"].get(f, [])),
        }

    candidates = []
    for i, a in enumerate(files):
        for b in files[i + 1:]:
            ma, mb = meta[a], meta[b]
            if not ma["type"] or ma["type"] != mb["type"]:
                continue
            union = ma["tokens"] | mb["tokens"]
            overlap = len(ma["tokens"] & mb["tokens"]) / len(union) if union else 0.0
            if overlap >= min_overlap:
                shared_links = sorted(ma["links"] & mb["links"])
                candidates.append({
                    "a": a, "b": b, "type": ma["type"],
                    "token_overlap": round(overlap, 2),
                    "shared_links": shared_links,
                })
    candidates.sort(key=lambda c: -c["token_overlap"])
    return candidates


def run_find_contradictions(state, as_json, min_overlap):
    candidates = contradiction_candidates(state, min_overlap)
    if as_json:
        print(json.dumps({
            "mode": "find-contradictions",
            "memory_dir": state["d"],
            "min_overlap": min_overlap,
            "candidates": candidates,
        }, indent=2))
        return 0

    print(f"=== memory-lint --find-contradictions: {state['d']} ===")
    print(f"min-overlap: {min_overlap} | candidate pairs: {len(candidates)}")
    print("Advisory pre-filter only — NOT a contradiction verdict. Read each pair by hand;")
    print("never auto-merge (two memories can both be right in different contexts).")
    print()
    if not candidates:
        print("  none — no same-type pairs cleared the overlap/shared-link threshold")
    for c in candidates:
        link_note = f", shared links: {', '.join(c['shared_links'])}" if c["shared_links"] else ""
        print(f"  [{c['type']}] {c['a']}  <->  {c['b']}  (overlap: {c['token_overlap']}{link_note})")
    return 0


def pattern_clusters(state, min_cluster, max_cluster=0):
    """Deterministic recurrence-cluster surfacer for --find-patterns.

    Builds a file<->file graph where two memories share an edge iff they both
    link the same RESOLVABLE [[target]] (target in stems or slug_set — dangling
    links are skipped so noise doesn't seed clusters), then returns connected
    components of size >= min_cluster (and <= max_cluster when max_cluster > 0).
    Pure graph topology, no embeddings, no LLM — the same signature ->
    episode-graph -> connected-component mechanism as Zep's "Observations" (see
    docs/research/observations-pattern-2026-08-13.md), with [[links]] as the
    signatures and memories as the episode nodes.

    max_cluster exists because a dense store collapses into one giant component
    that swamps the smaller, tighter clusters which are the real signal. The
    giant is the LARGEST component, so raising min_cluster cannot remove it
    (it filters the small clusters first) — only an upper bound can. 0 = no
    cap. This function's own default stays 0 (uncapped); the CLI's
    --max-cluster flag defaults to 10 instead (see its argparse help and
    SKILL.md's "Pattern clusters" section for why).

    NEVER writes a synthesis — only groups. An LLM writing the summary is a
    separate, by-hand paste step (--prompt emits the prompt; this script never
    calls an LLM), so the maker (model) never grades its own grouping — the
    verifier here is this deterministic pass (CLAUDE.md's maker/verifier
    doctrine). Manual, on-demand: a heuristic over a small graph will both over-
    and under-cluster, which is why it stays a hand-run tool until a real run
    proves the signal is worth scheduling.
    """
    files = sorted(state["files"])
    stems = state["stems"]
    slug_set = state["slug_set"]
    resolvable = {
        f: {t for t in state["links_out"].get(f, []) if t in stems or t in slug_set}
        for f in files
    }
    # target -> files that link it. Only targets linked by >=2 files create edges.
    by_target = {}
    for f in files:
        for t in resolvable[f]:
            by_target.setdefault(t, []).append(f)

    parent = {f: f for f in files}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for group in by_target.values():
        for i in range(1, len(group)):
            union(group[0], group[i])

    comp = {}
    for f in files:
        comp.setdefault(find(f), []).append(f)

    clusters = []
    for members in comp.values():
        if len(members) < min_cluster:
            continue
        if max_cluster and len(members) > max_cluster:
            continue
        mset = set(members)
        # shared_links = signatures binding THIS cluster: targets linked by >=2
        # of its members. All linkers of a target land in one component, so a
        # multi-linker target always belongs to exactly one cluster.
        shared = sorted(t for t, group in by_target.items()
                        if sum(1 for f in group if f in mset) >= 2)
        clusters.append({
            "members": sorted(members),
            "shared_links": shared,
            "size": len(members),
        })
    clusters.sort(key=lambda c: (-c["size"], c["members"]))
    return clusters


def _synthesis_prompt(c):
    """One paste-ready LLM synthesis prompt for a single --find-patterns cluster.
    Shared by both the text and JSON output paths of run_find_patterns() so
    --prompt means the same thing in each — see run_find_patterns()'s own
    docstring note on why that parity matters."""
    shared = ", ".join(c["shared_links"]) or "none"
    return (
        f"## Cluster ({c['size']} memories, shared: {shared})\n"
        f"Members: {', '.join(c['members'])}\n\n"
        "Write a 2-4 sentence observation about what these memories share,\n"
        "constrained to the evidence above (members + shared links). Write only\n"
        "what the shared referents and member topics support — do not invent\n"
        "claims, and do not assert causation the links alone don't show. Name\n"
        "the recurring pattern, not each file."
    )


def run_find_patterns(state, as_json, min_cluster, max_cluster, prompt):
    """--find-patterns. NOTE: --prompt must produce the same content in --json
    mode as in text mode — run_detector() already sets this precedent (JSON
    mirrors every text-mode field, e.g. stale/template_compliance), and a
    caller building automation around --json has no other signal that
    --prompt was silently a no-op there (confirmed live 2026-08-17:
    --find-patterns --json --prompt previously returned byte-identical
    output to --find-patterns --json alone, since the old as_json branch
    `return`ed before the prompt block below it ever ran)."""
    all_clusters = pattern_clusters(state, min_cluster, 0)
    clusters = [c for c in all_clusters if not max_cluster or c["size"] <= max_cluster]
    hidden = len(all_clusters) - len(clusters)
    if as_json:
        result = {
            "mode": "find-patterns",
            "memory_dir": state["d"],
            "min_cluster": min_cluster,
            "max_cluster": max_cluster,
            "hidden_above_cap": hidden,
            "clusters": clusters,
        }
        if prompt:
            result["prompts"] = [_synthesis_prompt(c) for c in clusters]
        print(json.dumps(result, indent=2))
        return 0

    print(f"=== memory-lint --find-patterns: {state['d']} ===")
    cap = f", max-cluster: {max_cluster}" if max_cluster else ""
    print(f"min-cluster: {min_cluster}{cap} | clusters: {len(clusters)}"
          + (f" | {hidden} above cap, hidden — rerun with --max-cluster 0 to see" if hidden else ""))
    print("Advisory recurrence pre-filter only — NOT a verdict. A cluster says these")
    print("memories share [[link]] referents, not that they say the same thing. Read")
    print("each cluster by hand; never auto-merge.")
    print()
    if not clusters:
        if hidden:
            print(f"  none within the cap — {hidden} component(s) above --max-cluster {max_cluster}, "
                  f"hidden. Rerun with --max-cluster 0 to see them.")
        else:
            print(f"  none — no connected component reached {min_cluster} members")
    for c in clusters:
        print(f"  [size {c['size']}] {', '.join(c['members'])}")
        if c["shared_links"]:
            print(f"      shared links: {', '.join(c['shared_links'])}")
    if prompt:
        print()
        print("--- paste-ready LLM synthesis prompts (one per cluster) ---")
        print("# The script does NOT call an LLM. Paste each block into a model to write")
        print("# the recurrence summary; the deterministic pass already decided the")
        print("# grouping — the model only turns that structure into prose.")
        print()
        for c in clusters:
            print(_synthesis_prompt(c))
            print()
    return 0


def _git_first_commit(d):
    """(sha, epoch) of the memory dir's first commit, or (None, None) if it isn't
    a git repo (or has 0 commits)."""
    try:
        out = subprocess.run(
            ["git", "-C", d, "log", "--reverse", "--format=%H|%ct"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None, None
    if out.returncode != 0:
        return None, None
    lines = out.stdout.strip().splitlines()
    if not lines:
        return None, None
    sha, _, epoch = lines[0].partition("|")
    return sha, int(epoch)


def _baseline_tree_files(d, sha):
    """Every filename tracked at the memory dir's first commit, or None if the
    git call itself failed (distinct from a genuinely empty tree).

    One call for the whole baseline tree, not one `ls-tree` per file — same
    tree-membership test as before (immune to later edits, unlike mtime), now
    O(1) subprocess calls instead of O(N).
    """
    try:
        out = subprocess.run(
            ["git", "-C", d, "ls-tree", "--name-only", sha],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return set(out.stdout.splitlines())


def _git_fold_commits(d):
    """Single-pass parse of MEMORY.md's own commit history: for every commit,
    every real markdown pointer-link (POINTER_RE) it removed. Returns
    (folds, ok) — folds maps filename -> the most recent {"sha", "subject"}
    whose diff removed a `](filename)` link; ok is False only if the git call
    itself failed, distinct from "ran fine, found nothing".

    Exact pointer-link match, not `git log -S<filename>` substring search:
    -S matches the filename anywhere in MEMORY.md's TEXT, including a bare
    mention in another entry's prose that was never a real link — editing that
    unrelated prose later would then look like a fold. Scanning only diff
    lines through POINTER_RE requires real `](file.md)` syntax, closing that
    as a side effect of batching everything into one call.
    """
    sep = "\x01"
    try:
        out = subprocess.run(
            ["git", "-C", d, "log", f"--format=COMMIT{sep}%h{sep}%s", "-p", "--", "MEMORY.md"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}, False
    if out.returncode != 0:
        return {}, False

    folds = {}
    sha = subject = None
    for line in out.stdout.splitlines():
        if line.startswith(f"COMMIT{sep}"):
            _, sha, subject = line.split(sep, 2)
            continue
        if sha is None or not line.startswith("-") or line.startswith("---"):
            continue
        for target in POINTER_RE.findall(line):
            folds.setdefault(target, {"sha": sha, "subject": subject})
    return folds, True


def classify_unindexed(state):
    """Bucket every UNINDEXED file (see detector_findings's index-drift check)
    into fold-vs-forgotten instead of treating them all the same.

    UNINDEXED is two different states sharing one label: a memory that was
    never pointed to (an authoring oversight) and a memory that WAS pointed to
    and got deliberately removed by a prior fold pass (MEMORY.md's own fold
    rule: "merge/drop stale entries... never delete the backing .md unless
    genuinely dead — just stop indexing it"). A blind auto-append would
    silently undo real prior fold decisions — see
    docs/research/claude-mem-architecture-study-2026-08-07.md, Adopt-1.

    Buckets, in order of confidence:
      folded-confirmed        — a real `](file.md)` pointer link to this file
                                 was removed from MEMORY.md at some past commit.
                                 NOT a candidate to re-add — a prior fold already
                                 made this call.
      never-indexed            — file is ABSENT from the tree at the memory
                                 dir's first commit (didn't exist yet when
                                 tracking started), and no fold commit was
                                 found — its whole life is inside git history
                                 and git never saw a pointer. Real candidate.
      ambiguous-pre-baseline   — file is PRESENT in the tree at the first
                                 commit, so it predates tracking and git has no
                                 opinion either way (a pre-baseline fold looks
                                 identical to "never indexed" from git alone).
                                 Needs a human to read the content. This is a
                                 tree-membership check, not an mtime check — an
                                 mtime-based version would misclassify a
                                 pre-baseline file as never-indexed the first
                                 time anyone edits it, since mtime resets on
                                 every save but tree membership at a past
                                 commit never changes.
      no-git-history           — the memory dir isn't a git repo at all (or has
                                 0 commits) — same ambiguity as above, always.
      git-query-failed          — the dir IS a git repo, but a git call failed
                                 mid-scan (lock contention, timeout, corrupted
                                 history). Distinct from no-git-history so a
                                 human can tell "no repo" from "transient
                                 failure" — and distinct from silently falling
                                 through to never-indexed, which would assert
                                 the wrong bucket with full confidence.
    """
    d = state["d"]
    referenced = state["referenced"]
    unindexed = sorted(f for f in state["files"] if f not in referenced)

    baseline_sha, _baseline_epoch = _git_first_commit(d)
    folds, folds_ok, baseline_files = {}, True, None
    if baseline_sha is not None:
        folds, folds_ok = _git_fold_commits(d)
        baseline_files = _baseline_tree_files(d, baseline_sha)

    results = []
    for f in unindexed:
        txt = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
        frontmatter = txt.split("---", 2)[1] if txt.startswith("---") else ""
        dm = DESCRIPTION_RE.search(frontmatter)
        description = dm.group(1) if dm else None

        if baseline_sha is None:
            bucket, commit = "no-git-history", None
        elif not folds_ok or baseline_files is None:
            bucket, commit = "git-query-failed", None
        elif f in folds:
            bucket, commit = "folded-confirmed", folds[f]
        else:
            bucket, commit = ("ambiguous-pre-baseline" if f in baseline_files else "never-indexed"), None
        results.append({"file": f, "bucket": bucket, "commit": commit, "description": description})
    return results


def run_classify_unindexed(state, as_json):
    results = classify_unindexed(state)
    order = ["folded-confirmed", "never-indexed", "ambiguous-pre-baseline", "no-git-history", "git-query-failed"]
    buckets = {b: [r for r in results if r["bucket"] == b] for b in order}

    if as_json:
        print(json.dumps({
            "mode": "classify-unindexed",
            "memory_dir": state["d"],
            "total_unindexed": len(results),
            "buckets": buckets,
        }, indent=2))
        return 0

    print(f"=== memory-lint --classify-unindexed: {state['d']} ===")
    print(f"total UNINDEXED: {len(results)}")
    print("Classification only — never auto-appends. A blind re-add would undo real prior")
    print("fold decisions; see docs/research/claude-mem-architecture-study-2026-08-07.md.")
    print()

    print(f"folded-confirmed ({len(buckets['folded-confirmed'])}) — already deliberately removed, NOT a candidate to re-add:")
    for r in buckets["folded-confirmed"]:
        print(f"  {r['file']}  (commit {r['commit']['sha']}: {r['commit']['subject']})")
    if not buckets["folded-confirmed"]:
        print("  none")
    print()

    print(f"never-indexed ({len(buckets['never-indexed'])}) — created after the git baseline, no fold found; real candidates to add:")
    for r in buckets["never-indexed"]:
        desc = f" — {r['description']}" if r["description"] else ""
        print(f"  {r['file']}{desc}")
    if not buckets["never-indexed"]:
        print("  none")
    print()

    print(f"ambiguous-pre-baseline ({len(buckets['ambiguous-pre-baseline'])}) — predates git tracking, can't tell fold vs forgotten; needs manual read:")
    for r in buckets["ambiguous-pre-baseline"]:
        desc = f" — {r['description']}" if r["description"] else ""
        print(f"  {r['file']}{desc}")
    if not buckets["ambiguous-pre-baseline"]:
        print("  none")

    if buckets["no-git-history"]:
        print()
        print(f"no-git-history ({len(buckets['no-git-history'])}) — memory dir isn't a git repo (or has 0 commits); same ambiguity as ambiguous-pre-baseline for all of these:")
        for r in buckets["no-git-history"]:
            print(f"  {r['file']}")

    if buckets["git-query-failed"]:
        print()
        print(f"git-query-failed ({len(buckets['git-query-failed'])}) — a git command failed mid-scan (lock contention, timeout, corrupted history); can't safely tell fold vs forgotten, needs manual read:")
        for r in buckets["git-query-failed"]:
            print(f"  {r['file']}")
    return 0


def run_detector(state, as_json, stale_days):
    findings, total_links, linked_count, context_layer = detector_findings(state)
    stale = staleness_findings(state, stale_days)
    template = template_compliance_findings(state)
    if as_json:
        print(json.dumps({
            "mode": "detector",
            "memory_dir": state["d"],
            "files": len(state["files"]),
            "links": total_links,
            "linked": linked_count,
            "context_layer": context_layer,
            "findings": findings,
            "stale": stale,
            "stale_days_threshold": stale_days,
            "template_compliance": template,
        }, indent=2))
        sys.exit(0 if not findings else len(findings))

    idx_bytes, idx_lines = measured_index(state["idx"])
    pct = int(max(idx_lines / LINE_CAP, idx_bytes / BYTE_CAP) * 100)
    print(f"=== memory-lint: {state['d']} ===")
    print(f"memories: {len(state['files'])} | links: {total_links} | "
          f"linked: {linked_count} | MEMORY.md: {pct}% of load cap | "
          f"findings: {len(findings)} | context-layer: {context_layer}")
    print()
    for line in findings:
        print(f"  {line}")
    if not findings:
        print("  clean — no dangling links, orphans, or index drift")
    if context_layer:
        print(f"  (context-layer: {context_layer} unindexed file(s) reachable from the "
              f"index via [[links]] — healthy Layer-2 per the fold rule, not findings)")
    print(f"\nExit: {len(findings)}")

    print()
    print(f"--- Staleness (advisory, not counted in exit code — threshold: {stale_days}d) ---")
    if stale:
        for s in stale:
            print(f"  STALE: {s['file']} — {s['age_days']}d since last edit")
        print(f"  {len(stale)} file(s) worth a re-check; not a defect, just old")
    else:
        print(f"  none — every memory touched within {stale_days}d")

    print()
    print("--- Template compliance (advisory, not counted in exit code — feedback/project only) ---")
    if template["scoped_total"]:
        why_pct = int(100 * (template["scoped_total"] - template["missing_why"]) / template["scoped_total"])
        how_pct = int(100 * (template["scoped_total"] - template["missing_how"]) / template["scoped_total"])
        print(f"  **Why:** present: {template['scoped_total'] - template['missing_why']}/{template['scoped_total']} ({why_pct}%)")
        print(f"  **How to apply:** present: {template['scoped_total'] - template['missing_how']}/{template['scoped_total']} ({how_pct}%)")
        if template["missing_both"]:
            print(f"  missing BOTH fields ({len(template['missing_both'])}): " + ", ".join(template["missing_both"][:10])
                  + (", ..." if len(template["missing_both"]) > 10 else ""))
    else:
        print("  no feedback/project-typed memories in this store")

    template_gap = template["missing_why"] + template["missing_how"] - len(template["missing_both"])
    print(f"\nadvisory: {len(stale)} stale, {template_gap} template-gap")

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
    lines by topic-file mtime, any type, until back under FOLD_TARGET_PCT of cap.
    exclude_files = filenames already claimed by plan A/B, so nothing double-counts.
    Self-contained byte accounting — does not participate in the shared
    estimated_impact sum used by A/B/C, which mixes savings-sign conventions
    across classes; D reports its own delta separately."""
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

    remaining_bytes = idx_bytes
    remaining_lines = idx_lines
    for _mtime, fname, full_line in candidates:
        if remaining_bytes <= target_bytes and remaining_lines <= target_lines:
            break
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
    ap.add_argument("--stale-days", type=int, default=STALE_DAYS_DEFAULT,
                    help=f"Advisory staleness threshold in days (default: {STALE_DAYS_DEFAULT})")
    ap.add_argument("--find-contradictions", action="store_true",
                    help="Advisory, one-off: surface candidate contradiction pairs "
                         "(same type + token-overlap or shared link) for manual review. "
                         "Never auto-resolves.")
    ap.add_argument("--min-overlap", type=float, default=0.35,
                    help="Token-overlap threshold for --find-contradictions (default: 0.35)")
    ap.add_argument("--classify-unindexed", action="store_true",
                    help="Classify UNINDEXED findings as folded-confirmed / never-indexed / "
                         "ambiguous-pre-baseline using git history on MEMORY.md. "
                         "Read-only — never appends anything.")
    ap.add_argument("--find-patterns", action="store_true",
                    help="Advisory, one-off: surface connected components of memories "
                         "sharing [[link]] referents (recurrence clusters, size >= "
                         "--min-cluster) for manual review. Deterministic — never calls "
                         "an LLM; --prompt emits a paste-ready synthesis prompt instead.")
    ap.add_argument("--min-cluster", type=int, default=3,
                    help="Minimum component size for --find-patterns (default: 3)")
    ap.add_argument("--max-cluster", type=int, default=10,
                    help="Upper bound on component size for --find-patterns (default: 10; "
                         "pass 0 for no cap / the raw uncapped view). A dense store produces "
                         "one giant component that swamps the smaller tight clusters which are "
                         "the real signal; the giant is the LARGEST component, so raising "
                         "--min-cluster cannot remove it — only an upper bound can. Clusters "
                         "hidden by the cap are counted, not silently dropped: the header and "
                         "the empty-result message both report how many were suppressed.")
    ap.add_argument("--prompt", action="store_true",
                    help="With --find-patterns, also emit one paste-ready LLM-synthesis "
                         "prompt per cluster. The script never calls an LLM itself.")
    args = ap.parse_args()

    d = memory_dir(args.memory_dir)
    if not os.path.isdir(d):
        sys.exit(f"FATAL: memory dir not found: {d}")
    state = collect_state(d)

    if args.find_contradictions:
        sys.exit(run_find_contradictions(state, args.json, args.min_overlap))
    elif args.find_patterns:
        sys.exit(run_find_patterns(state, args.json, args.min_cluster, args.max_cluster, args.prompt))
    elif args.classify_unindexed:
        sys.exit(run_classify_unindexed(state, args.json))
    elif args.auto_archive:
        sys.exit(run_action_mode(state, args))
    else:
        run_detector(state, args.json, args.stale_days)


if __name__ == "__main__":
    main()
