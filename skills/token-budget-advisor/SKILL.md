---
name: token-budget-advisor
description: >-
  Present depth options (25/50/75/100%) before answering when user wants
  to control response length or token usage. Use when the user asks to
  trim, shorten, or budget an upcoming response. Don't use for
  already-running answers where the depth was not negotiated first.
metadata:
  origin: community
  upstream: https://github.com/Xabilimon1/Token-Budget-Advisor-Claude-Code-
  ecc: skills/token-budget-advisor
---

# Token Budget Advisor

Intercept the response flow to offer the user a choice about response depth **before** answering.

## Trigger

- User mentions tokens, budget, depth, or response length
- User says "short version", "tldr", "brief", "exhaustive", "detailed answer"
- User explicitly asks to control answer size

**Do not trigger** when: user already set a level this session (maintain it silently), or the answer is trivially one line, or "token" refers to auth/session/payment tokens.

## How It Works

### Step 1 — Estimate input tokens

Use heuristics:
- prose: `words × 1.3`
- code-heavy: `chars / 4`

### Step 2 — Estimate response window by complexity

| Complexity | Multiplier | Example |
|---|---|---|
| Simple | 3× – 8× | "What is X?", yes/no |
| Medium | 8× – 20× | "How does X work?" |
| Medium-High | 10× – 25× | Code request with context |
| Complex | 15× – 40× | Multi-part analysis, architecture |

Response window = `input_tokens × mult_min` to `input_tokens × mult_max`

### Step 3 — Present depth options

```
Analyzing your prompt...

Input: ~[N] tokens  |  Type: [type]  |  Complexity: [level]

Choose your depth level:

[1] Essential   (25%)  ->  ~[tokens]   Direct answer only
[2] Moderate    (50%)  ->  ~[tokens]   Answer + context + 1 example
[3] Detailed    (75%)  ->  ~[tokens]   Full answer with alternatives
[4] Exhaustive (100%)  ->  ~[tokens]   Everything, no limits

Which level? (1-4 or "25% depth", "50% depth", etc.)

Precision: heuristic estimate ~85-90% accuracy (±15%).
```

Level token estimates (within the response window):
- 25% → `min + (max - min) × 0.25`
- 50% → `min + (max - min) × 0.50`
- 75% → `min + (max - min) × 0.75`
- 100% → `max`

### Step 4 — Respond at the chosen level

| Level | Target | Include | Omit |
|---|---|---|---|
| 25% Essential | 2-4 sentences | Direct answer, key conclusion | Context, examples, nuance |
| 50% Moderate | 1-3 paragraphs | Answer + context + 1 example | Deep analysis, edge cases |
| 75% Detailed | Structured | Multiple examples, alternatives | Extreme edge cases |
| 100% Exhaustive | No restriction | Everything | Nothing |

## Shortcuts — skip the question

| User says | Level |
|---|---|
| "1" / "25% depth" / "tldr" / "brief answer" | 25% |
| "2" / "50% depth" / "balanced answer" | 50% |
| "3" / "75% depth" / "detailed answer" | 75% |
| "4" / "100% depth" / "exhaustive answer" | 100% |

If the user set a level earlier in the session, maintain it silently for subsequent responses.
