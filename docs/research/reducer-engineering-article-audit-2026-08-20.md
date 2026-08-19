# "Reducer Engineering" article vs. kbg-harness — audit (2026-08-20)

**Source:** "Reducer Engineering: Cutting What Your Model Has To Read (Full Guide)," @gippp69,
published 2026-08-11 (X/Twitter thread, 154 lines, `~/llm-wiki/raw/`). Not yet ingested to
`wiki/`.

**Core claim (the article's, not independently reproduced by kbg):** feeding 40 raw Claude Haiku
worker outputs into one Claude Sonnet synthesis call cost $1.38/51s per run; inserting a
deterministic code reducer (drop malformed, group-by-normalized-claim, keep highest-confidence,
flag corroboration/contradiction) between them dropped it to $0.19/11s — an 86%/78% drop — and
surfaced 23 cross-worker contradictions the raw dump had buried. Single-author, unreproduced,
from an X post — cited here as *the article's claim*, not a verified benchmark. The one external
citation it makes checks out: Liu et al. (Stanford, TACL 2024, "Lost in the Middle") did find a
U-shaped accuracy curve — worst when relevant info sits mid-context, even on long-context models
(confirmed via [aclanthology.org/2024.tacl-1.9](https://aclanthology.org/2024.tacl-1.9/)).

**Verdict: nothing to build.** kbg-harness's own doctrine already states this article's principle
near-verbatim (`CLAUDE.md`'s "Same crux, N-worker fan-in" paragraph, `docs/METHODOLOGY.md` Rule
13's context-economy block), and one live implementation already matches the article's specific
mechanism — including having already reached, and declined to cross, the article's own unresolved
caveat. Two days *before* this article was fed into this session.

## Guard-by-guard: `deep-research.js`'s claim-dedup vs. the article's `reduce_findings()`

`scripts/workflows/deep-research.js:284-349`. Comment at line 298 dates the mechanism itself:
"2026-08-17 reducer-engineering audit, 3-agent independent convergence on this gap" — this is
CLAUDE.md's own already-documented "Gap confirmed 2026-08-17" fix, not new work.

| Article's guard | Present? | Where |
|---|---|---|
| Drop malformed, log the count (not silently absorbed) | ✅ | line 302-303, logged into the run summary line 335 |
| Group by normalized claim, keep highest-confidence/quality | ✅ | line 317-322 — keeps best by `sourceQuality` rank, tags `corroboratedBy: N` (the article's `[confirmed by N other worker(s)]`) |
| Empty input → skip synthesis, don't run on nothing | ✅ (stronger) | line 340-349 — two distinct branches: "no claims extracted" vs. "all malformed and dropped," not one generic empty case |
| Two findings in a group disagree → flagged as an explicit contradiction | ❌ — deliberately | see below |

**The contradiction-flag guard is a documented non-build, not a gap.** Lines 305-309 carry a
`ponytail:` comment: *"exact-normalized-match only, not fuzzy/embedding similarity — a false merge
here silently drops a claim from verification entirely, the worst place for the false-merge risk
the source article itself flags (§7) to land. Upgrade only if a real run shows literal near-dupes
slipping through unmerged."* The article's own §7 ("What I Haven't Tested") admits `normalize()`'s
false-merge rate is unvalidated. kbg's implementation independently reached that same caution and
chose exact-match grouping specifically to keep that risk from landing — which is also why
contradiction-flagging can't fire here: two claims about the same fact that phrase differently
normalize to different keys and never land in the same group to compare. Building fuzzy grouping
to enable it would reopen the exact risk the article itself couldn't rule out. Not pursued.

## Other fan-in surfaces checked

| Surface | Mechanism today | Verdict |
|---|---|---|
| `memory-lint` pattern-cluster (`skills/memory-lint/scripts/memory-lint.py:449-529`) | Real code (union-find graph clustering) | Different shape — clusters files by shared `[[link]]` targets for discovery, no claim/confidence fields, returns all members by design. CLAUDE.md's citation is about the general "code not model" principle, not a literal pattern match. |
| `review-pr` Phase 5 overlap detection (`skills/review-pr-tier/SKILL.md` step 1) | Prompt-only ("Do NOT blend... overlap on the same file:line = signal") | Open, but blocked — see below. Not built. |
| `bug-sweep` Consolidate (`commands/bug-sweep.md:26`) | Prompt-only, one paragraph | **Closed by doctrine, not deferred.** `bug-sweep` is markdown-only with no backing script — CLAUDE.md's own N-worker-fan-in paragraph names prompt-instruction as the *correct* mechanism where no code layer exists to hold a real reducer, not a weaker fallback. Converting it would mean writing a script this command was never given. |
| `orchestrate/reference.md` fan-out-and-synthesize row (line 471) | Prompt-only, named as such | Matches CLAUDE.md verbatim already. No new finding. |
| `ideate` Phase 2 score+cluster (`commands/ideate/COMMAND.md:127-156`) | Model judgment, by design | Doesn't fit — novelty/viability/fit scoring and angle-clustering are subjective, no ground-truth claim text to normalize on. |
| `harness-audit` aggregation | N/A | No fan-in-reduction need — every check is deterministic shell/Python, no synthesis call reads raw text in a loop. |

## The one open item: `review-pr` Phase 5, and why it's not built now

The prose instruction ("overlap on the same file:line = signal, not noise") relies on the
orchestrating model noticing overlap by reading N per-agent JSON reports — a correctness risk
(a missed overlap), not primarily a cost problem like the article's 40-worker case (review-pr's
fan-out is a handful of specialist agents, not 40).

**Why not built:** the mechanical part looks trivial — group findings by `(file, line)` — but
`agent_findings`' actual schema doesn't support it yet. `skills/review-pr/scripts/write-review-checkpoint.sh`
and `read-review-checkpoint.sh:110-115` only enforce `agent_findings` as a `list`; the per-finding
shape (whether each entry reliably carries a `file` and `line` field, vs. narrative text with a
`file:line` mention embedded in prose) is authored by the orchestrating model at Phase 4 hand-off,
not schema-enforced. A code reducer grouping on `(file, line)` needs that field to exist and be
reliable first — the actual first step would be tightening the Phase 4 write-checkpoint schema,
which is a bigger, more invasive change (touches how the orchestrator is instructed to build the
payload in an actively-used pipeline) than the reducer itself. Not clearly worth it at review-pr's
current fan-out scale.

**Revisit trigger** (state-based, not time-based): a Phase 5 run demonstrably misses a `file:line`
overlap that two dispatched agents both independently flagged — i.e., the prompt-only mechanism
fails in a way this session could only speculate about. If that happens, the fix starts at the
Phase 4 checkpoint schema, not at Phase 5.

## Bottom line

This article's playbook is already live in this codebase, verified against the actual code (not
the doctrine prose describing it), including the one part the article's own author flagged as
unresolved. No build follows from this audit.
