---
name: memory-lint
description: "Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health."
---

# memory-lint

Karpathy's llm-wiki **Lint** operation for the memory store: catch the bookkeeping rot a human would let slide — dangling `[[links]]`, orphaned facts, index drift. Deterministic; judging whether a candidate is a real contradiction is still a human (or separately-invoked LLM) call — `--find-contradictions` only narrows the field, it never rules.

**When to use:** after writing/editing/removing memories, or on demand to check memory health.

**When NOT to use:** writing a memory (just Write it + add the MEMORY.md line), semantic review of memory *content*, or skill-ecosystem health (use `harness-audit`).

## Run

```bash
# Detector mode (default — read-only, exit code = finding count)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py"
# or point at a specific store:
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" /path/to/memory

# Action mode (apply the A3 trim rubric — dry-run by default)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --auto-archive --dry-run
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --auto-archive --yes

# Contradiction pre-filter (manual, one-off — see "Contradiction pre-filter" below)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --find-contradictions
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --find-contradictions --min-overlap 0.5

# UNINDEXED fold-vs-forgotten triage (manual, read-only — see below)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --classify-unindexed
```

Auto-derives the store from the current repo (`~/.claude/projects/<enc>/memory`). Exit code = finding count; 0 = clean. Two advisory sections print below the findings and never affect the exit code: staleness (mtime-based — tune with `--stale-days N`, default 90) and template compliance (`**Why:**`/`**How to apply:**` coverage for `feedback`/`project` memories) — see Checks table for both.

## Contradiction pre-filter (`--find-contradictions`)

A deterministic, manual-only candidate surfacer — never a scheduled job, never an auto-resolver. Pairs same-`type:` memories whose filename+description token-overlap crosses `--min-overlap` (default 0.35); a shared outbound `[[link]]` is reported as *context* alongside a qualifying pair, never as an independent trigger.

**Why never a trigger on its own:** the first hand-run against this store (2026-08-07) used "shared link OR high overlap" and returned 296 candidates on 178 files — almost all of them pairs that merely cite one common well-known memory (e.g. `verify-adversarially-before-nothing`), not anything resembling a contradiction. Token-overlap alone, same threshold: 4 candidates. That run's own spot-check found 0/4 were real contradictions (two were a SUPERSEDED feature and its own already-cross-linked history note; two were sequential phase-log entries of one project) — a negative result, and a useful one: it confirms the store had no detectable internal contradiction at that point, and it's the evidence this stays a manual, occasional tool rather than something scheduled. Per Article 1 (`docs/research/agent-memory-engineering-2026-08-07.md`): "a memory system that runs against three notes will hallucinate connections that are not there and train you to ignore it, so prove each pass by hand, then automate" — this only earns a schedule if a future hand-run's precision says otherwise.

**Never auto-resolves.** Two memories can both be right in different contexts — every candidate is for a human (or a separately-dispatched, adversarial LLM pass) to read and judge. An extraction step that both writes memories and unilaterally decides which one is now false is the same maker-grades-itself failure this harness already rejects everywhere else (CLAUDE.md's operating model: an LLM can't grade its own output).

## UNINDEXED fold-vs-forgotten triage (`--classify-unindexed`)

UNINDEXED (a file with no MEMORY.md pointer) is two different states wearing one label: an authoring oversight, or the fold rule's own documented correct end-state ("merge/drop stale entries... just stop indexing it, never delete the backing file"). Blind-appending every UNINDEXED file back into MEMORY.md would silently undo real prior fold decisions. This mode classifies instead of auto-fixing, using git history on MEMORY.md — see `docs/research/claude-mem-architecture-study-2026-08-07.md` (Adopt-1) for the full design rationale, including the first draft (blind auto-append) that adversarial review caught before it shipped.

| Bucket | Meaning | Action |
|---|---|---|
| **folded-confirmed** | `git log -S<filename> -- MEMORY.md` finds a commit where this file's occurrence count changed | Already deliberately removed — NOT a candidate to re-add |
| **never-indexed** | File's mtime is after the memory dir's first git commit (its whole life is inside tracked history) and no fold commit was found | Real candidate to add |
| **ambiguous-pre-baseline** | File predates the memory dir's first commit — git has no opinion either way | Needs a human to read the content |
| **no-git-history** | Memory dir isn't a git repo (or has 0 commits) | Same ambiguity as ambiguous-pre-baseline, for everything |

