---
name: agent-architecture-audit
description: Scan 12-layer agent stacks, regression, memory pollution, tool discipline, repair loops. Use when debugging a misbehaving harness (stuck loops, rot). Don't use for code review.
bucket: meta
metadata:
  origin: oh-my-agent-check (via ECC)
---

# Agent Architecture Audit

A structured diagnostic for agent systems that hide failures behind wrapper layers,
stale memory, retry loops, or transport mutations. Use when the model worked in
isolation but breaks inside the application, or when behavior degrades over time.

## When to activate

- Agent behavior degrades after adding wrapper layers or prompt changes
- Same model works in playground but breaks inside the application
- User reports "the agent is getting worse" or "tools are flaky"
- Debugging agent behavior for more than 15 minutes without finding root cause
- Before releasing any agent or LLM-powered feature to production

## The 12-layer stack

Any layer can corrupt the answer. Start from the top (system prompt) when the
model produces wrong answers; start from the bottom (persistence) when behavior
is inconsistently wrong across sessions.

| # | Layer | What goes wrong |
|---|-------|-----------------|
| 1 | System prompt | Conflicting instructions, instruction bloat |
| 2 | Session history | Stale context injection from previous turns |
| 3 | Long-term memory | Pollution across sessions; old topics in new conversations |
| 4 | Distillation | Compressed artifacts re-entering as pseudo-facts |
| 5 | Active recall | Redundant re-summary layers wasting context |
| 6 | Tool selection | Wrong tool routing; model skips required tools |
| 7 | Tool execution | Hallucinated execution — claims to call but doesn't |
| 8 | Tool interpretation | Misread or ignored tool output |
| 9 | Answer shaping | Format corruption in final response |
| 10 | Platform rendering | Transport-layer mutation (UI, API, CLI mutates valid answer) |
| 11 | Hidden repair loops | Silent fallback/retry agents running a second LLM pass |
| 12 | Persistence | Expired state or cached artifacts reused as live evidence |

## Failure pattern quick-check

| Question | If yes → |
|----------|----------|
| Can the model skip a required tool and still answer? | Tool not code-gated (Layer 6) |
| Does old conversation content appear in new turns? | Memory contamination (Layer 3) |
| Same info in system prompt AND memory AND history? | Context duplication (Layers 1–5) |
| Platform runs a second LLM pass before delivery? | Hidden repair loop (Layer 11) |
| Output differs between internal generation and user delivery? | Rendering corruption (Layer 10) |
| "Must use tool X" is only in prompt text, not code? | Tool discipline failure (Layer 6–7) |
| Agent's own monologue becomes persistent memory? | Memory poisoning (Layer 3) |

## Audit workflow

**Phase 1 — Scope:** target system, entrypoints, model stack, reported symptoms, time window.

**Phase 2 — Evidence collection:** grep the codebase for anti-patterns:

```bash
# Tool requirements expressed only in prompt text (not enforced in code)
grep -r "must.*tool\|required.*call" --include="*.md" --include="*.txt"

# Hidden LLM calls outside the main agent loop
grep -r "completion\|chat\.create\|messages\.create\|llm\.invoke" --include="*.py" --include="*.ts"

# Memory admission without user-correction priority
grep -r "memory.*admit\|long.*term.*update\|persist.*memory" --include="*.py" --include="*.ts"

# Silent output mutation
grep -r "fallback\|retry.*llm\|repair.*prompt\|rewrite.*response" --include="*.py" --include="*.ts"
```

**Phase 3 — Failure mapping:** for each finding: symptom → mechanism → source layer → root cause → evidence (file:line) → confidence (0–1).

**Phase 4 — Fix strategy** (code-first, not prompt-first):

1. Code-gate tool requirements — enforce in code, not just prompt text
2. Remove or narrow hidden repair agents — make fallback explicit with contracts
3. Reduce context duplication — same info shouldn't flow through prompt + history + memory + distillation
4. Tighten memory admission — user corrections must override agent assertions
5. Reduce rendering mutation — pass-through, don't transform
6. Convert to typed JSON envelopes — structured internal flow, not freeform prose

## Severity model

| Level | Meaning | Action |
|-------|---------|--------|
| `critical` | Agent can confidently produce wrong operational behavior | Fix before next release |
| `high` | Agent frequently degrades correctness or stability | Fix this sprint |
| `medium` | Correctness usually survives but output is fragile or wasteful | Next cycle |
| `low` | Cosmetic or maintainability issues | Backlog |

## Output format

1. Severity-ranked findings (most critical first)
2. Architecture diagnosis (which layer corrupted what, and why)
3. Ordered fix plan (code-first, not prompt-first)

Do not lead with summaries or compliments. If the system is broken, say so directly.

## LangGraph agent application

Apply Layers 1–8 for LangGraph agents:
- **Layer 6–7** — verify every `interrupt()` placement is code-enforced, not just described in a comment
- **Layer 3** — LangGraph `State` must not accumulate unbounded history; check for missing message trim
- **Layer 11** — if the graph has a fallback edge that re-routes to the LLM on tool failure, name it explicitly and add a human gate

## Guardrail

Do not blame the model before falsifying wrapper-layer regressions. The most common
finding is that the model was fine and a wrapper layer introduced the defect.

## Completion criterion

Every finding carries symptom → mechanism → source layer → root cause → evidence (file:line) →
confidence — a diagnosis without file:line evidence is a guess, not a finding. The fix plan is
code-first (Phase 4): a fix that only edits prompt text doesn't close a Layer 6/7 tool-discipline
finding, since that's the exact gap the finding named.
