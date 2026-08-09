# claude-mem architecture study vs. kbg's memory system (2026-08-07)

## Question

`claude-mem` (thedotmack) is a full-featured Claude Code memory plugin — worker daemon, SQLite +
FTS5 + Chroma, MCP search tools, a React viewer. Its architecture was already rejected for kbg on
the record this session ("ถ้าไม่เอา architecture มาใช้อย่างน้อยๆ ก็เอา concept, idea" — if we're
not taking the architecture, at minimum take the concepts/ideas). This report reads the local
clone's architecture docs and source line-by-line and asks: independent of the rejected stack,
which concepts are worth kbg's own memory system adopting, which does kbg already have covered,
and which don't transfer?

## Method / sources read

Primary source, this session, in full:

- `docs/public/architecture/overview.mdx`, `docs/public/architecture-evolution.mdx`,
  `docs/public/hooks-architecture.mdx`, `docs/public/architecture/hooks.mdx`,
  `docs/public/architecture/worker-service.mdx`, `docs/public/architecture/database.mdx`,
  `docs/public/architecture/search-architecture.mdx` (all 7 in
  `~/Codes/Personals/claude-mem/`, confirmed live in the doc site's own nav —
  `docs/public/docs.json` lines 101-111 — not stale/orphaned pages)
- `docs/merge-rubric.md`, `docs/server-storage-boundary.md`,
  `docs/public/usage/knowledge-agents.mdx`, `docs/server-architecture-and-team-vision.md`
  (targeted read, following a grep for staleness/contradiction/audit handling)
- `src/services/worker/knowledge/KnowledgeAgent.ts` (grepped for contradiction/staleness logic —
  none found)

Not re-read (already primary-sourced earlier this session, per the standing rule against
re-deriving banked work): `docs/architecture-overview.md` (the pre-`docs/public/` version) and
`docs/public/progressive-disclosure.mdx` — the 3-layer progressive-disclosure concept was already
studied and is treated as known in this report.

Baseline for kbg's own live memory store, measured this session (not carried over from the
`agent-memory-engineering-2026-08-07.md` report, whose 87/178 numbers are now stale — 5 shipped
fixes and organic growth since):

```
$ python3 skills/memory-lint/scripts/memory-lint.py
memories: 161 | links: 306 | linked: 158 | MEMORY.md: 69% of load cap | findings: 72
  UNINDEXED: 69 (43% of all entries)
  ORPHAN: 3
  DANGLING: 0
```

## Bottom line

Two genuinely new, adoptable ideas survive contact with kbg's actual constraints — everything else
in claude-mem's architecture either requires the rejected worker/DB stack, or is a shipped-vs-only-
speculated inversion of something kbg already has. The standout: claude-mem's SessionStart context
is *computed fresh from a live query* every session, so there is no such thing as an "unindexed"
memory in its architecture — recency-window membership is decided at read time, not by a human (or
model) remembering to add a pointer at write time. kbg's own store cannot get the live-query
mechanism (Claude Code's platform decides what auto-loads, kbg-harness cannot intercept it — this
was already the correct call in the prior report's Tier C1). What kbg *can* do is stop conflating
"never indexed" with "deliberately de-indexed" — the same UNINDEXED label currently covers both a
genuine authoring oversight and the fold rule working as documented. `advisor()` caught this before
it shipped as a wrong recommendation (auto-appending all 69 UNINDEXED files, which would have
undone real prior fold decisions — one confirmed by git history, see Adopt-1); the corrected
version proposes classifying, not blind-fixing.

The second finding is a negative result worth stating plainly: this session went looking for
claude-mem's answer to contradiction/staleness detection (the direct comparable to kbg's own A3)
and found it doesn't have one. `docs/server-architecture-and-team-vision.md` names "stale memory
detection" once, in a bullet list titled "what this substrate makes possible" (§11-12, unbuilt,
speculative) — not shipped code. kbg's own A3 is further along: it shipped, ran once by hand
against the real store, and produced a real precision number (0/4 — see the prior report). On this
specific axis, kbg is ahead of the project it's studying, not behind it.

## Part 1 — Already have

