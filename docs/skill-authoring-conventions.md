# Skill authoring conventions

**Status:** Convention reference. Owned by the harness. Sibling of
[`agent-authoring-conventions.md`](./agent-authoring-conventions.md) and
[`command-authoring-conventions.md`](./command-authoring-conventions.md). Load this when actually
writing or editing a skill/command/agent's content — it moved out of the root `CLAUDE.md` because
none of it is needed for routine work in this repo.

**Core doctrine:** when creating or editing a skill under `skills/`, follow matt-pocock's
`writing-for-agents` doctrine — canonical: the `mattpocock-skills:writing-for-agents` skill
(installed as the `mattpocock-skills` plugin, not vendored in this repo since v0.46.0 — see
README.md Quick Start). Renamed from `writing-great-skills` in matt v1.2.0 (no alias) and
restructured: the live elements are leading words, one trigger per branch, completion criterion +
demand, the no-op test, and progressive disclosure across the two loads (context load vs cognitive
load); skill-only mechanics (invocation choice, router skills) live in its `SKILL-MECHANICS.md`.
The old "two-cuts" and "failure-mode guard" labels dissolved into its When-to-split/Pruning prose.
The ≤25-word description cap is kbg's own token-budget rule (root `CLAUDE.md` § skill/agent
mechanics), not matt's — misattributed to matt here until 2026-08-10.

The `docs/skill-template/SKILL.md` template carries this checklist as a `## Design checks`
section — but `harness-audit` check 36 does **not** check for that heading's presence. It checks
the doctrine via INFO-only regex proxies against each skill's live
description/body (leading-word vocabulary, ≤25-word count [the kbg-native cap], completion-criterion
phrasing, a no-op-test line-count heuristic); "two-cuts" and "failure-mode guard" have no shell check — a
failure-mode regex proxy was tried and retired 2026-07-16 (vacuous before a reset-bug fix, 5/5
false-positive after: every flagged skill already named its failure mode in a prose section or
bullet list the numbered-window proxy couldn't see). INFO findings never fail the gate. Confirmed
2026-07-22: only 2/35 native skills (`pr`, `task-prep`) actually carry a `## Design checks`
section — the template's checklist is documentation, not an enforced requirement.

**Named Model footers:** a skill/command/agent that makes load-bearing reasoning/judgment choices
may end with a `## Named Model` footer citing cc-thinking-skills lenses. Apply the 3-condition
rubric from `memory/mental-models-sweep-v0302-2026-07-03.md`: (1) load-bearing reasoning gap, (2)
name-a-lens benefit for the operator, (3) honesty posture preserved (footer is a scaffold +
catalog pointer, never "this lens proves correctness"). The curated catalog is
`docs/reference/reasoning-models.md`; the 39 raw models live under
`docs/reference/thinking-skills/skills/`.

**Suggested next step footers:** a workflow surface (command or workflow skill run as a discrete
step) may end its Output/Summary phase with a `Suggested next step:` marker — outcome-branched
(`situation → action`), citing skills as `kbg:<name>` and commands as `/<name>`. Skills are ALWAYS
cited `kbg:`-form (never `/name`) — get this right at authoring time: `harness-audit` check 40
only catches rename/deletion drift on refs already in `kbg:` form, it does **not** scan for a skill
mis-cited in slash form (confirmed: this exact bug shipped twice — `commands/pr.md` and
`diagnosing-bugs/SKILL.md` both cited a skill as `/name` undetected until a manual survey caught
it, v0.35.0). Passive suggestion only — never "invoke X now" / auto-chain (that collides with the
no-model-self-start doctrine). Skip self-contained reference/pattern/catalog surfaces (a forced
footer there is the retired canonical-sections ceremony, 2026-06-16) and terminal workflows
(post-mortem, ship-release terminus).

**Escalation to `AskUserQuestion`:** a branch belongs in the passive footer only while it's
anticipatory — conditional on a fact not yet known (did the reviewer comment, did CI go red). If
every branch is already true/decidable right now and there's no sensible default, that's a
present-tense fork, not a suggestion — surface it via `AskUserQuestion` (per
`output-styles/staff-eng.md`'s decision-question rule: one-line consequence per option) instead of
text the user might not read. Model: obra/superpowers' `finishing-a-development-branch` skill,
which ends by presenting exactly N concrete options (merge/PR/keep/discard) and blocking for the
pick — not superpowers' separate (and rejected) `using-superpowers` auto-chain directive. None of
kbg's shipped footers (v0.35.0/.1) currently qualify — they're all anticipatory-conditional — so
this is a criterion for future surfaces, not a rewrite of what shipped.
