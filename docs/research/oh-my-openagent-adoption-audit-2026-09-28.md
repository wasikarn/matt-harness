# oh-my-openagent adoption audit (2026-09-28)

**Date:** 2026-09-28
**Source:** github.com/code-yeongyu/oh-my-openagent, branch `dev`, `docs/` tree (38 files). Read
directly this session (4 general-purpose agents covering guide/reference/examples/legal, then 8
of those docs re-fetched raw via `curl` for the idea-audit's saved-source requirement). No local
clone, no pinned revision — the repo carries no release tag referenced in this read; `dev` is a
moving branch.
**Verdict:** Adopt at most one mechanism (checkout isolation for delegated subagent tasks), as a
scoped opt-in pilot — not a wholesale import. The other five candidate mechanisms solve problems
this repo's own `docs/reference/operating-model.md` states by design it does not have (no
orchestration layer, no persistent process, no external DAG viewer). One of Agent B's five "solves
nothing here" verdicts (team-mode mailbox) turned out to rest on an unverified equivalence claim,
caught by the adversarial pass — downgraded from confident-decline to lower-confidence-decline,
verdict unchanged.
**Score:** 74.5/100 — **PASS** (threshold 65; confidence medium). Full criteria table: see
Decision score below.

Every claim below about the source's internals is what it describes as of this read, not a
verified fact about the source as it exists today or in the future.

## Method

Two isolated `general-purpose` analysts (Agent A — claims extraction from a saved, raw-`curl`'d
copy of 8 source docs; Agent B — fit analysis against this repo's actual delegation/orchestration
machinery), followed by one adversarial attacker (`codex exec`, `gpt-6-sol`/medium, read-only,
`--cd` repo root) that independently re-checked both reports against primary evidence. Attacker
returned `pass: false` with 4 findings, all schema-valid and citation-verified via this skill's
`check-verdict.py` + `check-citations.py` (both exit 0). No prior `docs/research/` coverage of
this source existed to increment on (`qmd` collections cover this repo's own memory/research, not
external repos, so no prior-coverage check applied).

## Claim-by-claim: does this repo already have it, or does adopting it solve a real gap

Legend: `MATCH` = repo already implements the equivalent · `PARTIAL` = a real but partial/narrower
analog exists, or the source's own detail was overclaimed in one direction · `GAP` = repo has
nothing and doesn't need it · `N-A` = not applicable.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | Category-not-model delegation: `task()` routes by intent label, resolved through a config fallback chain, never by naming a model directly | Yes — observed directly (numbered resolution algorithm, gate tables) | Already present in substance: `agents/*.md` frontmatter `model:` pins by role, plus `docs/reference/codex-integration-map.md`'s Luna/Terra/Sol/Astra task-category table. Missing only the multi-rung *fallback chain* — blocked on the Agent tool having no per-dispatch fallback-model parameter today | MATCH (core idea); PARTIAL (fallback-chain half) |
| 2 | prompt-async-gate: reservation mutex stopping multiple internal callers racing to inject a prompt into one session | Yes — observed directly (TS code, exact constants, process-local limit stated) | No matching problem: hooks return `additionalContext` synchronously, single-caller, no concurrent-injection race exists here | GAP |
| 3 | mass-ulw-protocol: gap-free DAG event streaming for external viewers (WAL-sequenced + unsequenced channels + overflow recovery) | Yes — observed directly (6-step algorithm, wire schema) | Nothing analogous; no external viewer watches a live multi-agent run here. `rg` for `dag\|wal\|highwaterseq\|throughseq` across hooks/agents/skills/docs/reference: 0 hits (attacker-run, independent of Agent B) | GAP |
| 4 | omo-daemon: shared RPC host process per agent dir, trust-checked launch spec, build-ordinal socket handoff | Yes — observed directly (JSON schema, trust-check rules, handoff logic) | No daemon/RPC/socket anywhere in `.sh`/`.py` source (0 hits, independently re-run by the attacker). Agent B cited ADR-0004 as a prior daemon rejection — **attacker correction: ADR-0004 is about a cloud Routine self-launching another session via a per-Routine GitHub credential, not a persistent local RPC host; it doesn't establish that a daemon design was ever evaluated.** The real anchor is `docs/reference/operating-model.md`'s stated no-persistent-process design, not ADR-0004 | GAP (verdict unchanged, citation corrected) |
| 5 | Checkout isolation: delegated subagent tasks run in a COW clone, merged back only on clean completion | Yes — observed directly (settings table, storage paths, error codes; no source code shown for the clone mechanism itself) | Real, partial gap: this repo has session-level worktree isolation (`docs/reference/branching-model.md`) but explicitly states "a subagent shares its parent session's worktree, not a worktree of its own" — handled today by discipline (FILES YOU OWN scoping, sequential dispatch, `gate:bash:subagent-git-guard` denying stash/reset/clean), not filesystem isolation. **Attacker correction: the source's merge-back is not unconditional — `task.isolation.apply: false` keeps patch/branch artifacts only, and a merge that can't apply cleanly retains the clone as `<clone>.retained-<timestamp>`; and the subagent-git-guard's deny regex is `stash\|reset\|clean` only — `git merge` is already permitted, so Agent B's claim that the gate "needs new logic to permit a scoped merge-back" was false** (verified independently: `hooks/gates/subagent-git-guard.py:156`) | PARTIAL — real gap, and cheaper to pilot than first estimated |
| 6 | Team-mode mailbox: atomic per-message files, `.delivering-*.json` reservation locks, 10-minute crash-recovery TTL | Yes — observed directly (directory-tree schema, TTL, dotfile-skip rule) | Native `SendMessage`/`ListAgents` (global `~/.claude/CLAUDE.md` rule, referenced in `branching-model.md`) covers file-claim coordination. **Attacker correction: Agent B's "zero lost capability" claim is insufficiently evidenced — the repo's file-claim discipline doesn't verify equivalence to the source's durable inbox/ack/crash-recovery behavior**; downgraded from confident-decline to lower-confidence-decline | GAP (verdict unchanged, confidence lowered) |

