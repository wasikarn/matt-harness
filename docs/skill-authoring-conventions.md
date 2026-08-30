# Skill authoring conventions

**Status:** Convention reference. Owned by the harness. Sibling of
[`agent-authoring-conventions.md`](./agent-authoring-conventions.md). Load this when actually
writing or editing a skill/agent's content — it moved out of the root `CLAUDE.md` because
none of it is needed for routine work in this repo. (`command-authoring-conventions.md` was
deleted 2026-08-25, #112 — its whole subject, the commands/ vs skills/ distinction, no longer
exists once commands/ retired as a surface type.)

**Core doctrine:** when creating or editing a skill under `skills/`, follow matt-pocock's
`writing-for-agents` doctrine — canonical: the `mattpocock-skills:writing-for-agents` skill
(installed as the `mattpocock-skills` plugin, not vendored in this repo since v0.46.0 — see
README.md Quick Start). Renamed from `writing-great-skills` in matt v1.2.0 (no alias) and
restructured: the live elements are leading words, one trigger per branch, completion criterion +
demand, the no-op test, negation (`writing-for-agents/SKILL.md`: steering by prohibition drags the
forbidden behaviour into context — state the target behaviour, not the ban; no mechanical check
exists for this one, same as completion criterion below — deciding whether a given negative-sounding
instruction is a necessary prohibition or the pattern matt describes needs semantic judgment a regex
can't make reliably), and progressive disclosure across the two loads (context load vs cognitive
load — a writing heuristic: how many tokens a passage costs vs how hard it is to parse); skill-only
mechanics (invocation choice, router skills) live in its `SKILL-MECHANICS.md`. **Not the same axis
as Anthropic's own "progressive disclosure"** (`platform.claude.com/.../agent-skills/overview.md`,
confirmed 2026-08-29): that's a 3-level *runtime loading-stage* mechanism (metadata always
loaded → SKILL.md body loaded on trigger → bundled files loaded only when read), a mechanical fact
about when content enters context, not a writing heuristic about how to phrase it. Same term,
different question — don't conflate matt's "two loads" with Anthropic's "three levels" when citing
either.
The old "two-cuts" and "failure-mode guard" labels no longer exist as named terms — two-cuts'
content lives in its When-to-split section (+ SKILL-MECHANICS.md for the invocation cut), and the
failure-modes section was distributed across the sections that now own each mode.
The ≤25-word description cap is kbg's own token-budget rule (root `CLAUDE.md`'s skill/agent
mechanics section), not matt's — misattributed to matt here until 2026-08-10.

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
pair to `skills/meta/compress-docs/scripts/verify-preserved.py`, which checks structural preservation
only (fenced code blocks, headings, inline code spans, link URLs, frontmatter) and never prose
comprehension: a compression pass can pass that script at 100% green while still turning
explanatory prose into an unclear telegram, as long as every structural element survives untouched.
The no-op test is what catches that case — a size check and `verify-preserved.py` passing is
necessary, never sufficient, on its own.

**Named Model footers:** a skill/agent that makes load-bearing reasoning/judgment choices
may end with a `## Named Model` footer citing cc-thinking-skills lenses. Apply the 3-condition
rubric from `memory/mental-models-sweep-v0302-2026-07-03.md`: (1) load-bearing reasoning gap, (2)
name-a-lens benefit for the operator, (3) honesty posture preserved (footer is a scaffold +
catalog pointer, never "this lens proves correctness"). The curated catalog is
`docs/reference/reasoning-models.md`; full write-ups for the 39 raw models live upstream in the
cc-thinking-skills repo it links to — kbg does not vendor them locally.

**Suggested next step footers:** a workflow skill run as a discrete
step may end its Output/Summary phase with a `**Suggested next step:**` marker — outcome-branched
(`situation → action`). Canonical shape (copy `skills/review/pr/SKILL.md`'s footer, don't reinvent
it): the bold marker alone on its own line, optionally prefixed by that phase's own step number
(`4. **Suggested next step:**`), followed by one `- <outcome> → \`<surface>\`` bullet per branch.
Not permitted: branches sharing the marker's line, an H2 heading in place of the marker, an
unbolded or lowercase marker, or unbacktick'd surface names — `harness-audit` check 57 catches
drift from this shape (file-level: it only requires the canonical line to appear somewhere in a
file that mentions "suggested next step" at all, so it never fires on ordinary report-content
prose like "a suggested next step per issue").

