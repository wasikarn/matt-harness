---
name: cost-aware-llm-pipeline
description: "Compact LLM-pipeline cost: model routing, prompt caching, retry. Use when designing a multi-model pipeline where cost/latency matter. Don't use for single calls or prompting tips."
bucket: patterns
metadata:
  origin: ECC
model: inherit
effort: high
---

# Cost-Aware LLM Pipeline

Patterns for controlling LLM API costs while maintaining quality. Combines model routing, budget tracking, retry logic, and prompt caching into a composable pipeline.

## When to Activate

- Building applications that call LLM APIs (Claude, GPT, etc.)
- Processing batches of items with varying complexity
- Need to stay within a budget for API spend
- Optimizing cost without sacrificing quality on complex tasks

## Technique Map

Full code and the verified caveats for each technique live in `reference.md` — this file
carries the decision rules; load the reference section when actually writing the code:

1. **Model routing by complexity** — threshold on text length/item count routes Haiku vs
   Sonnet; `force_model` escape hatch. `reference.md#1-model-routing-by-task-complexity`.
2. **Immutable cost tracking** — frozen dataclasses, each call returns a new tracker;
   `over_budget` is the branchable stop. `reference.md#2-immutable-cost-tracking`.
3. **Narrow retry** — retry only transient errors (connection/rate-limit/5xx) with exponential
   backoff **plus jitter** (lockstep retries amplify a shared 429); fail fast on auth/bad-request.
   A safety refusal is HTTP 200 with `stop_reason: "refusal"`, not an exception — it isn't billed,
   so skip its `CostRecord` (overcounting guard, not a retry case).
   `reference.md#3-narrow-retry-logic`.
4. **Prompt caching** — `cache_control: ephemeral` on the stable prefix; net win only when the
   prefix outlives enough reads to amortize the ~25% `cache_creation` surcharge — watch
   `cache_read` vs `cache_creation`, negative net savings means stop caching.
   `reference.md#4-prompt-caching`.
5. **Effort parameter** — sweep `effort` on the current model before routing to a cheaper one;
   Haiku models don't support it, so it composes with routing only on the Sonnet/Opus branch.
   Changing effort mid-conversation invalidates the prompt cache. Measured tradeoffs per level:
   `reference.md#5-effort-parameter`.

Composition of all five in one pipeline function: `reference.md#composition`.

## Relative Cost

The routing intuition this pattern exploits — Haiku-tier models run roughly
1x, Sonnet-tier ~2-3x, Opus-tier ~5x per token (current tiers, confirmed
2026-07-31; the ratio compresses as pricing evolves — it used to be closer
to 1x/4x/19x under now-retired model pricing) — is what motivates routing
simple tasks to the cheapest model. **For current model ids and exact
per-token pricing, check Anthropic's pricing docs or the live session
context** — absolute prices and model ids change across releases; this
skill owns the routing pattern, not the price sheet.

## Best Practices

- **Start with the cheapest model** and only route to expensive models when complexity thresholds are met
- **Sweep effort levels on the current model before routing to a cheaper one** — a smaller, cheaper change to test, and it composes with model routing rather than replacing it
- **Set explicit budget limits** before processing batches — fail early rather than overspend
- **Log model selection decisions** so you can tune thresholds based on real data
- **Use prompt caching** for system prompts over the model's minimum cacheable prefix — saves both cost and latency. The minimum is model-dependent, not a flat 1024 tokens: 512 for Claude Opus 5, 1024 for Sonnet 5/Sonnet 4.6/Opus 4.8, but 4,096 for Claude Haiku 4.5 — a prompt sized for Sonnet's threshold routed to Haiku by this skill's own routing logic would silently fail to cache (no error, `cache_creation_input_tokens` stays 0). Check the target model's actual minimum before sizing the cached prefix.
- **Never retry on authentication or validation errors** — only transient failures (network, rate limit, server error)
- **For latency-sensitive callers, stream the response** (`stream=True`) instead of waiting for the full completion — improves perceived responsiveness even though total generation time is unchanged
- **Set `max_tokens` as a latency lever, not just a cost one** — a lower cap bounds worst-case response time, at the cost of a hard cutoff (the response is truncated, possibly mid-sentence, if it hits the limit)

## Anti-Patterns to Avoid

- Using the most expensive model for all requests regardless of complexity
- Routing to a smaller model before trying a lower effort level on the current one
- Retrying on all errors (wastes budget on permanent failures)
- Mutating cost tracking state (makes debugging and auditing difficult)
- Hardcoding model names throughout the codebase (use constants or config)
- Ignoring prompt caching for repetitive system prompts

## When to Use

- Any application calling Claude, OpenAI, or similar LLM APIs
- Batch processing pipelines where cost adds up quickly
- Multi-model architectures that need intelligent routing
- Production systems that need budget guardrails

## Done when

Each cost lever is measured against a real budget and the pipeline's spend is traceable — verify a spike surfaces a named cause, not a vibe.
