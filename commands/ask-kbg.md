---
name: ask-kbg
description: "Context-aware guide to kbg's own fleet: recommends the on-ramp for what this session is doing right now, plus the full narrative map of what chains to what and why. Say 'ask kbg', Thai 'จะเริ่ม flow ไหนดี'. Don't use for a full listing (kbg:inventory), a stage table (/kbg-help), or matt's fleet (the user types /mattpocock-skills:ask-matt)."
disable-model-invocation: true
disable-model-invocation-reason: explicit discovery aid — auto-firing would compete with kbg:inventory and /kbg-help for the same routing-language triggers; the user asks by name when they want a live recommendation or the narrative map
---

# Ask KBG

Read-only. Do not change mode, write files, or persist anything.

You don't remember every surface, so ask.

## Right now

Before showing the reference map, look at this actual session — the request in play, files touched, branch/PR state, errors, what the last few turns were doing — and answer in this shape:

1. **What's happening** — one line naming the concrete evidence (the ask, the file, the state). Thin or fresh session, no real signal yet → say so and ask what they're working on. Don't guess a recommendation from nothing.
2. **Do this** — one literal string to type or run, not a menu of candidates.
3. **Why this one, not X** — name the nearest adjacent surface from the map below and the one fact that separates them. This is the judgment call `/kbg-help`'s stage table and `kbg:inventory`'s listing can't make — it's the reason this command exists instead of just pointing at those two.
4. **Then what** — the next hop in the chain per the map below (e.g. after `/ideate` comes `/ship`; after `kbg:review-pr` comes `/address-review` or `/ship-merge`).

If step 2 lands on a `disable-model-invocation` surface (`/ship-merge`, `kbg:recursive-improve`, `kbg:score-decision`, this file itself, etc.), print the literal string for the user to type and stop — never imply you'll run it once they confirm.

## Reference: the full map

kbg's shape differs from matt's: matt's flow is many small skills you chain yourself (`mattpocock-skills:grilling` → `/mattpocock-skills:to-spec` → `/mattpocock-skills:to-tickets` → `/mattpocock-skills:implement` — the slash-form ones are user-typed). kbg's is a trunk command — `/ship` runs Explore → Clarify → Define-done → Implement → Test → Review → Fix-loop → Merge as one gated pipeline (full phase table: `/ship`). Most of what you'd chain by hand in matt's world, `/ship` already chains internally. What's left to narrate is what feeds *into* it and what happens *after* it.

## On-ramps: what feeds `/ship`

- **Fuzzy idea, not yet a task** → `/ideate` — 5 parallel agents, rotating frames, novelty/viability/fit scoring. Take the winning idea into `/ship` as a blank-slate run.
- **A pile of competing tasks/asks** → `kbg:orchestrate` — triages the pile, routes each item inline/parallel/sequential/drop. One item lands on `/ship`; the rest go wherever they route.
- **One hard, contested-diagnosis decision, before any task exists yet** → `kbg:decide` (full breakdown below, under "Thinking & deciding"). `/ship` Phase 2 already calls this internally for blank-slate ambiguity; reach for it standalone when the decision is upstream of a task, or isn't code at all.
- **A production fire** → `kbg:incident` — mitigate first (rollback/kill-switch/circuit-breaker/scale before hotfix), hands off to `/fix-bug` (S3) or its own hotfix path (S1/S2), closes to `/post-mortem`.
- **A known bug, not urgent** → `/fix-bug` directly, or let `/ship` Phase 4 route to it once scope is known.
- **A non-trivial task you're about to hand off (fresh session or sub-agent) and don't want three "wait, I forgot to mention" rounds** → `kbg:task-prep` — maps the draft against the 9-field handoff template, fills gaps, verifies fresh-context.

## Thinking & deciding — the layer under every on-ramp, not one itself

Every on-ramp above assumes you already know which one to pick. This is what runs underneath that choice, on every non-trivial act, not just the ones with a named skill:

- **Default, every time** → the decision-sizing triad inline (one-way door? blast radius? riskiest assumption?), then `advisor()` before committing. No skill to invoke — the doctrine-bootstrap hook injects this baseline every session.
- **One hard, contested-diagnosis decision past advisor()-level pressure-testing** → `kbg:decide` — 5 modes (clarify/probe/decide/critique/strategize), picked by reversibility and whether the reasoning already exists or still needs building.
- **That decision needs a formal, traceable numeric verdict** (approve/reject/rank/recommend/optimize/validate) → `kbg:score-decision` — weighted criteria, pass threshold + fatal-weakness floor, confidence, trace. `kbg:decide`'s own closing step hands off here when the record needs a number, not just a verdict.
- **Drafting a `/goal` stop condition** → `kbg:goal-craft` — one-way-door screen + turn bound, paste-ready for Claude Code's native `/goal` loop. kbg never invokes `/goal` itself; the string sits inert until you paste it.
- **Naming the lens behind why a surface reasons the way it does** → `docs/reference/reasoning-models.md` — 39 vendored mental models (cc-thinking-skills), mapped to which kbg surface already applies each one. Reference only, not a menu to open before every task — and it carries its own honesty caveat: none of the 39 are proven to improve accuracy, they're framing scaffolds, not a correctness mechanism.

