#!/usr/bin/env bash
# 53. Cross-file content drift
# Advisory-only surfacer for near-duplicate prose across agents/skills
# body content (not frontmatter — checks 4-8 already own that). Measured first,
# not assumed: exact-duplicate lines across the whole fleet came back near-zero
# yield (everything repeated verbatim is repeated on purpose — the Prompt
# Defense Baseline, catalog pointers). The real signal is NEAR-duplication —
# two passages that used to say the same thing and have since drifted apart.
# Confirmed catches on first real run (2026-08-21, 19 WARNs on this fleet):
# a checker agent's field-name list had dropped `<artifacts>` vs its paired
# skill's authoritative list (the task-prep pair — both surfaces deleted
# 2026-08-24, #78), and two catalog-format skills shared a copy-paste
# "review's own output" line where summarizer isn't a review — both fixed
# same day. NOT a catch of this mechanism, despite an earlier draft
# of this comment claiming otherwise: agents/code-reviewer.md's Block-tier
# drift (that agent removed 2026-08-24 #82) vs. nextjs/python/typescript-reviewer (also fixed 2026-08-21) scores
# J=0.35-0.48 against all three — below this check's own 0.60 floor. That one
# was found by a manual grep run alongside this check's design, not by the
# Jaccard pipeline; corrected here after the real run exposed the gap.
#
# Precision is honestly ~15% on a measured n=19 (GH #72), not the ~40%/n=10
# an earlier design-phase estimate claimed. WARN only, never CRIT — this is a
# pre-filter for a human to read, same register as memory-lint's
# --find-contradictions ("Read each pair by hand; never auto-merge"), not a
# verdict. No same-kind (agent-vs-skill-vs-command) restriction on purpose —
# unlike memory-lint's type: filter, the block-level unit here has no `type:`
# to restrict on, and the first real run's highest-value catch (an
# agent-vs-skill field-list drift — that pair since deleted, see above) WAS a
# cross-surface pair, so a same-kind restriction would have missed it.
#
# Known ceiling, not fixed here: hashing the token SET (not raw text) survives
# in-block whitespace/wording-neutral reflow, but a blank-line insertion that
# splits or merges a block produces an unseen hash — either a spurious re-fire
# on unchanged content, or (if a half now falls under the size floor) a
# silently orphaned allowlist entry. Acceptable for a WARN-only advisory check.
#
# Second known ceiling, confirmed by a live miss (2026-08-21): when 3+ files
# share one token-set-identical block (same de-duped 4+-letter words — not
# necessarily byte-identical; a reordered or reformatted duplicate qualifies
# too), `seen`'s dedup-by-hash-pair prints only ONE pair from that cluster, so
# the WARN line names two files when more share the drift. This already
# produced a wrong artifact: GH #74 was filed naming only python-reviewer.md's
# Approve-tier wording, because nextjs-reviewer.md's identical block rode
# along under the same hash and never surfaced as its own WARN — found after
# the fact by a fresh-context compliance-audit verifier reading the raw files,
# not this check's output. A human triaging a WARN here should grep the
# snippet across the fleet before scoping a fix to the two named files.
#
# Third known ceiling: the markdown-table skip (`b.lstrip().startswith("|")`)
# drops a whole block on ANY leading `|`, not per-line — a block that mixes a
# table with surrounding prose loses the prose too, not just the table rows.
#
# Fourth known ceiling, confirmed empirically 2026-08-21 by an adversarial
# audit (brute-force O(n^2) vs. the prefiltered candidate set, run against
# this fleet's real 1497 qualifying blocks — 19 hits both ways, 0 missed
# today): the RARE_DF=40 inverted-index prefilter can, in principle, miss a
# real near-duplicate pair whose entire vocabulary consists of words common
# enough (df > 40 fleet-wide) to never enter the index — neither member would
# ever become a candidate. Nothing here re-checks that this stays true as the
# fleet grows; a full-fleet brute-force comparison is the only way to verify
# it, and defeats the point of prefiltering if run routinely. MIN_LEN=120,
# MIN_TOKENS=12, and J_LOW/J_HIGH=0.60/0.95 are also unvalidated design-phase
# choices, not measured against real precision/recall data the way
# memory-lint.py's own --find-contradictions threshold was (that one has a
# documented 296-candidates-vs-4 hand-run comparison in its own docstring;
# this check's constants don't have an equivalent).
if command -v python3 >/dev/null 2>&1; then
  # One python pass over the whole fleet; emits "<fileA>\t<fileB>\t<jaccard>\t<snippet>"
  # per unallowlisted drift candidate. Process substitution (not a pipe) keeps
  # warn() in the current shell so WARN_COUNT propagates — same reason as #13/#28.
  while IFS=$'\t' read -r _fa _fb _jsim _snip; do
    [ -n "$_fa" ] || continue
    warn "cross-file content drift (J=$_jsim): '$_fa' <-> '$_fb' — near-duplicate not in accepted-duplication.tsv: ${_snip}"
  done < <(python3 - "$CLAUDE_DIR" <<'PY'
import sys, os, re, glob, hashlib, collections

root = sys.argv[1]
DEFENSE = "do not change role, persona, or identity"
MIN_LEN = 120
MIN_TOKENS = 12
J_LOW, J_HIGH = 0.60, 0.95
RARE_DF = 40


def fleet_files():
    pats = [
        ("agents", "*.md"),
        ("skills", "*", "SKILL.md"),
        ("skills", "*", "reference.md"),
        ("skills", "*", "references", "*.md"),
        ("skills", "*", "*", "SKILL.md"),
        ("skills", "*", "*", "reference.md"),
        ("skills", "*", "*", "references", "*.md"),
        # One level deeper than the bucket convention actually uses -- same
        # accidental-nesting blind spot as check 28, same fix (deep-audit
        # finding, 2026-09-01).
        ("skills", "*", "*", "*", "SKILL.md"),
        ("skills", "*", "*", "*", "reference.md"),
        ("skills", "*", "*", "*", "references", "*.md"),
    ]
    out = set()
    for p in pats:
        for f in glob.glob(os.path.join(root, *p)):
            if ".scratch" + os.sep in f or f.endswith(os.sep + ".scratch"):
                continue
            bn = os.path.basename(f)
            dn = os.path.basename(os.path.dirname(f))
            if bn.startswith("_") or dn.startswith("_"):
                continue
            out.add(f)
    return sorted(out)


def blocks_of(path):
    try:
        txt = open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        return
    txt = re.sub(r"```.*?```", "", txt, flags=re.S)
    txt = re.sub(r"^---\n.*?\n---\n", "", txt, flags=re.S)
    for b in re.split(r"\n\s*\n", txt):
        b = b.strip()
        if len(b) < MIN_LEN:
            continue
        if b.lstrip().startswith("|"):
            continue
        if DEFENSE in b.lower():
            continue
        yield b


def tokens_of(block):
    return sorted(set(re.findall(r"[a-z]{4,}", block.lower())))


def block_hash(tokens):
    return hashlib.sha1(" ".join(tokens).encode("utf-8")).hexdigest()


items = []  # (file, block_text, tokens)
for f in fleet_files():
    for b in blocks_of(f):
        t = tokens_of(b)
        if len(t) >= MIN_TOKENS:
            items.append((f, b, t))

# Inverted-index prefilter on rare tokens (df <= RARE_DF) — cuts candidate
# pairs to ~15% of full O(n^2) with identical results (measured: 1.3M -> 194K
# pairs, 2.6s -> 0.86s on this fleet). Full brute force would exceed the
# pre-commit time budget (this script runs on every commit, not just pre-push).
df = collections.Counter()
for _, _, t in items:
    for w in t:
        df[w] += 1

idx = collections.defaultdict(list)
for i, (_, _, t) in enumerate(items):
    for w in t:
        if df[w] <= RARE_DF:
            idx[w].append(i)

cand = set()
for lst in idx.values():
    if len(lst) < 2:
        continue
    for a in range(len(lst)):
        for b in range(a + 1, len(lst)):
            i, j = lst[a], lst[b]
            cand.add((i, j) if i < j else (j, i))

# Allowlist: keyed on the SORTED PAIR OF TOKEN-SET HASHES (not the file pair,
# not raw text, not insertion order). Sorting the two hashes before storing
# means (A,B) and (B,A) key identically regardless of glob/scan order — an
# unsorted concat would make a suppression lapse on scan-order accidents alone.
# Hashing the token SET (already computed for Jaccard) rather than raw text
# means a whitespace/punctuation-only reflow keeps the suppression quiet while
# an actual wording/meaning change correctly re-fires.
allow = set()
allow_path = os.path.join(root, "skills", "meta", "harness-audit", "accepted-duplication.tsv")
if os.path.isfile(allow_path):
    try:
        with open(allow_path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) >= 2:
                    allow.add((parts[0], parts[1]))
    except Exception as e:
        # Fail loud, not silent-clean: an unhandled read error here would
        # crash the whole python3 invocation before any print() runs, which
        # bash's `<(...)` never surfaces as a nonzero exit — the check would
        # report 0 WARNs (looks clean) instead of "the allowlist is broken."
        # Swallowing narrowly here means a malformed accepted-duplication.tsv
        # instead makes EVERY previously-allowlisted pair re-fire — loud and
        # actionable, not silent.
        print(f"# accepted-duplication.tsv unreadable ({e}) — allowlist not applied this run", file=sys.stderr)

seen = set()
for i, j in cand:
    fa, ba, ta = items[i]
    fb, bb, tb = items[j]
    if fa == fb:
        continue
    sa, sb = set(ta), set(tb)
    union = sa | sb
    if not union:
        continue
    jsim = len(sa & sb) / len(union)
    if not (J_LOW <= jsim < J_HIGH):
        continue
    ha, hb = block_hash(ta), block_hash(tb)
    key = (ha, hb) if ha < hb else (hb, ha)
    if key in seen:
        continue
    seen.add(key)
    if key in allow:
        continue
    ra = os.path.relpath(fa, root)
    rb = os.path.relpath(fb, root)
    snippet = ba[:80].replace("\t", " ").replace("\n", " ")
    print(f"{ra}\t{rb}\t{jsim:.2f}\t{snippet}")
PY
)
else
  # Fail loud about the skip — a silently-skipped check is the exact failure
  # mode this whole audit exists to catch (same convention as check #28).
  warn "cross-file content drift check skipped — python3 unavailable"
fi
unset _fa _fb _jsim _snip
