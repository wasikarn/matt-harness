# Claude Code and Codex CLI: models and effort levels (2026-09-07)

Question: what models and effort/reasoning levels do Claude Code and OpenAI Codex CLI expose as of 2026-09-07, and how are they selected?

Installed binaries checked: `claude` 2.1.263, `codex-cli` 0.153.4 (`claude --version`, `codex --version`) [10][11].

## Summary

- Claude Code current lineup: Fable 5.1 (`claude-fable-5-1`, default `fable`), Opus 5, Sonnet 5, Haiku 4.5; legacy Fable 5, Opus 4.8/4.7/4.6/4.5, Sonnet 4.6/4.5 still available [1][2].
- Claude effort levels: `low | medium | high | xhigh | max`; default `high` everywhere except Opus 4.7 (`xhigh`). `xhigh` needs Fable 5.x, Opus 5/4.8/4.7, or Sonnet 5; Opus 4.6/Sonnet 4.6 stop at `max` without `xhigh`; Haiku has no effort [1][3]. `ultracode` is a Claude Code mode (= `xhigh` + dynamic workflows), not an API level [1].
- Claude model selection precedence: `/model` (session, `s` = session-only) > `--model` > `ANTHROPIC_MODEL` > settings `model` > `ANTHROPIC_DEFAULT_MODEL` > account default (Opus 5 on Max/Team Premium/Enterprise/API, Sonnet 5 on Pro/Team Standard) [1]. Effort: `CLAUDE_CODE_EFFORT_LEVEL` > `--effort` > `/effort` > `modelSettings.<model>.effortLevel` > `effortLevel` > model default [1]. Inside a subagent, the agent file's `effort:` frontmatter overrides the session effort level; `/tasks` shows the effective model and effort per subagent (CC >= 2.1.242) [17].
- Fable 5.x, Opus 5, Sonnet 5 are natively 1M context on the Anthropic API; `[1m]` suffix applies to Opus 4.7+ and Sonnet 4.6, and to `sonnet[1m]`/`opus[1m]` for Sonnet 5/Opus 5 on gateways (usage credits on Pro and for Sonnet 4.6 on every subscription) [1][2]. Fable needs usage credits off Enterprise [1].
- Codex CLI catalog as served to the installed 0.153.4 binary: `gpt-6-astra` (bundled default since 0.153.4), `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`, `gpt-5.4-mini` (retiring 2026-08-31, upgrade path Luna), plus hidden `gpt-reserve` and `codex-auto-review`; every model reports a 272,000-token context window [12][13].
- Codex reasoning levels in the live catalog: `low | medium | high | xhigh | max` (+ `ultra` on Astra, Sol, Terra); defaults `low` for Astra/Sol, `medium` for the rest [12]. The config reference still documents `model_reasoning_effort = minimal | low | medium | high | xhigh` and "xhigh is model-dependent" — docs and binary disagree on `minimal`, `max`, `ultra` [5][12].
- Codex selection: `codex -m/--model <slug>`, `-c model="..."`, `config.toml` `model` / `model_reasoning_effort` (also per `[profiles.<name>]`, `-p <profile>`), or the TUI `/model` picker [5][11][16].
- Plan gating on Codex: Astra and Sol need ChatGPT Plus/Pro, Business, Enterprise or API key; Terra/Luna on all plans; `gpt-5.3-codex-spark` is Pro-only and does not appear in this account's catalog [6][12].

## Claude Code

Aliases and how they resolve (Anthropic API) [1][2]:

