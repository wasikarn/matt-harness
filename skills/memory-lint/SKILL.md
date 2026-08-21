---
name: memory-lint
description: "Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health."
bucket: meta
model: inherit
effort: medium
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

# Pattern clusters (manual, one-off — see "Pattern clusters" below)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --find-patterns                    # --max-cluster defaults to 10 — the clean signal
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --find-patterns --max-cluster 0    # uncapped — see the raw giant component too
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --find-patterns --prompt           # + paste-ready LLM-synthesis prompt per cluster

# UNINDEXED fold-vs-forgotten triage (manual, read-only — see below)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --classify-unindexed
```

Auto-derives the store from the current repo (`~/.claude/projects/<enc>/memory`). **Verify** the run against the exit code: it equals the finding count, so 0 confirms a clean store. Two advisory sections print below the findings and never affect the exit code: staleness (mtime-based — tune with `--stale-days N`, default 90) and template compliance (`**Why:**`/`**How to apply:**` coverage for `feedback`/`project` memories) — see Checks table for both.

## Contradiction pre-filter (`--find-contradictions`)

See `references/contradiction-prefilter.md` for the full design rationale (why this
stays manual-only, the 2026-08-07 hand-run evidence, and why it never auto-resolves).

## Pattern clusters (`--find-patterns`)

See `references/pattern-clusters.md` for the full design rationale (graph-topology
mechanism, the `--max-cluster` giant-component fix and its 2026-08-13/2026-08-17
evidence, and why this stays a manual, on-demand mode rather than an always-on
layer).

## UNINDEXED fold-vs-forgotten triage (`--classify-unindexed`)

See `references/unindexed-triage.md` for the full bucket table, the git-history
classification mechanism (tree membership at first commit, not mtime), the
v0.68.229 adversarial rewrite, and the SessionStart nudge wiring.

## Action mode (`--auto-archive`)

See `references/action-mode.md` for the full A/B/C/D rubric (trigger/action/safety
table for each class), the `--trim` plan/apply/status workflow, and the thresholds'
source-of-truth note.

## Checks

| Check | Catches |
|---|---|
| **Dangling links** | `[[target]]` resolving to no memory (by filename stem or `name:` slug; strips `[[t\|alias]]`) — suggests a close-name match (stdlib `difflib`, cutoff 0.6) when one exists, to catch typos |
| **Orphans** | indexed in MEMORY.md but no `[[links]]` in or out — disconnected from the wikilink graph |
| **Index drift** | MEMORY.md and files, both directions (stale pointer, plus UNINDEXED — which is **reachability-aware** since v0.68.241: a file with no pointer but `[[link]]`-reachable from an indexed root is the fold rule's Context layer, reported as an advisory `context-layer` count and never a finding; only unindexed AND unreachable files fire) |
| **Load budget** | MEMORY.md within the official 200-line / 25KB session-load cap (warn ≥80%, fail if over — trailing entries silently never load) |
| **Staleness** *(advisory only)* | A memory file's mtime past `--stale-days` (default 90) — surfaced for a human to re-check, not a defect; excluded if already marked `**SUPERSEDED**`. Doesn't count toward exit code. |
| **Template compliance** *(advisory only)* | `**Why:**`/`**How to apply:**` coverage for `type: feedback`/`type: project` memories — the fields that separate a fact/skill from a raw log line. Reports a count + worst-offender sample; never gates (a presence-only check has twice trained authors to paste filler elsewhere in this fleet — visibility only). |
| **Contradiction candidates** *(manual, `--find-contradictions` only)* | Same-`type:` pairs above a token-overlap threshold — a pre-filter for human review, never a verdict and never scheduled. See "Contradiction pre-filter" above. |
| **Pattern clusters** *(manual, `--find-patterns` only)* | Connected components of memories sharing resolvable `[[link]]` referents, ≥N members — a recurrence signal, not a verdict; never scheduled. Dense stores produce one giant component (expected) — `--max-cluster` filters it, not `--min-cluster`; defaults to 10 so the signal is in the smaller clusters by default. See "Pattern clusters" above. |
| **UNINDEXED triage** *(manual, `--classify-unindexed` only)* | Splits UNINDEXED findings into folded-confirmed / never-indexed / ambiguous-pre-baseline / no-git-history / git-query-failed using git history on MEMORY.md — never auto-appends. See "UNINDEXED fold-vs-forgotten triage" above. |

mtime is a proxy for "untouched," not "unverified" — editing a file resets the clock even if the edit didn't re-check the underlying claim, and a file can be genuinely still-true well past the threshold. Claude Code 2.1.214 added a native `modified:` frontmatter timestamp (already populated on memories in this store), but it doesn't close this gap — it's stamped on any edit, the same "touched" signal as mtime, not a `last_verified` field. kbg still has no per-memory `last_verified` field distinct from "last edited" (retrofitting one means migrating the whole store — not worth it for a lint-surface add-on); mtime (or the now-native `modified:` field, equivalent for this purpose) remains the cheapest signal available without a schema change. Confirmed proven need, not speculative: this session hit repeated real staleness incidents (`disable-model-invocation-criterion` drift, fleet-count drift, folded version counts going stale) that a check like this would have surfaced for review.

`[[ ]]` is memory↔memory only. Reference skills/doctrine (`decommission`, METHODOLOGY) in prose with backticks, not `[[links]]` — those resolve to no memory and surface as dangling.

**Author links by filename stem** (the file name minus `.md`), not the `name:` slug. A link resolves by filename-stem OR `name:`, but `name:` fields are inconsistent storewide (hyphen vs underscore, prefixed or not — 81/110 differed from their filename as of 2026-06-08), so the filename stem is the one identifier guaranteed to resolve. The SessionStart `memory-health-nudge` hook (`hooks/session/memory-health-nudge.sh`) surfaces danglers each session — advisory, silent when clean — and also runs the UNINDEXED fold-vs-forgotten triage above when applicable. It replaces the earlier `memory-lint-check` hook (`hooks/maintenance/memory-lint-check.sh`), deleted in the 2026-06-27 "reset: rebuild from scratch" (`c452102`) and undocumented-as-gone for ~6 weeks; see `docs/research/agent-memory-engineering-2026-08-07.md` proposal A1 for the incident writeup and rebuild rationale.

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
