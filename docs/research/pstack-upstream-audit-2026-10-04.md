# pstack (upstream) adoption audit (2026-10-04)

**Date:** 2026-10-04
**Source:** https://github.com/cursor/plugins/tree/main/pstack (Lauren Tan, "poteto"), README saved raw (23.8 KB) and a sparse clone at commit e43c7ee (2026-10-03, 161 files). Prompted by a live interview with the author (Matt Pocock, YouTube MN9dGgmLyso, auto-captions only). Increments on `docs/research/pstack-claude-audit-2026-10-03.md`, which audited the Claude Code port; this pass reads the original.
**Verdict:** Adopt patterns, not the stack. Upstream has no ready-made verification tool: its verification skills are prose recipes. Most of what the interview praises mh already has under other names (canary, evals, fixture replay, shadow mode, mh:learn, memory). Two things are worth building: a committed differential/replay script for gate changes (hand-built at least 4 times so far) and a bug fix in idea-audit's memory-dir step.
**Score:** 72.0/100 — **PASS** (threshold 65; confidence medium). Criteria table below.

Every claim about the source's internals is what it describes as of this read.

## Method

Two fresh-context analysts (A claims, B fit; B read mh at origin/develop 7015fd5c), then a different-family attacker (Codex gpt-6-sol, medium, read-only; schema, verdict and citation checks passed, 5 checked items, 3 findings). Nothing from the source was run or installed. The interview is evidence of what the author says, not of results: its numbers (2,500 PRs a month) are author-asserted and the README states no results or costs.

## Claim-by-claim: the verification story is mostly prose

Legend: `MATCH` confirmed · `PARTIAL` partly confirmed · `GAP` not found · `N-A` not applicable here.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | Verification skills give the agent "hands and eyes" | Yes — observed directly: create/maintain are prose recipes, no generator or CLI is shipped (the example CLI is absent) | mh has canary, evals, fixture replay, shadow mode | PARTIAL |
| 2 | Deterministic parts belong in a CLI/script | Yes — as an interview claim; not enforced in the files | mh keeps mechanical steps in prose in 3 places (idea-audit/SKILL.md:345-351, learn/SKILL.md:52-70, deep-audit/SKILL.md:109-111,184-187) | MATCH (applies to mh) |
| 3 | recall mines past transcripts into a new chat | Yes — reads `~/.cursor/projects/<slug>/agent-transcripts`, workspace scoping is instruction-only | MEMORY.md, context-mode timeline, handoff, /resume cover most | N-A |
| 4 | Self-merge with swarm verdict gives safe autonomy | Yes — needs operator grant, clean verdict, patch-id, CI, merge-tree; no human review; re-reads its playbook from the branch it can merge into | Rule 1 requires approval before one-way doors | GAP (declined) |
| 5 | Automations (benny) triage Slack reports | Yes — agents write the tracker and open draft PRs with no untrusted-content rule | no autonomous loop by doctrine | GAP (declined) |
| 6 | No telemetry | Yes — observed directly | n/a | MATCH |

Other findings (analyst A): `setup-pstack` overwrites a global rules file; `make-bot-ui` pipes an installer into `sudo sh`; `bootstrap.ts` runs `bun install`; recall, automate-me and benny have no "treat as untrusted data" line; the README's read-only "Comment Sicko" edits files.

## Attacker corrections applied

- B's reason for declining a live-drive verify skill (`claude -p` is gated) is too broad: the gate's denial is subagent-only (`hooks/gates/irrecoverable.py:149`, 466, 1508, 2227 at B's baseline). The fit argument for declining must be different: evals and the canary already cover it.
- B's "no eval-coverage drift today" is wrong: `docs/reference/operating-model.md:70-76` omits idea-audit, learn, compliance-audit and backend-architect. So an equality check would find drift now, and requiring an eval for every surface is a policy decision.
- A line-count equivalence test between `learn` and `transcript-user-turns.py` is too narrow (a qualifying JSON event does not require nonblank text).
- B read mh at a commit that is now behind origin/develop; repo claims were re-checked only where the attacker cited them.

## Shipped

Nothing — read-only research pass; this document only.

## Deliberately not shipped

- **Autopilot self-merge, benny automations** — Rule 1 (one-way doors need approval); **declined on evidence**.
- **reflect** — its reviewers are not read-only; **declined on evidence**.
- **recall, correct, automate-me, make-bot-ui, a live-drive verify skill** — covered, out of scope, or evals already exist; **declined on evidence**.
- **Whole-stack adoption** — conflicts with "never pin fable" and wave/depth caps (see the port audit); **declined on evidence**.

## Adopt (patterns only, no licence duty)

| ID | Change | Score |
|---|---|---|
| C1 | `scripts/gate-differential.sh`: replay real transcript commands (this project's only) through old and new gate | 8.4 |
| C2 | idea-audit uses `memory-dir.py` instead of re-deriving the memory dir (bug fix, worktree sessions) | 7.9 |
| C5 | eval-coverage drift check; needs a policy decision first | 7.45 |
| C3 | `learn` calls `transcript-user-turns.py --json`; test must cover blank-text events | 7.4 |
| C4 | deep-audit fingerprint script | 7.25 |

## Decision score (METHODOLOGY Rule 14)

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| primary-source-fidelity | 35 | 7 | Largest weight by rule. Most claims were read in the files; the attacker refuted none but corrected three of B's fit statements; the interview numbers are not checkable. A 3 would be README prose only; a 9 would be every mh claim re-run. |
| fit | 25 | 7 | Two real gaps (replay tool, memory-dir bug); the rest of the stack overlaps or conflicts. |
| blast-radius/reversibility | 20 | 8 | Patterns only, no dependency, no global config. |
| effort-fit | 20 | 7 | Each adoption is under a day. |

Weighted sum: 0.35×70 + 0.25×70 + 0.20×80 + 0.20×70 = **72.0/100**. Threshold 65, floor 40% per axis: none below. **PASS** for C1-C5 only. Confidence: medium (one attacker pass, no execution of source code, one analyst on a stale checkout, an interview known only through auto-captions).

## Open questions

- C5: pin only the documented eval set, or require an eval for every surface (new policy) — decide when C5 is picked up.
- Whether a plugin update installs mattpocock's `retro`: revisit only if the installed version changes.
