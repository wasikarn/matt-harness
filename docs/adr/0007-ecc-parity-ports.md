# ADR 0007 — ECC behavioral-parity ports

Date: 2026-06-26
Status: Accepted
Supersedes: — (extends ADR 0006's ECC-aligned operating model with capability
ports, not a supersedence)

## Context

ADR 0006 retired the L2–L5 autonomy ratchet and adopted the ECC operating
model (scoped denials, advisory friction, operator-as-authority, no autonomy
flag). A cross-repo parity audit (ECC vs kbg, 2026-06-26) found five ECC
capabilities kbg lacked — not operating-model differences, but concrete
runtime gates an operator who moved from ECC to kbg would notice missing:

1. **GateGuard four-fact-force** — deny the FIRST edit of each file path per
   session, forcing the agent to state importers/callers, affected API, data
   schemas, and the user's verbatim instruction before the edit lands. Second
   touch passes — friction, not a wall.
2. **MCP runtime health** — block MCP calls to a server known unhealthy, with
   exponential backoff; mark unhealthy on failure; optional operator-configured
   reconnect.
3. **Dev-server auto-tmux** — rewrite a dev-server Bash command into a detached
   tmux session so the agent doesn't block on a long-running foreground process.
4. **PostToolUse context/scope/loop monitor** — advisory nudge when scope
   (distinct files modified) or a repeated-tool loop crosses a threshold.
5. **Profile ladder** — `CLAUDE_HOOK_PROFILE=minimal|standard|strict|off` so an
   operator can dial friction down (`minimal`) without losing the safety floor.

The operator does not run ECC; the goal is kbg working the same as ECC at
ECC's own activation semantics, default-on under `standard`.

## Decision

Port all five at ECC's activation semantics, default-on under `standard`,
with two documented fidelity deviations and one profile-ladder design choice.

### Ports

- **`hooks/gates/fact-force-gate.sh`** — PreToolUse:Edit|Write|MultiEdit,
  first in the Edit chain. Per-session state at
  `~/.claude/fact-force/<session>.txt` (one path per line, 30-min idle reset,
  atomic temp+mv). Denial budget (`KBG_FACT_FORCE_FULL_DENIALS`, default 3):
  first N denials get the full 4-fact block, then a condensed one-liner.
  Exemptions (parity): empty path, `.claude/settings*.json` (config-protection
  owns those), subagent (`agent_id`/`parent_tool_use_id` present — parent
  already gated), state-write failure (allow + warn). Off-switches:
  `KBG_GATEGUARD=off` (parity with `ECC_GATEGUARD`), `KBG_FACT_FORCE_DISABLED=1`,
  `CLAUDE_DISABLED_HOOKS=fact-force-gate`, `CLAUDE_HOOK_PROFILE=minimal`.

- **`hooks/gates/mcp-health-gate.sh`** — PreToolUse:mcp__.* (blocks unhealthy
  within backoff) + PostToolUseFailure (marks unhealthy + reconnect). State at
  `~/.claude/mcp-health-cache.json` (`{servers:{<name>:{status,expiresAt,
  failureCount,nextRetryAt,lastError}}}`). Exponential backoff 30s base,
  600s cap. Off-switches: `KBG_MCP_HEALTH_FAIL_OPEN=1` (block→allow),
  `CLAUDE_DISABLED_HOOKS=mcp-health-gate`, `CLAUDE_HOOK_PROFILE=minimal`.
  **Deviation (documented):** ECC actively probes stdio servers by spawning
  their command with a 5s timeout. This bash port does NOT spawn MCP server
  processes (risk of hanging the hook / orphan processes). Health is
  failure-driven: a stdio server is marked healthy optimistically once
  `nextRetryAt` passes, so the next call is allowed and either succeeds (reset)
  or fails again (re-mark). An http server gets a bounded curl probe. This is
  strictly safer (no spawn) and never false-blocks a healthy server.

