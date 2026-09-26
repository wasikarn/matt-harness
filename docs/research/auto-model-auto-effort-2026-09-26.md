# Automatic model and effort mechanisms, seen from the mh plugin (2026-09-26)

Question: in Claude Code 2.1.283 (`claude --version`), which automatic model or effort mechanisms
other than the `opusplan` alias affect mh **as a plugin** (its 10 agents, 12 `SKILL.md` files, the hooks in
`hooks/hooks.json`, model-bench, and the Codex pairing), and what can a plugin do about them?

Companion docs (user-config side, already verified; this note builds on them and doesn't redo
them): wasikarn/dotfiles `docs/research/auto-model-auto-effort-2026-09-26.md` (40-row mechanism
table) and wasikarn/dotfiles `docs/research/frontmatter-model-effort-2026-09-26.md` (26
frontmatter rules, probes P1-P3). Also this repo's
`docs/research/claude-code-codex-models-efforts-2026-09-07.md`, addendum 2026-09-26.

Method: raw-markdown doc snapshots fetched 2026-09-26 (line numbers below refer to those
snapshots), the local changelog (version = nearest `## x.y.z` header above the line), `strings`
of the 2.1.283 binary where the docs are silent (marked "binary-inferred"), a read of every mh
agent, skill, hook and the model-bench scripts, and, for Codex, `codex` 0.156.1 plus
`learn.chatgpt.com`. No paid `claude -p` or `claude plugin eval` run was made for this note; open
questions are listed as `NEEDS-PROBE`.

## Short answer

