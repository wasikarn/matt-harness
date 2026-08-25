# Cost-Aware LLM Pipeline — Reference

Full code and the verified caveats for each technique summarized in `SKILL.md`'s map. Content
moved verbatim from SKILL.md (2026-08-23, 200-LOC cap refactor) — the bolded caveat paragraphs
carry externally-verified claims; edit here, don't re-derive.

## 1. Model Routing by Task Complexity

Automatically select cheaper models for simple tasks, reserving expensive models for complex ones.

```python
# Model ids drift across releases — check the current session context or
# Anthropic's model docs for the live ids rather than hardcoding stale ones.
MODEL_SONNET = "claude-sonnet-5"
MODEL_HAIKU = "claude-haiku-4-5-20251001"

_SONNET_TEXT_THRESHOLD = 10_000  # chars
_SONNET_ITEM_THRESHOLD = 30     # items

def select_model(
    text_length: int,
    item_count: int,
    force_model: str | None = None,
) -> str:
    """Select model based on task complexity."""
    if force_model is not None:
        return force_model
    if text_length >= _SONNET_TEXT_THRESHOLD or item_count >= _SONNET_ITEM_THRESHOLD:
        return MODEL_SONNET  # Complex task
    return MODEL_HAIKU  # Simple task (3-4x cheaper)
```

## 2. Immutable Cost Tracking

Track cumulative spend with frozen dataclasses. Each API call returns a new tracker — never mutates state.

```python
from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class CostRecord:
    model: str
    input_tokens: int
    output_tokens: int
    cost_usd: float

@dataclass(frozen=True, slots=True)
class CostTracker:
    budget_limit: float = 1.00
    records: tuple[CostRecord, ...] = ()

    def add(self, record: CostRecord) -> "CostTracker":
        """Return new tracker with added record (never mutates self)."""
        return CostTracker(
            budget_limit=self.budget_limit,
            records=(*self.records, record),
        )

    @property
    def total_cost(self) -> float:
        return sum(r.cost_usd for r in self.records)

    @property
    def over_budget(self) -> bool:
        return self.total_cost > self.budget_limit
```

## 3. Narrow Retry Logic

Retry only on transient errors. Fail fast on authentication or bad request errors.

```python
from anthropic import (
    APIConnectionError,
    InternalServerError,
    RateLimitError,
)

_RETRYABLE_ERRORS = (APIConnectionError, RateLimitError, InternalServerError)
_MAX_RETRIES = 3

def call_with_retry(func, *, max_retries: int = _MAX_RETRIES):
    """Retry only on transient errors, fail fast on others."""
    for attempt in range(max_retries):
        try:
            return func()
        except _RETRYABLE_ERRORS:
            if attempt == max_retries - 1:
                raise
            time.sleep(2 ** attempt)  # Exponential backoff
    # AuthenticationError, BadRequestError etc. → raise immediately
```

**Add jitter to the backoff for concurrent batch callers.** Pure `2 ** attempt` is synchronized across N parallel requests hitting the same 429 — they retry in lockstep at 1s/2s/4s and amplify the rate limit, wasting wall-clock and compute on attempts that never reach the API (and therefore never produce a `CostRecord`). Use `time.sleep((2 ** attempt) + random.uniform(0, base))` to decorrelate; AWS SDKs add full jitter (`random.uniform(0, base)`) by default in standard/adaptive retry mode for exactly this reason.

**A refusal isn't an exception — check `stop_reason` before tracking cost.** Sonnet-5-and-later models can decline a request for safety reasons and still return a normal HTTP 200 with `stop_reason: "refusal"`, so `call_with_retry` never sees it (nothing raised, nothing to retry — that part is already correct). What it doesn't guard is cost tracking: a refused-before-any-output request isn't billed, so building a `CostRecord` for one overcounts spend. Check `response.stop_reason != "refusal"` before adding to the tracker (see Composition step 4).

## 4. Prompt Caching

Cache long system prompts to avoid resending them on every request.

```python
messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "text",
                "text": system_prompt,
                "cache_control": {"type": "ephemeral"},  # Cache this
            },
            {
                "type": "text",
                "text": user_input,  # Variable part
            },
        ],
    }
]
```

**Caching is a net win only when the prefix outlives enough reads to amortize the write premium.** Anthropic charges a ~25% surcharge on `cache_creation` and a discount on `cache_read` — a churn-heavy prefix (per-user system prompt, dynamic tool set) that changes per request costs more to write than it saves. Don't cache what changes per request; watch `cache_read` vs `cache_creation` in the usage response like uptime — negative net savings means stop caching, not cache harder.

## 5. Effort Parameter

Sweep effort on the current model before routing to a different one — it's the cheaper experiment, and it composes with model routing instead of replacing it.

```python
response = client.messages.create(
    model=model,
    max_tokens=4096,
    messages=messages,
    output_config={"effort": "low"},  # low | medium | high (default) | xhigh | max
)
```

**Effort is a request parameter, not a model choice — sweep it first.** No beta header required. Claude Sonnet 5 defaults to `high` on both the API and Claude Code (confirmed against `platform.claude.com/docs/en/build-with-claude/effort`, 2026-08-20); `medium` is the first cost-saving step down, `low` fits high-volume or latency-sensitive work, `xhigh`/`max` exist for the hardest coding/agentic tasks. **Haiku models aren't on the supported list** (Fable 5, Mythos 5/Preview, Opus 5/4.8/4.7/4.6/4.5, Sonnet 5/4.6 are) — this composes with `select_model()`'s routing only on the branch that returns one of those, not the Haiku branch. Anthropic's own measurements: on knowledge-work benchmarks, `medium` matched the default's accuracy at 70-85% of its cost — a free cut — and `low` gave up 1-3 points for a third to a half off the cost; on long-horizon coding the tradeoff is steeper, `medium` gave up about 2 points for half the cost and `low` gave up about 8 points for a quarter of it. Test each level in its own session: changing `effort` mid-conversation invalidates the prompt cache.

## Composition

Combine all five techniques in a single pipeline function:

```python
def process(text: str, config: Config, tracker: CostTracker) -> tuple[Result, CostTracker]:
    # 1. Route model
    model = select_model(len(text), estimated_items, config.force_model)

    # 2. Check budget
    if tracker.over_budget:
        raise BudgetExceededError(tracker.total_cost, tracker.budget_limit)

    # 3. Call with retry + caching + effort
    response = call_with_retry(lambda: client.messages.create(
        model=model,
        messages=build_cached_messages(system_prompt, text),
        output_config={"effort": config.effort},
    ))

    # 4. Track cost (immutable) — skip refusals, they aren't billed
    if response.stop_reason != "refusal":
        record = CostRecord(model=model, input_tokens=..., output_tokens=..., cost_usd=...)
        tracker = tracker.add(record)

    return parse_result(response), tracker
```