- **`hooks/gates/dev-tmux-transform.sh`** — PreToolUse:Bash, first in the Bash
  chain. Detects dev-server command patterns (npm/yarn/pnpm/bun run dev|start,
  next/vite/astro dev, ng serve, python http.server/manage.py runserver,
  uvicorn/gunicorn/flask, rails s, go run main.go, cargo run); rewrites
  `tool_input.command` to `tmux new-session -d -s kbg-dev-$$ '<escaped cmd>'`.
  Skips when tmux absent or the session name is taken (never clobbers a running
  dev server). Off-switches: `KBG_DEV_TMUX_DISABLED=1`,
  `CLAUDE_DISABLED_HOOKS=dev-tmux-transform`, `CLAUDE_HOOK_PROFILE=minimal`.

- **`hooks/post-tool/context-monitor.sh`** — PostToolUse:* observe-only.
  Session log at `~/.claude/context-monitor/<session>.jsonl` (append-only,
  30-min idle reset). Advises when distinct files modified > 20
  (`KBG_CONTEXT_MONITOR_SCOPE`) or the same tool repeats ≥3 in the last 6
  PostToolUse events (`KBG_CONTEXT_MONITOR_LOOP`/`_WINDOW`). Emits
  `hookSpecificOutput.additionalContext` (advisory; never blocks).
  **Deviation (documented):** ECC's context-% and cost-USD thresholds need a
  statusline/metrics bridge producer kbg doesn't ship. Those two signals are
  deferred, gated on `KBG_CONTEXT_MONITOR_FILE` pointing at a bridge JSON with
  `context_remaining_pct` / `total_cost_usd`. Scope + loop ship now.

### Profile ladder

`hooks/_lib.sh` `hook_init` gained a profile-tier gate: a hook runs only if
`$CLAUDE_HOOK_PROFILE` is in the hook's declared `HOOK_PROFILES` (space-delimited
full-token match, default `"standard strict"`). `off` short-circuits all hooks
(via the existing `HOOK_HONOR_PROFILE_OFF` path).

- **`minimal`** = the friction dial-down. All four new ports default
  `"standard strict"` → OFF under `minimal`. The irrecoverable-floor gates
  (block-dangerous-bash, block-dangerous-git, secret-read-guard, secret-scan,
  block-bash-doctrine-write) opt into all three via
  `HOOK_PROFILES="minimal standard strict"` so the safety floor survives a
  `minimal` session. `minimal` dials friction, not safety.
- **`standard`** = default, byte-identical to pre-0.6.0 behavior for existing
  gates (no regression) plus the four new ports on.
- **`strict`** = currently equals `standard`'s gate set. Reserved for future
  strict-only friction; not a separate dial today.

`doctrine-bootstrap.sh` (SessionStart context injector) deliberately does NOT
declare `HOOK_PROFILES` — it doesn't call `hook_init`, so the profile gate
never runs against it, and doctrine loading stays always-on. Doctrine is
context, not a friction gate; a `minimal` session still loads METHODOLOGY.

## Contracts verified (not assumed)

Three Claude Code hook-contract facts were verified against
`code.claude.com/docs/en/hooks` (2026-06-26) before shipping, because the ports
were sourced from a third-party framework (ECC) and "verify before asserting"
applies:

1. **Tool-input mutation** requires `hookSpecificOutput.updatedInput` (with
   `hookEventName:"PreToolUse"`). Printing modified top-level JSON + exit 0 is
   **silently ignored** — the original command runs unchanged. ECC's
   `auto-tmux-dev.js` ships this broken pattern; the bash port uses the correct
   structured field.
2. **Advisory injection** requires `hookSpecificOutput.additionalContext` with
   the matching `hookEventName`; top-level `{"additionalContext":...}` is
   silently ignored. This found a pre-existing sibling bug in
   `hypothesis-gate.sh` (UserPromptSubmit) — fixed in this release to emit
   `hookSpecificOutput.{hookEventName:"UserPromptSubmit",additionalContext:$c}`
   via `jq -nc`.