| Model | id / alias | Context | Effort levels | How to select | Source |
|---|---|---|---|---|---|
| Claude Fable 5.1 | `claude-fable-5-1`; alias `fable`, `best` (where available); needs CC >= 2.1.255 | 1M native, 128K out | low, medium, high, xhigh, max; default high; adaptive thinking always on | `/model fable`, `--model fable`, `ANTHROPIC_DEFAULT_FABLE_MODEL` | [1][2][3][4] |
| Claude Fable 5 (legacy) | `claude-fable-5`; `fable` before 2.1.255 | 1M native | low..max incl. xhigh | same as above with explicit id | [1][3] |
| Claude Opus 5 | `claude-opus-5`; alias `opus`, `best` fallback; CC >= 2.1.219 | 1M native; auto-compact 200K unless 1M | low..max incl. xhigh; default high; fast mode supported (`/fast`, $10/$50) | `/model opus`, `opus[1m]` for gateways, `ANTHROPIC_DEFAULT_OPUS_MODEL` | [1][2][3][7] |
| Claude Sonnet 5 | `claude-sonnet-5`; alias `sonnet`; CC >= 2.1.197 | 1M on Anthropic API; `sonnet[1m]` on gateways | low..max incl. xhigh; default high | `/model sonnet`, `ANTHROPIC_DEFAULT_SONNET_MODEL` | [1][2][3] |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001`; alias `haiku` | 200K, 64K out | none (effort not supported); extended thinking | `/model haiku`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL=haiku` | [1][2] |
| Opus 4.8 / 4.7 (legacy) | `claude-opus-4-8`, `claude-opus-4-7` | 200K; `[1m]` suffix or auto-upgrade on Max/Team/Enterprise | low..max incl. xhigh; 4.7 default xhigh; 4.8 fast mode yes, 4.7 fast mode removed 2026-07-24 | `/model claude-opus-4-8[1m]` | [1][3][7] |
| Opus 4.6 / Sonnet 4.6 (legacy) | `claude-opus-4-6`, `claude-sonnet-4-6` | 200K; `sonnet[1m]` needs usage credits on every subscription | low, medium, high, max (no xhigh); default high | `/model sonnet[1m]` | [1][3] |
| `opusplan` | hybrid alias | `opusplan[1m]` variant | inherits per-model | Opus in plan mode, Sonnet for execution; `/model opusplan` | [1] |
| `default` | alias | — | — | clears override; org default > `ANTHROPIC_DEFAULT_MODEL` > account default | [1] |

Selection mechanics [1][8][9]:

- `/model <alias|id>` switches and saves as user default; bare `/model` opens the picker (Enter saves, `s` session-only). `claude --model` for one session. `ANTHROPIC_MODEL` is session-only; `ANTHROPIC_DEFAULT_MODEL` (>= 2.1.236) sets the default for new sessions. `--help` on 2.1.263 lists `--model`, `--effort <level>`, `--fallback-model` [10].
- Effort: `/effort` (slider), `/effort <level>`, `/effort auto`, `/effort ultracode` (>= 2.1.203), `s` inside the bare `/effort` slider for session-only (>= 2.1.257) — the argument form `/effort <level>` saves immediately, and `s` after it does nothing; same split for `/model` [18]. Settings keys `effortLevel` (global) and `modelSettings.<model>.effortLevel` (per model; `/effort` saves per model since 2.1.248). `ultracode` is not accepted in `effortLevel` or `CLAUDE_CODE_EFFORT_LEVEL`. `max` and `ultracode` apply to the current session only via `/effort` and the settings keys [1][8][9]; separately, the sub-agents reference lists `max` among the accepted frontmatter `effort` values (`low`, `medium`, `high`, `xhigh`, `max`) [17].
- Other switches: `/fast` toggles fast mode (Opus 5 default since 2.1.219; usage credits only on subscriptions); `fastMode`, `fastModePerSessionOptIn` settings; `CLAUDE_CODE_DISABLE_FAST_MODE=1` [7]. `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` forces 200K. `MAX_THINKING_TOKENS=0` disables thinking except on Fable 5.x. `alwaysThinkingEnabled` via `/config` or Option+T [1].
- Enterprise: `availableModels` + `enforceAvailableModels` restrict `/model`, `--model`, env, subagents, advisor, fast mode; managed list overrides user additions [1][8].
- Operator's live config (verified on this machine 2026-09-07; superseded 2026-09-08, see addendum): `~/.claude/settings.json` had `"model": "fable"`, `"fallbackModel": ["sonnet"]`, `"effortLevel": "xhigh"`, `"modelSettings": {"fable": {"effortLevel": "low"}}`, `"advisorModel": "opus"` [10]. So Fable ran at `low` while every other model would get `xhigh`. Live probe the same day (recorded transcript metadata, not self-report): a subagent forced onto `claude-fable-5-1` by a stray `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` still ran at `effort: xhigh` from its agent-file frontmatter, so frontmatter beats `modelSettings.<model>.effortLevel`; its rank against `CLAUDE_CODE_EFFORT_LEVEL`/`--effort` was not probed. After removing the var, `mh:plan-reviewer` recorded `claude-opus-5` / `xhigh`.
- Doc vs binary: no disagreement found. Changelog 2.1.257 introduced Fable 5.1 as default Fable; 2.1.260 fixed the `/model` picker hiding Fable 5.1 for eligible orgs and `[1m]` on `ANTHROPIC_DEFAULT_FABLE_MODEL` [9].

