# codex integration map

`codex@openai-codex` (source `openai/codex-plugin-cc`) paired alongside mh as a second,
independent coding agent — a different model family, routed to by name. Not a wrapper, mirror,
or orchestration layer: mh creates no surface whose only job is to call Codex (see
`CONTEXT.md`'s "pairing" entry). Re-verify this table whenever the installed `codex` plugin
cache version changes; no check parses it. Full reasoning: `docs/plans/codex-pairing-2026-09-06.md`.

## Routing

| skill | invocation | mh touchpoint / fallback |
|---|---|---|
| `/codex:review` | user or model | read-only diff review; Claude-side alternative: `mattpocock-skills:code-review`. On rate-limit or absence, run the Claude-side review instead, invoked by the operator — independence is lost for that pass |
| `/codex:adversarial-review` | user or model | challenges a plan after `mattpocock-skills:grilling`; Claude-side alternative: `mh:plan-reviewer`. Same fallback as review |
| `/codex:rescue` | **user or model** — ships without `disable-model-invocation`, and `codex:codex-rescue` is a full Agent-tool `subagent_type` | writes files through the Codex app-server, not Claude Code tools — see Gate gap below. The review-gate toggle is gated (ADR-0001); the rescue dispatch itself is not |
| `/codex:setup` | **user or model** — ships without `disable-model-invocation` | the one surface mh puts a real gate on: `gate:skill:codex-setup-guard` asks before a model-invoked call carrying `--enable-review-gate` |
| `/codex:transfer` | user only (`disable-model-invocation: true`) | Claude near its own limit → hands the session to a resumable Codex thread. The reverse of the fallback direction above |
| `/codex:status` | user only | job and review-gate status, read-only |

## Gate gap

`/codex:rescue` edits files through the Codex app-server, not through Claude Code's tool-call
pipeline — none of mh's other gates (`gate:bash:irrecoverable`, `gate:bash:subagent-git-guard`,
`gate:task:complete-separation`, `gate:write:test-integrity`, `gate:write:config-guard`) see
those writes. **This repo's own git hooks (`git-hooks/pre-commit`, `pre-push`) are the
vendor-agnostic floor**: whatever wrote a file, the same lint, harness-audit, and gauntlet run
before it ships, regardless of which agent produced it. ADR-0001 records why the rescue
dispatch itself stays ungated rather than picking up a novel Agent-tool gate as a rider on
this trial.

Sandbox/approval note: no `~/.codex/config.toml` recommendation is needed for this pairing.
The plugin hardcodes its own sandbox per call — `read-only` for `/codex:review` and
`/codex:adversarial-review`, `workspace-write` (never `danger-full-access`) for rescue's write
path — as a structured parameter to its app-server, not a config file setting. `config.toml`
only governs a bare `codex`/`codex exec` run by a human directly, outside the plugin.

## AGENTS.md

Codex reads `AGENTS.md`, not `CLAUDE.md`. Drop this paragraph into a repo pairing Codex with
mh:

> This repo runs under `mh@wasikarn` (Claude Code). Its full doctrine is `CLAUDE.md` +
> `docs/METHODOLOGY.md`; the parts that bind you too: (1) the decision-sizing triad before any
> non-trivial change — one-way door? blast radius? riskiest assumption? — (2) a requirement is
> a claim to test, not a truth to obey: name what's ambiguous, missing, or assumed before
> touching code, (3) a bug fix starts with a failing test, the test passing is done. mh's
> `gate:*` PreToolUse hooks are Claude Code hooks — you are not under them; this repo's git
> hooks (`git-hooks/pre-commit`, `pre-push`) are the floor that applies to every edit
> regardless of which agent made it.

No generator, no sync script — short enough to hand-keep in sync with `CLAUDE.md`'s own map.

## Degrading gracefully

Every line above still has to make sense with the plugin absent, the Codex CLI missing, or the
operator logged out: the routing table just names an unavailable fallback path (the "on
rate-limit or absence" column), the gate no-ops if `Skill(codex:setup)` is never called, and
check 71 (`skills/meta/harness-audit/scripts/checks/71-codex-review-gate-state.sh`) reports
INFO "not installed" rather than erroring.