An mh-owned skill is cited `mh:<name>` (this repo's own surface type — commands/ retired
2026-08-25, #112). A **matt-owned** skill is cited `mattpocock-skills:<name>` the same way — the
"ALWAYS `mh:`-form" framing this section used to carry was narrower than shipped practice
(`bug-sweep`, `refactor-clean`, and `complexity-check` all correctly cite
`mattpocock-skills:code-review`/`diagnosing-bugs`). Either namespace, model-invocable, cite bare;
`disable-model-invocation: true` on either side means the footer prints the literal slash string
the user types themselves — `` `/mh:<name>` `` or `` `/mattpocock-skills:<name>` `` — never
"invoke X now" in either case. Verified 2026-08-30: a namespaced slash citation like
`` `/mattpocock-skills:implement` `` does not false-positive check 46 (its bare-`/name` regex
requires no `:` before the closing backtick).

**Passive footer, active runtime — a deliberate split, not a loophole.** The footer text itself
stays passive: never "invoke X now" / auto-chain (that collides with the no-model-self-start
doctrine) — get this right at authoring time, since `harness-audit` check 37 only catches
rename/deletion drift on refs already in `mh:` form, and check 46 catches a skill mis-cited in
bare slash form (confirmed: this exact bug shipped historically — a former `commands/pr.md` and
`diagnosing-bugs/SKILL.md` both cited a skill as `/name` undetected until a manual survey caught
it, v0.35.0). What the footer's passivity does NOT constrain is the model's own next turn: once a
model-invocable skill's footer names a next step, the model may act on it in that turn exactly as
it would on any other self-invocable skill trigger — the doctrine gates the *text a skill's
author writes*, not whether the *runtime model* may continue. A gated (`disable-model-invocation`)
next step still requires relaying the literal string for the user to type; that boundary is
unaffected.

Skip self-contained reference/pattern/catalog surfaces (a forced
footer there is the retired canonical-sections ceremony, 2026-06-16) and terminal workflows
(post-mortem, ship-release terminus). No `PostToolUse (Skill)` hook exists for this and none is
planned: that event fires when a skill's instructions *load*, not when its work finishes, so a
completion-time nudge there would fire at the wrong moment — the footer text embedded in the
skill's own Output phase is the only mechanism.

**`model_limitation:` frontmatter field:** optional, kbg-native (non-standard-but-harmless
per root `CLAUDE.md`'s skill/agent mechanics section). Declare it when a skill's correctness rests on
a model capability or behavior that could shift on a model upgrade — a moving-target
assumption, not a stable fact. Canonical spec + worked example: `docs/skill-template/SKILL.md`
(frontmatter comment + "Model Limitation Assumption" body section). The quarterly cadence
(`docs/harness-decay-cadence.md`'s Cadence section) walks every skill carrying this field and prompts
a re-verify. First real adopter: `tech-humanize/SKILL.md` (`f940729`) — its lexical-tell catalog
assumes current-gen LLM output still carries the enumerated tells (em dash, delve,
rule-of-three), which decays across model generations. No shell check enforces re-verification
today — it's a human-cadence pointer, not a gate.

**Explicit `model:` + `effort:` on every surface (fleet convention, v0.68.430):** every file in
`agents/` and `skills/*/SKILL.md` carries both keys
explicitly — a new surface must ship with them. Rules: skills always use
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
dominates). Skill entrypoints only — `skills/*/references/*.md` fragments stay
unstamped. Scope facts: skill `effort:` applies only while the surface is active;
`CLAUDE_CODE_EFFORT_LEVEL` env would override every frontmatter value (unset in this environment);
harness-audit check 21 accepts `inherit` as an agent model value. Drift backstop: check 54 WARNs on
any surface missing either key, a non-tier `effort:` value, or a non-`inherit` skill
`model:` (unless `context: fork`) — deliberately NOT the per-surface tier map, which stays a
judgment call retiered via normal version-bumped edits.

**Reference-file conventions (Anthropic Agent Skills best-practices, verified 2026-08-29):**
source: `platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices.md`. Three
rules; one was already followed once but never generalized:

- **One level deep from SKILL.md.** Every reference file must be linked directly from SKILL.md —
  never SKILL.md → `advanced.md` → `details.md`. Claude partial-reads long files with `head -100`;
  a second-hop reference risks never being reached at all. Previously stated only as one skill's
  local note (`tech-humanize/SKILL.md:123`); this promotes it repo-wide.
- **Table of contents on any reference file over 100 lines**, so a partial read still shows the
  full scope before the rest of the file loads.
- **MCP tools named in fully-qualified `ServerName:tool_name` form** in skill/agent prose (e.g.
  `qmd:query`, not bare `query`) — avoids a "tool not found" miss once more than one MCP server is
  active. Applies to root `CLAUDE.md`'s own qmd/context7 references and any skill body that names
  an MCP tool.

Declined from the same audit, not adopted: eval-driven authoring (write 3
`{query, files, expected_behavior}` scenarios before the skill body, so the skill solves a
demonstrated gap rather than an imagined one) and the "degrees of freedom" framing (match
prose-vs-exact-script specificity to task fragility) — both real, both left for a future pass, no
owner yet. Full cross-check: two-agent parallel audit against `overview.md` + `best-practices.md`,
2026-08-29. The description-length discrepancy the same audit surfaced (official spec states 1,024
chars; check 20 enforces 1,536, sourced from a different page) is deliberately unresolved — verify
`code.claude.com/docs/en/skills` directly before touching that number either way.

**Evals-first authoring (Anthropic Agent Skills best-practices, adopted 2026-08-29):** before
drafting a new skill's body, run the task WITHOUT the skill and write down 3 concrete example
requests it should handle — what's asked, what context/files it needs, what a correct answer
looks like. If Claude already clears the bar on all 3 without any skill at all, the skill
shouldn't exist (the no-op test, above, is the same instinct applied post-hoc to individual
sentences; this applies it pre-hoc to the whole skill). Then write only the instructions that
close the gaps the baseline run actually showed — not instructions for a failure mode you
imagined but never observed. Deliberately lighter than the official doc's full 5-step
eval-driven-development process (a JSON `{query, files, expected_behavior}` schema, a
build-your-own-harness step) — `mh:eval-harness` exists for exactly that scale, aimed at
downstream product quality, not per-skill authoring. This is the proportionate version for a
personal harness: 3 real examples and an honest baseline check, not a formal suite.

**Degrees of freedom (same source, adopted 2026-08-29):** match how tightly a step is specified
to how expensive a wrong deviation would be — not a uniform level of detail across the whole
skill. High freedom (a paragraph of judgment criteria, several valid approaches) for genuinely
open calls where the model's judgment is the point. Medium freedom (parameterized pseudocode
or a script with documented options) for semi-structured work with a few right shapes. Low
freedom (an exact script, run it, no deviation) for fragile or high-stakes operations where an
improvised variant breaks something — file-format manipulation, anything destructive, anything
where "close enough" isn't. A different axis from the two-cut check above: two-cut governs
*whether to split a skill*; this governs *how tightly to constrain a single step once it's in
one*. Over-specifying a judgment call reads as condescending noise the model ignores;
under-specifying a fragile one is where a plausible-looking wrong variant slips through.

**Escalation to `AskUserQuestion`:** a branch belongs in the passive footer only while it's
anticipatory — conditional on a fact not yet known (did the reviewer comment, did CI go red). If
every branch is already true/decidable right now and there's no sensible default, that's a
present-tense fork, not a suggestion — surface it via `AskUserQuestion` (per
`output-styles/crisp.md`'s decision-question rule: one-line consequence per option) instead of
text the user might not read. Model: obra/superpowers' `finishing-a-development-branch` skill,
which ends by presenting exactly N concrete options (merge/PR/keep/discard) and blocking for the
pick — not superpowers' separate (and rejected) `using-superpowers` auto-chain directive. None of
kbg's shipped footers (v0.35.0/.1) currently qualify — they're all anticipatory-conditional — so
this is a criterion for future surfaces, not a rewrite of what shipped.
