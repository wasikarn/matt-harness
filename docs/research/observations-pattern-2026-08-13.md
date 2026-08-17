# Zep "Observations" → kbg `--find-patterns`: constrained synthesis over deterministic structure (2026-08-13)

## Question

Akshay Pachaar's article *Your Agent Remembers Everything and Understands Nothing* (2026-08-09, Zep-sponsored; raw at `~/llm-wiki/raw/Your Agent Remembers Everything and Understands Nothing.md`, llm-wiki synthesis at `wiki/ai-agents/knowledge-context/structured-memory-for-agents.md`) describes Zep's **Observations** feature. Its core mechanism is a two-stage pipeline: a **deterministic** algorithm decides which facts group together, then an **LLM writes prose** over the structure the algorithm already decided — the model never decides what gets grouped.

Is the one transferable idea worth borrowing into kbg-harness's memory store, and if so, what's the faithful adaptation — not a cargo-cult of the whole platform?

## The mechanism (what to borrow)

Zep reduces every fact to a **signature** (the two entities it connects + the relationship type), builds an **episode graph** where conversations are nodes and **shared signatures** are edges, then takes **connected components** as the clusters. A single constrained LLM call then writes a name + summary over each cluster, steered toward durable signals (decisions, constraints, dependencies) and restricted to evidence the graph explicitly supports.

Three properties matter:

- **Pure graph topology** — no embeddings, no semantic similarity, no ML model in the grouping step. Embedding-based clustering groups content that *discusses similar topics* (all status updates cluster together); signature-based clustering groups episodes that *reference the same relationships between the same entities*, which is what makes a specific cross-conversation chain detectable.
- **Transitive bridging** — Alice's update and Clara's update join the same cluster despite sharing no entity, because Bob's update bridges both sides. The connected component catches two-hop structure a single retrieval pass cannot.
- **Maker/verifier separation** — every structural property (which entities, which conversations, the time window) is decided by the algorithm. The LLM only turns that structure into readable prose. This is why observations are read-only: they're structural properties of the graph described in natural language, not opinions.

## Convergence with harness doctrine

That last property is the unifying crux. kbg-harness's own operating model (CLAUDE.md) is: **the gate is a verifier, the model is the maker, and the maker can never grade its own work.** Zep's "deterministic algorithm decides the grouping, LLM only writes prose" is the same separation arriving from the memory side. The adaptation must preserve it: the grouping is deterministic; synthesis is a separate, manually-pasted LLM step, never in-loop.

## The mapping into kbg's store

kbg's memory store is not a knowledge graph — it's curated one-lesson-per-file markdown with `[[wikilinks]]` as the connective tissue. The mapping:

| Zep | kbg |
|---|---|
| Episode (one conversation) | One memory file |
| Signature (entity pair + relationship) | A **resolvable** outbound `[[link]]` target (target exists as filename stem or `name:` slug) |
| Episode graph (shared signatures = edges) | File↔file graph (shared resolvable link targets = edges) |
| Connected component | Recurrence cluster |
| LLM summary call | `--prompt` paste block (manual, never in-loop) |

Dangling links (target resolves to nothing) are skipped — they're noise, not signatures, so they don't seed edges. This mirrors `collect_state`'s existing resolvability check (memory-lint.py ~line 187).

## Decision: `--find-patterns` mode, deterministic-only, no always-on layer

**What ships (v0.68.264):** a new `--find-patterns` mode on `skills/memory-lint/scripts/memory-lint.py` — `pattern_clusters(state, min_cluster, max_cluster)` builds the file↔file graph via union-find and reports connected components of size ≥ `--min-cluster` (default 3) and ≤ `--max-cluster` (function default 0 = no cap, **superseded at the CLI layer by a default of 10, v0.68.317** — see `skills/memory-lint/SKILL.md` § "Pattern clusters"); `--prompt` emits one paste-ready, evidence-constrained synthesis prompt per cluster. The script never calls an LLM. Documented in `skills/memory-lint/SKILL.md` ("Pattern clusters" section + Checks table row). One regression test in `tests/skills/memory-lint/test_memory_lint.py`.