## Codex CLI

Live catalog from `codex debug models` on 0.153.4 (cache fetched 2026-09-07T14:51Z) [12]:

| Model | id / display | Context | Effort levels (default) | How to select | Source |
|---|---|---|---|---|---|
| Astra | `gpt-6-astra` (GPT-6-Astra); bundled default since 0.153.4 when no model configured | 272,000 | low, medium, high, xhigh, max, ultra (default low) | `/model`, `codex -m gpt-6-astra`, `model = "gpt-6-astra"`; Plus/Pro, Business, Enterprise, API key | [6][12][14] |
| 5.6 Sol | `gpt-5.6-sol` | 272,000 | low..ultra (default low) | same; Plus/Pro and above | [6][12] |
| 5.6 Terra | `gpt-5.6-terra` | 272,000 | low..ultra (default medium) | same; all plans | [6][12] |
| 5.6 Luna | `gpt-5.6-luna` | 272,000 | low, medium, high, xhigh, max (default medium) | same; all plans | [6][12] |
| GPT-5.5 (legacy) | `gpt-5.5` | 272,000 | low, medium, high, xhigh (default medium) | same; docs list as retiring 2026-08-31 yet still `visibility: list` in catalog | [6][12] |
| GPT-5.4 Mini (legacy) | `gpt-5.4-mini` | 272,000 | low, medium, high, xhigh (default medium) | catalog carries `upgrade` → `gpt-5.6-luna`, `retirement_at` 2026-08-31T19:00Z | [6][12] |
| 5.3 Codex Spark | `gpt-5.3-codex-spark` | — | — | docs: Pro-only text-only research preview; absent from this account's catalog | [6][12] |
| hidden | `gpt-reserve`, `codex-auto-review` | 272,000 | low..max (default medium) | `visibility: hide`; not user-selectable in picker | [12] |

Selection mechanics [5][11][15][16]:

- Flags: `codex -m/--model <MODEL>`, `-c model="..."` (any config key via dotted TOML override), `-p/--profile <name>`; same on `codex exec`. `--help` on 0.153.4 shows no `--effort` flag; effort goes through `-c model_reasoning_effort="high"` or config [11].
- `~/.codex/config.toml`: `model`, `model_reasoning_effort` (documented values `minimal | low | medium | high | xhigh`, "Responses API only; xhigh is model-dependent"), `model_reasoning_summary` (`auto | concise | detailed | none`), `model_verbosity` (`low | medium | high`), `model_context_window`, `model_provider` (default `openai`), `[model_providers.<id>]`, `[profiles.<name>]` [5][16].
- Operator's config on this machine sets no top-level `model` or `model_reasoning_effort`; only `[profiles.ollama-launch-codex-app] model = "kimi-k2.6:cloud"` for a local Ollama provider, and `[tui.model_availability_nux]` markers for `gpt-5.5` and `gpt-6-astra` [11]. So the OpenAI default (Astra) applies.
- GitHub release rust-v0.153.4 (2026-09-04): "Fixed Astra's visibility in the bundled model picker and made it the bundled default when no model is explicitly configured. (#42874)" [14].
- Doc vs binary disagreements: (a) config reference lists `minimal` and omits `max`/`ultra`; the served catalog has no `minimal` and adds `max` and `ultra` [5][12]. (b) Docs label `gpt-5.5` and `gpt-5.4-mini` as retiring 2026-08-31, a week before today, yet both still appear as listable models [6][12]. (c) Docs use display names "Light/Medium/High/Extra High/Max/Ultra"; catalog slugs are `low/medium/high/xhigh/max/ultra` [6][12].

## Addendum 2026-09-08: modelSettings resolution, advisor effort, `/effort` persistence

Findings from the dotfiles deep-audit of `claude/settings.json` (full note with binary excerpts and offsets: dotfiles `docs/research/effort-sweet-spot-2026-09-08.md`) [18]:

