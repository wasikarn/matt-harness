# Deep analysis: Vercel Workflow SDK (workflow-sdk.dev/llms.txt)

Date: 2026-08-31. Method: full read of the 1.17MB llms.txt docs dump (4 parallel readers, 100%
coverage each), plus independent provenance checks (GitHub API, npm registry, domain headers).
Source: `https://workflow-sdk.dev/llms.txt` (raw scrape archived in session scratchpad, chunks
`wf-chunk-{1..4}.txt`).

## TL;DR

Vercel's Workflow SDK is Temporal-style durable execution (event log + deterministic replay)
embedded in your own app via a compiler transform — no worker fleet, no control plane. The
engineering is real and the docs are unusually honest about failure modes, but three structural
facts should drive any adoption decision: steps are **at-least-once with silent retries**, run
survival is **coupled to deployment retention** (a months-long sleep dies if its pinned deployment
ages out), and portability off Vercel is genuine-but-second-class (Postgres World requires a
long-lived worker; several features are Vercel-only). It is 10 months old with a fast-churning
5.0 beta and two deprecations already in the AI layer.

## 1. Identity and maturity (independently verified)

- **Vendor**: Vercel. Monorepo `github.com/vercel/workflow`, Apache-2.0, created 2025-10-23,
  2,364 stars, 105 open issues, pushed 2026-08-28. `workflow-sdk.dev` is the current canonical
  docs domain — launch-era `useworkflow.dev` now 308-redirects to it. (The npm name `workflow`
  dates to 2011; Vercel took over an existing name, so npm download totals are not meaningful.)
- **Versions**: stable `workflow@4.8.5` (2026-08-25); `5.0.0-beta.46` (2026-08-26) with
  near-weekly betas. 5.0 brings multi-region (4.x Vercel World is `iad1`-only) and merges the
  step entrypoint into a combined handler (4.x runs steps in a separate worker process).
- **Packages**: `workflow` (+ subpath adapters `next/nitro/nuxt/sveltekit/astro/vite/nest`),
  `workflow/api`, `workflow/errors`, `workflow/runtime`, `workflow/observability`,
  `@ai-sdk/workflow` (current AI layer), `@workflow/serde`, `@workflow/vitest`,
  `@workflow/world-{local,postgres}`; Python SDK in beta (≥3.12, decorator-based).
- **Churn signals**: `DurableAgent` and `@workflow/ai`'s `WorkflowChatTransport` already
  deprecated (moved into AI SDK as `WorkflowAgent`); "may be removed/renamed in the future"
  language on `respondWith()` and `deploymentId`; two doc code samples with visible syntax errors.

## 2. Core architecture

Two directives, one transform. `"use workflow"` marks an orchestrator function, `"use step"`
marks work. An SWC plugin (wired via `withWorkflow()` etc.) compiles these into handlers at
`/.well-known/workflow/v1/{flow,step,webhook}`. This is a **compiler-level integration, not a
library** — frameworks without a build system (Express/Fastify/Hono) must add Nitro as a build
layer to use it.

Durability = event log + deterministic replay, explicitly contrasted with memoization and
CRIU/snapshotting. Every boundary-crossing value is serialized (devalue-based, pass-by-value;
custom classes need `WORKFLOW_SERIALIZE`/`WORKFLOW_DESERIALIZE` symbols) into a per-run,
AES-256-GCM-encrypted, ULID-ordered event log; runs/steps/hooks are materialized views over it.
On resume, the workflow body re-executes and consumes recorded history.

The workflow body runs in a **sandboxed VM**: no global `fetch` (a step-wrapped
`import { fetch } from "workflow"` replaces it), no Node core modules, no timers, no `Buffer`;
seeded `Math.random()`/`crypto.randomUUID()` and a logical-clock `Date` keep replay stable.
Steps are the escape hatch: full Node, non-determinism allowed, results cached in the log,
auto-retried (default `maxRetries = 3`; `RetryableError{retryAfter}` / `FatalError` to steer).
The 16-entry error catalog is effectively the sandbox's shadow — `fetch-in-workflow`,
`node-js-module-in-workflow`, `timeout-in-workflow`, `serialization-failed`,
`replay-divergence`, `corrupted-event-log`.

**Worlds** (pluggable backend = storage + queue + streamer): Local (dev-only, JSON files,
in-memory queue, no auth), Vercel (managed, zero-config, OIDC, Vercel Queues), Postgres
(self-hosted: graphile-worker, NOTIFY/LISTEN streams — requires a long-lived worker process,
"does not work on serverless environments"). Custom Worlds implement
`World extends Storage, Queue, Streamer` and can be listed via a `worlds-manifest.json` PR.

## 3. The AI-agent layer

This is the SDK's actual go-to-market: durable AI agents on the AI SDK.

- **`WorkflowAgent`** (AI SDK v7): the agent loop is a workflow; tools marked `"use step"`
  get retry + observability per tool call.
- **Session modeling**: single-turn (run per message, client owns history) vs the recommended
  multi-turn (one long-lived run *is* the session; `runId` = session ID; follow-up user messages
  injected via hooks — enabling multiplayer sessions and webhook-injected messages).
- **HITL**: `defineHook({schema})` (Standard Schema v1) → `.create({token})`/`.resume(token,
  payload)`; `createWebhook()` exposes `/.well-known/workflow/v1/webhook/:token`. Hooks are
  awaitable and `AsyncIterable`, auto-disposed on terminal states.