3. **Event name** is the top-level `.hook_event_name` field in stdin JSON —
   there is NO `CLAUDE_HOOK_EVENT_NAME` env var. `mcp-health-gate.sh` (wired
   under two events) branches on `.hook_event_name`, matching the
   `task-lifecycle.sh` precedent.

A fourth bug was caught by empirical smoke test before release:
`mcp-health-gate.sh`'s jq helpers initially piped `$STATE` (the filename) into
jq instead of the file contents, so every state read/write silently no-op'd —
the gate would never have blocked an unhealthy server. Fixed to read file
content explicitly (`state_content` helper, seed `{}` when absent).

## Consequences

- An operator who sets `CLAUDE_HOOK_PROFILE=minimal` gets a lower-friction
  session with the safety floor intact; the four new ports turn off. Default
  (`standard`) users see four new advisory/blocking gates and one profile knob.
- First-touch-of-each-file now denies once per session — the intended ECC
  friction. `KBG_GATEGUARD=off` or `minimal` disables it for setup/repair work.
- Dev servers launched by the agent run detached under tmux; the agent doesn't
  block. Operators without tmux see no change (gate no-ops).
- The two documented deviations (no stdio spawn-probe; context-%/cost deferred)
  are strictly narrower than ECC, never wider — kbg never false-blocks a
  healthy MCP server and never injects a context/cost nudge it can't source.

## Verification

- `bash -n` clean on all four new hooks + the five relabeled floor gates + the
  hypothesis-gate fix.
- Empirical smoke tests (mock stdin, isolated temp HOME): fact-force
  first-touch deny → second-touch allow → subagent allow; dev-tmux
  `npm run dev` → `hookSpecificOutput.updatedInput` with tmux cmd, `ls -la` →
  pass-through; mcp-health fresh→allow, 503 failure→unhealthy state written,
  retry within backoff→deny; context-monitor scope>20→advisory, loop≥3→advisory.
- `hooks/hooks.json` valid JSON; five new wirings present.
- Harness self-audit: 0 Critical, 0 Warnings (56 hooks); 57 check fragments
  (integrity guard 1..57, fail-closed).
- Critical-hooks suite: 426 passed, 0 failed (the 10-assertion "ECC-parity
  ports (ADR 0007)" block covers all four ports: first-touch deny / second-touch
  allow / subagent exempt / off-under-minimal; tmux rewrite / pass-through;
  fresh-server allow / unhealthy-retry deny; scope>20 advisory).
- **Audit regression guards #53–57** (added to `harness-audit/scripts/checks/`):
  each port's load-bearing CC hook contract is now a CRIT check, verified
  bidirectionally (fires on a deliberate break, silent on clean). The checks
  strip full-line comments before grepping so a doc-only mention of a contract
  cannot mask a code regression:
  - #53 profile-ladder floor coverage — the five floor gates carry
    `HOOK_PROFILES="minimal standard strict"` AND `_lib.sh` implements the
    profile tier (a dropped `minimal` = a minimal session loses the safety floor).
  - #54 fact-force structured-decision — the deny path routes through _lib's
    `hook_decision` (a hand-rolled top-level `permissionDecision` is silently
    ignored, the ECC-shipped-broken class).
  - #55 mcp-health event-name — reads stdin `.hook_event_name` (no
    `CLAUDE_HOOK_EVENT_NAME` env branch; that env var does not exist).
  - #56 dev-tmux updatedInput — the rewrite uses
    `hookSpecificOutput.updatedInput` (a top-level command mutation is silently
    ignored; the agent would block on a foreground dev server).
  - #57 context-monitor additionalContext + advisory-only — the advisory uses
    `hookSpecificOutput.additionalContext` with `hookEventName:"PostToolUse"`
    AND never emits a `permissionDecision` (a PostToolUse deny is a category
    error).