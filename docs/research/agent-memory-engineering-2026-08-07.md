# Agent memory engineering: two articles vs. kbg's live memory store (2026-08-07)

## Question

Two clippings in `llm-wiki/raw/` lay out memory-engineering doctrine from Stanford/Microsoft/
Anthropic/Nvidia (cost, utility, control, hardware) and from a Zep/Pydantic ontology walkthrough
(typed entities/edges beat generic extraction). Do these ideas expose real gaps in kbg's own
memory system — the native Claude Code auto-memory store at
`~/.claude/projects/<enc>/memory/` plus kbg-harness's `memory-lint` governance layer — and if so,
what's concretely worth building?

## Bottom line

Yes, and the store's own linter proves it: **87 findings on a 178-entry store** (75 unindexed,
10 orphaned, 2 dangling links) have accumulated silently because the SessionStart hook that used
to surface them was deleted in the 2026-06-27 "reset from scratch" (`c452102`) and never rebuilt
— `skills/memory-lint/SKILL.md` still documents it as active. That single fact anchors this
report: it is Stanford's "maintenance... usually missing entirely" and Anthropic's "a wrong
memory... persists into every future session" landing as measured numbers, not analogy. The
highest-ROI fix is restoring that loop (Tier A1) and fixing the doc drift, which this report
also does as part of the deliverable.

The one place the two articles genuinely disagree — auto-invalidate contradictions (Zep) vs.
never auto-merge, always surface (Stanford/Microsoft) — is resolved decisively for kbg by kbg's
own already-adopted doctrine: an LLM cannot grade its own output, so an extraction pipeline that
both writes facts and unilaterally invalidates them is the same maker-grades-itself failure kbg's
CLAUDE.md already rejects for every other verifier/gate. See Part 2.

Six improvements follow, tiered by where they can actually land: **Tier A** ships in
`kbg-harness` today; **Tier B** requires editing `~/.claude/CLAUDE.md` (a dotfiles symlink this
repo can't write through — named, not assumed editable); **Tier C** is a platform boundary
(Claude Code owns what auto-loads at session start) with no real fix, stated plainly instead of
invented.

**Status (2026-08-07): all five Tier A items shipped** (v0.68.220 doc-drift fix, v0.68.222 A1+A4,
v0.68.223 A2+A3+A5) — Tier B (B1) stays deferred per Part 6's own reasoning, unchanged by
anything A1-A5 surfaced. Two findings emerged only from actually building and running the tools,
not from the original proposal: `pwd -P` vs `$PWD` broke A1's directory check on macOS symlinked
paths (caught in fixture testing, fixed before shipping); A3's original heuristic (token-overlap
OR shared-link) returned 296 near-useless candidates on the live store, fixed to token-overlap
only (4 candidates, 0 genuine contradictions on spot-check) — see A3's own section for the full
account. Both are exactly the kind of thing "prove it by hand first" is supposed to catch.

## Sources

- `llm-wiki/raw/How to be a Memory Engineer, from the perspective of Stanford, Microsoft,
  Anthropic and Nvidia.md` (@N01ennn, 2026-08-03) — hereafter **Article 1**.
- `llm-wiki/raw/Pydantic fixed my Agent's Memory.md` (@akshay_pachaar, 2026-05-26) — hereafter
  **Article 2**.
- Live measurement against `~/.claude/projects/<project-dir>/memory/`
  via `skills/memory-lint/scripts/memory-lint.py`, run 2026-08-07 (detector mode, read-only;
  `--auto-archive` was never invoked against the live store while producing this report).