Live-run confirmed 2026-08-07 against the real store (69 UNINDEXED at the time): 27 folded-confirmed (all citing the same fold-rule compaction commit, `ce2c21f`), 0 never-indexed, 42 ambiguous-pre-baseline (the memory dir's git tracking only started 2026-08-07 — see `docs/research/claude-mem-architecture-study-2026-08-07.md`, Adopt-1 — so most of the existing backlog predates it). Read-only — never appends anything to MEMORY.md.

## Action mode (`--auto-archive`)

Mechanical fold of verbose/closed entries per the **A3 rubric** (codified 2026-06-04, [[project_memory_trim_session_2026_06_04]]), plus a **Class D fallback valve** (added 2026-08-07). This engine is the **canonical home of the trim workflow** — the `--trim` aliases below wrap it; there is no separate trim skill.

- **<2KB delta per session for A/B/C** — never collapse the whole store; trim only the worst. Class D is the deliberate exception: it's a last-resort valve for a store shape A/B/C structurally can't catch (many small terse entries, no verbose outlier), so its delta can be larger — confirmed live at -5,039B in one fold, see below.
- **<30 min elapsed** — if it takes longer, the store is unhealthy in ways trim won't fix
- **Reversible** — A moves via `mv` (never `rm`); B/C rewrite in place; D deindexes only (removes the MEMORY.md pointer line, backing file untouched — recoverable via git history, `qmd`, or re-adding the line by hand)

| Class | Trigger | Action | Safety |
|---|---|---|---|
| **A — stale-superseded** | MEMORY.md pointer has `**SUPERSEDED**` marker + topic has 0 surviving inbound `[[wikilinks]]` | `mv <topic> _archive/<date>/` + collapse pointer to 1-line stub | Always safe (marker = user intent) |
| **B — near-budget-collapse** | MEMORY.md >80% cap + pointer ≥250 chars + topic >5KB + pointer ≥ 1.2x first paragraph | Replace pointer with ~80-char stub + add `supersedes:` note in topic | Editorial; review each rewrite |
| **C — dangling-link-rewrite** | Surviving file's `[[wikilink]]` resolves to nothing or to `_archive/` | Rewrite `[[X]]` → `[[<ledger>]]` | Mechanical when target is already-archived |
| **D — count-fold** | Index ≥80% of cap AND A+B+C together found nothing (confirmed live 2026-08-07: 0 candidates from either class at 84% of cap on the real store — its growth is many small terse entries, not a few verbose outliers) | Deindex oldest pointer lines by topic-file **mtime**, any type, until back under 65% of cap | Dry-run/confirm gated, same as A/B/C — but ranks by "hasn't been edited," which can catch a stable, correct, evergreen reference for the wrong reason (confirmed live: `harness-engineering-2x2-model.md` was a real candidate). Review the dry-run list before confirming. |

> **Source of truth:** the thresholds above (≥250 chars, >5KB, ≥1.2×, 200L/25KB cap, Class D's 80%/65% fold band) are enforced in `scripts/memory-lint.py` (`class_a_stale_superseded` / `class_b_near_budget_collapse` / `class_c_dangling_link_rewrite` / `class_d_count_fold`). Update this table when the code changes — this prose mirrors the code, it does not define it.

Default for `--auto-archive` is dry-run with confirm prompt; `--yes` skips the prompt (use for CI/scripts). `--json` produces machine-readable output (mode-aware: detector JSON for plain lint, action-plan JSON for `--auto-archive --dry-run`).

### `--trim` mode (plan / apply / status)

The trim workflow is `--auto-archive` under three intents — no separate skill. Run them in order:

1. **plan** — `--auto-archive --dry-run --json` → the action plan (what would move, projected before/after size) without touching the store. Never skip straight to apply: drift the plan review and you `mv` entries you meant to keep.
2. **apply** — `--auto-archive --yes` → executes the reversible `mv`s (collapsed pointers stay grep-able in `_archive/`; never `rm`).
3. **status** — `python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py"` (detector mode) → current finding count + load-budget %; run before and after an apply to read the size delta.

Reach for trim when MEMORY.md is over its 200-line / 25KB cap or after a big session; for routine link/index checks the default detector is enough.

## Checks

| Check | Catches |
|---|---|
| **Dangling links** | `[[target]]` resolving to no memory (by filename stem or `name:` slug; strips `[[t\|alias]]`) — suggests a close-name match (stdlib `difflib`, cutoff 0.6) when one exists, to catch typos |
| **Orphans** | indexed in MEMORY.md but no `[[links]]` in or out — disconnected from the wikilink graph |
| **Index drift** | MEMORY.md ↔ files, **both** directions (unindexed file + stale pointer) |
| **Load budget** | MEMORY.md within the official 200-line / 25KB session-load cap (warn ≥80%, fail if over — trailing entries silently never load) |
| **Staleness** *(advisory only)* | A memory file's mtime past `--stale-days` (default 90) — surfaced for a human to re-check, not a defect; excluded if already marked `**SUPERSEDED**`. Doesn't count toward exit code. |
| **Template compliance** *(advisory only)* | `**Why:**`/`**How to apply:**` coverage for `type: feedback`/`type: project` memories — the fields that separate a fact/skill from a raw log line. Reports a count + worst-offender sample; never gates (a presence-only check has twice trained authors to paste filler elsewhere in this fleet — visibility only). |
| **Contradiction candidates** *(manual, `--find-contradictions` only)* | Same-`type:` pairs above a token-overlap threshold — a pre-filter for human review, never a verdict and never scheduled. See "Contradiction pre-filter" above. |
| **UNINDEXED triage** *(manual, `--classify-unindexed` only)* | Splits UNINDEXED findings into folded-confirmed / never-indexed / ambiguous-pre-baseline / no-git-history using git history on MEMORY.md — never auto-appends. See "UNINDEXED fold-vs-forgotten triage" above. |

mtime is a proxy for "untouched," not "unverified" — editing a file resets the clock even if the edit didn't re-check the underlying claim, and a file can be genuinely still-true well past the threshold. Claude Code 2.1.214 added a native `modified:` frontmatter timestamp (already populated on memories in this store), but it doesn't close this gap — it's stamped on any edit, the same "touched" signal as mtime, not a `last_verified` field. kbg still has no per-memory `last_verified` field distinct from "last edited" (retrofitting one means migrating the whole store — not worth it for a lint-surface add-on); mtime (or the now-native `modified:` field, equivalent for this purpose) remains the cheapest signal available without a schema change. Confirmed proven need, not speculative: this session hit repeated real staleness incidents (`disable-model-invocation-criterion` drift, fleet-count drift, folded version counts going stale) that a check like this would have surfaced for review.

`[[ ]]` is memory↔memory only. Reference skills/doctrine (`decommission`, METHODOLOGY) in prose with backticks, not `[[links]]` — those resolve to no memory and surface as dangling.

**Author links by filename stem** (the file name minus `.md`), not the `name:` slug. A link resolves by filename-stem OR `name:`, but `name:` fields are inconsistent storewide (hyphen vs underscore, prefixed or not — 81/110 differed from their filename as of 2026-06-08), so the filename stem is the one identifier guaranteed to resolve. The SessionStart `memory-health-nudge` hook (`hooks/session/memory-health-nudge.sh`) surfaces danglers each session — advisory, silent when clean. It replaces the earlier `memory-lint-check` hook (`hooks/maintenance/memory-lint-check.sh`), deleted in the 2026-06-27 "reset: rebuild from scratch" (`c452102`) and undocumented-as-gone for ~6 weeks; see `docs/research/agent-memory-engineering-2026-08-07.md` proposal A1 for the incident writeup and rebuild rationale.

## METHODOLOGY

- **Fail loud:** a broken cross-link or orphan is silent rot; exit code = finding count makes it visible.
- **Read before write:** before adding a memory, lint surfaces an existing one it should link to or supersede.
- **Memory authoring format:** one lesson per file, frontmatter (`name:`, `description:`), body with the fact plus `**Why:**` and `**How to apply:**`, link related memories with `[[slug]]`; dedupe against existing files before writing, and never delete — archive under `_archive/` (see the A3 rubric above).

## Failure modes

- **Skipping straight to apply.** `--auto-archive --yes` without first reading the `--dry-run` plan
  can `mv` entries you meant to keep — always review the plan-mode action list before applying.
- **Linking by `name:` slug instead of filename stem.** `name:` fields are inconsistent storewide
  (hyphen vs underscore, prefixed or not) — a link authored against the slug can resolve to nothing
  even though the file exists. Always link by filename stem.
- **Using `[[links]]` for non-memory references.** Wikilinks only resolve memory↔memory — a link to
  a skill or doctrine file (`decommission`, METHODOLOGY) always shows as dangling. Use backticked
  prose references for those instead.

## Related

- `harness-audit` — same shape for the skill/agent/hook ecosystem (check 13 covers MEMORY.md pointer→file; this covers the reverse + links)
- `inventory` — lists artifacts; doesn't judge memory health
