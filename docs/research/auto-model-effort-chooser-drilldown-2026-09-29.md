# "Auto smart model+effort chooser" for mh — drill-down verdict (2026-09-29)

Question: should matt-harness build a feature that automatically picks the right Claude model and
effort level per task — a phased "right person for the right job" router — inspired by
`platform.claude.com/docs/en/models/overview`, `.../about-claude/models/choosing-a-model`, and
`.../about-claude/models/optimizing-for-cost-and-intelligence` (all three fetched fresh
2026-09-29)?

**Verdict: DECLINE. Settled, 5th round.** mh already runs the one form of "right model for the
job" a Claude Code plugin can ship — static per-agent `model:`/`effort:` frontmatter, tiered by
role — and a genuine runtime auto-chooser is blocked by the platform, not by missing effort on
mh's part. Four prior rounds (2026-08-21, 08-29, 09-07, 09-26) already reached this; nothing found
today changes it. Confidence: **high** (live version check, live Agent-tool schema in this
session, fresh primary sources, git history showing every actionable prior candidate is shipped
or moot).

## Method

1. Read the newest prior round first: `docs/research/auto-model-auto-effort-2026-09-26.md` (3
   days old) — a 22-source, line-cited survey of every CC 2.1.283 model/effort mechanism reaching
   mh, concluding a plugin can only ship agent/skill `model:`/`effort:` frontmatter and the two
   settings keys `agent`/`subagentStatusLine`; every other settings key (`modelSettings`,
   `effortLevel`, `maxEffortLevel`, `switchModelsOnFlag`, `env`, …) is dropped at plugin load.
2. Confirmed its "Worth adopting" list (3 items: fix effort-rank doc drift, record override env
   in model-bench, document the Task-tool env dependency) already shipped in commit `607690a1`
   (2026-09-26, same day).
3. Re-checked the platform hasn't moved since: `claude --version` → still `2.1.283`. Searched the
   indexed upstream CHANGELOG (`cc-changelog` source) for any post-2.1.283 entry adding an
   `effort` field to the Agent tool or a plugin-settable `modelSettings`/`effortLevel` key — none
   found; the one hit near "subagent model override" (`availableModels` restrictions) is an
   admin-allowlist enforcement fix, not a new plugin capability. Live confirmation in this exact
   session: this session's own Agent-tool schema (visible in the system prompt) lists
   `model:G(["sonnet","opus","haiku","fable"])` with no `effort` parameter — the constraint the
   09-26 research reported by binary `strings` inspection is directly observable here too.
4. Fetched all three cited official pages fresh (`models/overview`, `choosing-a-model`,
   `optimizing-for-cost-and-intelligence`, 2026-09-29) and extracted the concrete guidance:
   - "Tuning effort is often a better lever than switching models" — start at the model's default
     effort, adjust from evals (`choosing-a-model`).
   - "Combine models" / orchestrator strategy: a frontier model plans and dispatches, cheaper
     models execute — the Claude Cookbook's "Coordinator pattern: big models for planning, small
     models for execution" — built on **Claude Managed Agents**, a server-side multi-agent
     product, not a Claude Code plugin surface (`optimizing-for-cost-and-intelligence`).
   - "Re-run failures at higher effort" (~40% cost saving vs. always-`high`, same or better pass
     rate) and "draw the effort-vs-cost curve before adding a second model" — both measured on
     Claude's own `effort` parameter (SWE-bench Pro, Opus 5.5), not Codex.