- **Primary sources, independently verified 2026-08-07** (a second, line-by-line re-read of
  both articles found the original pass never checked these — see Part 7 for the full account
  and one real naming-collision caveat):
  - Stanford — [Agent Memory: Characterization and System Implications of Stateful Long-Horizon
    Workloads](https://arxiv.org/abs/2606.06448) (arXiv 2606.06448, Omri et al., 2026-06-04)
  - Microsoft — [PlugMem: A Task-Agnostic Plugin Memory Module for LLM
    Agents](https://arxiv.org/abs/2603.03296) (arXiv 2603.03296, UIUC/Tsinghua/MSR)
  - Microsoft — [Memento: Teaching LLMs to Manage Their Own
    Context](https://arxiv.org/pdf/2604.09852) (arXiv 2604.09852) — **not** to be confused with
    the differently-mechanismed, identically-titled-minus-one-word [Memento: Fine-tuning LLM
    Agents Without Fine-tuning LLMs](https://arxiv.org/abs/2508.16153) (arXiv 2508.16153)
  - Anthropic — [Built-in memory for Claude Managed
    Agents](https://claude.com/blog/claude-managed-agents-memory) — a product/customer-case-study
    blog post (Rakuten's numbers), not a peer-reviewed paper; cited by Article 1 in parallel with
    the three papers above despite the different evidentiary tier
  - **No standalone Nvidia paper exists.** Article 1's own sources line says the hardware framing
    comes "from the H100, vLLM and B200 setups in the Stanford and Memento papers" — "four labs"
    is the article's rhetorical framing, not four independent sources.

---

## Part 1 — Concept extraction

### Article 1: cost, utility, control, hardware (Stanford / Microsoft / Anthropic / Nvidia)

| # | Concept | Core claim |
|---|---|---|
| 1 | Memory has a metabolism | Not a bucket — it eats energy on write, grows every session, rots without pruning, and serves stale-but-confident answers if nothing maintains it. |
| 2 | Four lenses, hold all at once | Cost (Stanford) / worth-keeping (Microsoft) / control (Anthropic) / hardware (Nvidia). Picking one and ignoring the rest is the failure mode. |
| 3 | Construction cost is the hidden bill | Query latency is what users feel and what gets measured; the write path (LLM prefill + embedding, turning raw history into records) is paid once, invisible, and for LLM-mediated systems burns more energy than 300 queries against the result. |
| 4 | Measure energy per correct answer, not accuracy | Two systems at identical accuracy can differ 47x in cost per correct answer. Quality and cost-per-correct-answer are reported together, always. |
| 5 | No universal-best system; pick a cost on purpose | Raw context / flat retrieval / structured extraction / fully agentic each trade build cost, query speed, accuracy differently. Mem0-style systems answer in <0.1s but cost thousands of seconds to build; a lexical index builds instantly but is slower/blunter at query time. |
| 6 | Store facts and skills, not logs | Microsoft's PlugMem: more raw memory can make an agent *worse* — retrieval drowns, attention burns wading through transcripts. Extract the fact/skill, discard the transcript. |
| 7 | Judge by utility per token, not size | One general-purpose fact/skill memory beat purpose-built designs across three tasks while spending fewer tokens. Density beats volume. |
| 8 | Model-managed context (Memento) | Reason in blocks, write a dense note, delete the raw reasoning — peak memory drops 2-3x, throughput nearly doubles. The article names two separate takeaways here, and the first was missed in the original pass: **first**, this is a learned skill from ordinary fine-tuning, not orchestration bolted on (confirmed against the real paper — trained on 228K annotated reasoning traces). **Second**, erased reasoning leaves a "shadow": rebuilding from the note alone costs 15 accuracy points. Forgetting ≠ deletion; remembering ≠ storage. |
| 9 | Memory as files you can delete | Anthropic's move: filesystem-based memory, same tools the agent already uses. The value is everything files make possible — export, inspection, programmatic control. |
| 10 | Scope, audit, roll back | A wrong memory persists into every future session that reads it, so control is the design, not a layer on top. Org (read-only) vs. per-user (read-write) scoping + an audit log (who/session/what/when) that supports export/rollback/redaction. Teams doing this cut first-pass errors 97% and sped verification ~33%. |
| 11 | Memory is a KV-cache problem underneath | Full context is quadratic cost; prefix caching inside a session collapses across sessions. The real currency is HBM bandwidth / GPU utilization / tokens-per-second / freed KV slots. On B200, the article's own cited number: Memento-on-vLLM's block-flush pattern measured 4,290 tok/s vs. 2,447 vanilla (~1.75x), same batch completing in 693s vs. 1,096s (~1.6x faster) — missed in the original pass's table, present in the article's raw text. |
| 12 | Construction as a background job | Construction is prefill-heavy (long reads, short writes) — behaves like batch indexing. Co-locating it with live queries stalls the scheduler exactly when a user query lands; rate-limit/batch/defer it instead. |
| 13-15 | Build order | Prove each pass by hand first (a system run against three notes hallucinates connections and trains you to ignore it). Ship: write path first (let it fill for weeks) → manual contradiction detection, schedule only if collisions surprise you → forgetting/maintenance policy before volume climbs → hardware tuning last. **Never auto-merge contradictions — two memories can both have been right in different contexts; the system surfaces, a human decides.** Growth *slope*, not starting size, is what bankrupts a long-lived agent (up to 9x footprint spread across systems at 1M tokens, none of which prune by default). |

### Article 2: schema as a reasoning boundary (Zep / Graphiti, Pydantic)

| # | Concept | Core claim |
|---|---|---|
| 1 | Flat retrieval misses bridging facts | Vector similarity retrieves facts that share surface terms with the query, not facts that connect them. Example: "Alice manages Atlas," "Atlas runs on Postgres," "Postgres went down Tuesday" — a query about Alice and Tuesday needs fact 2, which shares vocabulary with neither. |
| 2 | Knowledge graphs fix traversal, not classification | Nodes/edges make multi-hop reasoning possible, but by default the extraction LLM freely invents entity types and relationship labels — everything becomes generic ("Topic," "Object," "RELATES_TO"), and typed queries ("open sev-1 tickets for enterprise customers") return noise because nothing is actually typed. |
| 3 | Extraction is the whole game | The pipeline is ingest → extract → store → retrieve → deliver. Extraction decides what the graph contains and what's queryable; in most frameworks it's a black box with zero developer control. |
| 4 | Fix: define the schema upfront (ontology) | Pydantic `EntityModel`/`EdgeModel` subclasses with typed fields and descriptions constrain what the extractor can produce — same pattern as FastAPI response models or function-calling schemas. Field *descriptions* aren't just labels; they teach the extractor domain vocabulary it never saw in training (critical for internal jargon, product names that collide with common words). |
| 5 | Source/target constraints are guardrails | `EntityEdgeSourceTarget` restricts which entity types an edge can connect (e.g. `WORKS_ON` can only join `User→Project`). A relationship the schema doesn't define simply can't be extracted, even if the conversation states it. **The schema defines the space of valid memories** — the same principle as constrained function-calling output. |
| 6 | Resolution + temporal validity happen after typed extraction | Zep's pipeline: entity extraction → entity resolution (dedupe "Nexus"/"the Nexus project") → fact extraction (typed edges) → **fact resolution (detects contradictions, invalidates outdated facts, preserves history)** → temporal extraction (validity windows per edge). |
| 7 | Context templates assemble typed facts, not a whole dump | A template pulls specific edge/entity types with limits (`%{edges types=[WORKS_ON] limit=5}`) into a purpose-built prompt block — retrieval is query/purpose-scoped, not "load everything." |
| 8 | 10/10/10 constraint forces prioritization | Zep hard-caps 10 entity types, 10 edge types, 10 fields per type — deliberately, to force picking what matters instead of modeling everything. Start with 3-4 entity/edge types covering 80% of the domain; add complexity incrementally. Without schema discipline, a graph store pays graph-construction cost while behaving like a plain vector store — worst of both. |

---

## Part 2 — Cross-article comparison

### Where they reinforce each other

- **Both reject default/emergent structure.** Article 1's fix for "more memory made the agent
  worse" is imposing extraction discipline (facts/skills, not transcripts). Article 2's fix for
  "the query returns noise" is imposing extraction discipline (typed schema, not free-form
  entities). Same diagnosis — ungoverned LLM extraction degrades with scale — from two different
  entry points.
- **Both treat memory as a system with a shape, not a bucket.** Article 1's "metabolism"
  language and Article 2's five-stage pipeline (ingest→extract→store→retrieve→deliver) describe
  the same lifecycle from different vocabularies.
- **Both prescribe minimal-viable-structure, not maximal.** Article 2: "start with 3-4 entity
  types... capture 80%, add incrementally." Article 1: "prove each pass by hand first... do not
  schedule everything on day one." Neither article argues for building the fullest possible
  system up front — both argue for the smallest structure that earns its keep, then growing it
  only when evidence demands it. This directly matches kbg's own ponytail/composer-not-creator
  doctrine already in force, independent of either article.
- **Both name retrieval quality as the actual cost of skipping structure**, not just an
  aesthetic complaint — Article 1's Microsoft finding (retrieval drowns, attention burns wading
  through transcripts) and Article 2's noise-return example are the same failure surfacing at
  query time from a construction-time cause.

### The one real contradiction — and how it resolves for kbg

Article 1, Step 14, is explicit and unqualified: **"never auto-merge contradictions: two
memories that disagree may both have been right in different contexts, so the system surfaces,
you decide."**

Article 2's flagship pipeline does the opposite as a matter of course: fact resolution "detects
contradictions **and invalidates outdated facts** (preserving history)" — step 4 of 5, run on
every ingest, no human in the loop. "Preserving history" softens this (you can look up what was
invalidated) but doesn't reconcile it — the *decision* that fact A supersedes fact B is still
made unilaterally by the same LLM pipeline that extracted both facts in the first place.

This isn't a minor style difference — it's the same maker-grades-itself failure kbg's own
CLAUDE.md already names and rejects for every other part of this harness: *"the gate is a
verifier..., the model is the maker, and the maker can never grade its own work — an LLM judging
its own output is circular."* An extraction pipeline that both writes facts and unilaterally
decides which one is now false is exactly that circularity, applied to memory instead of code.
kbg didn't need either article to reach this position — it's already load-bearing doctrine — but
the articles sharpen *where* it applies: contradiction resolution in a memory system is a verifier
act, and the extractor is never the right verifier for its own output.

**Consequence:** any contradiction-detection capability kbg builds must surface candidates for a
human (or a separately-invoked, adversarial pass) to decide — never auto-invalidate on ingest.
This directly shapes proposal A3 below (manual-trigger only, explicitly not scheduled).

---

## Part 3 — Current implementation, measured

### Architecture

Two layers, not one system:

1. **Native Claude Code auto-memory** (platform feature, `autoMemoryEnabled`, shipped ~CLI
   v2.1.59; confirmed via `skills/learn/SKILL.md`'s own documented verification against
   `code.claude.com/docs/en/memory`) — the model writes `memory/<slug>.md` files plus a
   `MEMORY.md` index directly, no per-write confirmation, whenever an in-the-moment trigger
   fires. This is the primary writer; kbg-harness has zero code path that intercepts, gates, or
   reroutes it. `kbg:learn` is the one supplementary writer (operator-invoked, retrospective
   whole-transcript sweep — the one thing native ambient capture structurally can't do:
   cross-turn pattern detection within a single already-finished session).
2. **kbg-harness's governance layer on top** — `skills/memory-lint/scripts/memory-lint.py`
   (deterministic detector: dangling links, orphans, index drift, load-budget cap, advisory
   staleness) plus its `--auto-archive` action mode (the A3 trim rubric — Class A
   stale-superseded, Class B near-budget-collapse, Class C dangling-link-rewrite, all `mv`-only,
   never `rm`) and `harness-audit` check 13 (MEMORY.md → file existence, one direction of the
   same drift memory-lint checks both directions of).

The memory type taxonomy itself (`user` / `feedback` / `project` / `reference`, each with a
one-line trigger description and a two-step save contract) lives in `~/.claude/CLAUDE.md`
— a symlink into the user's dotfiles repo, not a kbg-harness file, and per prior session findings
(`global-claudemd-symlink-dotfiles` memory) the Edit tool refuses to write through it. Any
taxonomy-level change is a Tier B item below, not a Tier A one.

### Live evidence (2026-08-07, `memory-lint.py` detector mode, read-only)

| Metric | Value |
|---|---|
| Memory entries (excl. `MEMORY.md` itself) | 178 files, 1.4 MB total |
| `MEMORY.md` index | 97 lines / 19,402 bytes — 76% of the 200-line/25,600-byte hard cap, already **past** its own documented ~17KB soft target |
| Total findings (exit code) | **87** |
| — UNINDEXED (file exists, no `MEMORY.md` pointer → never loads at session start) | **75 (42% of all entries)** |
| — ORPHAN (indexed, zero inbound/outbound `[[wikilinks]]`) | 10 |
| — DANGLING (`[[link]]` resolves to nothing) | 2 |
| Wikilinks written / resolved | 341 written, 167 successfully link a pair |
| Type distribution | project 98 (55%) · feedback 56 (31%) · reference 22 (12%) · user 1 (0.6%) · unparseable 1 |
| Entry size | min 791B · median 3,053B · mean 4,285B · max 33,417B (17 entries >8KB) |
| Template compliance, `feedback`+`project` only (n=154, the types whose own template requires it) | `**Why:**` present: 74/154 (48%) · `**How to apply:**` present: 106/154 (69%) |
| Typed relations among links | 5/341 (1.5%) — the free-text `**SUPERSEDED** by [[x]]` pattern; every other link is untyped |
| Version control on the store directory | **None.** `git rev-parse --is-inside-work-tree` fails — confirmed, not assumed. Only durable change signal is a single native `modified:` timestamp per file, overwritten on every edit |
| SessionStart automated surfacing of the above | **None currently wired.** `hooks/maintenance/memory-lint-check.sh` (the hook `skills/memory-lint/SKILL.md` still documents as active) was deleted in the 2026-06-27 "reset: rebuild from scratch" (`c452102`); `hooks/hooks.json`'s SessionStart array now contains only `command-root-anchor.sh` and `doctrine-bootstrap.sh` |
| Instrument for MEMORY.md's own session-start token/byte cost | **None.** `harness-audit --health` reports aggregate per-session model cost from the ledger, not a per-context-source breakdown; `context-budget` scans skills/agents/MCP/rules — zero mentions of `memory` (confirmed by grep) |

The single most load-bearing number here is **75/178 unindexed (42%)** next to **zero automated
surfacing** — this is Stanford's "maintenance... usually missing entirely" and Anthropic's
"a wrong memory... persists into every future session" as a measured, not hypothetical, fact
about this exact store, caused by a documented, dated regression (the doc still claims the safety
net exists; it hasn't since the reset).

---

## Part 4 — Improvements

### Tier A — ships in kbg-harness, no external dependency

#### A1. Restore SessionStart health surfacing + fix the SKILL.md drift — **SHIPPED v0.68.222**

Implemented as `hooks/session/memory-health-nudge.sh` (wired `session:memory-health-nudge`),
26/26 tests green in `tests/hooks/test-session-stop.sh`. One divergence from the plan below worth
recording: the directory-existence pre-check must use `pwd -P` (physical path), not `$PWD` — on
macOS `/tmp` and `/var` are symlinks into `/private/…`, so a naive `$PWD` substitution silently
never matched during this hook's own fixture testing (caught before shipping, not after).

**Current implementation.** `skills/memory-lint/SKILL.md` states: *"The SessionStart
memory-lint-check hook surfaces danglers each session (advisory; silent when clean)."* That hook
(`hooks/maintenance/memory-lint-check.sh`) doesn't exist — deleted in `c452102`, never rebuilt.
The detector script is correct and complete; nothing calls it automatically.

**Proposed implementation.** One commit:
1. Fix the SKILL.md line to state the true current state (no automated surfacing wired; run
   manually, or via the hook below once shipped).
2. Add `hooks/session/memory-health-nudge.sh` — SessionStart matcher (startup/resume, same
   category as `doctrine-bootstrap.sh`), calls `memory-lint.py --json` against the current
   project's memory dir, and if `findings > 0` prints one advisory line: `[memory-lint] N
   findings (U unindexed / O orphan / D dangling) — run kbg:memory-lint for detail`. Silent when
   clean, per the same convention `compliance-audit-nudge`/`learn-nudge` already use. No
   `permissionDecision` — pure advisory, matching CLAUDE.md's "gates deny, sensors journal"
   operating model.
3. Wire it into `hooks/hooks.json`'s SessionStart array.

**Why it should be better.** This is the exact gap both articles name: a forgetting/maintenance
policy that isn't wired doesn't exist in practice, no matter how correct the detector underneath
it is. A check nobody runs is not a control (Anthropic's "control is the design, not a layer on
top"). It also removes an active harm: the current doc doesn't just lack a safety net, it *lies*
about having one, which is worse than admitting the gap.

**Potential risks / regressions.** Nudge fatigue — 87 findings won't clear in one sweep, so the
line fires every session until fixed; mitigated by matching the existing one-line/silent-when-clean
convention the fleet already tolerates. SessionStart hooks must fail gracefully (never block
session start) if the script errors.

| Category | Baseline | Predicted | Basis |
|---|---|---|---|
| Correctness (doc matches reality) | 2/10 | 9/10 | SKILL.md asserts a hook that doesn't exist today; true after the fix |
| Robustness | 3/10 | 8/10 | Drift is currently permanent until someone happens to run the script by hand; nudge makes it self-correcting |
| Maintainability | 4/10 | 8/10 | One more hook, identical shape to 4 existing advisory hooks — low marginal complexity |
| Developer experience | 4/10 | 8/10 | False documentation misleads; fixed doc + working nudge restores trust |
| Memory quality (index health) | 3/10 (87 findings/178 entries) | target 9/10 (0 findings) | The one real instrument — `memory-lint.py` exit code |

**Evidence.** `python3 memory-lint.py` → 87 findings, live, this session. `git log --oneline -- hooks/maintenance/memory-lint-check.sh` shows the file existing through `b8e2109`, removed at `c452102`. `hooks/hooks.json`'s SessionStart array currently has exactly 2 entries, confirmed by direct read.

**Validation plan.** Baseline already captured (87). After shipping: bump plugin version, restart
Claude Code (cache-invalidation gotcha), start a fresh session, confirm the nudge fires once and
matches the live count with no `permissionDecision`. Clear a batch of UNINDEXED findings, re-run
the detector, confirm the count drops and the nudge updates on the next session. Run
`scripts/run-gauntlet.sh` for regression safety on the hook suite.

---

#### A2. Template-compliance visibility (`**Why:**` / `**How to apply:**`) — **SHIPPED v0.68.223**

Implemented as `template_compliance_findings()` in `memory-lint.py`, printed as an always-on
advisory section (no flag — matches the existing `staleness_findings()` precedent: advisory
sections in this tool are additive and never gate, so a flag added no real safety and only added
a surface to forget). Live run confirms the report's own baseline exactly: 74/154 (48%) `**Why:**`,
106/154 (69%→68% under `int()` truncation, matching the codebase's existing rounding convention)
`**How to apply:**`. 2 new tests in `tests/skills/memory-lint/test_memory_lint.py`.

**Current implementation.** `memory-lint.py` checks link/index/budget health but never checks
whether `feedback`/`project` memories follow their own documented template. Baseline: 74/154
(48%) have `**Why:**`, 106/154 (69%) have `**How to apply:**`.

**Proposed implementation.** Add a `--check-template` flag (opt-in, doesn't touch the existing
exit-code contract other tools like `harness-audit` check 13 may depend on) that prints the
missing-field count plus a sample of the worst offenders (neither field present). Advisory tier
only, same status as the existing staleness check — never counted toward exit code.

**Why it should be better.** Article 1's Microsoft finding is specifically that a fact/skill
beats a log because it carries *why it matters* and *how to act on it* — that's literally what
the template's two fields encode. A memory missing both fields is closer to Article 1's rejected
"raw history" pattern than to the "skill" its `type:` frontmatter claims it is. Roughly half of
kbg's feedback memories — the type most directly meant to change future behavior — currently
carry no stated reason, which matters concretely: kbg's own memory-authoring doctrine states the
Why is what lets a future session judge whether a rule still applies to a new situation; without
it, the memory can only be followed blindly, not reasoned about.

**Potential risks / regressions.** kbg has retired presence-only compliance checks twice already
(`type: command`, near-miss on `disable-model-invocation-reason`) precisely because they train
authors to paste filler that satisfies the check without adding value. Mitigation: this stays
strictly a *count*, never a gate, and is never wired into anything that blocks or scores a
commit — visibility only.

| Category | Baseline | Predicted |
|---|---|---|
| Memory quality (Why: compliance, scoped) | 48% (74/154) | not directly settable by code — visibility is the deliverable; trend becomes measurable session-over-session |
| Developer experience | 5/10 (no way to find undercooked memories) | 7/10 (greppable list, fixable opportunistically) |
| Maintainability | 6/10 | 6/10 (pure addition, flag-gated, no exit-code regression risk) |

**Evidence.** Direct scan of the live store, type-scoped to `feedback`+`project` (n=154): 74 have
`**Why:**`, 106 have `**How to apply:**` (computed and verified this session).

**Validation plan.** Run `--check-template` before/after any batch cleanup, diff the count.
Confirm exit code is unaffected when the flag is omitted — regression guard for existing callers.

---

#### A3. Manual-trigger contradiction detection (never scheduled, never auto-resolves) — **SHIPPED v0.68.223**

Implemented as `--find-contradictions` in `memory-lint.py`. **The proposal design changed during
implementation, based on the first real hand-run** — this is worth recording precisely because it's
exactly the "prove it by hand first" discipline the proposal itself argued for, catching a real
design flaw before it shipped:

- First implementation used "same `type:` AND (token-overlap ≥ threshold OR shared outbound
  `[[link]]`)" — run once against the live 178-file store, it returned **296 candidates**, almost
  all triggered purely by two memories citing one common well-known prior finding (e.g.
  `verify-adversarially-before-nothing`), independent of any real topical overlap.
- Removing the `OR shared_links` clause (making token-overlap the sole trigger, shared links
  reported as context only) dropped the same run to **4 candidates** — a genuinely reviewable
  number.
- Spot-checking those 4 by hand: **0/4 were real contradictions.** Two were a `SUPERSEDED` feature
  and its own already-cross-linked history note (`armed-push-review-path.md` /
  `l4-l5-autonomy-build.md` / `l3-bounded-autonomy-build.md` — all about the retired L2-L5
  autonomy ladder, ADR 0006); two were sequential phase-log entries of one project
  (`ecc-provenance-merge-phase3-2026-06-27.md` / `...-phase4-...`).

**This is a real, honest negative result, not a wasted effort**: 0/4 precision on the one hand-run
means this store currently has no detectable internal contradiction — exactly the confirmation
needed to justify NOT scheduling this tool, which was always the intended outcome of running it
once. The tool ships as a manual-only command; 4 new tests cover both the fixed heuristic and a
regression test for the shared-links-alone bug specifically.

**Current implementation.** None exists, not even manual. `memory-lint.py`'s own docstring
disclaims this scope ("semantic checks... are a separate LLM pass") but that pass was never
built. `kbg:learn` only scans a single session's transcript, not the 178-entry corpus.

**Proposed implementation.** `memory-lint.py --find-contradictions`: cheap deterministic
pre-filter (shared `[[links]]`, shared `type:`, filename/description token overlap above a
threshold) surfaces *candidate* pairs — no semantic judgment in the script itself. A human, or a
subsequently-dispatched agent, reviews the candidates. Never auto-resolves, never schedules
itself — this directly implements Part 2's resolution of the two articles' one contradiction, and
follows Article 1's own build order (Step 13: "prove each pass by hand first... if the output
genuinely changes a decision, it earns a schedule").

**Why it should be better.** Closes a gap kbg's own docs already flag as missing. Its human-gated
shape is required, not optional, given Part 2's finding that auto-invalidation is a
maker-grades-itself failure under kbg's own already-adopted doctrine.

**Potential risks / regressions.** Heuristic pre-filtering will over- and under-match — Article 1
warns explicitly that a system run against a handful of notes will hallucinate connections and
train users to ignore it. That's exactly why this ships as a one-off manual command, not a
scheduled job, until a hand-run proves the signal is real.

**Confidence: implementation feasibility HIGH (pure Python, no new dependency); value delivered
LOW/unmeasured** — no instrument exists yet for "how many real contradictions live in this
store," so no baseline or predicted score is given. Stating that plainly, per the task's own
instruction, beats inventing one.

**Validation plan.** Run once by hand against the real store. Count candidate pairs surfaced; of
those, count genuine contradictions vs. false positives (precision). Only consider scheduling or
formalizing further if precision is high enough that the output "genuinely changes a decision" —
Article 1's own bar — and record that number before deciding.

---

#### A4. Git-backed audit trail for the memory store — **SHIPPED v0.68.222**

Implemented as `hooks/stop/memory-audit-commit.sh` (wired `stop:memory-audit-commit`, `async:
true`, mirroring `stop:cost-tracker`'s own wiring), 26/26 tests green (same suite as A1). Design
decision made explicit here: the hook fires on **Stop** (per-turn), not `SessionEnd` — matching
this repo's own existing precedent for "don't lose the data" hooks (`stop:cost-tracker` uses Stop
for the same reason), not the once-per-session `SessionEnd` `learn-nudge` uses for its
lower-stakes advisory case. `git add`/`commit` is a no-op when the tree is already clean, so the
extra firing frequency buys finer rollback granularity at effectively zero cost. The live memory
store (`~/.claude/projects/<project-dir>/memory/`) was `git init`'d and
given a baseline commit as part of shipping this — see Part 3's live-evidence table for the
"before" state (confirmed no version control existed prior).

**Current implementation.** `~/.claude/projects/<enc>/memory/` is not a git repository (verified:
`git rev-parse --is-inside-work-tree` fails). The only change signal is a single native
`modified:` timestamp per file, overwritten on the next edit — no diff, no revert path beyond the
A3 trim rubric's `mv`-not-`rm` convention, which only protects *moves*, not in-place edits.

**Proposed implementation.** One-time `git init` inside the memory directory (user-run — this
touches a real directory outside the repo, so it needs explicit go-ahead, not silent execution)
plus a new advisory hook (session-boundary, e.g. piggybacked on A1's nudge or a SessionEnd
equivalent) that runs `git -C <memdir> add -A && git -C <memdir> commit -m "session <id>
snapshot"` when the tree is dirty.

**Why it should be better.** Anthropic's Step 10 is explicit: control is the design, and the
concrete mechanism named is export/audit-log/rollback/redact. kbg's memory currently has *weaker*
version control than every other file in this repo. Git is already installed and already the
project's standard tool — this is the cheapest possible way to close the gap, not a new
subsystem.

**Potential risks / regressions.** Initializing git in a directory the user didn't explicitly ask
to version-control is a real (if small) one-way-ish action — flag for confirmation, don't auto-run.
Auto-committing without review risks committing half-finished edits; mitigated by committing on a
session boundary (a natural checkpoint) rather than on every single write. Multi-year daily
commits will accumulate — periodic squash/gc is a non-blocking maintenance item, not a blocker.

| Category | Baseline | Predicted |
|---|---|---|
| Robustness / auditability | 2/10 (one mtime field, no diff, no revert) | 8/10 (full git history, matches repo standard) |

**Evidence.** `git rev-parse --is-inside-work-tree` failed against the live memory dir, verified
this session, not assumed.

**Validation plan.** After `git init` + hook: make a memory edit in a session, confirm an
automatic commit lands at session boundary, confirm `git log -p` shows the real diff, confirm a
deliberately bad edit can be reverted (`git checkout <path>~1 -- <file>`) without touching any
other memory file.

---

#### A5. Visibility for MEMORY.md's recurring session-start cost — **SHIPPED v0.68.223**

Implemented as a Phase 1 inventory line + a Phase 4 report row in `skills/context-budget/SKILL.md`.
One correction from the original proposal: `context-budget` turned out to have no scripts at
all — it's a pure prompt-driven skill (origin: ECC), not a runnable tool. "Extending" it means
adding an instruction + report-template row the model follows, not a code change. The byte→token
figure is explicitly labeled `(est.)` and reuses the skill's own pre-existing "prose files: word
count × 1.3" estimation rule — no new, unstated conversion assumption was introduced.

**Current implementation.** No tool reports MEMORY.md's byte/token contribution to every session
start. `harness-audit --health` is aggregate per-session model cost from the ledger, not
per-context-source. `context-budget` scans skills/agents/MCP/rules bloat with zero mentions of
`memory` (confirmed by grep against `skills/context-budget/`).

**Proposed implementation.** Extend `context-budget`'s scan with one line: MEMORY.md's current
byte size vs. its documented caps (200L/25,600B hard, ~17,408B soft target from its own header).
Report-only — reads a file, prints a number, no new subsystem.

**Why it should be better.** Article 1's central Stanford finding is that construction cost is
invisible because nobody measures it. For this store, the closest recurring analog is the
MEMORY.md load paid at every session start — and today it's genuinely unmeasured. It's already
past its own soft target (19,402B vs. 17,408B, 76% of the hard cap) with nothing surfacing that.

**Potential risks / regressions.** A bytes→tokens conversion must be labeled an estimate, not a
measurement — no tokenizer call is actually made. State the assumption (e.g. ~4 bytes/token for
English prose ⇒ ~4,850 tokens, *estimated*) rather than presenting a derived figure as measured.

**Baseline:** no instrument exists (new capability, not an improvement to an existing number).
**Predicted:** every `context-budget` run reports a real, reproducible byte count.

**Validation plan.** Run before/after; confirm the new line's byte count matches `wc -c
MEMORY.md` exactly — a deterministic correctness check, not a judgment call.

---

### Tier B — requires editing `~/.claude/CLAUDE.md` (dotfiles-owned symlink; name it, don't pretend it's a repo edit)

#### B1. Scoped relation vocabulary for wikilinks

**Current implementation.** Every `[[link]]` is untyped except the free-text `**SUPERSEDED** by
[[x]]` pattern (5/341 links, 1.5%). This is Article 2's exact complaint transposed to markdown:
every relationship is effectively `RELATES_TO`.

**Proposed implementation.** Extend the memory-authoring convention in
`~/.claude/CLAUDE.md`'s auto-memory section with an *optional* 3-verb vocabulary,
appended via the alias slot `memory-lint.py` already parses (`[[target|verb]]`):
`supersedes` / `contradicts` / `elaborates`. Kept to 3, under Article 2's own "start with 3-4,
capture 80%" guidance — `supersedes` already covers the highest-value case in prose form. Add a
`link_relation()` reporting view to `memory-lint.py` (e.g. "files with a `contradicts` edge") —
advisory only, never enforced.

**Why it should be better.** Article 2's core mechanism — typed edges make a graph queryable
instead of generic — does generalize to a 178-node store, just at 3 types instead of 10.

**Potential risks or regressions — HIGH, the most speculative item in this report.** At this
scale, with mostly organic prose-driven linking, mandating relation labels risks becoming exactly
the presence-only-boilerplate failure kbg has hit twice (`type: command`, near-miss on
`disable-model-invocation-reason`). It only pays off as a voluntary convention, not a requirement.

**Confidence LOW on adoption/value.** Baseline: 5/341 links (1.5%) carry any relation label
today. No predicted score is given — this is adoption-dependent, not code-forced.

**Validation plan.** After 90 days, grep for the three markers across the store. If usage stays
near zero, the convention failed adoption and should be dropped — per ponytail's own
"deletion over addition," unused surface area is a cost even when it's just a documented
convention, not code.

---

### Tier C — platform-constrained, not a proposal

**C1. "Always load whole MEMORY.md" vs. relevance-scoped, per-query retrieval (Article 2's
context-template idea).** This is Claude Code's own platform behavior — native auto-memory
decides what's injected at session start, and there is no documented hook point that runs before
that injection and can selectively omit lines. kbg-harness cannot intercept it. Stating this
plainly instead of proposing a fictional fix: the only lever kbg actually holds is MEMORY.md's
own density (already governed by the fold rule / 200L-25,600B cap and A5's new visibility), not
its loading mechanism. Revisit only if Claude Code ships scoped/topic-filtered memory loading.

**C2. Model-native memory management via fine-tuning (Memento's actual mechanism).** Missed in the
first pass, found on re-read: Article 1 flags this as the *first* thing to take from Memento, not
a footnote — its context compression is a trained model behavior, not orchestration bolted on.
That's categorically unavailable to a plugin author; kbg cannot fine-tune the underlying model.
Named for completeness, same boundary class as C1: the ceiling on how good context-compression
memory management can get here is Claude's own general capability, not a lever this repo can pull.

---

## Part 5 — Considered and rejected

| Idea | Why rejected |
|---|---|
| Auto-invalidating contradictions on ingest (Zep's pipeline behavior) | Resolved in Part 2 — a maker-grades-itself failure under kbg's own verifier-separation doctrine. A3 is the human-gated substitute. |
| Full Pydantic-style ontology (10 entity types × 10 edges × 10 fields) | Over-scoped for a 178-entry single-operator store. The existing 4-type taxonomy already plays the role Zep's ontology plays, at the right altitude for this scale; B1 is the appropriately-sized version. |
| Per-memory `last_verified` field | Already explicitly rejected in `memory-lint/SKILL.md` ("not worth the migration cost for a lint-surface add-on") — reaffirmed here, not reopened. |
| Nvidia's KV-cache / HBM / prefill-batching framing applied literally | Inapplicable — no GPU-serving layer exists for a personal markdown store. Only the session-start prefill-cost *analogy* survives, captured in A5; the hardware machinery itself doesn't transfer. |
| "`user`-type memory is only 1/178 — that's a coverage gap" | False positive. Durable user-facing facts (identity, accounts, conventions, communication style) already live correctly in `~/.claude/CLAUDE.md`, a different and correct storage location outside the per-project store. Near-zero count there is expected, not a defect. |

---

## Part 6 — Prioritization: Impact × Effort

| Item | Impact (1-5) | Effort (1-5, lower = less) | Ratio | Status | Notes |
|---|---|---|---|---|---|
| A2 — template-compliance visibility | 3 | 1 | 3.0 | **Shipped v0.68.223** | Extends existing script, always-on (not flag-gated — see A2's own note), zero regression risk |
| A1 — restore SessionStart nudge + fix doc drift | 5 | 2 | 2.5 | **Shipped v0.68.222** | Highest absolute impact; also the delivery mechanism A2/A3's findings need to actually get seen |
| A4 — git audit trail | 4 | 2 | 2.0 | **Shipped v0.68.222** | Live store `git init`'d + baseline commit; auto-commit + `git revert` rollback verified end-to-end |
| A5 — MEMORY.md cost visibility | 2 | 1 | 2.0 | **Shipped v0.68.223** | `context-budget` turned out script-less (pure prompt skill) — shipped as instruction + report row, not code |
| A3 — manual contradiction pass | 3 | 2 | 1.5 | **Shipped v0.68.223** | Design changed mid-implementation after the first hand-run found the original heuristic too noisy — see A3's own note |
| B1 — relation vocabulary | 2 | 3 | 0.67 | **Deferred** | Cross-repo (dotfiles) coordination + real adoption risk; lowest ROI in the set — no new evidence from A1-A5 changed that call |

**Implementation order actually followed** (impact-weighted, then Article 1's own build order —
index integrity and control first, forgetting/quality signals next, contradiction detection as a
bounded one-off, cost visibility last, speculative structure deferred). All five Tier A items
shipped across two sessions (v0.68.220 doc-drift fix → v0.68.222 A1+A4 → v0.68.223 A2+A3+A5),
matching this order exactly:

1. **A1** (shipped) — restore the surfacing loop + fix the doc lie.
2. **A4** (shipped) — git-backed audit trail; live store `git init`'d, rollback verified end-to-end.
3. **A2** (shipped) — template-compliance visibility, extending the same script.
4. **A5** (shipped) — MEMORY.md cost-visibility line, batched with A2 in the same session.
5. **A3** (shipped) — the manual contradiction pass was run once, by hand, against the real store
   before shipping — see A3's own note for the negative result (0/4 precision) that came out of
   that run and the design fix it drove.
6. **B1** — still deferred. Nothing in A1-A5's real output changed the original call: no evidence
   surfaced (from A3's run or organic `SUPERSEDED` usage) that relation-typing would have caught
   something the other four items didn't.

---

## Part 7 — Confidence ledger

| Claim | Status |
|---|---|
| 87 findings (75/10/2), 178 entries, MEMORY.md 97L/19,402B, template compliance 74/106 of 154, 5/341 typed links, no git in the memory dir, SessionStart hook deleted at `c452102` | **Measured**, this session, against the live store — reproducible by re-running the cited commands |
| ~4,850 tokens for MEMORY.md's session-start load | **Estimated**, not measured — stated bytes-per-token assumption (~4B/token), no tokenizer invoked |
| A3's real-world contradiction rate / precision | **Measured, one hand-run, 2026-08-07** (was "no instrument exists" until A3 shipped): 296 candidates under the original shared-links-OR heuristic, 4 under the fixed token-overlap-only version, 0/4 spot-checked as genuine contradictions. One data point, not a trend — re-run and re-check precision before ever considering automation |
| B1's adoption/value if shipped | **Low confidence** — adoption-dependent, no current usage signal beyond the 5 existing `SUPERSEDED` instances |
| Native auto-memory shipped ~CLI v2.1.59, autoMemoryEnabled | **Sourced** from `skills/learn/SKILL.md`'s own prior verification against `code.claude.com/docs/en/memory`, not re-verified independently in this session |
| Named primary sources exist and are real (Stanford, PlugMem, Memento, Anthropic) | **Verified 2026-08-07**, second pass — the original report cited these from the secondary-source article only, never independently checked. All four are real and findable (arXiv 2606.06448, 2603.03296, 2604.09852; claude.com/blog/claude-managed-agents-memory). One real risk found: a second, unrelated paper is also titled "Memento" (arXiv 2508.16153, opposite mechanism — non-fine-tuned case-based reasoning) — anyone re-verifying must match on content, not title. The Anthropic source is a product/customer-case-study blog post (Rakuten), not a peer-reviewed paper — a different evidentiary tier than the other three, despite Article 1 citing all four in parallel. |
| Headline numbers cross-checked against the found primary/secondary sources | 97% first-pass-error reduction and "~33%" faster verification: **match** the Anthropic source (97% / 34% lower latency) — the source also states 27% lower cost, which Article 1 doesn't mention (an omission in the article, not an error in this report). Stanford's "construction dominates cost" and PlugMem's "beat purpose-built designs across three tasks": **match** each paper's own stated findings. B200 throughput/latency numbers (4,290 vs 2,447 tok/s, 693s vs 1,096s): **plausible and consistent** with the Memento paper's described vLLM benchmarking setup, not independently re-derived from the paper's own tables — would need a full read of arXiv 2604.09852 to confirm exactly; not done here, stated as a scope limit, not a doubt. |
| "Four labs" framing (Stanford/Microsoft/Anthropic/Nvidia) | **Partially unsupported by the article's own sourcing.** No standalone Nvidia paper exists — Article 1's own Sources line says the hardware framing comes "from the H100, vLLM and B200 setups in the Stanford and Memento papers." Three papers plus one product blog post, not four independent sources. Doesn't invalidate the underlying hardware claims, but the framing this report inherited overstates source count by one. |