**Why not a Zep-like always-on layer:**

1. **This repo's memory architecture already rejected heavy read-time-synthesis tools** (incl. Zep) in favor of write-time curation — one curated line per lesson, paid at write time (`docs/research/agent-memory-engineering-2026-08-07.md`, `memory-architecture-tabula-rasa-debate`). The curator already wrote the pattern into the memory itself at write time; an always-on synthesis pass re-deriving it at read time is redundant by design and pays the construction cost the Memory Engineer article warns against (Stanford: construction burns more energy than ~300 subsequent queries).
2. **The falsification trigger is unfired.** The rejection came with a stated trigger: ≥5 episodic queries in 2 weeks that grep + git + wiki + hotcache can't answer → only then reconsider heavy memory tools; don't re-evaluate before 2026-10-18. No such run has occurred. Borrowing the one transferable idea as an on-demand manual tool does not require relitigating the always-on decision.
3. **Maker/verifier holds.** An in-loop LLM that both groups memories and writes the summary is the maker grading its own grouping — the same circularity the harness rejects everywhere else. The deterministic pass groups; a separately-pasted LLM call synthesizes; the human curator reads and decides.

So the faithful adaptation is **not** the Zep platform — it's the one durable idea (constrained synthesis over deterministic structure) extracted into the smallest surface that preserves the doctrine: a manual, deterministic cluster report that feeds the curator on the rare occasion recurrence is worth checking.

## Live-run finding: dense stores produce one giant component

The first hand-run against the real store (2026-08-13) at `--min-cluster 3` returned 6 clusters: one of **size 102** (most of the store, chained transitively through popular hubs like `verify-adversarially-before-nothing`, `harness-engineering-2x2-model`) plus 5 tight small clusters (sizes 5/4/4/4/3) bound by specific shared lessons (`re-review-after-every-fix-round-2026-07-25`, `delegation-validation-is-orchestrator-role-2026-07-16`, `askuserquestion-consistency-gap-2026-07-02`).

This is the expected behavior of connected components on a dense graph — a curated store that encourages linking *should* be mostly connected. The giant component is "the graph is connected," not a pattern. The real recurrence signal is in the **small, tight clusters** (few members, few shared links).

A first-draft instinct was to tell users to raise `--min-cluster` to filter the giant. That is **backwards**: the giant is the *largest* component, so raising the lower bound filters the small clusters first and leaves only the giant (confirmed live: `--min-cluster 8` returns *just* the size-102 blob). There is no `--min-cluster` value that hides the giant but keeps the tight groupings — they overlap in the wrong direction. The principled fix is an **upper bound**, `--max-cluster`: `--find-patterns --min-cluster 3 --max-cluster 10` returns exactly the 5 tight clusters and hides the giant. This was added the same session the live run surfaced the flaw — the plan's "raise `--min-cluster`" guidance was corrected from evidence before it shipped, not after.

This is the same noise the contradiction pre-filter found with shared-link-as-trigger — and the same observation inverted: noise for contradiction-hunting *is* the signal for recurrence. The two modes stay separate (`--find-contradictions` hunts disagreement with token-overlap as the primary trigger; `--find-patterns` hunts recurrence with shared links as the primary trigger) because their signals and outputs differ.

This stays a manual, occasional tool — it earns a schedule only if a future hand-run's precision says otherwise (same bar as the contradiction pre-filter, per `docs/research/agent-memory-engineering-2026-08-07.md` Article 1: "prove each pass by hand, then automate").

## Cross-refs

- `docs/research/agent-memory-engineering-2026-08-07.md` — the memory-architecture decision that rejected heavy read-time-synthesis tools in favor of write-time curation; the falsification trigger; Article 1's "prove each pass by hand, then automate."
- `~/llm-wiki/wiki/ai-agents/knowledge-context/structured-memory-for-agents.md` — the three-angle synthesis (lifecycle cost / ontology schema / code graph) this article extends; "the agent should reference what it knows, not re-derive it."
- `skills/memory-lint/SKILL.md` "Pattern clusters" section — the user-facing docs for the mode.
- CLAUDE.md operating model — the maker/verifier separation this adaptation preserves.