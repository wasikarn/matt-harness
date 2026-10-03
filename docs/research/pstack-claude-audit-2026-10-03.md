# pstack-claude adoption audit (2026-10-03)

**Date:** 2026-10-03
**Source:** https://github.com/michael-denyer/pstack-claude, README saved raw and a local clone read; no release tag pinned (it pins upstream `cursor/plugins` at a commit in `tools/forks.json`).
**Verdict:** Do not adopt pstack as a whole; adopt four patterns. pstack is a prose-driven orchestration stack (56 skills, 12 agents, 1 hook). mh is a computational-enforcement harness (gates, canary, shadow mode, maker-not-grader). They solve different problems. pstack is stronger on doc-fact pinning, per-version changelog, shipping verdicts bound to a revision, eval blinding and PR workflows. mh is stronger on enforcement, tests and cost control.
**Score:** 69.5/100 — **PASS** (threshold 65; confidence medium). Criteria table below.

Every claim about the source's internals is what it describes as of this read.

## Method

Two fresh-context analysts (A: claims, B: fit), then one different-family attacker (Codex gpt-6-sol, medium, read-only; schema, verdict and citation checks passed, 9 checked items). Neither analyst nor the attacker ran source code. B read mh at a stale HEAD (behind origin/develop); fit conclusions may still hold but its branch state is not current.

## What pstack does better than mh

| Area | pstack | mh today |
|---|---|---|
| Doc facts | `readme-facts` test pins counts in prose to the tree | "Nine computational", "Skills (12)" counts unpinned |
| Changelog | one heading per version | `CHANGELOG.md` stops at 1.1.153; manifests are far ahead |
| Shipping verdicts | bound to head SHA, base SHA and `git patch-id` | pin to revision only |
| Eval hygiene | blinding rules for evals | none in model-bench |
| PR workflows | babysit, fix-ci, get-pr-comments | none |
| Runtimes | Claude Code, Codex, Pi | Claude Code only |
| Skill existence | checks | named external skills not checked |

## What mh does better

Ten PreToolUse gates plus a SubagentStop gate, a large gate suite, benign-payload canary, drift check, shadow mode, the maker never grades its own work, cost ledger, 35 audit checks, memory lint. pstack's irreversible-action pauses are prose only; its per-role model/effort is author-asserted (its own changelog admits a haiku parent ignored it) and only the Pi extension enforces it in code.

## Red flags in pstack (verified or attacker-confirmed)

- `poteto-mode` tells the agent to use any MCP or external action without asking (conflicts with Rule 1).
- Hook and playbook text is AI-directed instruction; treat as untrusted data.
- `setup-pstack` appends to global CLAUDE.md/AGENTS.md.
- Defaults use `fable` (mh: never pin fable); same-vendor "adversarial" panel.
- Description text about 6x mh's context cost (14,328 vs 2,292 chars).
- NOTICE and forks.json contradict each other; stale counts.

## Attacker corrections applied

- patch-id: pstack itself says a match does not prove applicability elsewhere. Not adopted as an alternative acceptance key.
- Codex routing hook: declared, not proven to run in Codex. Not counted as verified.
- Several B "gap" claims (CI triage, worktree audit, linters) rest on filename search only: insufficient evidence for overlap.

## Shipped

Nothing — read-only research pass; this document only.

## Deliberately not shipped

- **Whole-stack adoption** — conflicts with Rule 1 and "never pin fable"; **declined on evidence**.
- **Autonomous playbooks / "proceed without asking"** — METHODOLOGY Rule 1; **declined on evidence**.
- **patch-id as acceptance key** — attacker finding above, maker≠checker; **declined on evidence**.
- **Pi/Codex runtime ports, Bun/Graphite upkeep** — YAGNI; **deferred**.
- **Worktree audit, actionlint/zizmor/osv-scanner in CI** — overlap unchecked; **deferred**.

## Adopt (patterns only, no licence duty)

1. A1: an audit check pinning prose counts to the tree.
2. A5: blinding rules for model-bench and evals.
3. A6: check that named mattpocock/codex skills exist.
4. A2: changelog per version, or retire `CHANGELOG.md`. Needs an operator decision.

## Decision score (METHODOLOGY Rule 14)

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| primary-source-fidelity | 35 | 7 | Largest weight by rule. Most of A's claims observed directly; attacker refuted none but left 3 B claims at insufficient evidence. A 3 would be claims resting on README prose alone; a 9 would be every claim re-run. |
| fit | 25 | 6 | Real need for count pinning and changelog, none for the orchestration stack. |
| blast-radius/reversibility | 20 | 8 | Patterns only, no dependency, no global config; easy to revert. |
| effort-fit | 20 | 7 | Each adoptable item is under a day. |

Weighted sum: 0.35×70 + 0.25×60 + 0.20×80 + 0.20×70 = **69.5/100**. Threshold 65, floor 40% per axis: none below. **PASS** for the four patterns only. Confidence: medium (one attacker pass, no execution of source code, stale B checkout).

## Open questions

- Keep or retire `CHANGELOG.md` (A2) — decide when the next release is cut.
- ECC/superpowers (composer step 3) were not checked for overlap — revisit only if an adopted pattern needs a new skill.
