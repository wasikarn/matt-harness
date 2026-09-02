# ADR 0012 — Main plans, dispatches, verifies, decides — never executes

> **Status:** Accepted
> **Date:** 2026-09-02 · **Decider:** operator · **Supersedes:** the rejection recorded at
> `skills/workflow/orchestrate/reference.md` (the "Inline-wins checklist" section, dated
> 2026-09-01). That section is deleted in the same change that ships this ADR; its argument
> survives below under "Steelman against", rebutted rather than erased.

## Problem

Seven days of this operator's own session data showed the top-level session ("main") hoarding
execution work: roughly 1,312 main Edit/Write calls against 326 Agent dispatches (about 4:1),
plus several hundred mutating Bash calls that no counter captured. In the heaviest sessions,
65–80% of main's writes were execution — gate code, tests, skill content, docs — not planning.
The doctrine meant to prevent this said the opposite in four places at once: an explicit
9-clause "Inline-wins checklist" in `orchestrate/reference.md`, a routing matrix whose cheapest
cell was literally `inline`, a "Fast Path Gate" in `orchestrate/SKILL.md` telling main to
"write the code directly", and METHODOLOGY Rule 13's "work directly in the main thread when you
already know the file and the location".

The only computational backstop, `hooks/gates/main-write-budget.sh`, was opt-in, off by
default, and returned an `ask` decision. Claude Code's hooks documentation states that `ask`
is treated as `allow` in `--dangerously-skip-permissions` sessions — the mode this operator
runs interactively — so even when switched on it could never deny anything here.

## What this ADR proposes

1. **A deny-tier PreToolUse gate, `hooks/gates/main-exec-guard.sh`**, opt-in via
   `MH_MAIN_EXEC_GUARD`: unset/off → no-op; `log` → count and journal without denying
   (calibration); `1` → deny. It keys on the *absence* of `agent_id` in the hook input — the
   documented way to tell the top-level session apart from a subagent call — and denies
   Write/Edit/MultiEdit/NotebookEdit plus an allowlist-defined set of mutating Bash commands
   (the gate's own header is the authoritative list). Carve-outs: plan files, the memory
   store, and the session scratchpad.
2. **A doctrine rewrite** collapsing the four conflicting statements above into one rule,
   stated once per surface: `output-styles/crisp.md` (the register), `docs/METHODOLOGY.md`
   Rule 13 (the rule plus a "Main retains" list), and `orchestrate/SKILL.md` +
   `orchestrate/reference.md` (the routing and the protocols).
3. **Protocols that keep the rule alive under friction**, written out in
   `orchestrate/reference.md`: a short-form F9 fix-round dispatch for tiny changes, a commit
   agent, a ship agent for the plugin release ritual, a validator-returns-a-score contract, a
   `NEEDS-DECISION <question>` stop line for subagents that hit ambiguity, and a
   deadline/stall-detection convention. Each answers the specific excuse under which the rule
   was abandoned before: "it's a one-liner", "the worker stalled", "someone has to commit".

## Steelman for

- The operator observed the same drift across many sessions, not once: main takes the first
  small edit, then the next, and the dispatch discipline is gone by mid-session.
- Research surveying strict-planner systems — Claude Code's own delegate mode,
  oh-my-claudecode's architect/verifier split, and similar lead-never-codes designs — found
  none that holds the line with prose alone; every one that holds it removes the tool. Prose
  states an intent; a gate states a fact.
- Claude Code issue #42856 documents a CLAUDE.md rule stating that delegation is required
  being ignored by the model "for efficiency" — the exact rationalization the 9-clause
  checklist handed main a vocabulary for.
- This repo's own nudge-compliance tracking (`hooks/stop/nudge-compliance-tracker.sh`)
  measures roughly 22.6% follow-through on advisory nudges. An advisory that lands one time in
  four is a suggestion, not a control.

## Steelman against

These are the arguments the 2026-09-01 rejection rested on. They are real and primary-sourced,
and this decision is made with them in full view — not in ignorance of them.

- **Claude Code's own sub-agents documentation** (`code.claude.com/docs/en/sub-agents`,
  confirmed 2026-09-01) names four conditions that favor main-thread execution: "The task
  needs frequent back-and-forth or iterative refinement", "Multiple phases share significant
  context, such as planning, implementation, and testing", "You're making a quick, targeted
  change", and "Latency matters. A subagent that isn't a fork starts fresh and may need time
  to gather context".
