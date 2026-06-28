---
name: agent-self-evaluation
description: "Post-task self-evaluation on 5 axes: accuracy, completeness, clarity, actionability, conciseness. Produces a 1-5 scorecard with improvement suggestions."
metadata:
  origin: ECC
---

# Agent Self-Evaluation

After completing a complex task, pause to rate the output against a structured 5-axis
rubric. This is NOT a pass/fail gate — it catches omissions and overconfidence before
the user has to surface them.

## When to activate

- After writing code that spans 3+ files or 50+ lines
- After a multi-step workflow (implement → test → review)
- After a debugging session that involved 3+ attempts
- After producing a design document, architecture decision, or written analysis
- When the user asks "how good was that?" or "rate yourself"

## The 5 axes

| Axis | Question | What it catches |
|------|----------|-----------------|
| **Accuracy** | Are the facts, claims, and outputs correct? | Hallucinations, wrong API names, incorrect syntax |
| **Completeness** | Did it cover everything asked? | Missed edge cases, unhandled errors, skipped subtasks |
| **Clarity** | Is the output understandable and well-structured? | Confusing explanations, jargon, missing context |
| **Actionability** | Can the user act on the output immediately? | Vague suggestions, missing steps, no verification path |
| **Conciseness** | Did it use the minimum words/tokens needed? | Redundancy, over-explanation, filler |

## Scoring scale

```
5 — Exceptional: no reasonable improvement possible
4 — Good: minor nits only
3 — Adequate: meets the request but has a notable weakness
2 — Weak: clear gap that affects usability or correctness
1 — Poor: fundamentally misses the request
```

**Evidence rule:** every score below 5 MUST cite specific evidence. "Could be better" fails.
Every score of 5 must also cite evidence of correctness. Show the gap — don't just name it.

## Workflow

1. **Collect** — original request, final output, tool outputs that verify correctness, any user corrections received during the task.
2. **Score each axis independently** — do NOT average first and work backwards. Fresh read per axis.
3. **Produce the report** — use the output format from `agents/agent-evaluator.md` (the format that `scripts/evaluate.py` expects).
4. **Apply the improvement** — axis scored ≤ 3: state what you'd do differently. If fixable in < 30 seconds, fix it now. Otherwise flag explicitly with the specific rework needed.

## Output format

Use the exact format from `agents/agent-evaluator.md`:

```
============================================================
AGENT SELF-EVALUATION REPORT
============================================================
Summary: Overall score X.X/5 across 5 quality axes.

  Accuracy         █████ 5/5
    + [evidence of correctness]

  Completeness      ████░ 4/5
    + [what's covered]
    → [improvement: only shown when score < 5]

  ...

  OVERALL           X.X/5

CRITICAL ISSUES (axes ≤ 2):
  [Axis] Score N/5 — specific fix needed
  (or "None")

Self-check: Would the user agree with this assessment? [Yes/No + brief justification]

TOP IMPROVEMENTS:
  1. [Highest impact fix]
  2. [Second highest]

VERDICT: [Deliver as-is / Fix N issues then deliver / Redo from scratch]
```

## Anti-patterns

- **"Everything is a 5"** — no evidence cited. A real 5 requires proving nothing to improve.
- **Over-penalizing scope creep** — only evaluate against what was actually requested.
- **Mixing preference with gaps** — "I don't like decorators" is not evidence. Cite a concrete concern.
