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

> **Added later the same day.** The verdict, Score and reopen text below were written before the live
> tests. The decision (do not build in mh) stands, but two things in them changed: a runtime chooser is
> not blocked by the platform (a `turn.step` hook can set effort on the main loop, Correction 3), and
> the reopen conditions below are not the only ones. The map of what supersedes what is in
> Correction 6 at the end.

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

## Correction 2 (2026-09-29, later same day): live test and official docs say the side channel does not work

The first correction above rated the side channel "plausible, corroborated but not self-verified".
It has now been tested and checked against Claude Code's official docs. **That rating is
withdrawn: writing effort into a settings file does not change a running session's effort on
Claude Code 2.1.284.** Three things in the first correction also need fixing:
- "Two open upstream feature requests" was wrong. #43326 is open (labels `area:model`,
  `area:hooks`); #60200 was closed as stale and locked, with no maintainer reply.
- The `ConfigChange` event and the `permissions.additionalDirectories` fix were offered as
  corroboration of hot-reload. They prove that some keys reload live, not that effort keys do.
- The claim that a community project's hot-reload "works" rests on its own README, which reports
  one measurement (n=1, Claude Code 2.1.177, Windows) and warns that the set of live-reloaded keys
  can change between versions.

**Live test (operator-run, in the dotfiles repo, model `claude-sonnet-5-5`).** A `PreToolUse`,
`PostToolUse` and `Stop` probe hook logged the `effort` field from hook input; `CLAUDE_CODE_EFFORT_LEVEL`
was unset and `MH_EFFORT_SIGNAL=0`. The operator ran every settings edit (the Self-Modification
classifier blocks the agent from editing `.claude/settings.local.json`). Three runs:
1. First run: inconclusive (one log line, no turn attribution). The probe was upgraded to log the
   command, session id and env, and to write marker lines.