- `modelSettings` keys are canonicalized before lookup, so short aliases (`fable`, `sonnet`, `opus`, `haiku`, `opusplan`, `[1m]` forms) are a supported key form, not a workaround. Confirmed live: transcript records with `model: claude-fable-5-1` carry `effort: low` from a `modelSettings.fable` entry. `/effort` writes the canonical id, and a canonical key wins over an alias key for the same model.
- `model: opusplan` = Opus in Plan Mode, Sonnet otherwise (binary literal "Use Opus in plan mode, Sonnet otherwise"); fable is not in that resolution. A doctrine line that names "the" baseline model rots on the next `/model`, which persists by default.
- Advisor: registered server-side as `{type:"advisor_20260301", name:"advisor", model:<id>}` with no effort field; `modelSettings.<advisor>.effortLevel` never reaches it. Gate is `advisor_rank(base) <= advisor_rank(advisor)`; Fable 5.x and Mythos rank 5, Opus 5 rank 4, Sonnet 5 rank 3, Haiku 4.5 rank 1 — fable advising fable passes on equality. Advisor calls bill to usage credits.
- Bundled `effort_cost_index` (high = 1): Sonnet 5 `{low .47, medium .74, xhigh 2.41, max 5.59}`; Opus 5 `{.67, .76, 1.6, 1.7}`; Fable 5.1 `{.6, .77, 1.74, 1.91}`. Sonnet's `xhigh` is the steepest premium of the three. Haiku 4.5 has no effort capability and sends none.
- Top-level `effortLevel` outranks a model's built-in default, so a model with no `modelSettings` entry gets the top-level value, not its own default — keep an explicit entry per model that should sit below it.
- `s` is a keybinding only in the `EffortSlider` and `ModelPicker` contexts; `/effort <level>` and `/model <name>` with an argument save at once. Session-only is the bare command, pick, `s`.
- Operator config after the audit: `model: fable`, `modelSettings` `fable: low`, `sonnet: high`, `opus: high`, top-level `effortLevel: xhigh`, `advisorModel: fable`. Every mh agent pins its own `effort:` in frontmatter, so none inherit `modelSettings`.

## Open questions / unverified

- Whether the Codex `/model` picker writes the chosen model and effort back to `config.toml`: not confirmed; the CLI reference and slash-command pages returned 404 at `learn.chatgpt.com` [15].
- Whether `minimal` is still accepted by the 0.153.4 binary for any model (config reference says yes, catalog says no): not tested live [5][12].
- Codex `ultra` semantics ("Maximum reasoning with automatic task delegation") come from catalog metadata only; no doc page found describing it [12].
- `gpt-reserve` purpose: hidden in catalog, undocumented [12].
- Claude `sonnet[1m]` behavior on the Anthropic API for Sonnet 5 (always 1M) vs gateways: from docs only, not exercised [1].
- Claude Mythos 5.1/5 appear in the API effort docs but not in Claude Code's model-config page; assumed not selectable in Claude Code [1][3].
- Claude Code `--help` text was grepped, not read in full; a `/model` picker screenshot was not taken [10].

## Addendum 2026-09-18: re-verified on 2.1.276/0.154.0 — CLAUDE.md's opus/catch-all effort claims are stale

Re-run triggered by an operator request to re-verify every model's effort setting to full
confidence. Installed: `claude` 2.1.276, `codex-cli` 0.154.0 [19][20].

Per-claim table (claim as written in `~/.claude/CLAUDE.md` "Models + efforts" today vs. live state):

