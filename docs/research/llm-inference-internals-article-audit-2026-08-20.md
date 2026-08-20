# "How LLM Inference Works" article vs. kbg-harness — audit (2026-08-20)

**Source:** "How LLM Inference Works, Clearly Explained," Avi Chawla (@_avichawla), published
2026-06-28 (X/Twitter thread, 226 lines, `~/llm-wiki/raw/`). Not yet ingested to `wiki/`.

**The article's content, in one paragraph:** a walkthrough of how a GPU actually runs one
`generate()` call — tokenization (BPE) → embedding + RoPE → transformer layers (attention + FFN) →
**prefill** (all prompt tokens processed in parallel, compute-bound, metric = Time-To-First-Token,
populates the KV cache) → **decode** (one token at a time, memory-bound, metric =
Inter-Token-Latency) → the **KV cache**'s linear growth cost and its mitigations (quantized cache,
sliding-window attention, GQA, PagedAttention/vLLM) → DeepSeek V4's redesigned compressed attention
(CSA/HCA, shrinks the cache structurally) → model-weight **quantization** (FP32→FP16→INT8→INT4,
concrete VRAM numbers) → serving infra (**continuous batching**, **speculative decoding**,
PagedAttention). This is GPU-serving-engine internals — it describes what Anthropic's own inference
stack does, not anything a client of that stack (kbg-harness) touches.

## Verdict

**No build — confirmed domain mismatch, and this ground was already checked once before.** Before
dispatching any agent, `qmd` search over `kbg-research`/`kbg-memory` surfaced a directly relevant
prior investigation: `docs/research/agent-memory-engineering-2026-08-07.md` already evaluated
"Nvidia's KV-cache / HBM / prefill-batching framing" against kbg's architecture (a narrower source
than this article, same underlying territory) and concluded (line 522): *"Inapplicable — no
GPU-serving layer exists... only the session-start prefill-cost analogy survives"* — which was
already shipped as `context-budget`'s MEMORY.md byte-count reporting line (v0.68.223, lines
427-459 of that doc). A fresh-context verification agent then checked this fuller article's 5
additional/more-detailed mechanisms specifically against kbg's live code (not just the prior
doc's territory) and found nothing new to build. A repo-wide grep for the article's own vocabulary
(`PagedAttention`, `speculative decoding`, `continuous batching`, `TTFT`, `GQA`, etc.) hit exactly
one file — the 2026-08-07 investigation itself. No part of the live fleet ever independently
reached for this domain.

## Mechanism-by-mechanism

| Article's mechanism | Checked against | Verdict |
|---|---|---|
| Prefill (compute-bound, parallel) / decode (memory-bound, sequential) split | Workflow tool's `agent()`/`parallel()`/`pipeline()` concurrency model | No application — each `agent()` call is a fully independent `generate()` call on Anthropic's own infrastructure; kbg has zero visibility into how those get scheduled server-side. A bounded local worker pool predates GPU serving by decades and shares no mechanism with continuous batching. |
| KV cache growth costs, "context length isn't free" | `docs/METHODOLOGY.md` Rule 13 / CLAUDE.md context-economy doctrine | No new application — Rule 13's reasoning is Lost-in-the-Middle/prompt-quality, not VRAM/batch-capacity. Same practical conclusion ("keep context lean"), different mechanism, already covered for a different, sufficient reason — surface resemblance only. |
| Speculative decoding (draft model proposes, big model verifies in one batched pass, gated on acceptance rate) | `compliance-audit` Phase 3, `review-pr` Phase 5 step 3.5 (fresh-context multi-agent verification) | No application, and forcing the metaphor would mislead — these dispatch N independent agents that each redo the analysis from scratch, no shared pass, no acceptance-rate concept. The correct existing name is maker-checker separation, already used correctly. |
| Model-weight quantization (FP32→INT4) | `skills/cost-aware-llm-pipeline/SKILL.md` model routing (Haiku vs. Sonnet vs. Opus tiers) | No application, but a real adjacent lever already exists under correct, different vocabulary: kbg swaps models entirely (routing), it doesn't reduce one model's numeric precision (quantization) — `scripts/workflows/deep-research.js:212-282` already routes cheap search/fetch work to Haiku and reserves Sonnet for verify/synthesize. |
| PagedAttention, DeepSeek V4's CSA/HCA (architecture-level redesign) | Whole repo | No application — VRAM paging and model-architecture redesign are both entirely inside the provider's serving stack. Same boundary class as the 2026-08-07 doc's own "C2" finding: kbg cannot fine-tune or redesign the underlying model, full stop. |
| Continuous batching (interleaving token-steps of many sequences on shared GPU weights) | Workflow tool's `min(16, CPUs-2)` concurrency cap | No application — capping concurrent HTTP calls to a client-side process limit is a generic queueing pattern, not GPU step-level batching. |

## The one distinction worth stating precisely: prompt caching ≠ the article's KV cache

Both techniques cache computed attention state for a repeated token prefix to skip re-running
prefill — same technique *family*, different contract. The article's KV cache is **within one
`generate()` call**, ephemeral, invisible, no client lever at all. Anthropic's prompt caching
(named in this session's own `ScheduleWakeup` tool description — "1-hour Anthropic prompt-cache
TTL") is **cross-request**, TTL-bounded, billed, and observable
(`cache_creation_input_tokens`/`cache_read_input_tokens`). Whether the persisted state is literally
K/V tensors under the hood isn't confirmed by Anthropic's public docs — not asserted here. This
distinction is already correctly kept in `skills/cost-aware-llm-pipeline/SKILL.md:178` ("Use prompt
caching for system prompts over the model's minimum cacheable prefix... The minimum is
model-dependent... 512 for Claude Opus 5, 1024 for Sonnet 5... 4,096 for Claude Haiku 4.5"), which
is a different skill than the one the 2026-08-07 investigation touched — worth naming so a future
pass doesn't blur the two mechanisms together under one "it's all KV caching" label.

## Bottom line

Every mechanism in this article is either a genuine domain mismatch (GPU-serving-engine internals
with no lever a Claude Code plugin author can pull) or already correctly represented elsewhere in
this repo under different, more accurate vocabulary (`cost-aware-llm-pipeline`'s model routing and
prompt-caching guidance, Rule 13's context economy). No build follows. This is useful background
knowledge for reading Anthropic's own pricing/latency behavior correctly — it is not a source of
new requirements for this codebase.