- **mh has no automatic model or effort mechanism of its own, and it pins everything.** All 10
  agents carry `model:` (5 `opus`, 5 `sonnet`) and `effort:` (8 `high`, 2 `xhigh`); all 12
  `SKILL.md` files (10 shipped by the manifest; `idea-audit` and `ste-lint` aren't listed) carry
  `model: inherit` plus `effort:`. While an mh surface is active, its `effort:` overrides the
  session level, so `modelSettings` and the dotfiles `claude-shim` bump don't reach it, and per
  the docs neither do `--effort` or `/effort` (that last part is not probed) [1:647][2:315][3:364].
- **What still moves mh at runtime is all outside plugin control:** family-alias resolution (the
  `opus` agents run the main session's exact Opus, including after a content fallback), the
  subagent fallback chain, `availableModels` substitution, `CLAUDE_CODE_EFFORT_LEVEL` (beats every
  `effort:` pin), `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` (erases every `model:` pin), `maxEffortLevel`
  and org caps, workflow stage models, and advisor inheritance [1][2][8][12].
- **A plugin can't ship model or effort settings.** A plugin `settings.json` (or the manifest
  `settings` key) honours only `agent` and `subagentStatusLine`; every other key, including
  `switchModelsOnFlag`, `modelSettings`, `effortLevel`, `maxEffortLevel` and `env`, is dropped at
  load [5:184][6:891]. The plugin's levers are frontmatter, hooks, and the Agent tool's `model`
  parameter, which accepts only `sonnet|opus|haiku|fable` and has no effort field
  (binary-inferred [15]).
- **No mh hook reads the model or the effort.** No `PreModelSwitch`/`PostModelSwitch` hook, no
  read of the hook `effort` field or `$CLAUDE_EFFORT`, and `gate:agent:subagent-spawn-guard` keys
  only on `agent_id`, never on `tool_input.model` [21].
- **model-bench:** eval children load no user settings, only managed ones; `claude plugin eval`
  has no `--effort` option, so effort reaches the child only through `CLAUDE_CODE_EFFORT_LEVEL`
  [7:491-498, 549]. Two claims in `skills/meta/model-bench/SKILL.md` contradict the docs (see
  Drift).
- **Codex has no automatic model router.** The only automatic behaviour is `ultra` effort
  delegating to subagents, Plan mode's built-in effort preset, multi-agent spawn defaults, and
  migration or rate-limit prompts that ask rather than switch [17][18][19].

## Mechanisms

M/E = model or effort. "What mh can do" is limited to what a plugin can ship (see the next
section). Effort rows first, then model rows, then plugin-surface rows.

| Mechanism | M/E | Effect on mh | What mh can do about it | Source |
|---|---|---|---|---|
| Frontmatter `effort:` (agents, skills) | E | All 10 agents and 12 `SKILL.md` files pin it. While active it overrides the session level (`--effort`, `/effort`, `modelSettings`, `effortLevel`, model default). Plugin agents have honoured it since 2.1.78, skills since 2.1.80; fixed for pinned-default models in 2.1.267 | Owns it. Tiers per the authoring conventions; check 54 enforces presence | [1:635-647]; [2:315]; [3:364]; [14] 2.1.78, 2.1.80, 2.1.267 |
| `CLAUDE_CODE_EFFORT_LEVEL` (incl. `auto`) | E | Outranks every mh `effort:` pin, agents and skills alike; `auto` sends every surface to its model default. Also reaches `claude plugin eval` children through the `CLAUDE_CODE_*` allowlist, which is how model-bench's `@effort` arms work | Can't block. Can detect (hook env, model-bench `arm-meta.txt`) | [1:568, 647]; [7:549]; `skills/meta/model-bench/scripts/model-bench.sh:117` |
| `--effort`, `/effort` (incl. `max`) | E | Session level. Doc-implied to lose to mh frontmatter while an mh surface is active (not probed). Reaches agents **without** `effort:` (P3): the `general-purpose` fallback lanes in `compliance-audit`/`idea-audit`, Explore, `codex:codex-rescue`. So `/effort max` doesn't reach any mh surface | Nothing to ship; fix the docs that say "bump with `/effort max`" (Drift) | [1:568, 581, 647]; [16] P3 |
| Unpinned-subagent effort | E | A subagent without `effort:` takes an explicit session choice, else **its own model's** `modelSettings` entry, not the parent's resolved level. Affects mh's `general-purpose` dispatches, not its own agents | Agent tool has no effort parameter; if a lane needs a tier, dispatch a pinned mh agent | [16] P1-P3; [15] |
| `maxEffortLevel`, org effort caps | E (cap) | Clamp the `xhigh` surfaces (`plan-reviewer`, `blind-spot-hunter`, `deep-audit`, `compliance-audit`, `idea-audit`). Managed caps also apply inside eval runs | Can't control | [1:428, 647]; [9] `maxEffortLevel`; [7:498] |
| Unsupported-level step-down | E | None today (every current model supports `xhigh`). If a pin lands on a 4.6 model (allowlist substitution, a user's `ANTHROPIC_DEFAULT_*_MODEL`), `xhigh` runs as `high`. The subagent status line reports the configured value, not the applied one | Nothing | [1:556-566]; [10:1103] |
| `ultracode` (setting, `/effort`, `--effort`) | E + orchestration | Session sends `xhigh`; how it ranks against frontmatter `effort:` is undocumented. Claude plans workflows whose stage models outrank mh `model:` pins (next rows) | Nothing | [1:589-607]; [8:146-164, 423] |
| Thinking on/off inheritance | E (model-side) | Subagents inherit the main session's thinking setting (2.1.198); no per-subagent field. A Sonnet 5 main with thinking off runs the 5 sonnet agents without thinking | Nothing | [2:389]; [1:653-661] |
| Hook `effort` input, `$CLAUDE_EFFORT` | E (observable) | Present on PreToolUse/PostToolUse/Stop/SubagentStop when the model supports effort; ultracode reports as `xhigh`. No mh hook reads either | Could add effort to cost-tracker rows; no need found | [4:758]; [3:427] |
| Subagent model order | M | Per-invocation `model` > frontmatter > `CLAUDE_CODE_SUBAGENT_MODEL` > main model (since 2.1.251). All 10 mh agents pin, so the env default never reaches them | Keep pins | [2:358-363, 374]; [14] 2.1.251 |
| Family-alias resolution | M | `model: opus`/`sonnet` (frontmatter or per-invocation) runs the main session's **exact** model when the main is in that family. The 5 opus agents therefore run Opus 5.5 in `opusplan` plan mode, and Opus 4.8/5 after a content fallback; a verifier gets no model independence from an Opus main | A full model ID pin would escape it (doc-inferred: the rule names aliases), but it stops alias auto-upgrades. Not recommended; document the limit | [2:365-367] |
| `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` | M | Ignores every mh `model:` pin and the Agent `model` parameter; with `CLAUDE_CODE_SUBAGENT_MODEL` set all subagents run that model, else the main model. Precedent: the 2026-09-07 stray-FORCE incident. Probably passes into eval children ("most `CLAUDE_CODE_*`") | Detect only | [2:393-414]; [7:549]; [14] 2.1.257; this repo's 09-07 research |
| Agent tool `model` parameter | M (per task) | Enum `sonnet`, `opus`, `haiku`, `fable`; no full IDs, no `effort`; outranks frontmatter; a same-family alias resolves to the main model. No mh gate reads it | A PreToolUse:Agent hook could deny `fable` or rewrite via `updatedInput`; no incident justifies it | [4:1751-1761, 1814]; [15]; `hooks/gates/subagent-spawn-guard.py` |
| Workflow stage models | M | A stage model counts as the per-invocation model, so it outranks mh pins when a workflow (including ultracode's) runs an mh agent type. mh ships no `workflows/` | Nothing | [8:423]; [5] path fields |
| Content-based fallback | M (sticky, main) | A flagged Opus 5.5/Fable request re-runs on Opus 5 or 4.8 and the main session stays there, so the opus agents follow (family alias). `switchModelsOnFlag` is user/managed only; what a flag does inside a subagent is undocumented. Eval runs default to switching unless a managed setting says otherwise | Nothing to block it. `hooks/stop/cost-tracker.sh` already logs one row per (model, `agent_type`), so it records what actually ran | [1:502-536]; [4:3271-3310]; [9:1331]; `cost-tracker.sh:129` |
| Fallback chain for subagents | M | On overload a subagent "continues on the model that accepts the request" from the user's `fallbackModel` chain (2.1.247+); session unchanged; no `PostModelSwitch`. An opus agent can finish on Sonnet. PostToolUse `modelsUsed` shows the swap (2.1.212+) | Observe only | [1:500]; [4:1770-1781, 3282] |
| `availableModels` substitution | M (admin) | A blocked `opus`/`sonnet` alias runs the newest permitted version of that family (2.1.222+), else the inherited model; also covers the Agent parameter and stage models | Nothing | [2:378-383]; [8:430]; [14] 2.1.222 |
| Advisor inheritance | M (Claude-timed) | mh agents inherit the user's advisor, checked against the agent's own model. A Fable advisor can bill usage credits from inside mh agents; no frontmatter field opts out | Nothing | [12:105] |
| Skill `model:` | M (turn) | All 12 mh skills use `inherit`, so none switches the turn model | Keep; check 54 WARNs on a concrete pin | [3:363] |
| Built-ins mh uses (Explore, `general-purpose`, fork) | M | Explore inherits the main model, capped at Opus; `general-purpose` unpinned follows the model order; a fork always runs the main model and ignores `model` | Nothing | [2] built-in subagents; [15] |
| Model-gated Task tools | tool set | `TaskCreate`/`TaskUpdate` exist by default only on Opus ≤ 4.7, Sonnet ≤ 4.6, Haiku 4.5, and in background/cloud sessions. On Opus 4.8+/Sonnet 5/Fable, `gate:task:complete-separation` (PreToolUse `TaskUpdate`) has nothing to match outside background/cloud sessions unless the tools are opted in (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, which the operator sets, or naming them in `--allowedTools`/`--tools`) | Document the dependency (Drift) | [11:526-539]; [13] `CLAUDE_CODE_ENABLE_TODO_TOOLS`; `hooks/hooks.json` |
| `claude plugin eval` (model-bench) | M + E | Child is a `claude -p` with a temp home: no user settings (no `modelSettings`, `switchModelsOnFlag`, `fallbackModel`, advisor); managed settings apply. `--model` sets the main model; there is no `--effort` option. A Fable arm bills usage credits without asking in `-p` | Already sets effort through the env var; record the env in `arm-meta.txt` (Worth adopting) | [7:373, 491-498, 549]; `claude plugin eval --help`; [1:112] |
| `PreModelSwitch` / `PostModelSwitch` hooks | M (block / observe) | mh ships neither. PreModelSwitch sees only user or client switches, never fallback or `opusplan`; PostModelSwitch sees the `opusplan` boundary, content fallback and resume, not the chain | Nothing needed: the dotfiles `advisor-pairing-signal.sh` already covers the user side. Harness-audit check 22 lacks `PreModelSwitch` in `DOC_EVENTS` (its header says so), so shipping one would WARN | [4:3116-3128, 3271-3320]; check 22 header |
| Plugin `settings.json` `agent` key | M (main thread) | The only main-session model lever a plugin has: run the main thread as a plugin agent, taking its model. Lowest settings layer; mh ships none | Keep unused | [6:889-908]; [9:4894] |
| Plugin `subagentStatusLine` | observe | A plugin may ship a default. The payload has each subagent's resolved `model` and configured `effort` (absent when inherited), which would surface a FORCE override or a fallback. The user's own wins | Optional; not needed now | [10:1099-1107]; [14] 2.1.214 |

## What a plugin can't control

- **Settings keys.** Only `agent` and `subagentStatusLine` survive from a plugin `settings.json`
  or the manifest `settings` key; everything else is dropped at load [5:184][6:891]. So mh can't
  set `model`, `modelSettings`, `effortLevel`, `maxEffortLevel`, `ultracode`,
  `switchModelsOnFlag`, `fallbackModel`, `advisorModel`, `availableModels*`,
  `alwaysThinkingEnabled`, `fastMode`, or `env` (so no `CLAUDE_CODE_EFFORT_LEVEL`,
  `CLAUDE_CODE_SUBAGENT_MODEL(_FORCE)` or `CLAUDE_CODE_ENABLE_TODO_TOOLS` either). Plugin
  settings have been a thing since 2.1.49 [14].
- **Env vars through a hook.** A SessionStart hook's `CLAUDE_ENV_FILE` exports reach later Bash
  commands [4:1224], not Claude Code's own model or effort resolution (inferred: the docs scope it
  to Bash).
- **Automatic switches.** Content fallback, the fallback chain, allowlist substitution and alias
  auto-advance happen without a PreModelSwitch event [4:3128]; PostModelSwitch can only annotate
  [4:3275].
- **Per-agent knobs that don't exist.** No per-subagent thinking [2:389], no advisor field, no
  effort on the Agent tool, and the Agent `model` accepts aliases only [15]. Plugin agents also
  ignore `permissionMode`, `hooks`, `mcpServers` and `initialPrompt` [6:739].
- **Eval environment.** User settings never load in eval runs; managed settings always do
  [7:497-498].

What a plugin **can** do: agent and skill `model:`/`effort:` frontmatter [6:738], a command's
`model` in the manifest `commands` map [5:214], PreToolUse hooks that deny or rewrite the Agent
`model` [4:1814], PreModelSwitch hooks that block user-requested switches [4:3116],
PostModelSwitch hooks that add context [4:3314], reading the hook `effort` field [4:758], and the
two settings keys above.

## Codex CLI

Checked on `codex-cli` 0.156.1; catalog from `codex debug models` (cache `fetched_at`
2026-09-26T07:54Z) [17].

- **No automatic model selection.** The model comes from `-m/--model`, `-c model=`, a profile, or
  `config.toml` `model` (documented as "Model to use"), else the bundled default [17][19]. `codex
  --help` has no auto-model flag. The "Power presets" on the models page (Luna High, Sol Light,
  and so on) are a composer control in the app, not a CLI router [18].
- **Automatic behaviour that does exist:**
  - `ultra` effort "uses subagents to accelerate complex work" [18]; catalog text: "Maximum
    reasoning with automatic task delegation" [17]. The `codex@openai-codex` 1.0.6 plugin rejects
    it (`VALID_REASONING_EFFORTS` = `none|minimal|low|medium|high|xhigh`) [20], and mh's policy
    never picks it on bare `codex exec`.
  - Plan mode: `plan_mode_reasoning_effort` — "When unset, Plan mode uses its built-in preset
    default" [19]. mh dispatches through `codex exec` and the plugin's task path, not Plan mode
    (inferred), so this doesn't reach mh.
  - Multi-agent: `features.multi_agent` is on by default, and spawned agents use
    `agents.default_subagent_model` / `agents.default_subagent_reasoning_effort` unless the spawn
    sets one [19]. The catalog also carries `multi_agent_reasoning_effort: xhigh` for Astra and
    Sol, meaning undocumented [17]. So a lane mh sends at Sol/medium may spawn helpers at other
    settings (inferred).
  - Migrations and nudges ask rather than switch: `gpt-5.5` carries `upgrade` → `gpt-5.6-sol`
    and retires 2026-10-14 [17]; `notice.model_migrations` tracks acknowledged migrations and
    `notice.hide_rate_limit_model_nudge` is a "rate limit model switch reminder" [19].
  - `--approve-for-me` / `approvals_reviewer = "auto_review"` routes approval prompts to a
    reviewer subagent [17][19]; the catalog lists a hidden `codex-auto-review` model (link between
    them inferred). mh doesn't use it.
- **Docs now match the binary on effort values.** The config reference lists
  `model_reasoning_effort` as "low, medium, high, xhigh, max, or ultra … depend on the model and
  client" [19], which settles the 2026-09-07 note's doc-versus-catalog disagreement (no
  `minimal`). No model in the 0.156.1 catalog lists `none` or `minimal`, although the plugin
  accepts both [17][20].
- **Claude-side wrapper.** `codex:codex-rescue` is `model: sonnet` with no `effort:`, so the
  Claude subagent that relays the rescue runs Sonnet 5 at its own `modelSettings` entry or an
  explicit session effort (P1-P3). That is separate from the Codex effort passed with `--effort`.
- **Starting efforts differ from OpenAI's.** The models page says "Start with Medium for Sol, High
  for Luna, or Light for Astra" (Light = `low`) [18]. The routing table in
  `docs/reference/codex-integration-map.md` starts Luna at `low` and Astra at `medium`: a
  deliberate policy, but the map doesn't say it departs from the vendor default.

## Drift (reported, not fixed)

Model and effort claims in the seven reference files, checked against the sources below.
`CLAUDE.md` and `docs/METHODOLOGY.md` make no model or effort claims (METHODOLOGY's "effort" at
L38 is the human sense). Line numbers are from the working tree on 2026-09-26.

| File:line | Verdict | Problem |
|---|---|---|
| `docs/reference/agent-authoring-conventions.md:31-34` | stale | Calls the rank against `CLAUDE_CODE_EFFORT_LEVEL` "undocumented"; [1:647] says frontmatter overrides the session level "but not the environment variable". The `--effort` rank is doc-implied ([1:568]), not probed |
| `docs/reference/agent-authoring-conventions.md:39-40` | overstated | "usage credits on subscriptions": Fable "can bill" credits "depending on your plan and seat tier", and `-p`/eval runs bill without asking [1:95, 112] |
| `docs/reference/agent-authoring-conventions.md:42-44` | missing | A different-model pin gives no independence when the main is in the same family: `model: opus` runs the main's exact Opus [2:365-367] |
| `docs/reference/skill-authoring-conventions.md:53-55` | wrong | "Bump per session with `/effort max`": a session level doesn't reach a surface that pins `effort:`; only `CLAUDE_CODE_EFFORT_LEVEL=max` does [1:581, 647]. Solid for agents; for an inline skill it holds while the skill is active, and when that ends is unverified. Sibling: check 54's WARN text (L38) |
| `docs/reference/spawn-brief.md:45-46` | missing | `none`/`minimal` pass the plugin but no model in the 0.156.1 catalog lists them [17][20] |
| `docs/reference/spawn-brief.md:57-60` | missing | The independence override can't work from an Opus main for an opus-pinned verifier: the parameter takes aliases only and a same-family alias resolves to the main model [15][2:365-367] |
| `docs/reference/spawn-brief.md:62-63` | overstated | "effort only comes from the agent's own frontmatter tier": the env var outranks it, caps clamp it, and unpinned agents follow P1-P3 [1:647][16] |
| `docs/reference/codex-integration-map.md:55-110` | missing | No statement on whether Codex picks model or effort automatically (see Codex section) [18][19] |
| `docs/reference/codex-integration-map.md:63-73` | stale | The GPT-6 slugs are now in this account's catalog (0.156.1), not only in the public docs [17] |
| `docs/reference/codex-integration-map.md:75-80` | missing | Departs from OpenAI's starting efforts without saying so [18] |
| `docs/reference/env-vars.md:16-23` | missing | Omits `CLAUDE_CODE_EFFORT_LEVEL` (set by `model-bench.sh:117`, reaches eval children [7:549]) and `CLAUDE_CODE_ENABLE_TODO_TOOLS` (needed for `gate:task:complete-separation` on current models [11:526-532]) |
| `skills/meta/model-bench/SKILL.md:65-68` (outside the seven) | wrong | Says agent `effort:` overrides the arm's `CLAUDE_CODE_EFFORT_LEVEL`; [1:647] says the reverse. Same defect as the first row |
| `skills/meta/model-bench/SKILL.md:24`, `model-bench-diff.py:172` (outside the seven) | overstated | "regardless of `--model`": a same-family arm moves the pinned agents [2:365-367] |
| `skills/meta/harness-audit/scripts/checks/21-*.sh:4-5` (outside the seven) | stale | "model is optional (defaults to inherit)": an omitted `model` follows the subagent model order, so `CLAUDE_CODE_SUBAGENT_MODEL` applies to it but not to an explicit `inherit` [2:306, 358-363] |

## Worth adopting (max 3)

1. **Fix the effort-rank statements** (Drift rows for `agent-authoring-conventions.md:31-34`,
   `skill-authoring-conventions.md:53-55`, check 54's WARN text, and model-bench `SKILL.md:65-68`).
   They say frontmatter beats the env var, or that `/effort max` reaches a pinned surface; the docs
   say the opposite. Cost: prose edits only.
2. **Record the override env in model-bench's `arm-meta.txt`.** One `env | grep -E
   '^(CLAUDE_CODE_(EFFORT_LEVEL|SUBAGENT_MODEL(_FORCE)?)|ANTHROPIC_(MODEL|DEFAULT_[A-Z]+_MODEL))='`
   line in `run_arm`. A stray `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` or effort var in the invoking
   shell would otherwise rewrite an arm with no trace. Same pass: replace the "regardless of
   `--model`" caveat with the family-alias fact.
3. **Document the Task-tool dependency** of `gate:task:complete-separation` in
   `docs/reference/env-vars.md` (`CLAUDE_CODE_ENABLE_TODO_TOOLS`), so a user on Opus 4.8+/Sonnet
   5/Fable knows the gate is inert without it.

Considered and not recommended: an mh `PostModelSwitch` hook (duplicates the dotfiles sensor), a
PreToolUse:Agent `model` gate (no incident), a plugin `subagentStatusLine` (the user's own wins;
nice-to-have), full-ID agent pins to escape family-alias resolution (they block alias upgrades;
the Codex lane already gives model independence).

## Unverified

- `NEEDS-PROBE CLAUDE_CODE_EFFORT_LEVEL=low claude plugin eval . --model sonnet --case <case that dispatches an mh agent> --keep-temp --ablation none --threshold 0` → read the subagent's assistant-turn `effort` in the kept child transcript. Settles whether the env var beats agent `effort:` inside an eval child (docs: yes; model-bench `SKILL.md:65-68`: no).
- `NEEDS-PROBE claude plugin eval . --model claude-opus-5 --case <case that dispatches an opus-pinned mh agent> --keep-temp --ablation none --threshold 0` → subagent assistant-turn `model`. Settles family-alias resolution inside an eval child (expect `claude-opus-5`).
- `NEEDS-PROBE CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 claude plugin eval . --model sonnet --case <opus-agent case> --keep-temp --ablation none --threshold 0` → subagent model. Settles whether `_FORCE` passes the eval env allowlist ("most `CLAUDE_CODE_*`").
- `NEEDS-PROBE claude -p --model sonnet --effort low` with a prompt that dispatches `mh:code-architect` (opus, `effort: high`) and has it echo `$CLAUDE_EFFORT` → expect `high`. Settles frontmatter versus `--effort` (doc-implied, not covered by P1-P3).
- `NEEDS-PROBE claude -p --model sonnet` running an inline skill with `effort: xhigh` that dispatches `general-purpose` with `model: "opus"` echoing `$CLAUDE_EFFORT` → `xhigh` means an active skill's effort propagates like an explicit session choice; `medium` means the subagent used its own model's entry. Affects the `idea-audit`/`compliance-audit` fallback lanes.
- What a safety-classifier flag does inside a subagent, under either `switchModelsOnFlag` value.
- How `ultracode` ranks against frontmatter `effort:`, and whether a workflow stage can set effort.
- Whether the plugin `agent` setting also applies the agent's `effort:` to the main session.
- Codex: the bundled default model on 0.156.1 (0.153.4 made Astra the default; not rechecked), and
  what `supports_reasoning_effort_updates` and `multi_agent_reasoning_effort` do.
- Binary-only: the Agent tool's `model` enum and missing `effort` field [15]. Its description also
  carries a conditional "Set this only when EXPLICITLY asked by the user" text behind a gate whose
  trigger wasn't identified, plus an undocumented `CLAUDE_CODE_COORDINATOR_FORCE_WORKER_INHERIT_MODEL`
  (0 hits in env-vars.md [13]). Neither is claimed to apply to normal sessions.

## Sources

All checked 2026-09-26. Doc pages fetched as raw markdown (`curl -sL <url>.md`); `[n:line]`
cites that snapshot's line.

1. https://code.claude.com/docs/en/model-config — effort levels and resolution order (556-647),
   non-interactive effort and ultracode (581-607), org effort limits (428), fallback chains incl.
   subagents (471-500), automatic model fallback and Ask before switching (502-536), Fable usage
   credits (93-112), adaptive reasoning (653-661).
2. https://code.claude.com/docs/en/sub-agents — plugin subagent field limits (236-240),
   frontmatter `model`/`effort` (306, 315), Choose a model (358-387), thinking inheritance (389),
   Run every subagent on one model (391-414).
3. https://code.claude.com/docs/en/skills — frontmatter `model`/`effort` (363-364),
   `${CLAUDE_EFFORT}` (427).
4. https://code.claude.com/docs/en/hooks — common input `effort` and no `$CLAUDE_MODEL` (758-770),
   `CLAUDE_ENV_FILE` (1224), Agent tool input and PostToolUse `resolvedModel`/`modelsUsed`
   (1751-1781), `updatedInput` (1814), PreModelSwitch (3116-3128), PostModelSwitch (3271-3320).
5. https://code.claude.com/docs/en/plugins-reference — `settings` key (134, 184), commands `model`
   (214), path fields incl. `workflows`.
6. https://code.claude.com/docs/en/plugins/components — plugin agent supported/ignored fields
   (738-740), Default settings (889-911).
7. https://code.claude.com/docs/en/plugin-evals — `--model` (373), How runs are isolated
   (491-498), prompt.md `env` allowlist (549).
8. https://code.claude.com/docs/en/workflows — ultracode (146-164), stage models and allowlist
   (423-430), distributing workflows in a plugin (222-226).
9. https://code.claude.com/docs/en/settings-reference — `maxEffortLevel` (1055),
   `switchModelsOnFlag` (1331), `agent` (4894).
10. https://code.claude.com/docs/en/statusline — Subagent status lines (1086-1107).
11. https://code.claude.com/docs/en/tools-reference — Task tool availability (526-539),
    `SubagentHandback` (53).
12. https://code.claude.com/docs/en/advisor — subagent inheritance and pairing check (105).
13. https://code.claude.com/docs/en/env-vars — `CLAUDE_CODE_ENABLE_TODO_TOOLS` (284),
    `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (311).
14. `~/.claude/cache/changelog.md`: 2.1.49 (plugin `settings.json`), 2.1.78, 2.1.80, 2.1.214
    (`subagentStatusLine` effort), 2.1.222 (family-alias allowlist fix), 2.1.243, 2.1.251
    (`CLAUDE_CODE_SUBAGENT_MODEL` default-only; Pre/PostModelSwitch), 2.1.257 (`_FORCE`), 2.1.267,
    2.1.269 (`claude plugin eval`).
15. Binary-inferred: `strings -n 8 ~/.local/share/claude/versions/2.1.283`. The Agent tool input
    schema: `description`, `prompt`, `subagent_type`,
    `model:G(["sonnet","opus","haiku","fable"])` ("Optional model override for this agent. Takes
    precedence over the agent definition's model frontmatter … Ignored for subagent_type:
    "fork""), `run_in_background`, then `name`, `team_name`, `mode`, `isolation`, `cwd`; no
    `effort`. Grep for the literal "Optional model override for this agent".
16. Live probes P1-P3 (orchestrator, 2026-09-26, `claude -p --model sonnet`): P1 main `high`,
    opus subagent without `effort` `medium`; P2 with `--settings` `claude-opus-5-5: low` →
    subagent `low`; P3 `--effort low` → main and subagent `low`. Recorded in wasikarn/dotfiles
    `docs/research/frontmatter-model-effort-2026-09-26.md`.
17. `codex --version` (0.156.1), `codex --help` (`-m`, `-p`, `--approve-for-me`), `codex exec
    --help`, `codex debug models` (`supported_reasoning_levels`, `default_reasoning_level`,
    `multi_agent_reasoning_effort`, `supports_reasoning_effort_updates`, `upgrade`; hidden
    `gpt-reserve`, `codex-auto-review`).
18. https://learn.chatgpt.com/docs/models?surface=cli — choosing a model and effort, Ultra mode,
    "Start with Medium for Sol, High for Luna, or Light for Astra", Power presets, retirements.
19. https://learn.chatgpt.com/docs/config-file/config-reference — `model`,
    `model_reasoning_effort`, `plan_mode_reasoning_effort`, `agents.default_subagent_model`,
    `agents.default_subagent_reasoning_effort`, `features.multi_agent`, `approvals_reviewer`,
    `notice.model_migrations`, `notice.hide_rate_limit_model_nudge`.
20. `~/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs`:
    `VALID_REASONING_EFFORTS` (L71), `review` options without `effort` (L714), `task` options with
    `model` and `effort` (L764); `agents/codex-rescue.md` `model: sonnet`, no `effort`.
21. This repo at 1.1.131 (working tree): `agents/*.md`, every `skills/**/SKILL.md`,
    `hooks/hooks.json`, `hooks/gates/subagent-spawn-guard.py`, `hooks/stop/cost-tracker.sh`,
    `skills/meta/model-bench/` (SKILL.md, `model-bench.sh`, `model-bench-diff.py`), and
    harness-audit checks 21, 22, 54. `git grep` for `CLAUDE_EFFORT`, `SUBAGENT_MODEL`,
    `PostModelSwitch`, `modelSettings`, `availableModels` outside the frozen dirs.
22. wasikarn/dotfiles `docs/research/auto-model-auto-effort-2026-09-26.md` and
    `docs/research/frontmatter-model-effort-2026-09-26.md` (user-config side).