| Claim | Live value | Verdict | Evidence |
|---|---|---|---|
| Plan Mode → opus at effort `high` | `modelSettings.claude-opus-5.effortLevel = xhigh` | **STALE** | dotfiles commit `cedd9e78` (2026-09-18 11:36 +0700, author matches this operator's email) [21] |
| Unlisted model → top-level `effortLevel: xhigh` | top-level `effortLevel = high` | **STALE** | same commit [21] |
| Every other turn → sonnet at effort `high` | `modelSettings.claude-sonnet-5.effortLevel = high` | current | same commit; unchanged by it [21] |
| `fable` at effort `low`, inert under opusplan | `modelSettings.claude-fable-5-1.effortLevel = low` | current | [21] |
| `advisorModel: fable` | `advisorModel = "fable"` | current | [21] |
| `fallbackModel` is `sonnet`, not `fable` | `fallbackModel = ["sonnet"]` | current | [21] |
| Every mh agent pins its own `effort:` frontmatter | 20/20 real agent files (excluding `tests/` fixtures) have `effort:` | current | grepped `agents/*.md` in this repo, 2026-09-18 |
| Codex Astra/Sol/Terra/Luna policy (medium/medium/medium/low bumps) | catalog defaults: Astra/Sol `low`, Terra/Luna/5.5 `medium`; no `minimal`, has `ultra` | current, deliberate bump not drift | `codex debug models` on 0.154.0, 2026-09-18 |
| Advisor mechanism = `advisor_20260301` server-side tool, no effort field | confirmed by name in official changelog (2.1.275 regression fix) | current, and now independently source-confirmed (not just `strings`-derived) | [20] line "Fixed every request failing with `400 … Input tag 'advisor_20260301'`" |
| (mechanism refinement, not previously documented) | Advisor's on/off + model decision is now made **once per session** and only re-announced when it changes, not re-decided per request | **new since 09-08** | official changelog, 2.1.264–2.1.276 range [20] |

Root cause of the two stale claims, from the commit message itself: a prior commit (`3905afeb`,
same day) had "corrected" what it read as effort drift by reverting both opus and sonnet to
`high`, matching what CLAUDE.md documents. `cedd9e78` traced the actual `/model`+`/effort` command
history in session `e0d1434b` and found opus's `xhigh` was a real, deliberate, explicitly-saved
choice — reverting it had been the actual bug. It also dropped the top-level catch-all from
`xhigh` to `high`, since that catch-all was the demonstrated cause of sonnet silently inheriting
`xhigh` (2.41x cost) for ~10 days, unnoticed through both the 2026-09-07 and 2026-09-08 research
passes. CLAUDE.md's doctrine text was last edited 2026-09-14, four days before this fix, so it
still describes the pre-fix state.

Live session cache lag observed: this session's own transcript recorded `claude-opus-5` /
`effort: high` at 05:01 UTC, ~25 minutes after the 04:36 UTC settings commit — consistent with
Claude Code reading `modelSettings` once at session start rather than hot-reloading a live edit to
`settings.json` mid-session. Not separately verified against the settings-reference doc; noted as
an operational caveat, not a claim to fix in CLAUDE.md.

New setting discovered in the changelog delta, not yet in use: `maxEffortLevel` (top-level or
per-model under `modelSettings`) caps the effort level across all providers including
Bedrock/Vertex/Foundry; not present in current `settings.json`, no impact on today's claims [20].

Score (criteria: doctrine text matches live, machine-checked state; weight equal per claim; 9
claims total): 7/9 current + accurately described, 2/9 stale = **78/100**, not 100/100 — the
shortfall is entirely the two effort-level numbers above, both fixable by editing two lines in
`~/.claude/CLAUDE.md`. Confidence in this verdict itself: high — every "current" row was read
directly off the live settings file, a live catalog call, or an official changelog line, not
inferred.

**Correction (found by `/mh:deep-audit`, 2026-09-18, same day):** the two STALE rows above were
already fixed before this addendum was committed. Dotfiles commit `1e801bd3` (2026-09-18 12:06:01
+0700) edited both lines in `~/.claude/CLAUDE.md` — opus `high`→`xhigh` and the top-level catch-all
`xhigh`→`high` — 3h44m before this file's own commit (`64b31094`, 15:50:30 +0700), and its own
message cites this addendum's analysis as the source. So "still describes the pre-fix state" was
already false at the moment this addendum was committed. Corrected: 9/9 claims current as of
commit time, score **100/100**. Failure class: weak_verification — the live-settings re-check
never extended to re-reading CLAUDE.md's own git history before publishing a claim about its
freshness.

## Addendum 2026-09-26: re-verified on 2.1.283 — config moved to official defaults; two corrections

Installed: `claude` 2.1.283. Full write-up: wasikarn/dotfiles
`docs/research/auto-model-auto-effort-2026-09-26.md`.

- **The 2026-09-18 table no longer describes the live config.** Dotfiles commit `93994d33`
  (2026-09-26) kept `model: opusplan` and set every `modelSettings` entry to that model's official
  default: `claude-opus-5-5` `medium` (CC 2.1.280 made Opus 5.5 the `opus` alias, with a `medium`
  default), `claude-sonnet-5` `high`, `claude-fable-5-1` `high`. It also dropped the top-level
  `effortLevel`. `switchModelsOnFlag: false` was added the same day. The opus `xhigh`,
  catch-all `high` and fable `low` rows above are now historical.
- **Fable 5.1 needs CC >= 2.1.257, not 2.1.255** (model table, Fable rows). Changelog 2.1.257:
  "Added Claude Fable 5.1 (`claude-fable-5-1`), now the default Fable model"; model-config:
  "Fable 5.1 requires Claude Code v2.1.257 or later". So `fable` meant Fable 5 before 2.1.257.
- **Alias `modelSettings` keys: the 2026-09-08 addendum stands.** Probed live on 2.1.283 with
  `claude -p --model sonnet --settings '<json>'`, reading `$CLAUDE_EFFORT` from a Bash call:
  `{"sonnet":{"effortLevel":"low"}}` → `low`; `{"claude-sonnet-5":{"effortLevel":"low"}}` → `low`;
  no override → `high` (the user-settings entry); both keys (`sonnet: low` and
  `claude-sonnet-5: medium`, either order) → `medium`. The alias key works, and within one
  settings source the canonical key wins. Across sources, normal precedence decides: the
  alias-only `--settings` case beat the canonical `claude-sonnet-5: high` in the user file.
  Dotfiles `claude/CLAUDE.md` had said alias keys were rejected; it was corrected the same day.
  The probe went through `--settings`, not the user settings file.
- **`CLAUDE_CODE_SUBAGENT_MODEL` changed meaning in 2.1.251.** It now only sets the model for
  unpinned agents; overriding frontmatter pins takes `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`
  (2.1.257). Sources: the sub-agents doc ("Before v2.1.251, `CLAUDE_CODE_SUBAGENT_MODEL` came
  first in this order and overrode both the per-invocation parameter and the frontmatter") and
  changelog 2.1.251, 2.1.257.

## Sources

1. https://code.claude.com/docs/en/model-config — Claude Code model configuration (aliases, precedence, effort, 1M, plans).
2. https://platform.claude.com/docs/en/about-claude/models/overview — Claude models overview (IDs, context, default effort, pricing).
3. https://platform.claude.com/docs/en/build-with-claude/effort — effort parameter, per-model level support.
4. https://platform.claude.com/docs/en/models/fable-5-1/overview — Fable 5.1 model page (linked from [2]; not fetched separately).
5. https://learn.chatgpt.com/docs/config-file/config-reference — Codex config reference (redirect target of developers.openai.com/codex/config-reference).
6. https://learn.chatgpt.com/docs/models — Codex models page (redirect target of developers.openai.com/codex/models).
7. https://code.claude.com/docs/en/fast-mode — fast mode.
8. https://code.claude.com/docs/en/settings — settings precedence; `effortLevel`, `modelSettings`, `availableModels`, `fallbackModel` notes.
9. https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — top version 2.1.263; entries 2.1.246–2.1.260.
10. `claude --version` → `2.1.263 (Claude Code)`; `claude --help`; `~/.claude/settings.json` keys `model`, `fallbackModel`, `effortLevel`, `modelSettings`, `advisorModel` (line numbers omitted: the file shifted the same day).
11. `codex --version` → `codex-cli 0.153.4`; `codex --help`; `codex exec --help`; `~/.codex/config.toml`.
12. `codex debug models` and `~/.codex/models_cache.json` (`fetched_at` 2026-09-07T14:51:32Z, `client_version` 0.153.4).
13. `codex debug --help` — documents `models` subcommand ("Render the raw model catalog as JSON").
14. `gh release view -R openai/codex` → rust-v0.153.4, published 2026-09-04T23:25:48Z.
15. https://learn.chatgpt.com/docs/cli-reference and /docs/slash-commands — both HTTP 404 on 2026-09-07.
16. https://learn.chatgpt.com/docs/config-file/config-basic — `model = "gpt-5.6"` example, `model_reasoning_effort = "high"`, profiles.
17. https://code.claude.com/docs/en/sub-agents — `effort` frontmatter field ("Overrides the session effort level"; options `low`, `medium`, `high`, `xhigh`, `max`), `/tasks` model+effort display, `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`.
18. wasikarn/dotfiles `docs/research/effort-sweet-spot-2026-09-08.md` — `strings` of the installed 2.1.263 binary (advisor registration object, `advisor_rank`, `effort_cost_index`, `y$e()` alias canonicalizer, `opusplan` picker literal, `EffortSlider`/`ModelPicker` `s` bindings) plus project transcript grep for `claude-fable-5-1` / `effort: low`; independently re-checked by a Codex read-only checker on 2026-09-08.
