---
name: usage-monitor
description: "Read-only cost and subagent usage summary for the current session. Use when the user asks about session cost, token burn, cost breakdown by agent, or suspects nested-team token amplification. Reads the SessionEnd capture at `~/.claude/usage/<slug>.jsonl`; L2 read-only, no gates. Don't use for: real-time cost gating (none exists), cross-session aggregation, or OTEL/OTLP export (not implemented)."
---

# Usage monitor

**Status:** L2-only, opt-in, read-only. Honors ADR 0002 (autonomy invariant) — no enforcement.

A passive observer for nested-team token cost. Captures per-session `claude_code.llm_request` and `claude_code.tool` span data (vendor v2.1.139/145) at SessionEnd; the skill reads back the captured JSONL on demand. No threshold gates, no L3 deny, no L4 auto-action — the cost warning is **after the burn**, by design (owner resolved 2026-06-12: passive monitor only, accept the late-warning tradeoff for the L2 guarantee).

## When to trigger

- User says "how much did this cost", "what did the sub-agents burn", "show me token usage for this session"
- User suspects a nested-team cost spike (the 7x amplification warning from the 2026-06-12 audit article "Nested Subagents 5 Levels Deep")
- After a long session with `orchestrate` or `/team-build` runs, as a postmortem check

**Do NOT trigger** for:

- Real-time cost gating (no such mechanism — by design, owner resolution A)
- OTEL export to Datadog/Honeycomb/etc. (not implemented; the capture is local JSONL only)
- Cross-session cost aggregation (the JSONL is per-project-slug, not merged)

## Quick start

The capture hook writes `~/.claude/usage/<project-slug>.jsonl` at SessionEnd (one line per session). The summarizer reads that file and formats a per-agent breakdown.

```bash
# Show the most recent session's cost breakdown by agent
bash "${CLAUDE_SKILL_DIR}/scripts/usage-summarize.sh"

# Show the last N sessions
bash "${CLAUDE_SKILL_DIR}/scripts/usage-summarize.sh" --last 5

# Show totals across all captured sessions for this project
bash "${CLAUDE_SKILL_DIR}/scripts/usage-summarize.sh" --all
```

## How capture works

`hooks/session/usage-monitor-capture.sh` is a `SessionEnd` hook (registered in `hooks/hooks.json`). It runs after every session and:

1. Reads the session's transcript path from the hook input (same pattern as `session-summary.sh:14`).
2. Extracts `agent_id`, `parent_agent_id`, and token counts from the transcript's `claude_code.llm_request` / `claude_code.tool` span records.
3. Appends one JSONL line per session to `~/.claude/usage/<project-slug>.jsonl`.
4. **Always exits 0** — best-effort, never blocks session end (matches `session-summary.sh` posture).

**Opt-in:** capture is gated on `KBG_USAGE_MONITOR=1`. Without the env var, the hook exits 0 immediately and writes nothing. The summarizer still works on whatever was captured in past sessions.

**Failure mode:** if the transcript path is missing, the JSONL line is unparseable, or `~/.claude/usage/` is unwritable, the hook logs to `auto-mode-denial-log.sh` (already wired) and exits 0. Capture failures never escalate.

## Output format

The summarizer produces a per-agent table:

```
| Agent | Calls | Input tokens | Output tokens | Parent |
|-------|-------|--------------|---------------|--------|
| main  | 12    | 45,210       | 18,902        | —      |
| backend-engineer | 3  | 22,100       | 8,440         | main   |
| code-architect  | 1  | 8,500        | 3,200         | main   |
```

Plus a totals row. If `parent_agent_id` is present and matches an `agent_id` in the same session, the row is indented and labeled with the parent — that is the nested-team detection surface.

## What this skill does NOT do

- **No enforcement.** A 7x cost spike fires no hook, no `permissionDecision`, no `deny`. Owner explicitly chose A (passive) over B (soft `ask` gate) on 2026-06-12 to preserve the L2 invariant.
- **No real-time monitoring.** The capture is at SessionEnd only. Mid-session cost is not visible.
- **No cross-project aggregation.** Each project-slug has its own JSONL. Merge yourself with `jq` or `cat` if needed.
- **No external OTEL export.** The capture is local JSONL only. Wiring an OTLP exporter would be a future D9-extension (out of scope for this commit).

## Why passive, not gated

The 2026-06-12 audit spec (D9) flagged "~7x token cost warning unaddressed." Owner resolved on 2026-06-12 to ship **passive monitor only**, accepting the late-warning tradeoff. Rationale:

- ADR 0002 (autonomy invariant) is **irreversible**. Adding an L3 `deny` on cost threshold collides with the invariant.
- The cost warning arriving after the burn is not ideal, but the burn was already in service of a user request — interrupting it would be L3 territory.
- The skill gives the user the data to **adjust the next session's prompt** (e.g. "don't use `/team-build` for this small task"), which is the L2-compatible intervention surface.

## Cross-references

- **2026-06-12 audit spec, D9** — originating finding, deferred from the original 4+1-phase audit epic.
- **2026-06-12 revalidation delta, D9** — vendor v2.1.139/145 verification.
- **ADR 0002 — Autonomy invariant** — the L2-only constraint that rules out the gating alternatives.
- **session-summary hook** — structural precedent; D9 mirrors the best-effort, exit-0, opt-out pattern.
- **F6 agent-tool-patterns** — the `tools:` allowlist convention that D9 doesn't disturb (this skill is read-only by default).
- **Phase 4a — agent-voice-extension** — sibling F5-extension doc; both are F-series follow-ons from the 2026-06-12 audit.