2. Second run: the session was already running when `modelSettings.claude-sonnet-5-5.effortLevel`
   was set to `low`; it reported `medium` (Sonnet 5.5's default) before and after both edits, so
   it never picked up either file change. Not clean, because that session never loaded `low` at launch.
3. Clean run: a fresh session started after the file said `low` reported `low` at launch and on
   turn 1 (so launch-time loading works). After the file was flipped to `high`, turn 2 still
   reported `low` on both `PreToolUse` and `PostToolUse` lines. The hook kept firing after the
   flip, so hooks reload live and only the effort value stays fixed.
A same-time contrast agrees: on the same model and the same file, the session started before the
edit stayed at `medium` while the session started after it read `low`.

**Official docs (fetched 2026-09-29).** `settings.md`, "When edits take effect": Claude Code
reloads most settings edits into a running session (`permissions`, `hooks`, credential helpers) but
"reads some keys only once, at session start". Among the keys listed for mid-session change,
`effortLevel` and `modelSettings` are given as "use `/effort` to change effort mid-session".
That names the top-level `effortLevel` too, so the top-level variant is refuted by the docs, not by our own test. `model-config.md`
gives the effort resolution order: an explicit choice first (`CLAUDE_CODE_EFFORT_LEVEL`, `--effort`,
`/effort` in the session), then saved settings, then the model default (`medium` for Opus 5.5 and
Sonnet 5.5). An upstream comment on #43326 reports the same for `model`: a hook that rewrites the
settings file affects only the next session.

**Revised verdict.** Platform feasibility of a settings-file side channel: 0/10 on the current
version (documented as read-once and confirmed by test). The decline for mh stands. What works for
effort selection today: `/effort`, `--effort` or `CLAUDE_CODE_EFFORT_LEVEL` at launch, agent
frontmatter, and advisory context injected from a `UserPromptSubmit` hook (which the model may or
may not follow). Reopen only if a changelog entry moves effort keys out of the read-once set;
recheck with the probe method above, since the community README suggests this behaviour differed on
2.1.177.

**Scope fix (same day, after 5 explorer agents read the 6 community repos and 5 opus attackers
re-checked them).** An earlier draft said "nothing changes the effort of a running main session
automatically". That is too broad. It holds for settings-file edits and hook fields, not for every
route. Routes found, with what survived the attack round:
- **Function hooks** (experimental, `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`; anthropics/claude-code#91870).
  Confirmed from the host-generated `types/claude-code.d.ts` in `rezzminator/agent-effort` (written
  by CC 2.1.282, "EARLY ACCESS"): `turn.step` fires for "main's or a subagent's" request,
  `effort` is rewritable via `next({...e, effort})` (d.ts:3923-3928, 11534, 11554), and `agentId` is
  "absent on main" (d.ts:11564). No text in types, README, CHANGELOG or the issue says main is
  pinned or bypassed; the plugin skips main by its own design (`agent-effort.ts:112`), and its test
  runs against a mock engine. **Not live-tested on main**, and whether the rewrite reaches the API
  body is unverified. "Prototype since 2.1.260" is attested by one commenter, not a maintainer
  (thread comment 2026-09-04: read and ran it in 2.1.260 behind the flag); the maintainer update of
  2026-09-09 names v267/v268 and publicly endorses `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` for testing.
  Thread commenters also confirm `effort` and `model` are the only rewritable `turn.step` fields
  (2026-09-15), and that `AgentSpawnInput` has no `effort` (2026-09-04). A per-request change might break
  prompt caching (unverified).
- **Function-hook limits from the thread** (commenter measurements on CC 2.1.263-2.1.284, not
  maintainer statements): a hook that overruns its 10 s budget is skipped and the layer beneath runs
  (fail-open), so an effort rewrite must be fast and do no heavy work; `agent.spawn` and `turn.step`
  do not fire for background-dispatched agents (2026-09-05), so this route would not cover them; the
  surface is still changing (new APIs keep being requested). Searched all 224 thread comments for
  `effort`/`turn.step`: 21 mention them, none reports a live main-session effort rewrite.
- **Probe correction.** The hook input field `effort.level` / `$CLAUDE_EFFORT` is "reasoning effort
  applied to the current turn" and reads as the session setting, so a normal logging hook can show
  the old level even when a `turn.step` rewrite worked, and record a false "refuted". A valid probe
  reads the outgoing request body (a logging `ANTHROPIC_BASE_URL` proxy or `--debug` request log),
  compared against a plain `/effort high` run, and also logs `e.model` and `e.effort`.
- **SDK controller wrapper** (`hodkovickybuh/claude-auto-model`). Confirmed against
  `@anthropic-ai/claude-agent-sdk` 0.3.284 `sdk.d.ts`: `applyFlagSettings` (L2911-2939) merges
  settings "mid-session", streaming-input mode only, and documents `effortLevel`; `set_model` and
  `get_settings` exist (L5018, L4189), and `get_settings` reports the effective value after env,
  caps and downgrades (L5891). The repo applies effort at `auto_model.py:533`. Limits: it replaces the
  native TUI with a `-p` REPL, tested on CC 2.1.263 only, one synthetic 5-turn run, 32 development-set
  routing cases; an `effortLevel` sent without `ultracode` turns ultracode off (SDK L2927-2931). Lives
  at the launcher/dotfiles layer, not in a plugin. Its own README agrees settings-file edits do not
  reach a running session (documentation-based, not an experiment).
- **Remote Control** (official docs): model and effort can be set from a connected claude.ai/code or
  mobile client and apply to the terminal session (effort v2.1.234+). Client-driven, not scriptable.
- **Skill `effort:`/`model:` frontmatter** (`handpickedlab/effort-router`). Official skills docs say
  `effort` "overrides the session effort level" while the skill is active, without saying when it
  ends (the repo's "resets at the next prompt" is unconfirmed); it is compliance-gated when Claude
  must choose to invoke the skill, but a user can type the skill's slash command, which is
  deterministic. The docs say `model` applies "for the rest of the current turn" without
  distinguishing who invoked it, which contradicts the repo's "ignored when Claude invokes"; neither
  side has transcript evidence, and the repo's "checked on 2.1.280" has no test.
- **Agent-variant files + `updatedInput.model`** (`tzachbon/claude-model-router-hook`, under
  `plugins/claude-model-router-hook/hooks/`; `moukrea/automodel`). Sub-agents only: a PreToolUse hook
  rewrites `model` (alias) and `subagent_type` to a variant with `effort:` frontmatter. `updatedInput`
  cannot carry effort (automodel spike S4, one run, requested value not recorded). tzachbon's
  `autoswitch` writes `~/.claude/settings.json` and "only affects new sessions".
- **Local API proxy** (`moukrea/automodel`): the only route found that changes a main session
  automatically (`ANTHROPIC_BASE_URL` plus a pseudo-model id rewriting `model` and
  `output_config.effort`). Risks: `ANTHROPIC_BASE_URL` sits in global settings, so a dead proxy stops
  every session; prompts, recent replies and compaction summaries go to two third parties; it sets an
  underscore-prefixed internal env var that may break on an update; its effort numbers (S10, S11) are
  n=1. Whether routing a subscription session through a proxy is allowed by the vendor terms is not
  settled by anything read, and is the operator decision.
- **Settings-file route, narrowed.** Our live test flipped `modelSettings.<model>.effortLevel` only.
  For the top-level `effortLevel` (what `blackreo123/claude-code-auto-effort` writes), the refutation
  rests on the docs (`settings.md`, "reads some keys only once"), not on our experiment; that
  project evidence is n=1 on CC 2.1.177, Opus, stream-json. No CHANGELOG entry between 2.1.177 and
  2.1.284 says the behaviour changed. One probe settles it: a fresh session with no `modelSettings`
  entry for the model anywhere, top-level `effortLevel: low` in `.claude/settings.local.json`, flipped
  to `high` mid-session, then read the per-message `effort` in the transcript JSONL (recorded since
  2.1.212) beside the hook `effort.level`.

The mh decision is unchanged, on different grounds: not "impossible", but "only an experimental API,
a launcher-layer wrapper or a third-party proxy remain, and there is no incident" (Rule 2). If the
main session should be routed automatically, test `turn.step` on main first with the corrected probe,
and build it in dotfiles, not in mh.

## Correction 3 (2026-09-29, later same day): function-hooks `turn.step` effort rewrite works on the main session

The scope fix above left one route untested: a `turn.step` hook rewriting `effort` on the main
session. It has now been run. **Result: it works on Claude Code 2.1.284 with `claude-sonnet-5-5`.**

**Probe.** A function-hooks plugin (`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`, loaded with
`--plugin-dir`) hooked `turn.step`. Each step it read a control file and, when the step had no
`agentId` (the main loop) and the file named a level, called `next({...e, effort})`. It logged
`effortIn`, target and `effortOut`. The operator ran the session and changed the control file between
turns, with no restart and no `/effort`.

| control file | `effortIn` | `effortOut` | effort recorded per assistant message in the transcript | output tokens |
|---|---|---|---|---|
| `off` | medium | medium | medium | 202, 213 |
| `low` | medium | low | low | 75 to 254 |
| `max` | medium | max | max | 2086 (then 336) |

`turn.step` fired for the main loop (`agent: main`), the rewrite changed the effort the transcript
records, and the `max` turn produced roughly 8 to 27 times the output of the `low` turns. That is
behavioural evidence that the request effort changed, not only a displayed value.

**What this does not prove.** n=1 per level, and the prompts differ (an `echo` against a five-step
proof), so the token ratio is a strong signal, not a measurement. The transcript field may record the
client's value rather than the request body; no logging proxy was used (a subscription session, and
the terms question above is open). Prompt-cache cost of a per-request change was not measured. The
10 s hook budget and the background-agent gap listed above still apply.

**Effect on the verdict.** The feasibility of an automatic main-session effort change moves from
"untested" to "works in a probe on 2.1.284, on an experimental API". The mh decision stays decline,
now for this reason: the mechanism exists but is experimental and its surface is still changing, it
belongs in a launcher or dotfiles layer or a separate mod rather than the mh plugin, and there is no
incident that shows the static per-agent tiering choosing wrongly (Rule 2). Reopen for mh if function
hooks reach a stable release and an incident or measured cost case appears; the probe above is the
recheck, and the next step for a real build is a cache-cost measurement and a body-level check.

## Correction 4 (2026-09-29, later same day): gap-closing research, two earlier lines corrected

Four read-only research agents checked the gaps left open above. Results, each against a primary source.

**Two earlier lines are wrong or incomplete; this note supersedes them.**
- Above, "a hook that overruns its 10 s budget is skipped and the layer beneath runs (fail-open)" is
  right as the default but incomplete. The typings (`types/claude-code.d.ts` in the `plugin-authoring`
  bundle, `HookBudget`) say the 10 s budget is per dispatch and counts only the hook's own code, not
  time waiting on `$` or `next`; a streaming `turn.step` hook is counted as the sum over the response.
  Past the budget the hook is absent, "its `.catch` asked, else `next(e)` run on its behalf".
  Fail-closed is possible through `.on(...).catch(...)` (the maintainer confirmed this in #91870).
- Above, "`agent.spawn` and `turn.step` do not fire for background-dispatched agents" is a commenter's
  measurement that the typings do not support: they say `turn.step` fires for "main's or a subagent's"
  request and name no exclusion. It is unproven both ways until a probe logs `e.agentId` for a
  background dispatch. Whether compaction and memory forks raise `turn.step` is also undocumented.

**Prompt cache.** `platform.claude.com/docs/en/build-with-claude/prompt-caching.md`, invalidation table
("Effort setting"): "Changing the `output_config.effort` value always invalidates message blocks", with
the same model-specific effect on the tool and system caches as thinking parameters (which model falls
on which side is not stated). Setting effort to the model's default equals omitting it and does not
invalidate. Models with per-message effort (beta `mid-conversation-output-config-2026-07-01`) can change
effort mid-conversation with the cached prefix intact; a hook rewriting the top-level value is not that
path. So a per-turn effort router pays a cache miss on each change (the orchestrator carries about
234,000 tokens per turn in the cost log), while a hook that holds one constant effort from the first
request causes no change and no miss. Not measured: the real cost, and Sonnet 5.5's tool/system side.

**Proxy on a subscription session.** `code.claude.com/docs/en/llm-gateway` documents `ANTHROPIC_BASE_URL`
with a saved claude.ai login as expected to work (the login stays the active credential), but the
protocol page says a gateway that "rewrites or redacts request bodies ... breaks the pairing", so
"inspect without modifying". No page allows or forbids rewriting `model` or `effort` on a subscription
session. The nearest restriction (`legal-and-compliance`) targets routing requests through plan
credentials "on behalf of their users". `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` is in none of nine
official pages read. Unsettled; only Anthropic Support could answer in writing. Recommendation stays: do
not use a rewriting proxy.

**Function hooks status.** `mods/README.md` in anthropics/claude-code: "Early access ... the API these
mods are written against may change between releases without notice". Gated by
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`; no release date found; the maintainer wrote in #91870 that whether
it ships depends on community feedback. An answer without `next` sends no request.

**`claude-shim` mapping** (all 239 lines read). A `turn.step` hook could replicate the hot branch/repo
test, the one-tier ladder bump and the kill switch. It cannot replicate PATH resolution and the `exit 127`
loud failure, or the skip when the caller passed `--effort`, `-p`, `--settings` (a hook cannot see argv).
Replacing the shim would also leave `hooks/effort-signal-report.sh:94` reporting "didn't boost this
launch" on every hot launch (nothing sets `MH_EFFORT_BOOSTED`) and break `hook-canary.sh` cases. The
claim that function hooks would not cover Superset-launched sessions has no support in the files; the
scoping doc points the other way for hooks.

**Decision (Rule 14).** Keep `claude-shim` as the actuator: shim 7.9, function-hook replacement 4.9
(stability 30%, fails loud 20%, launch coverage 20%, added benefit 20%, cache risk 10%); confidence
medium-high. The one movable part, effort logging, shipped as a log-only mod (`effort-log` in the
operator's dotfiles) so the cost log can finally show effort. Reopen when function hooks are stable and
a measured cache cost is neutral. Still open, needs a live test: whether the rewritten value reaches the
API body, and hot-reload of the top-level `effortLevel` key.

## Correction 5 (2026-09-29, later same day): measured results close the remaining gaps

Four gaps were left open by Correction 4. Two were closed from transcripts that already existed and two
by operator-run tests on Claude Code 2.1.284. The `effort-log` mod (log-only, function hooks, enabled
through `CLAUDE_CODE_PLUGIN_DIRS` in the operator's dotfiles) supplied the per-turn effort for the
tests.

**1. The rewritten effort reaches the API, and what a change costs the cache.** In the probe session
(`claude-sonnet-5-5`, effort rewritten by a `turn.step` hook), per-assistant-message usage in the
transcript, one row per message id:

| request | effort | cache_read | cache_creation |
|---|---|---|---|
| first of session | medium | 28,031 | 38,180 |
| last before change | medium | 68,845 | 403 |
| first after change to `low` | low | **28,031** | **41,539** |
| first after change to `max` | max | 70,616 | 501 |
| first after change back to `medium` | medium | 73,528 | 736 |

The first change dropped the read to the system and tools part (28,031, the same figure as the
session's first request) and recreated the message part (about 41.5k tokens): the server saw a
different request, which is direct evidence that the hook's value reaches the API, and it matches the
prompt-caching doc's "Effort setting" row. The later changes (`low` to `max`, `max` to `medium`) did
not invalidate: reads stayed at 70k to 73k with normal small creations. So on this model one effort
change cost one message-cache rebuild and later changes cost about nothing. The cause of that
difference is not established (a hypothesis: Claude Code sends effort per message after the first
change, the path the docs say preserves the cache; the transcript's `perTurnEffort` field fits but
proves nothing). n=1 session, one model. Correction 4's expectation of "a miss on each change" was too
pessimistic for this case and is superseded here; a hook holding one constant effort still costs
nothing.

**2. A top-level `effortLevel` edit does not reach a running session.** Scratch project, model
`claude-sonnet-4-6` (no `modelSettings` entry anywhere), top-level `effortLevel: low` in
`.claude/settings.local.json`. Turn 1: `effort-log` and the transcript both record `low`. The file was
flipped to `high` 15 seconds before turn 2. Turn 2: both still record `low`. This refutes the community
project's hot-reload claim for the top-level key by experiment (it was refuted by docs only before) and
agrees with `settings.md`: edits reach only the next session.

**3. Subagents, background agents and compaction.** In the same test session `effort-log` recorded
`turn.step` rows for two subagents, each with an agent id and the parent's effort (`low`): a `fork`
and a `general-purpose` agent. Both tool results read "Async agent launched successfully", so both ran
in the background even though the input carried no `run_in_background` field in this build. That
refutes the community claim that `turn.step` does not fire for background-dispatched agents, at least
for these launch paths on 2.1.284 (n=2). Running `/compact` (the transcript shows the compact
boundary) produced no `turn.step` row: the hook, which logs each loop's first request, did not see a
compaction request (n=1; a compaction that is not a turn would look the same).

**Consequence.** A `turn.step` hook can see and set effort for the main loop and for subagents, and a
constant value costs no cache. That makes a per-spawn or per-agent-type effort policy technically sound
(the route the `agent-effort` plugin takes), separate from the per-turn router this doc declines. It
does not change the mh decision: the mechanism is still experimental, mh already pins model and effort
per agent in frontmatter, and there is no incident (Rule 2). No gap from Correction 4 remains open
except the proxy terms question, which only Anthropic Support can answer.

## Correction 6 (2026-09-29, later same day): deep-audit findings, claims narrowed

Two independent checkers (a fresh Opus agent and Codex `gpt-6-sol`, read-only, given only the file list
and commit range) reviewed this doc, its memory entry and the dotfiles changes. They agreed on the
points below. Nothing here changes the mh decision; it narrows what the evidence supports.

**What supersedes what.**

| Earlier claim | Where | Status |
|---|---|---|
| "a genuine runtime auto-chooser is blocked by the platform"; feasibility 0/10 | Verdict, Score | Superseded by Correction 3: a `turn.step` hook set effort on the main loop (experimental API). The decline now rests on Rule 2 (no incident), the experimental status and mh's frontmatter tiering, not on impossibility |
| Reopen for an Agent-tool `effort` field or a plugin-honoured settings key, "or on a concrete incident" where static tiering chose wrong | "What would change this verdict" | Additional, not replaced: all three original triggers still count, and an incident alone still reopens. Added trigger: function hooks reach a stable release and a measured cost case appears (Correction 4's "stable and a measured cache cost is neutral" line is folded into this one) |
| "Two open upstream feature requests" (#43326, #60200) | Correction | Fixed in Correction 2 |
| The settings-file side channel is "plausible, ~6/10" | Correction | Withdrawn in Correction 2; the modelSettings and top-level variants are both refuted by test (Corrections 2 and 5) |
| "Hook overruns 10 s, fail-open"; "no `turn.step` for background agents" | Correction 2 | Hook timing corrected in Correction 4; the background-agent claim was made "unproven both ways" in Correction 4 and refuted in Correction 5 (n=2) |
| "A per-change cache miss" | Correction 4 | Narrowed by Correction 5, and again below |
| "No gap from Correction 4 remains open except the proxy terms question" | Correction 5 | Wrong; see the open list below |

**The cache result, restated.** The rows in Correction 5 are correct (they were recomputed from the raw
transcript). What they support is narrower than "direct evidence that the hook's value reaches the API":
- Only the first of three effort changes was followed by a cache miss. The other two were full hits,
  which contradicts the prompt-caching doc's "always invalidates message blocks", so that row does not
  explain the data by itself.
- Between the last `medium` response and the first `low` response the transcript holds a shell exchange
  (bash-input and bash-stdout lines, apparently the control-file write). Appended messages alone cannot make the earlier prefix miss
  (the read fell back to the system and tools part), but the history did differ, and no request body
  was captured.
- The one change that missed came in the session's only `!`-bash turn; the two that hit came in
  cross-session-message turns. Turn type is a second confound with the effort value itself.
- Consistent reading: the server saw a changed request at that point. It does not show which field
  changed, and the body-level check named in Correction 3 was never done. The other evidence that the
  rewrite took effect is the transcript's recorded effort and the 8x to 27x change in output tokens.
- The `perTurnEffort` remark in Correction 5 is withdrawn: the field is present before any hook edit
  (turn 1 of that session) and in sessions with no function hook, and it is null for the whole
  Sonnet 4.6 session, so it is a per-model field, not a marker of what happens after the first change.

**Forks and per-spawn effort.** "A constant value costs no cache" holds for a loop that keeps one effort
from its first request. It is untested for a per-spawn override on a fork: the fork's first request
reused the parent's cached prefix (both read 55,225 tokens), so a fork whose effort differs from the
parent's is the "change" case, which cost about 41.5k tokens once in the measured session. Correction
5's Consequence paragraph should read "a per-spawn effort policy is untested for forks".

**Still open** (Correction 5 said only the proxy terms question was): the request-body check of what
was actually sent; whether compaction and the memory forks raise `turn.step` on a path the index-0 log
does not see; the cache cost of a per-spawn effort on a fork; and the proxy terms question.

**Wording fixes.** `effort-log` logs each turn's first step (`index === 0`), not each loop's first
request. `claude/hooks/effort-signal-report.sh` in the operator's dotfiles reads `MH_EFFORT_BOOSTED` at line 94;
lines 118 and 121 emit the "claude-shim did not boost this launch" messages. In the
top-level `effortLevel` test the model's own default is `high`, so the turn-1 `low` can only have come
from the file. `effort-log` ignored `process.run`'s exit code (a failed append vanished); fixed in
dotfiles commit `b21d0d9f`, which now logs the exit code and stderr.

**The Correction 3 probe, condensed** (its source folder was deleted after the run; the full `Write` is
recoverable from the operator session transcript. The real source also logs an `effortOut` column, which
is the same value as `target` whenever the hook rewrites, so it is not a measurement. Correction 3's
"recheck" needs this probe rewritten). A function-hooks plugin, loaded with
`--plugin-dir` and `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`; a `control.txt` beside it holds `off`, `low`,
`medium`, `high`, `xhigh` or `max`, changed between turns:

```ts
import type { Register } from 'claude-code'
const DIR = '<absolute path of the plugin folder>'
const LEVELS = new Set(['low', 'medium', 'high', 'xhigh', 'max'])
export const register: Register = on => {
  on('turn.step', async function* ($, e, next) {
    let target = 'off'
    try { target = (await $.fs.read(`${DIR}/control.txt`)).trim() } catch { /* log only */ }
    const rewrite = e.agentId === undefined && LEVELS.has(target)
    // ...append {turnId, index, model, agent, effortIn: e.effort, target} to a log here...
    return yield* next(rewrite ? { ...e, effort: target as 'low' } : e)
  })
}
```

**Checker scope note.** Codex marked its scope check false only because the literal commit range also
spans two gate files from other sessions' merged pull requests; neither belongs to this work.

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
- Correction 2 sources (2026-09-29): operator-run live test on `claude --version` 2.1.284 (probe hook logs, model `claude-sonnet-5-5`); `code.claude.com/docs/en/settings.md` ("When edits take effect"), `.../settings-reference.md` (`effortLevel`, `modelSettings`), `.../model-config.md` (effort resolution order); `gh issue view` on anthropics/claude-code#43326 (open, comments) and #60200 (closed, stale, locked); the auto-effort project README's own "Cost & limitations" section (n=1 on 2.1.177)
- Scope-fix sources (2026-09-29): source code read via `gh api` in `rezzminator/agent-effort` (`plugins/agent-effort/hooks/agent-effort.ts`, `src/effort.ts`, `types/claude-code.d.ts` `TurnStepInput`), `tzachbon/claude-model-router-hook`, `moukrea/automodel`, `handpickedlab/effort-router`, `blackreo123/claude-code-auto-effort`, `hodkovickybuh/claude-auto-model` (README, native-integration and controller sections); anthropics/claude-code#91870
- Function-hooks thread (2026-09-29): anthropics/claude-code#91870, all 224 comments searched (frsorrentino 2026-09-04, jdainsworthsnb 2026-09-05, Butanium 2026-09-15, Marat 2026-09-15), maintainer update 2026-09-09; built-in mods listing at `anthropics/claude-code/mods` (agents-md, diff, sec-default, telemetry, none about effort routing)
- Correction 4 sources (2026-09-29): platform.claude.com prompt-caching and effort docs; code.claude.com llm-gateway, llm-gateway-protocol, legal-and-compliance, model-config, env-vars; anthropics/claude-code `mods/README.md`; the `plugin-authoring` bundle `reference.md` and `types/claude-code.d.ts` (HookBudget, turn.step); dotfiles `claude/bin/claude-shim` and `hooks/effort-signal-report.sh`; `mh:cost-report` output (2026-09-29)
- Correction 5 sources (2026-09-29): operator-run tests on CC 2.1.284 (probe session transcript usage rows; scratch-project top-level `effortLevel` test with `effort-log` rows and transcript effort; background-agent and `/compact` test with `effort-log` rows and tool results); dotfiles `claude/mods/effort-log`
- Correction 3 sources (2026-09-29): operator-run probe session, transcript of the session whose id starts `87a15847` (usage rows and per-message effort); the `plugin-authoring` bundle `types/claude-code.d.ts` (`TurnStepInput`)
- Correction 6 sources (2026-09-29): `mh:deep-audit` checkers (Opus agent; Codex `gpt-6-sol`, effort medium, read-only) run against this doc as it stood before this correction (sha256 prefix `0282eaf626bf`); transcript sessions `87a15847` and `3da5bc7c`; dotfiles commit `b21d0d9f`
