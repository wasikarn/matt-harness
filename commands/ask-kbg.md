---
name: ask-kbg
description: "Narrative flow map of kbg's own fleet — what chains to what, and why. Say 'ask kbg', Thai 'จะเริ่ม flow ไหนดี'. Don't use for a full listing (kbg:inventory), a stage table (/kbg-help), or matt's fleet (/ask-matt)."
disable-model-invocation: true
disable-model-invocation-reason: explicit discovery aid mirroring /ask-matt's posture — auto-firing would compete with kbg:inventory and /kbg-help for the same routing-language triggers; the user asks by name when they want the narrative map
---

# Ask KBG

Display this map. One-shot, read-only. Do not change mode, write files, or persist anything.

You don't remember every surface, so ask.

kbg's shape differs from matt's: matt's flow is many small skills you chain yourself (grill → spec → tickets → implement). kbg's is a trunk command — `/ship` runs Explore → Clarify → Define-done → Implement → Test → Review → Fix-loop → Merge as one gated pipeline (full phase table: `/ship`). Most of what you'd chain by hand in matt's world, `/ship` already chains internally. What's left to narrate is what feeds *into* it and what happens *after* it.

## On-ramps: what feeds `/ship`

- **Fuzzy idea, not yet a task** → `/ideate` — 5 parallel agents, rotating frames, novelty/viability/fit scoring. Take the winning idea into `/ship` as a blank-slate run.
- **A pile of competing tasks/asks** → `kbg:orchestrate` — triages the pile, routes each item inline/parallel/sequential/drop. One item lands on `/ship`; the rest go wherever they route.
- **One hard, contested-diagnosis decision, before any task exists yet** → `kbg:decide` — 5 modes (clarify/probe/decide/critique/strategize). `/ship` Phase 2 already calls this internally for blank-slate ambiguity; reach for it standalone when the decision is upstream of a task, or isn't code at all.
- **A production fire** → `kbg:incident` — mitigate first (rollback/kill-switch/circuit-breaker/scale before hotfix), hands off to `/fix-bug` (S3) or its own hotfix path (S1/S2), closes to `/post-mortem`.
- **A known bug, not urgent** → `/fix-bug` directly, or let `/ship` Phase 4 route to it once scope is known.
- **A non-trivial task you're about to hand off (fresh session or sub-agent) and don't want three "wait, I forgot to mention" rounds** → `kbg:task-prep` — maps the draft against the 9-field handoff template, fills gaps, verifies fresh-context.

## After `/ship` — or standalone

- **Someone else's PR, or a re-review** → `kbg:review-pr` (by number or branch — `/ship` Phase 6 calls the same skill internally for its own diff).
- **Reviewer left comments to address** → `/address-review` — fetch, classify, fix via `/fix-bug`, reply.
- **Approved PR, ready to land** → `/ship-merge` — a scored gate (Critical findings, CI, freshness, approval, coverage), not a bare boolean.
- **Cutting a version** → `/ship-release` — bump, changelog, review gate, tag, merge, monitor.

## Codebase & harness health

Upkeep, not feature work — reach for these on a spare moment, or when the harness itself misbehaves:

- `kbg:harness-audit` — fleet/schema audit (default) or `--health` for session token cost.
- `kbg:memory-lint` — dangling `[[links]]`, orphans, index drift in the memory store.
- `kbg:context-budget` — scan context-window consumption, flag bloat.
- `kbg:agent-architecture-audit` — diagnose a misbehaving 12-layer agent stack (stuck loops, memory pollution).
- `kbg:recursive-improve` — self-repair loop; gated at an `AskUserQuestion` before any mutation.
- `kbg:learn` — capture a durable session learning as memory (also gated).
- `kbg:production-audit` — pre-launch readiness scan (not in-flight feature work — that's `/ship`).
- `kbg:security-auditor` — deep threat-model (auth/secrets/injection/XSS) on PRs touching auth/APIs/payments.
- `kbg:security-scan` — AgentShield sweep of agent/hook/MCP/permission/secret surfaces (not code vulnerabilities — that's `security-auditor`).
- `kbg:cost-report` / `kbg:eval-harness` / `kbg:goal-craft` / `kbg:score-decision` — narrower single-purpose tools (cost ledger, EDD setup, `/goal` condition drafting, formal decision scoring).
- `kbg:codebase-onboarding` — catalogue an unfamiliar codebase into an onboarding guide.
- `kbg:build-fix` / `kbg:refactor-clean` / `kbg:test-coverage` — single-purpose engineering utilities; `/ship` also reaches for these internally at the right phase.

## Stack references — pull in ad hoc, not part of any flow

Framework/language pattern skills, invoked when you're working in that stack, sequenced with nothing: `kbg:adonisjs-patterns`, `kbg:backend-patterns`, `kbg:dart-flutter-patterns`, `kbg:drizzle-patterns`, `kbg:effect-ts-patterns`, `kbg:fastapi-patterns`, `kbg:grpc-node-patterns`, `kbg:hono-patterns`, `kbg:langchain-langgraph-patterns`, `kbg:latency-critical-systems`, `kbg:mysql-patterns`, `kbg:tauri-v2-patterns`, `kbg:cost-aware-llm-pipeline`, `kbg:tech-humanize`.

## Discovery layer — three surfaces, don't confuse them

- **`kbg:inventory`** — mechanical, full listing of every loadable surface. Grep it when you know roughly what you need and want the exact name.
- **`/kbg-help`** — flat stage table (DEFINE/PLAN/BUILD/VERIFY/REVIEW/SHIP → entry points). Fast lookup when you know the stage.
- **`/ask-kbg`** (this file) — the narrative in between: what feeds what, and why you'd branch. Reach for it when the stage table doesn't tell you which on-ramp fits, or the phase connections aren't obvious.

## Crossing sessions

- **`/frame`** — load a working posture (dev/review/research). A posture-setter, not a workflow switch.
- **matt's `/handoff`** (globally available, not kbg-native) — kbg has no equivalent for compacting a full conversation into a resumable file. Use it the same way matt's flow does.

## The other fleet

kbg-native and matt-origin skills are separate installs (matt's migrated out of this repo in v0.46.0 — `gh skill install`, not vendored). For grill/prototype/spec/tickets/tdd/code-review/wayfinder/domain-modeling/codebase-design/diagnosing-bugs and the rest of that flow, ask `/ask-matt` — it owns that map, this file doesn't duplicate it.
