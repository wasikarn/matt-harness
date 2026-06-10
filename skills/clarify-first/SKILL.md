---
name: clarify-first
description: "ALWAYS run this gate before asking the user anything when the request is vague, ambiguous, or underspecified. Trigger on: 'fix the bug', 'refactor X', 'make it faster', 'add a Y system', 'help with frontend', 'database is slow', 'update the page', 'API errors', or any task lacking concrete scope. Also trigger before dispatching write-capable agents or choosing sequential vs parallel execution. Don't use for: simple parameter collection, rhetorical questions, or unambiguous file reads."
---

# Clarify-First

Every question Claude asks a user is a transaction: the user pays attention, Claude pays trust. Make the question sharp, respectful, and worth answering. This skill governs HOW questions are structured — not whether to ask them.

## Core Principle

> A well-crafted question follows four rules: **Be Specific**, **Remove Jargon**, **Avoid Leading**, **Provide Context**.

Apply these rules through the **Analyze → Recommend → Ask** gate. Never ask without running the gate first.

---

## The 3-Step Gate (Mandatory)

Before every user-facing question — whether `AskUserQuestion` or prose — execute all three steps.

### 1. Analyze

Read the relevant context first. Lazy questions cost double: user frustration + rework.

- What does the codebase already tell us? (file paths, conventions, existing features)
- What does the conversation history already tell us? (prior decisions, stated constraints)
- What is genuinely unknown vs. what is just unexamined?
- If the user wrote Thai, what is implied between the lines? (high-context read)

**Brevity constraint**: State the analysis in **2–4 tight sentences**. Do not enumerate every possible gap or list all 5W1H dimensions unless the user explicitly asked for full requirements elicitation. Over-analysis overwhelms the user and burns tokens.

**Tool-call budget**: Spend no more than **3 Read/Grep calls** in the Analyze step. If you cannot determine scope in 3 calls, proceed with what you know and surface the uncertainty in the recommendation. Do not recursively explore the codebase.

**Fast path**: If the prompt clearly references an external system (e.g. "My API returns 500s" when the current repo is dotfiles or a static site) or the repo has zero relevant code, skip the Read/Grep entirely. Limit the analysis to **exactly 1 sentence** stating that the target is external, then proceed directly to Recommend and Ask.

**Small-file fast path**: If the target file is <50 lines, limit analysis to **1 tight sentence** describing what it does and what's missing. Do not read secondary files (e.g. `main.py` that only imports the middleware) unless they materially change scope.

**Stop signal**: If the "unknown" can be answered by reading one more file, read it — don't ask.

### 2. Recommend

State what you would choose if forced to decide now, with one concrete reason.

- Not "I think maybe X or Y" — pick one.
- Frame the recommendation as a working hypothesis: *"If I had to choose now: [choice], because [reason]."*
- Identify what information would change the recommendation.
- **Brevity constraint**: Keep the recommendation to **1–2 sentences**. If you need more context to justify it, move that context into the Analyze step.

This gives the user something to correct, not a blank page to fill.

### 3. Ask

Present the question. If using `AskUserQuestion`, include the recommendation in the question text or option descriptions.

- Lead with the recommendation, then ask for confirmation or override.
- If the user said "whatever you think is best," still ask — but frame it as "confirm my recommendation" not "tell me what to do."
- **Brevity constraint**: The question itself should be **one sentence**. If you need to add context or examples, keep them to a single trailing sentence. The user should be able to read the whole Ask block in under 5 seconds.

---

## Framework Selector

Match the situation to the right questioning model. Don't mix models — pick one and apply it fully.

| Situation | Framework | Key Pattern |
|---|---|---|
| Architecture / design trade-off | **Probe** (`/probe`) | Why? → What if? → Shared fate → Contradiction |
| User task is vague or underspecified | **Coaching Habit** | Kickstart ("What's on your mind?") → Focus ("What's the real challenge?") → Strategic ("What are you saying no to?") |
| Innovation / feature ideation | **Beautiful Question** | Why? (understand) → What If? (explore) → How? (execute) |
| Bug with unknown root cause | **Blameless 5 Whys** | Symptom → Immediate cause → Systemic cause. Stop at mechanism, not person. |
| Requirement elicitation | **5W1H** (Kipling) | Who / What / When / Where / Why / How — cover all six before designing. |
| Clarifying ambiguous scope or intent | **Socratic Clarification** | "What exactly do you mean by X?" — target meaning, not justification. |

**Rule**: `/probe` is read-only analysis — use it when the user asks "should we..." or "what if...". Use `clarify-first` when Claude needs the user to fill a gap.

**Discipline**: Select one framework internally, but **do NOT output the framework name** (e.g. "Framework: Blameless 5 Whys"). The user doesn't care about the label — they care about the analysis. Keep the selection implicit in the content.

---

## Tool Choice: AskUserQuestion vs Prose

Use `AskUserQuestion` when the decision is discrete (2–4 options), high-stakes, and guessing creates rework. Use prose for open-ended or narrative clarification. In both cases, run the 3-step gate first.

See [reference.md](reference.md) for: the 4 rules with Thai adaptations, anti-patterns, question templates (5W1H, blameless, scope), Thai-register softening phrases, METHODOLOGY alignment, and integration notes (Auto Mode, sub-agents, budget).