## After `/ship` — or standalone

- **Someone else's PR, or a re-review** → `kbg:review-pr` (by number or branch — `/ship` Phase 6 calls the same skill internally for its own diff).
- **Reviewer left comments to address** → `/address-review` — fetch, classify, fix via `/fix-bug`, reply.
- **PR reviewed, ready to land** → `/ship-merge` — a scored gate (Critical findings, CI, freshness, coverage), not a bare boolean.
- **Cutting a version** → `/ship-release` — bump, changelog, review gate, tag, merge, monitor.

## Codebase & harness health

Upkeep, not feature work — reach for these on a spare moment, or when the harness itself misbehaves:

- `kbg:harness-audit` — fleet/schema audit (default) or `--health` for session token cost.
- `kbg:memory-lint` — dangling `[[links]]`, orphans, index drift in the memory store.
- `kbg:context-budget` — scan context-window consumption, flag bloat.
- `kbg:agent-architecture-audit` — diagnose a misbehaving 12-layer agent stack (stuck loops, memory pollution).
- `kbg:recursive-improve` — self-repair loop; gated at an `AskUserQuestion` before any mutation.
- `kbg:learn` — end-of-session sweep for cross-turn patterns native ambient auto-memory can't catch (also gated).
- `kbg:production-audit` — pre-launch readiness scan (not in-flight feature work — that's `/ship`).
- `kbg:security-auditor` — deep threat-model (auth/secrets/injection/XSS) on PRs touching auth/APIs/payments.
- `kbg:security-scan` — AgentShield sweep of agent/hook/MCP/permission/secret surfaces (not code vulnerabilities — that's `security-auditor`).
- `kbg:cost-report` / `kbg:eval-harness` — narrower single-purpose tools (cost ledger, EDD setup). Decision tools (`kbg:decide`, `kbg:score-decision`, `kbg:goal-craft`) are under "Thinking & deciding" above.
- `kbg:build-fix` / `kbg:refactor-clean` / `kbg:test-coverage` — single-purpose engineering utilities; `/ship` also reaches for these internally at the right phase.

## Stack references — pull in ad hoc, not part of any flow

Framework/language pattern skills, invoked when you're working in that stack, sequenced with nothing: `kbg:backend-patterns`, `kbg:drizzle-patterns`, `kbg:grpc-node-patterns`, `kbg:latency-critical-systems`, `kbg:mysql-patterns`, `kbg:cost-aware-llm-pipeline`, `kbg:tech-humanize`.

## Discovery layer — three surfaces, don't confuse them

- **`kbg:inventory`** — mechanical, full listing of every loadable surface. Grep it when you know roughly what you need and want the exact name.
- **`/kbg-help`** — flat stage table (DEFINE/PLAN/BUILD/VERIFY/REVIEW/SHIP → entry points). Fast lookup when you know the stage.
- **`/ask-kbg`** (this file) — reads the current session and leads with a live recommendation, then the narrative map for browsing. Reach for it when the stage table doesn't tell you which on-ramp fits, or you want a pointed answer instead of a browse.

## Crossing sessions

- **`/frame`** — load a working posture (dev/review/research). A posture-setter, not a workflow switch.
- **matt's `/mattpocock-skills:handoff`** (a separate plugin, not kbg-native; user-invoked) — kbg has no equivalent for compacting a full conversation into a resumable file. Use it the same way matt's flow does.

## The other fleet

kbg-native and matt-origin skills are separate installs (matt's migrated out of this repo in v0.46.0, and off unnamespaced `gh skill` installs onto the `mattpocock-skills` plugin 2026-07-17 — not vendored either way). For grill/prototype/spec/tickets/tdd/code-review/wayfinder/domain-modeling/codebase-design/diagnosing-bugs and the rest of that flow, the user types `/mattpocock-skills:ask-matt` — it owns that map, this file doesn't duplicate it. (Caveat: matt's own docs flag ask-matt as hand-maintained and sometimes stale; the plugin's `plugin.json` is the authority on what's actually installed.)

matt-only tools kbg has no equivalent for (all user-typed except wizard):

- `mattpocock-skills:wizard` (model-invocable) — generates an interactive bash wizard for steps only a human can do: credentials, third-party dashboards, one-off cutovers.
- `/mattpocock-skills:wait-what` — the last reply didn't land; re-pitch it in the project's own vocabulary. (`output-styles/staff-eng.md`'s own voice now does a narrower, ambient version of this on detected confusion — but wait-what stays the explicit, user-typed trigger for when you want the repair deliberately, not left to the assistant noticing.)
- `/mattpocock-skills:to-questionnaire` — turn an unresolved decision into a shareable questionnaire for a stakeholder outside the session.
- `/mattpocock-skills:grill-me` — run matt's batched grilling interview (rounds over a dependency frontier) on a plan or design.