## Shipped

Nothing — this is a read-only research pass, per this skill's own scope (idea-audit evaluates,
it doesn't implement).

## Deliberately not shipped

- **prompt-async-gate** — `docs/reference/operating-model.md`'s stated no-orchestration-layer
  design; no concurrent-injection caller exists in this repo's hook model. **Declined on
  evidence.**
- **mass-ulw-protocol** — same doc; zero external-viewer consumer exists for a single-operator CLI
  session. **Declined on evidence.**
- **omo-daemon** — `docs/reference/operating-model.md`'s "ships as a plugin... nothing symlinked,
  nothing persistent" design (not ADR-0004, which the adversarial pass showed is scoped to a
  different, credential-based proposal and doesn't establish a prior daemon rejection).
  **Declined on evidence.**
- **Team-mode mailbox** — native `SendMessage`/`ListAgents` plus composer-not-creator doctrine
  (`docs/reference/composer-not-creator.md`); equivalence to the source's durability guarantees is
  unverified, not proven, so this is a lower-confidence decline than the other three.
  **Declined on evidence** (medium confidence).
- **Category fallback-chain extension** (the missing half of claim #1) — blocked on the Agent
  tool exposing no per-dispatch model-fallback parameter; nothing to build until the host adds
  one. **Deferred.**
- **Checkout isolation as a wholesale default** — the one real gap, but adopting it as the default
  dispatch mode (rather than a scoped opt-in) would be an architecture change with unclear payoff
  for a repo whose Rule 13 discipline has not yet had a documented subagent file-collision
  incident. **Deferred** — see Open questions for the pilot-scoping trigger.

## Decision score (METHODOLOGY Rule 14)

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| primary-source-fidelity | 40 | 9/10 | Agent A's claims were almost entirely "Yes — observed directly," backed by code snippets, exact constants, or explicit schemas/algorithms. The attacker independently re-checked 4 items (process-local mutex scope, async-reply-flow documentation, checkout-isolation worktree-gap match, DAG/daemon negative-search results) and found zero contradictions of Agent A's source-side claims. |
| fit | 35 | 6/10 | Agent B's overall directional conclusion (0-1 mechanisms fit, checkout isolation is the one real gap) held under adversarial re-check, but 3 of its supporting claims were wrong or overclaimed: a false statement about `subagent-git-guard.py`'s deny regex, an ADR-0004 citation scoped to the wrong proposal, and an unverified "zero lost capability" equivalence claim for team-mode. Directionally right, evidentially sloppy in three places. |
| blast-radius-reversibility | 25 | 7/10 | The one adoption candidate (checkout isolation) is a moderate, reversible, opt-in extension of an isolation model already proven at the session level — and the adversarial pass's correction (merge already permitted by the gate, configurable `apply` flag and retained-clone recovery already documented upstream) makes it cheaper to pilot than Agent B originally estimated. |

Weighted sum: (9×40 + 6×35 + 7×25) / 100 = 74.5/100 → **7.45/10**. Pass threshold 65, fatal-weakness
floor 40% of each axis's own max (4/10) — no axis tripped it (`weighted-score.py`: `belowFloor: []`,
`primaryWeightOk: true`). **PASS.** Confidence: medium (one Phase 1 pass per side, one adversarial
check that found and corrected 3 real evidentiary errors in the fit analysis but was not itself
re-verified by a second independent pass).

## Open questions

- **Checkout-isolation pilot scope** — revisit only if a real subagent file-collision incident
  occurs under the current discipline-based model (FILES YOU OWN + sequential dispatch), or if the
  Rule 13 validator flow is extended to cover multi-file builder dispatches more broadly. Not from
  further reading of the OmO source.
- **Category fallback-chain** — revisit only if Claude Code's Agent tool adds a model-fallback-list
  parameter to dispatch calls. Not worth tracking otherwise.
- **ADR-0004 citation hygiene** — a future daemon-adjacent proposal in this repo should cite
  `docs/reference/operating-model.md`'s no-persistent-process design, not ADR-0004, as the reason
  to decline — the adversarial pass showed ADR-0004 doesn't actually cover this ground.

**Correction (2026-09-28, operator override):** the pilot-scoping trigger in Open Questions above
(a documented file-collision incident, or a Rule 13 validator-flow extension) had not fired. The
operator explicitly chose to override the deferral rather than wait for it. Shipped same day:
`docs/reference/spawn-brief.md`'s "Isolated checkout dispatch" section (a real git-worktree branch
per opt-in builder dispatch, merged back only on a clean validator pass, reusing
`skills/review/compliance-audit`'s existing disposable-worktree pattern rather than inventing new
tooling) and a pointer from `docs/reference/branching-model.md`. No new script — the sequence is
short enough to stay inline, matching compliance-audit's own style.