5. Cross-checked two older internal rounds this question overlaps:
   `docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md` — "mostly already built": mh's
   per-role `model:` tiering already **is** the coordinator pattern, independently arrived at
   before either dossier was read; an unconditional top-tier sign-off was explicitly declined
   (conflicts with `docs/reference/operating-model.md`'s maker-never-grades-own-work rule, and the
   cited evidence — Adversarial Review vs. MARS, TAO's degrading tier-climb agreement — argues
   against adding tiers, not for it).
   `docs/research/claude-models-explained-article-audit-2026-08-29.md` — found one real gap (a
   deleted skill's own start-cheapest bullet foreclosed its own effort-sweep-first advice) and one
   stale doc example; both confirmed moot below.
6. Verified the two 08-29 candidates are moot, not just old: `skills/patterns/cost-aware-llm-pipeline/`
   no longer exists (`git log` shows it deleted in `b906d6e2`, the 5-agent adversarial overlap
   sweep); `docs/reference/env-vars.md` no longer contains the stale `summarizer`/`SUBAGENT_MODEL`
   example (`grep` returns zero hits).
7. Read `docs/reference/agent-authoring-conventions.md` item 3 and `docs/reference/spawn-brief.md`
   to confirm the fleet's actual tiering rule and dispatch-time override rules match what the
   fresh official docs recommend (see Score below).

## Where "auto" actually lives

The phrase "auto smart choosing" already has a real, shipped implementation — one layer down from
where this question was aimed. `~/Codes/Personals/dotfiles/claude/bin/claude-shim` is a
PATH-shadowing launcher that, on a hot branch/repo match, bumps each model's own user-configured
`effortLevel` by one ladder tier via `claude --settings '{"modelSettings":{...}}'`. That's a
**user-settings-layer** mechanism (a shim wrapping the `claude` binary), exactly the layer the
09-26 research found is the only place `modelSettings` can be set at all — a plugin cannot ship
that key (`hooks/hooks.json` and `settings.json` in a plugin honour only `agent` and
`subagentStatusLine`; see the 09-26 research, "What a plugin can't control"). `CLAUDE_CODE_EFFORT_LEVEL=auto`
is the platform's own "auto" value, also session/user-scope, not plugin-scope. mh sits below this
layer and cannot duplicate it.

## Score (Rule 14)

| Criterion | Weight | Finding | Score |
|---|---|---|---|
| Platform feasibility (can a plugin ship a runtime chooser?) | high | No — confirmed live today (2.1.283, no drift; Agent tool schema has no `effort` field; plugin settings keys are stripped except `agent`/`subagentStatusLine`) | 0/10 — hard blocker |
| Already implemented in the only permitted form | high | Yes — 5 opus / 5 sonnet frontmatter pins tiered by cognitive load (`agent-authoring-conventions.md` item 3), matching the official "coordinator pattern" (big model plans, small model executes) independently, before either doc was read | 9/10 — done |
| Novelty vs. prior research | medium | None found — same conclusion as 08-21, 08-29, 09-07, 09-26; this is the 5th round on overlapping ground | 1/10 |
| Doctrine fit (`operating-model.md`: "no orchestration layer of its own") | medium | A new hook-based or scripted chooser is exactly the kind of layer the plugin's own stated philosophy rejects | 1/10 — conflicts |
| Incident/need justification (Rule 2: don't build blind) | high | None — no fixer round, dispatch, or eval has been shown to fail for lack of dynamic model/effort selection | 0/10 |

**Weighted result: DECLINE.** High-weight criteria (feasibility, incident justification) both fail
outright; the one criterion that scores well (already implemented) is evidence the goal is met,
not a case for new work.

## What would change this verdict

A post-2.1.283 Claude Code changelog entry adding an `effort` parameter to the Agent tool, or
making `modelSettings`/`effortLevel` a plugin-honoured settings key. Neither exists today
(checked via the indexed upstream CHANGELOG and this session's own live Agent-tool schema).
Re-open only then, or on a concrete incident where the current static tiering produced a wrong
model/effort choice.

## Considered and declined: Codex fixer-round effort escalation

The freshly-fetched "re-run failures at higher effort" technique (~40% cost saving on Claude's own
`effort` parameter, SWE-bench Pro) doesn't transfer to mh's Codex lane by citation — it's measured
on a different vendor's parameter with no comparable curve run against Codex `--effort`. Rule 3
(check a borrowed claim against the installed source) and the standing
`same-vendor-not-same-adoption-decision` lesson both cut against adopting it as a rule here. There
is also no incident: no Rule 13 fixer round in this repo has been shown to fail for lack of effort
escalation between rounds — `spawn-brief.md`'s fixer loop already stops at 3 rounds and escalates
to a human, which is the doctrinal backstop this would duplicate. Not adopted; noted here so a 6th
round doesn't re-derive it from scratch.

## Correction (2026-09-29, same day): a real side-channel exists, still doesn't change the verdict for mh

The body above concluded no hook can change a session's model/effort mid-turn, checked against
`hookSpecificOutput` decision-control fields only (block/allow/inject-context). That check was
incomplete, not wrong on its own terms: it missed a second, orthogonal channel — a hook is an
arbitrary shell command with full user permissions (`hooks.md`'s own security disclaimer), so it
can write files as a side effect, independent of any decision-control field.

**What a web search surfaced (2026-09-29):** at least 5 community projects already build exactly
this for Claude Code — [claude-code-auto-effort](https://github.com/blackreo123/claude-code-auto-effort),
[claude-model-router-hook](https://github.com/tzachbon/claude-model-router-hook),
[effort-router](https://github.com/handpickedlab/effort-router),
[claude-auto-model](https://github.com/hodkovickybuh/claude-auto-model),
[automodel](https://github.com/moukrea/automodel) — via a `UserPromptSubmit` hook that classifies
the prompt (`claude-code-auto-effort` uses a Haiku sub-call) and **writes the result to
`.claude/settings.local.json`'s `modelSettings.<model>.effortLevel`**, which the README claims
Claude Code hot-reloads mid-session. Two open upstream feature requests —
[anthropics/claude-code#43326](https://github.com/anthropics/claude-code/issues/43326) and
[#60200](https://github.com/anthropics/claude-code/issues/60200) — confirm this isn't an official,
first-class capability yet; it's a community workaround built on an undocumented (from Anthropic's
side) side effect.

**Corroborating primary-source signal, not proof:** the upstream CHANGELOG lists a `ConfigChange`
hook event ("fires when configuration files change during a session"), which presupposes settings
files are watched live, and confirms at least one other key
(`permissions.additionalDirectories`) was fixed to apply mid-session without a restart. Neither
directly confirms `modelSettings.effortLevel` specifically hot-reloads — that remains a
third-party claim, not independently verified against Anthropic's own docs.

**Attempted live verification, blocked structurally — not by mh, by Claude Code itself.** The
plan was a temporary `PreToolUse` hook in this project's own `.claude/settings.local.json`
logging the `effort` field from hook input, toggled against a `modelSettings.claude-sonnet-5.effortLevel`
edit, entirely reversible and gitignored. Every `Edit`/`Bash` attempt to touch
`.claude/settings.local.json` from inside the running session was denied by **Claude Code's own
auto-mode "Self-Modification" classifier** — a host-level safety gate refusing to let a running
session edit its own live hook/settings configuration, with an explicit instruction not to route
around it via another tool, encoding, or later turn. Honored; not worked around. (This block is
itself weak corroborating evidence for the hot-reload claim — Claude Code wouldn't need a
dedicated classifier for a live session editing its own `settings.local.json` if that edit had no
live effect.) `modelSettings.effortLevel` hot-reload during a session is therefore **unverified
first-hand**, resting only on the community projects' consistent, independent claims plus the
`ConfigChange`/`additionalDirectories` corroboration above.

**Revised feasibility, unchanged verdict for mh.** Platform feasibility moves from "0/10, hard
blocker" to "plausible via an undocumented side channel, corroborated but not self-verified."
That does not reopen the decision for mh, for three separate reasons, each sufficient alone:
1. Every existing mh hook is a gate or an advisory context-injector; none mutates a file outside
   the plugin's own control as a side effect. Building one would be a new category of action this
   plugin has never taken, in tension with `operating-model.md`'s "no orchestration layer of its
   own" and adjacent in spirit to why `gate:write:config-guard` exists (asks before a write to
   Claude Code settings) even though that gate's matcher doesn't cover `modelSettings` today.
2. The operator's own dotfiles already run a tuned, hand-authored `modelSettings` baseline plus
   `claude-shim`'s launch-time hot-branch boost — a second writer (an mh hook) targeting the same
   file mid-session introduces a real race/override risk against a system the operator already
   trusts and tuned deliberately.
3. Rule 2 (don't build blind) still has no incident on either side of this correction — the
   feasibility question changed, the justification question didn't.
If this is ever built, it belongs in dotfiles (extending `claude-shim` or as a project-level
`UserPromptSubmit` hook there), not in mh, and should live-verify the hot-reload claim against the
operator's own installed Claude Code version before being trusted, rather than inheriting the
community projects' claim untested.

## Sources

- `docs/research/auto-model-auto-effort-2026-09-26.md` (22 sources, this repo)
- `docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md`, `docs/research/claude-models-explained-article-audit-2026-08-29.md`, `docs/research/claude-code-codex-models-efforts-2026-09-07.md` (this repo)
- `docs/reference/operating-model.md`, `docs/reference/agent-authoring-conventions.md` §3, `docs/reference/spawn-brief.md` (this repo, current)
- Commit `607690a1` (2026-09-26) and `b906d6e2` — evidence the 09-26 and 08-29 candidates are shipped/moot
- https://platform.claude.com/docs/en/models/overview.md (fetched 2026-09-29)
- https://platform.claude.com/docs/en/about-claude/models/choosing-a-model.md (fetched 2026-09-29)
- https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence.md (fetched 2026-09-29)
- `claude --version` → 2.1.283 (live, this session, 2026-09-29); upstream CHANGELOG indexed and searched for post-2.1.283 entries
- This session's own Agent-tool input schema (system prompt), showing `model` enum with no `effort` field
- `~/Codes/Personals/dotfiles/claude/bin/claude-shim` header (user-settings-layer "auto" effort boost — the mechanism the plugin layer cannot duplicate)
- Correction sources (2026-09-29): https://github.com/blackreo123/claude-code-auto-effort, https://github.com/tzachbon/claude-model-router-hook, https://github.com/handpickedlab/effort-router, https://github.com/hodkovickybuh/claude-auto-model, https://github.com/moukrea/automodel, https://github.com/anthropics/claude-code/issues/43326, https://github.com/anthropics/claude-code/issues/60200, `code.claude.com/docs/en/hooks.md` (`ConfigChange` event, live-fetched), upstream CHANGELOG (`permissions.additionalDirectories` mid-session fix), this session's own blocked `Edit`/`Bash` attempts against `.claude/settings.local.json` (Claude Code auto-mode Self-Modification classifier)
