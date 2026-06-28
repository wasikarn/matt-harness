---
name: dual-process
description: Use when an answer arrives too fast on a high-stakes or irreversible task — force one deliberate verification pass before committing. Also the architectural framing for AI agent path design: which actions need a fast-path (small model, no gate) vs a slow-path (larger model + human confirmation).
metadata:
  origin: kbg
  reasoning-model: dual-process
  vendored-ref: docs/reference/thinking-skills/skills/thinking-dual-process/SKILL.md
---

# Dual-Process

Two applications: (1) model-level verification trigger, (2) AI agent path design.

## Application 1 — Verification trigger (for the model itself)

Fluency is not correctness. A fast, confident-sounding answer on a high-stakes task
is the trigger to slow down, not to ship.

**Trigger:** easy answer + high cost of being wrong.

```
Answer formed immediately?  AND  (High-stakes OR unfamiliar domain)?
  → yes → run ONE deliberate verification pass before committing
  → no  → ship the fast answer; over-verifying trivial work wastes budget
```

### Verification pass (one pass, not infinite loop)

1. Re-state the claim explicitly.
2. Re-derive or test it a second, independent way (run the code, read the doc, grep the codebase).
3. Check against ground truth — file, test output, monitoring data, not memory.
4. If the second derivation disagrees, investigate before committing.

### When to skip verification

- Routine, reversible, low-stakes work (rename a variable, obvious lookup).
- You already worked through it deliberately — if the answer was hard-won, a second pass is redundant.
- You can just run it — a test or execution settles it faster than more reasoning.

## Application 2 — AI agent path design

When designing a LangGraph, tool-chain, or multi-step agent, every action falls into
one of two paths. Choose the path before writing the node.

| | Fast path (System 1) | Slow path (System 2) |
|---|---|---|
| **Model** | Haiku / smallest capable | Sonnet / Opus |
| **Human gate** | None — runs autonomously | `interrupt()` or explicit confirmation |
| **Use for** | Classification, extraction, boilerplate generation, deterministic tool calls | Reasoning over ambiguous input, irreversible actions, security or financial decisions, calls with broad side effects |
| **Failure mode** | Wrong answer ships silently | Blocks on every decision (analysis paralysis) |

**Design rule:** default to the fast path; promote to the slow path only when the action
is irreversible, affects external state, or carries a blast radius the user must own.

### LangGraph example

```python
# Fast path — extraction node runs unattended
def extract_plates(state):
    # Haiku: deterministic field extraction from webhook payload
    return {"plates": haiku_extract(state["raw"])}

# Slow path — deletion node gates on human
def delete_session(state):
    # Sonnet reasons about what to delete; interrupt() before execution
    plan = sonnet_plan_deletion(state["session_id"])
    interrupt({"confirm": plan})  # human sees the plan before it runs
    execute_deletion(plan)
```

## Guardrail

Do not apply the slow path universally. An agent that `interrupt()`s every tool call
is not safer — it is unusable. The slow path is for actions with real blast radius,
not for procedural comfort.
