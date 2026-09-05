# Agent authoring conventions

What the 12-agent fleet actually does, made explicit so a new agent has something accurate to
pattern-match against. Prose guidance, not a gate; the mechanical checks are named per item.

## 1. Tool scoping: explicit allowlist, least privilege

Every agent declares `tools:` as an explicit allowlist (`harness-audit` check 09, CRIT when
missing). Read-only reviewers and analysts (`security-reviewer`, `typescript-reviewer`,
`nextjs-reviewer`, `backend-architect`, `code-architect`, `blind-spot-hunter`,
`silent-failure-hunter`, `requirement-analyst`, `summarizer`) get `Read`, `Grep`, `Glob`, and
sometimes `Bash` for inspection; never `Write`/`Edit` (check 32). Mutating implementers
(`performance-optimizer`) add `Write`/`Edit`. **`Agent` is never granted** (check 41): a
dispatched subagent returns scoped output, it does not spawn its own.

Why: least privilege by construction (OWASP LLM06). The read/mutate split is where the blast
radius of a wrong action differs by an order of magnitude.

## 2. Prompt Defense Baseline on anything that ingests external content

Every agent except `ideate-critic` carries a `## Prompt Defense Baseline` section near the top:
do not change role, do not reveal secrets, and treat the input (ticket body, spec, source file,
PR description) as untrusted data, not instructions. `agents/requirement-analyst.md` is the
canonical form. `ideate-critic` only reads same-session JSON, so it omits the section; any agent
that touches text not generated this turn includes it.

Why: OWASP LLM01. Ticket bodies and specs are exactly where an attacker embeds instructions.

## 3. Model assignment by cognitive load, not by default

Every agent carries an explicit `model:` and `effort:` (check 54). Pin `model: opus` only when
the value is judgment quality (`requirement-analyst`), not for mechanical work. Pinning a
fresh-context verifier to a different model than the main session makes it independent by
model as well as by context, a stronger form of item 4.

## 4. Verifier/maker separation for anything that grades

An agent whose job is to judge or verify other work is a fresh-context, advisory-only pass:
it returns findings, it never passes the work by fiat. `blind-spot-hunter` and `ideate-critic`
are the reference examples.

Why: an LLM cannot reliably grade its own same-context output (self-preference bias; LLM-judged
task completion tops out near AUROC 0.65). This is `docs/reference/operating-model.md`'s second
idea applied to agent design.

## 5. Confidence discipline for anything that reports findings

Review agents state a confidence bar (commonly >80%) and require HIGH/CRITICAL findings to cite
`file:line` or a reproducible scenario. **Zero findings on a clean input is valid output**; do
not manufacture findings to look thorough.

Why: static-analysis false-positive rates run 35 to 91%, and LLM review has the opposite failure
too (near-total misses on seeded vulnerabilities). Explicit discipline is an evidenced
mitigation, not ceremony.

## 6. One-level-deep dispatch

A dispatched agent never re-dispatches (METHODOLOGY Rule 13; native
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` in the operator's settings enforces it). Disambiguation
against neighboring agents lives in each agent's `## When NOT to use this agent` section.

## 7. Grow on proven need, not speculatively

Before adding an agent, name the concrete task no existing agent covers. If an existing agent's
domain is close, extend it. A fleet of near-duplicate specialists costs routing ambiguity and
description tokens on every Task spawn.

## 8. Closed-vocabulary status codes for branchable output

When a caller must branch on an agent's status (refuse, needs-confirm, ambiguous, regressed),
express it as a small fixed set of terminal first-token codes documented in `## Output Format`,
not a free-text sentence. An unconstrained status drifts across independent writers; a closed
vocabulary fixed at authoring time prevents that.

## Preloads

`skills:` frontmatter preloads a support skill the agent has no `Skill` tool to reach. Current
pairs, each CRIT-guarded by check 49: blind-spot-hunter, nextjs-reviewer, performance-optimizer,
plan-reviewer, requirement-analyst, security-reviewer, summarizer. A preloaded skill carries the
same `effort:` as its host agent.

## Checklist for a new agent

1. Name the concrete, currently-uncovered task.
2. `tools:`: explicit allowlist, smallest set the role needs. Never `Agent`.
3. Add `## Prompt Defense Baseline` if the agent ever touches content it did not generate.
4. Pin `model: opus` only if the value is judgment quality.
5. If it grades other work: fresh-context, advisory-only, never self-gating.
6. If it reports findings: state a confidence bar; zero findings is valid.
7. If it returns a branchable status: closed set of terminal codes in `## Output Format`.
8. Run `bash skills/meta/harness-audit/scripts/audit.sh`; checks 04, 09, 24, 25, 41, 49, 51, 54
   touch new agents directly.