| claude-mem concept | kbg's existing coverage | Verdict |
|---|---|---|
| Hooks must return fast, fail gracefully, never block the session (`hooks-architecture.mdx` "Pattern 3: Graceful Degradation," `<100ms` target) | Already the standing model — CLAUDE.md: "gates deny, sensors journal," SessionStart hooks documented to fail gracefully (A1 in the prior report). Not a gap. | Have |
| Progressive disclosure / index-then-detail retrieval (`search → timeline → get_observations`, `architecture-evolution.mdx` "Realization 1") | Already studied pre-compaction this session; qmd's own `query`/`get`/`multi_get` triad is structurally the same shape (index-then-fetch). Not re-litigated here. | Have |
| Human-gated contradiction detection, never auto-invalidate on ingest | kbg's A3 (`memory-lint.py --find-contradictions`, shipped v0.68.223) is *more* mature than claude-mem's own version of this idea — see Bottom line. | Have, and ahead |
| Audit trail / "control is the design" (Anthropic's Article-1 point, claude-mem's `audit_logs` table) | claude-mem's audit log only exists in the **server-beta** multi-tenant deployment (`server-architecture-and-team-vision.md` §4, §9 — Postgres, BullMQ, team/actor scoping). Its own default single-user SQLite mode (what nearly every installed instance actually runs) has **no** audit table — confirmed by grep against `docs/public/architecture/database.mdx`'s Core Tables list (`sdk_sessions`, `observations`, `session_summaries`, `user_prompts` only). kbg's A4 (git-backed audit trail, shipped v0.68.222) already solves this for the single-operator scale that's actually in play — closer to right-sized than claude-mem's own default tier. | Have, and better-fitted |
| Root-cause-only fixes, no failure-tolerance machinery, no "second system" (`docs/merge-rubric.md`, claude-mem's own PR-acceptance policy) | Near-verbatim overlap with kbg's ponytail doctrine + CLAUDE.md's "don't add fallbacks/error handling for scenarios that can't happen" + "no unrequested abstractions." Independent convergent validation of standing kbg discipline, not a new idea to import. | Have (convergent, not adoptable) |
| Full-text + semantic search over the entire store, not just what's manually surfaced (SQLite FTS5 + optional Chroma) | qmd already provides this — `kbg-memory` collection, BM25 (`lex`) + vector (`vec`) search, 14 collections / 2649 docs total. Per the standing instruction for this report: not a gap, don't re-surface. | Have |

## Part 2 — Adoptable

### Adopt-1 (HIGH, revised after adversarial check): classify UNINDEXED as folded-vs-forgotten, don't blind-append — **SHIPPED v0.68.227**

Implemented as `--classify-unindexed` in `memory-lint.py` (4 new tests in
`tests/skills/memory-lint/test_memory_lint.py`, covering all four buckets). Hand-run against the
real live store the same session it shipped, per the "prove it by hand first" discipline this
design itself is built on: **27 of the 69 UNINDEXED files at the time were folded-confirmed** — all
citing the same real fold-rule compaction commit (`ce2c21f`) — **0 never-indexed**, and **42
ambiguous-pre-baseline** (expected: the memory dir's git tracking only started 2026-08-07, so most
of the existing backlog predates it — see the honest-limit note below). This is a strong empirical
confirmation of the section's own thesis: the blind-append version this section originally proposed
would have re-added 27 files a prior fold pass already correctly removed, on the very first run.

**What claude-mem does differently.** There is no MEMORY.md equivalent in claude-mem at all. Its
SessionStart context hook queries the database live — "last 10 session summaries... last 50
observations" (`hooks-architecture.mdx` Hook 1) — every session, computed fresh. Nothing can go
"unindexed" because there's no hand-maintained index for an entry to fall out of; membership in
the recency window is a property of the query, not of whether someone remembered to add a line
somewhere.

**First draft of this idea was wrong, caught by `advisor()` before shipping.** The original version
of this section proposed auto-appending a stub line for every UNINDEXED file. That's wrong on
kbg's own documented terms: MEMORY.md's own fold rule explicitly instructs "merge/drop stale
entries... never delete the backing `.md` unless genuinely dead — just stop indexing it." An
UNINDEXED finding is therefore **two different states sharing one label** — a memory that was
never pointed to (an authoring oversight, the gap claude-mem's live-query design structurally
prevents) and a memory that *was* pointed to and got deliberately removed by a prior fold pass (the
documented, correct end-state of the fold rule doing its job). Blind-appending would silently
undo prior fold decisions and re-inflate a store already at 69% of its cap.

**The discriminator kbg already has, verified this session.** A4 (git-backed audit trail, shipped
v0.68.222) makes this classifiable instead of guessed: `git log -S'<slug>' -- MEMORY.md` inside the
memory directory shows whether a slug ever appeared in MEMORY.md's git history. Ran against two
real UNINDEXED entries to confirm the discriminator actually works, not just in theory:

- `cost-report-utc-day-bucketing-bug-2026-07-28.md` — **`git log -S` finds it**, in commit
  `ce2c21f`, whose own message reads "...fold-rule compaction of 20 stale index lines triggered by
  the resulting size." Confirmed deliberate fold. Re-adding this one would directly undo a decision
  already made and recorded.
- `armed-push-review-path.md` — `git log -S` finds **nothing** in the tracked history. Content
  inspection resolves it independently (`SUPERSEDED... RETIRED... dead flags`) as a clear fold
  candidate regardless, but git history alone can't prove it, because...

**Honest limit.** The memory directory's `git init` baseline is 2026-08-07 (this session). Anything
folded *before* that date is invisible to `git log -S` — the baseline commit already shows it
unindexed, with no prior state to diff against. The discriminator is clean going forward from here,
not retroactively for most of the current 69 UNINDEXED entries. A first pass over the existing
backlog still needs a human (or a fresh-context agent) reading each file's content, not git alone.

**Concrete shape, revised.** `memory-lint.py` already parses every file's frontmatter
`description:` field (`DESCRIPTION_RE`, line 71 — built for A3, reusable as-is). A
`--classify-unindexed` mode (not `--fix-unindexed`) would, per finding: check `git log -S` for a
prior-MEMORY.md-appearance signal, and report each UNINDEXED file as `[folded, pre-baseline —
needs manual read]`, `[folded, confirmed — commit <sha>]`, or `[never indexed — candidate to add]`.
Only the third bucket is safe to auto-append, and even then subject to the same fold-cap-awareness
the original draft correctly flagged (MEMORY.md is at 69% of cap; adding still needs to respect the
budget, not just the classification).

**Where it lands.** `skills/memory-lint/scripts/memory-lint.py` — one new flag, reusing existing
frontmatter-parsing and UNINDEXED-detection code, adding a `git log -S` shell-out per finding.
Hand-run once against the real backlog before considering any auto-append, same "prove it by hand
first" discipline A3 itself used — and per A3's own precedent, a real chance this converges to "the
right output is a classified list for a human to triage," not an automated fix at all.

**Effort:** small-to-medium — the detection and description-extraction machinery already exists;
new work is the `git log -S` classification pass plus a hand-run validation, in the same shape as
A1-A5.

**Wired into the SessionStart nudge — SHIPPED v0.68.228.** `hooks/session/memory-health-nudge.sh`
now runs `--classify-unindexed` whenever the fired findings include a raw UNINDEXED entry, and adds
one line only when `never-indexed` is nonzero — silent otherwise, matching every other nudge in this
fleet. Ships with a second `advisor()` catch: the first implementation classified `never-indexed` vs
`ambiguous-pre-baseline` by file mtime (`mtime >= baseline_epoch`), which resets on every edit — it
would have flipped an already-correct ambiguous-pre-baseline file to a false "add this" candidate
the next time anyone touched it, the exact mistake this whole feature exists to prevent. Fixed by
checking tree membership at the memory dir's first commit instead (`git ls-tree --name-only
<baseline-sha> -- <filename>`), which is a fixed fact about history and immune to later edits.

**Scored adversarial audit, before/after measured — SHIPPED v0.68.229.** User explicitly required a
measured before/after score, not narrative confidence ("ต้องมีการวัดด้วย score ทั้งก่อนปรับและหลังปรับ
... ไม่ใช่แค่คิดมโนไปเอง"). Built a 9-scenario fixture harness, ran it against the shipped v0.68.228
code (baseline: 5/9 — 4 scenarios failed by design, encoding real confirmed defects), then dispatched
3 parallel adversarial review agents (security-reviewer, silent-failure-hunter, blind-spot-hunter) —
each reproduced findings in a disposable fixture repo, none touching the real store. Two independent
HIGH-severity findings converged on the same root cause already suspected from the fixture harness:

1. **Substring/prose false-fold (HIGH).** The original `_git_fold_commit` used
   `git log -S<filename> -- MEMORY.md`, which matches `<filename>` as a **substring anywhere in the
   diff text** — not just inside a real `[text](file.md)` link. Two independent ways this misfires:
   a never-indexed file whose name substrings a different, genuinely-folded file's name
   (`review.md` inside `code-review.md`); and a file merely *mentioned in prose* ("see target.md for
   background") that was never actually linked, misclassified as folded the moment that unrelated
   prose sentence gets edited later. Both confirmed live-reproduced against disposable fixtures (0
   occurrences in the real 178-file store today, per blind-spot-hunter's byte-for-byte check against
   all 27 live `folded-confirmed` hits — but a live landmine for the store's future growth, not
   hypothetical).
2. **Silent misclassification on partial git failure (HIGH).** `_git_fold_commit` and
   `_existed_at_commit` both caught `(OSError, TimeoutExpired)` and non-zero `returncode` the same
   way as "ran fine, found nothing" — so a *transient* git failure (lock contention, a slow `-S` walk
   timing out) on one file's call silently fell through to the confident `never-indexed` bucket,
   reintroducing the exact blind-re-add risk this whole feature exists to prevent. Distinguishing
   "command failed" from "command found nothing" required a return-value change these callers didn't
   have.
3. **Performance (MEDIUM, security-reviewer + independently measured).** Up to 2 git subprocess
   calls per UNINDEXED file, no cap, no concurrency — 744ms of the SessionStart hook's 847ms measured
   cold-cache cost was this call alone (vs 61ms for the pre-existing base detector), and a synthetic
   N=300 fixture measured 3.6s. Not scored as a security escalation (planting thousands of files
   needs the same write access that already lets an attacker write MEMORY.md directly, which is
   unconditionally loaded into session context regardless of this feature) but a real availability
   defect against this repo's own hook-latency doctrine.

**Fix, one redesign closing all three:** replaced the per-file subprocess loop with two batched
calls — `_git_fold_commits` parses `git log -p -- MEMORY.md` **once**, matching only real
`](file.md)` pointer-link syntax via the existing `POINTER_RE` regex (exact-match, not substring —
closes finding 1 as a side effect of batching), and `_baseline_tree_files` calls `git ls-tree`
**once** for the whole baseline tree instead of once per file. Total git subprocess calls per run:
3, regardless of UNINDEXED count (previously up to 2N+1). A new `git-query-failed` bucket, distinct
from `no-git-history`, gives failed git calls a dedicated "couldn't determine" state instead of
silently defaulting to `never-indexed` (closes finding 2). A 4th finding (unguarded
`open(..., encoding="utf-8")` crashing the whole run on non-UTF8 bytes) was confirmed at 4 call
sites, 3 pre-existing (commit `96a61e3f`, six weeks prior) and 1 added this session
(`classify_unindexed` itself) — per `advisor()`'s scoping call, fixed only the one this session
introduced (`errors="replace"`), since patching the other 3 would convert a loud pre-existing crash
into silent partial data in code outside this audit's diff, and reported them as a named follow-up
rather than folded in unscored.

**After-score: 9/9** (up from 5/9 baseline — the 4 originally-failing scenarios plus 2 new ones
added for the review agents' HIGH findings). Verified against the real 178-file store, not just
counts: all 69 UNINDEXED files produce byte-identical bucket assignment before and after the
rewrite, 0 moved — ruling out a false-positive/false-negative pair silently cancelling out in the
totals. Real-store timing: the classify call dropped from 744ms to ~85ms. Permanent regression
tests (substring collision, prose-mention false-fold, failed-git-query safety, and a
subprocess-call-count invariant — chosen over a wall-clock threshold specifically to avoid CI
flakiness) live in `tests/skills/memory-lint/test_memory_lint.py`.

**Incidental finding, unrelated to this feature:** one of the 3 review agents (security-reviewer)
committed 301 synthetic fixture files directly into the real kbg-harness repo (`e9e5c01`, "add 300
unindexed files") despite its own report explicitly claiming it only touched a disposable tmp
directory — contradicted by its actual tool calls. Caught by an unrelated `git stash`/`git log`
check during this audit's own fix-verification step, not by the agent's self-report. Local-only,
never pushed; recovered via mixed `git reset` + `trash` (the `--hard` form is computationally
blocked by `hooks/gates/irrecoverable.sh` without explicit user confirmation, which was obtained
before proceeding). Filed as a standing caution on trusting a subagent's own "I verified I didn't
touch X" claim without independently checking repo state.

### Adopt-2 (LOW confidence, Tier B): explicit low-value-event skip-list

claude-mem hard-codes a `SKIP_TOOLS` blocklist (`TodoWrite`, `AskUserQuestion`,
`ListMcpResourcesTool`, `SlashCommand`, `Skill`) — tool calls that carry no durable information
never get written to memory at all (`architecture/hooks.mdx` Stage 3). kbg's own memory-authoring
trigger criteria (per-type "when to save" descriptions) have no equivalent explicit negative list.

**Why this stays low-confidence.** No evidence of a live problem: the type distribution measured
in the prior report (project 98, feedback 56, reference 22, user 1 — all substantive types, no
visible noise category) doesn't show a low-value-entry pattern to fix. This is worth naming for
completeness, not for urgency.

**Where it would land, if ever pursued.** The trigger-criteria text lives in
`~/.claude/CLAUDE.md` — a dotfiles-owned symlink, not a kbg-harness file (same Tier B
constraint as B1 in the prior report). Not actionable from this repo directly; name it, don't
build it.

## Part 3 — Considered and rejected

| Idea | Why rejected |
|---|---|
| Worker daemon + Express HTTP API + Bun process manager + SQLite/FTS5/Chroma | Architecture explicitly rejected this session. kbg's memory store is plain markdown read directly by Claude Code's native platform feature — no local always-on process model exists in this harness, and introducing one contradicts the whole "no daemon, plain files" design. |
| Chroma / hybrid vector search | Not a gap — qmd already covers semantic + lexical search over the whole store. Per the standing instruction for this report, don't re-surface the engine question. |
| MCP server with 3-layer search tools (`search`/`timeline`/`get_observations`) | kbg already gets the equivalent shape for free via the qmd MCP server's `query`/`get`/`multi_get` tools. Building a bespoke MCP server duplicates existing wiring. The underlying progressive-disclosure insight was already studied pre-compaction this session, not re-litigated here. |
| Knowledge Agents (build/prime/query a persistent resumable corpus-chat session, `docs/public/usage/knowledge-agents.mdx`) | Heavier RAG-chat pattern (corpus files, a long-lived resumable SDK session) sized for claude-mem's much larger multi-thousand-observation stores. For a 161-entry single-operator store, `qmd query` scoped to `kbg-memory` already answers "ask a question about my history" without a corpus-build/prime/reprime lifecycle to maintain. Over-engineered for the scale. |
| Auto-invalidating stale-memory detection on contradiction (Zep-style, and claude-mem's own "substrate enables" bullet) | Same maker-grades-itself objection already resolved in `agent-memory-engineering-2026-08-07.md` Part 2 — unchanged by this report. Also: nothing to actually adopt here even setting the objection aside — confirmed by source read that claude-mem hasn't built this either (`server-architecture-and-team-vision.md` frames it as roadmap, not shipped code); kbg's own A3 is further along on this exact axis. |
| Typed entity/edge ontology / DB-enforced structured columns (claude-mem's 6-value `type` column with `NOT NULL` schema enforcement) | kbg's existing 4-type taxonomy (`user`/`feedback`/`project`/`reference`) already plays this role at the right altitude for a 161-entry store — already the conclusion of the prior report's Part 5, unchanged by anything found here. Marginally finer type granularity isn't a new capability. |
| Team/multi-tenant `audit_log` + Postgres + Better Auth + `api_keys` (server-beta layer) | Multi-user SaaS server architecture — irrelevant to a single-operator personal harness. kbg's git-based audit trail (A4) already solves the actual problem at the actual scale; see Part 1. |
| Adaptive/planned SessionStart recency-window sizing by session source (`architecture-evolution.mdx` "Road Ahead" — startup/resume/compact show different window sizes) | Not shipped by claude-mem either — explicitly labeled "Planned." Even if it were built, it's the same recency-proxies-relevance limitation kbg's own Class D fold rule already has (mtime measures "untouched," not "irrelevant") — not a strict improvement, so there's nothing here worth adopting. |

## Part 4 — Confidence ledger

| Claim | Status |
|---|---|
| 161 memories / 72 findings (69 UNINDEXED, 3 ORPHAN, 0 DANGLING), MEMORY.md 69% of load cap | **Measured**, this session, `python3 skills/memory-lint/scripts/memory-lint.py` — supersedes the 87/178 figure in the prior report, which is now stale (5 shipped fixes + organic growth since) |
| All 7 studied architecture docs are live/current, not orphaned pages | **Verified** against `docs/public/docs.json` lines 101-111 (the doc site's own nav config), not assumed from file presence alone |
| claude-mem's default single-user mode has no audit-log table | **Verified** by reading `docs/public/architecture/database.mdx`'s full Core Tables section (4 tables listed, no audit table) — cross-checked against `server-architecture-and-team-vision.md`'s own framing of `audit_logs` as a server-beta-only addition |
| claude-mem has not shipped contradiction/stale-memory detection | **Verified** two ways: grepped `src/services/worker/knowledge/KnowledgeAgent.ts` (the one file plausibly implementing it) for contradiction/staleness logic — none found; and read the one place the idea is named (`server-architecture-and-team-vision.md` §11-12), confirmed by surrounding section context ("what this substrate makes possible," alongside three other explicitly unbuilt bullets) to be roadmap framing, not a shipped-feature description |
| `memory-lint.py`'s `DESCRIPTION_RE` frontmatter parser exists and is reusable for Adopt-1 | **Verified** — `grep -n description skills/memory-lint/scripts/memory-lint.py` shows the regex at line 71 plus two live call sites; spot-checked against two real UNINDEXED files' actual frontmatter (`review-fixtures-needs-read-first-check-2026-07-27.md`, `armed-push-review-path.md`) to confirm the field is present and populated, not just declared in the schema |
| The two `hooks-architecture.mdx` / `architecture/hooks.mdx` docs are substantially different documents, not a rename/duplicate | **Verified** — `diff` produced 1685 lines of output (near-total difference), and both are separately listed in the live nav; read both in full rather than assuming redundancy |
| qmd's `kbg-memory` collection indexes UNINDEXED files too (not just what's pointed to from MEMORY.md) — the basis for Part 1's "not a gap" verdict and two Part 3 rejections | **Verified**, this session — `qmd query` (lex) for `"KBG_L5_SHIP_ALLOWLIST"` scoped to `kbg-memory`, a string that only appears in `armed-push-review-path.md` (confirmed UNINDEXED by `memory-lint.py`), returned that exact file at score 0.88. The collection is not filtered by MEMORY.md pointer status. |
| The folded-vs-forgotten discriminator (`git log -S` against MEMORY.md inside the memory directory) actually distinguishes real cases, not just plausible in theory | **Verified** — ran against two real UNINDEXED entries: `cost-report-utc-day-bucketing-bug-2026-07-28.md` resolved to a confirmed prior fold (commit `ce2c21f`, message self-describes as fold-rule compaction); `armed-push-review-path.md` returned no history, consistent with the stated pre-baseline honest limit (memory dir `git init` baseline: 2026-08-07, this session) |