- **Message queueing**: `prepareStep` callback drains a hook-fed queue into the model's messages
  between agent-loop steps (can also swap models mid-run).
- **Resumable streams**: `WorkflowChatTransport` reconnects via `x-workflow-run-id` +
  `getRun(id).getReadable({startIndex})`; named per-run streams, negative tail indexing,
  paginated snapshots via `getChunks()`.

## 4. What the docs admit (the honest constraint picture)

These are the load-bearing admissions, all verbatim or near-verbatim from the docs themselves:

1. **At-least-once steps, silently retried.** "There may be cases where you see multiple
   `step_started` events for the same step… the step will be re-tried according to your retry
   policy… but no error will be visible in the Observability UI." Any side-effecting step needs
   idempotency keys (the docs teach `idempotencyKey: \`charge:${stepId}\``). Waits, by contrast,
   complete exactly once.
2. **Run survival is coupled to deployment retention.** Runs pin to the immutable deployment
   that started them. "A run whose deployment has been deleted or has aged out cannot be resumed
   and must be re-run." The same docs advertise months-long `sleep()` — those two claims are in
   tension, and the operator owns reconciling them (deployment retention policy).
3. **The SDK owns an unrecoverable failure class.** `corrupted-event-log` / persistent
   `replay-divergence` / `runtime-decryption-failed` are fatal and uncatchable; the docs say
   plainly this "indicates a bug in the Workflow SDK or Workflow server, not in your workflow
   code."
4. **Webhook auth is the token in the URL, full stop.** "The token in that URL is the only
   authorization performed." Self-hosters must additionally secure all of
   `/.well-known/workflow/v1/*` themselves (on Vercel, handlers are queue-consumer-only and not
   publicly invokable).
5. **Cancellation is cooperative and lossy at the edges.** `Promise.race` doesn't cancel the
   loser ("the losing operation keeps running"); stopping an agent doesn't stop the model stream
   ("tokens generated after the stop signal are still produced (and billed)"); hard
   `run.cancel()` skips `finally` blocks.
6. **Resume-or-start is not atomic.** "Two concurrent requests can both observe 'no hook yet'
   and each call `start()`" — a native atomic start+hook API is "in the works."
7. **Identity is name-and-path derived.** Renaming a workflow function or file changes its
   identity and breaks in-flight chains; publishing a library bumps every step ID (version is
   embedded in the compiled ID).
8. **Portability is aspirational.** Every guide ends with "apps currently work best when
   deployed to Vercel"; `deploymentId: "latest"` is Vercel-only; Postgres World is not
   serverless-compatible.

## 5. The comparisons section, slant-checked

The docs ship vendor-authored comparisons (disclaimer: "not based on head-to-head benchmarks").
Fairness varies:

| vs | Their claim | What the framing underplays |
|---|---|---|
| Temporal | No workers/queues/control plane to run; pinning beats patch APIs | Temporal's far richer retry policy (backoff coefficient, non-retryable error types) vs the SDK's single `maxRetries`; "no duration cap" is a Vercel World property sold as SDK-generic |
| Inngest | Co-located, no per-step HTTP round trip | Concedes no analog for Inngest's flow control (concurrency/throttle/debounce/batching) — a real gap for rate-limited AI workloads |
| Cloudflare Workflows | Per-run E2E encryption vs at-rest; "highest lock-in" | Key custody for the managed Vercel World is never stated; concurrency row compares platforms, not SDKs |
| Step Functions | Plain TypeScript vs ASL JSON | Lists SFN's dollar pricing against "SDK free; pay your platform" — its own effective cost never priced |
| trigger.dev | Replay vs CRIU snapshotting | Fairest entry; concedes CRIU removes determinism rules entirely |
| AgentCore | "Different axis" | Compliance jab relies on community-sourced figures by its own admission |

## 6. Verdict

**Adopt-when**: you're on Vercel (or can run a Postgres worker), on the AI SDK, and need
durable agent sessions, HITL approval gates, or resumable chat streams without operating
Temporal. The DX (directives, one mental model, honest error catalog, built-in observability
UI) is the best-in-class version of this idea, and per-run E2E encryption of the event log is a
real differentiator.

**Hold-off-when**: you need exactly-once side effects without doing idempotency work yourself,
strict flow control (Inngest's territory), runs that must outlive arbitrary redeploy/retention
policies, or vendor-neutral infra. And on any adoption: pin to 4.8.x, treat 5.0 betas as
moving ground, expect API renames (the docs themselves flag several), and wrap every mutating
step in an idempotency key from day one.

**Maturity grade**: promising-but-young. 10 months old, weekly-churn beta line, deprecations
already accumulated, candid changelog (its own "Resilient start" entry documents a remaining
cold-start race and a "narrow crash window in world-postgres" as known concerns). The honesty
is a good sign; the churn is the cost.

## 7. Relevance to matt-harness (brief)

Different layer, transferable patterns. This SDK durably orchestrates *application* code;
matt-harness orchestrates *agents inside a Claude Code session* (Workflow tool scripts,
`parallel()`/`pipeline()`), with no persistence across process death — complementary, not
competing. Three patterns worth noting for this repo's doctrine, no build proposed:
per-step idempotency keys as the answer to at-least-once execution (mirrors the "score, not
feel" determinism stance); HITL as a typed, awaitable hook rather than a chat convention
(stronger than a prose confirm); and the deployment-pinning model as a clean answer to
"what happens to in-flight work on upgrade" — a question this repo's own plugin-cache
staleness gotchas orbit constantly.