- **Anthropic's multi-agent research system post**
  (`anthropic.com/engineering/multi-agent-research-system`, confirmed 2026-09-01) reports
  that subagent dispatch used about 15× the tokens of a single-agent chat interaction, and
  that token usage alone explained about 80% of that system's performance variance on
  BrowseComp. Fan-out has a real multiplier.
- **superpowers issue #1120** (obra/superpowers) reports a strict planner-only workflow
  costing 10–15× more than direct file creation for a trivial 5-line file — the fix-round
  case this ADR now routes through an agent anyway.
- **Cognition (maker of Devin)** has argued publicly against splitting planning from
  execution across agents, preferring a single-threaded linear agent that carries full
  context end to end.
- **Claude Code issue #40339** shows the failure from the other side: raising delegation
  rate without raising scoping quality has made results worse in the field. That is why the
  protocols in `orchestrate/reference.md` ship with the gate, not after it.

## Decision

**Accepted (2026-09-02).** The top-level session plans, dispatches, verifies, and decides; it
never edits files, runs mutating commands, runs tests, or commits. Enforced by
`hooks/gates/main-exec-guard.sh` when `MH_MAIN_EXEC_GUARD=1`.

The guard is switched on for this operator's interactive sessions through a shell alias (the
`csp`/`cspr` launchers export `MH_MAIN_EXEC_GUARD=1` before starting `claude`), not through
the global `settings.json` `env` block — a settings-level export would also gate background and
Superset-dispatched workers, which are the executors the rule exists to route work to. The
plugin ships with the guard off.

## Accepted costs

- **The incident fast path gets one more round-trip.** Prior doctrine on the hotfix path told
  main to "execute inline (no sub-agents)" for latency. This ADR knowingly overrides that: the
  hotfix goes to one foreground fixer agent, and the added latency is the price of an absolute
  rule.
- **Main loses its own syntax and lint checks.** `bash -n`, `shellcheck`, `py_compile`, `tsc`
  are read-only in effect, but the Bash classifier denies them as validation commands under
  the same rule that denies test runs — a validator agent runs them and returns the output.
- **Every tiny fix pays a dispatch.** The 10–15× superpowers figure applies to exactly this
  case. The short-form F9 fix-round (haiku, four slots, batched per wave) is the mitigation,
  not a refutation.

## What this ADR does NOT authorize

- **No MCP-mutating-tool deny leg, no `Monitor`-tool deny leg, no `Artifact`
  write_db/upload_asset deny leg.** None is built in v1. Add one only if real usage shows
  main executing through it.
- **No per-skill custom command allowlists for main.** A skill that currently executes steps
  directly — including the handful carrying `disable-model-invocation: true` — routes its
  execution steps through a dispatched agent. No per-skill exceptions.
- **No default-on in the shipped plugin.** The guard stays off by default; the operator turns
  it on locally.
- **No change to what subagents may do.** The gate keys on the absence of `agent_id`; a
  subagent's toolset is untouched.

**Non-goal: this is a habit guard, not a security sandbox.** The mutating-Bash detector is
pattern-based and can be evaded by a sufficiently obscure shell construct. awk/sed program text
that writes files through internal redirects or shells out via `system()` is matched and denied
where recognized, but that is not an exhaustive proof of absence. The threat model is a
well-meaning model reaching for the nearest tool, not an adversary.

## Revisit trigger

- **Claude Code ships a native, supported way to restrict the top-level session's own tools**
  (a "delegate mode" or equivalent) → replace this gate with that; delete, don't layer.
- **Evidence that `fork`-type subagents or Workflow-tool-spawned agents do NOT carry
  `agent_id` in hook input** (unverified locally as of this ADR) → a policy or code exception
  is needed before the gate can safely stay on for those paths. Until then, a `fork` that
  gets denied is a bug report, not something to route around.
- **The operator relaunches with the guard off three or more times in one week** → re-open
  this decision. Repeating the workaround silently is the exact failure this ADR names.
