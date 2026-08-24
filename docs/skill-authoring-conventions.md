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
The old "two-cuts" and "failure-mode guard" labels no longer exist as named terms — two-cuts'
content lives in its When-to-split section (+ SKILL-MECHANICS.md for the invocation cut), and the
failure-modes section was distributed across the sections that now own each mode.
The ≤25-word description cap is kbg's own token-budget rule (root `CLAUDE.md` § skill/agent
mechanics), not matt's — misattributed to matt here until 2026-08-10.

The `docs/skill-template/SKILL.md` template carries this checklist as a `## Design checks`
section — but `harness-audit` check 34 does **not** check for that heading's presence. It checks
the doctrine via INFO-only regex proxies against each skill's live
description/body (leading-word vocabulary, ≤25-word count [the kbg-native cap], completion-criterion
phrasing, a no-op-test line-count heuristic); "two-cuts" and "failure-mode guard" have no shell check — a
failure-mode regex proxy was tried and retired 2026-07-16 (vacuous before a reset-bug fix, 5/5
false-positive after: every flagged skill already named its failure mode in a prose section or
bullet list the numbered-window proxy couldn't see). INFO findings never fail the gate. Confirmed
2026-07-22: only 2/35 then-native skills actually carried a `## Design checks` section (`pr` is
the sole survivor — the other was removed in the 2026-08-24 planning-surface retirement) — the
template's checklist is documentation, not an enforced requirement.

**No-op test — the qualitative backstop for every size-driven trim:** source doctrine
`mattpocock-skills:writing-for-agents`. One operative sentence: delete the line — does agent
behavior change on a real branch of the skill's own worked examples? If not, prunable regardless
of what the char count says; if so, load-bearing regardless of char count. Applies to every trim
driven by any of the six size checks — 20, 34, 38, 43, 47, 52 — not just 34. It's the required
pair to `skills/compress-docs/scripts/verify-preserved.py`, which checks structural preservation
only (fenced code blocks, headings, inline code spans, link URLs, frontmatter) and never prose
comprehension: a compression pass can pass that script at 100% green while still turning
explanatory prose into an unclear telegram, as long as every structural element survives untouched.
The no-op test is what catches that case — a size check and `verify-preserved.py` passing is
necessary, never sufficient, on its own.

**Named Model footers:** a skill/command/agent that makes load-bearing reasoning/judgment choices
may end with a `## Named Model` footer citing cc-thinking-skills lenses. Apply the 3-condition
rubric from `memory/mental-models-sweep-v0302-2026-07-03.md`: (1) load-bearing reasoning gap, (2)
name-a-lens benefit for the operator, (3) honesty posture preserved (footer is a scaffold +
catalog pointer, never "this lens proves correctness"). The curated catalog is
`docs/reference/reasoning-models.md`; full write-ups for the 39 raw models live upstream in the
cc-thinking-skills repo it links to — kbg does not vendor them locally.

**Suggested next step footers:** a workflow surface (command or workflow skill run as a discrete
step) may end its Output/Summary phase with a `Suggested next step:` marker — outcome-branched
(`situation → action`), citing skills as `kbg:<name>` and commands as `/<name>`. Skills are ALWAYS
cited `kbg:`-form (never `/name`) — get this right at authoring time: `harness-audit` check 37
only catches rename/deletion drift on refs already in `kbg:` form, it does **not** scan for a skill
mis-cited in slash form (confirmed: this exact bug shipped twice — `commands/pr.md` and
`diagnosing-bugs/SKILL.md` both cited a skill as `/name` undetected until a manual survey caught
it, v0.35.0). Passive suggestion only — never "invoke X now" / auto-chain (that collides with the
no-model-self-start doctrine). Skip self-contained reference/pattern/catalog surfaces (a forced
footer there is the retired canonical-sections ceremony, 2026-06-16) and terminal workflows
(post-mortem, ship-release terminus).

**`model_limitation:` frontmatter field:** optional, kbg-native (non-standard-but-harmless
per root `CLAUDE.md` § skill/agent mechanics). Declare it when a skill's correctness rests on
a model capability or behavior that could shift on a model upgrade — a moving-target
assumption, not a stable fact. Canonical spec + worked example: `docs/skill-template/SKILL.md`
(frontmatter comment + "Model Limitation Assumption" body section). The quarterly cadence
(`docs/harness-decay-cadence.md` § Cadence) walks every skill carrying this field and prompts
a re-verify. First real adopter: `tech-humanize/SKILL.md` (`f940729`) — its lexical-tell catalog
assumes current-gen LLM output still carries the enumerated tells (em dash, delve,
rule-of-three), which decays across model generations. No shell check enforces re-verification
today — it's a human-cadence pointer, not a gate.

**Explicit `model:` + `effort:` on every surface (fleet convention, v0.68.430):** every file in
`agents/`, `commands/*.md` + `commands/*/COMMAND.md`, and `skills/*/SKILL.md` carries both keys
explicitly — a new surface must ship with them. Rules: skills/commands always use
`model: inherit` (a main-thread `model:` value switches the session model for the REST OF THE
TURN — official skills.md frontmatter reference — so a concrete pin there is a footgun unless the
skill runs `context: fork`); effort tiers are low = script wrapper/display, medium =
deterministic tooling + bounded interpretation, high = normal judgment (the doc default), xhigh =
reserved for surfaces whose own procedure contains an independent re-check step (fresh-context
refute, re-score, drift guard) — the falsifiable membership test from the 2026-08-22 verifier
round. A support skill that an agent preloads via `skills:` frontmatter OR runtime-`Skill()`-loads
must carry the SAME effort as its host agent (preload-vs-agent effort precedence is undocumented
platform behavior — matching values moots it). Deliberate exceptions: `frontend-patterns` and
`typescript-patterns` stay `high` despite medium reviewer hosts (dual-use; main-thread coding
dominates). The 26 command entrypoints only — `commands/*/references/*.md` fragments stay
unstamped. Scope facts: skill/command `effort:` applies only while the surface is active;
`CLAUDE_CODE_EFFORT_LEVEL` env would override every frontmatter value (unset in this environment);
harness-audit check 21 accepts `inherit` as an agent model value. Drift backstop: check 55 WARNs on
any surface missing either key, a non-tier `effort:` value, or a non-`inherit` skill/command
`model:` (unless `context: fork`) — deliberately NOT the per-surface tier map, which stays a
judgment call retiered via normal version-bumped edits.

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
