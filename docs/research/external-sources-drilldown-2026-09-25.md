# External sources drill-down — matt-harness, 2026-09-25

User supplied 7 external sources (a LinkedIn post, a GitHub PR, three Jev-ecosystem repos, an
agent-observability repo, and a local llm-wiki file) and asked for a staff-engineer drill-down to
find something to apply to matt-harness. Grouped into 5 workstreams by shared mental model (not
1:1 with sources) and ran 5 parallel agents against primary sources. One actionable, deferred
item surfaced; everything else reconfirmed a prior no or was out of scope.

## 1. mattpocock-skills PR #1120 — adopt, deferred

PR #1120 (`mattpocock/skills`, base `main`, head `release/v1.3` @ `2aecca1`) is **open, not
merged**. mh's installed plugin is 1.2.3, 18 commits behind `origin/main`; the local clone (when
present) has the PR commits only on `origin/release/v1.3`/`origin/fix/1117-…`, not on `main`.

What it does:
- Ships `implement-spec` (user-invoked, spawns implementer subagents), `pr` (model-invoked), and
  `retro` (user-invoked) out of `skills/in-progress/`.
- Drops `resolving-merge-conflicts` from `plugin.json` with no replacement
  ("nothing replaces it" — upstream's own changeset note).
- Merges #876: renames the domain-doc convention `CONTEXT.md`/`CONTEXT-MAP.md` →
  `GLOSSARY.md`/`GLOSSARY-MAP.md` across `domain-modeling/SKILL.md`, `tdd/SKILL.md:10`,
  `diagnosing-bugs/SKILL.md:10`, `codebase-design/DESIGN-IT-TWICE.md:30`. Skills stop reading
  `CONTEXT.md` after this ships.

mh has a root `CONTEXT.md` (`CLAUDE.md:40` names `domain-modeling` as its maintainer) that would
go stale the moment mh updates past 1.3.0 without a matching rename.

**Rule 14 score: 7.5/10** (relevance 8, already-covered 3, effort 9, risk 7). **Confidence:
high** on the diff/install-state facts (read from the actual diff + local clone + installed
manifest); **medium** on final PR content, since it's still open.

**Deferred checklist — execute in the same commit as the next mh plugin update to ≥1.3.0:**
1. `git mv CONTEXT.md GLOSSARY.md`.
2. Update pointers: `CLAUDE.md:40`, `docs/reference/mattpocock-integration-map.md:15`,
   `docs/reference/codex-integration-map.md:6`, `hooks/gates/codex-setup-guard.py:45`,
   `hooks/gates/codex-setup-guard.sh:8`,
   `skills/meta/harness-audit/scripts/checks/71-codex-review-gate-state.sh:3,30`.
3. `skills/meta/harness-audit/scripts/checks/70-stray-top-level-entries-working-tree-clutter.sh:10`
   — swap the `CONTEXT.md` allowlist entry for `GLOSSARY.md`, or the audit flags it as clutter.
4. Leave `docs/research/`, `docs/plans/`, `CHANGELOG.md` alone (frozen, exempt).
5. Update `mattpocock-integration-map.md`: drop/mark-removed `resolving-merge-conflicts`; move
   `implement-spec` (main-session only) and `retro` from watch-list to the main table; add `pr` as
   a `model` row marked `deferred` (mh commits straight to `develop`, opens no PRs). `retro` looks
   complementary to `mh:learn` (env/check suggestions vs. memory writes) — confirm after install.
6. Reword the comment at `hooks/gates/irrecoverable.py:131` so it doesn't name the removed skill;
   keep the `git add -A`-during-merge behavior unchanged.
7. Do **not** build an mh replacement for `resolving-merge-conflicts` — upstream replaced it with
   nothing, composer-not-creator doctrine agrees.

Nothing to change today; mh is still on 1.2.3.

## 2. Jev ecosystem (router + review + Builder's Guide) — don't adopt, 4th confirmation

Sources: `llm-wiki/raw/How to Build Agentic Harness using Jev (Builder's Guide).md` (keel 0.2.0,
Rust/gpui coding app), `davila7/claude-code-templates`'
`cli-tool/components/mods/productivity/jev-model-router`, `NiazMorshed2007/jev-review`.

Confirmed in code: all three call the same TypeSafe Jev `typesafe:typesafe-ai` already covers
(jev-review `src/jev/client.ts:4-5`, jev-model-router, and keel's `jev_routing.rs:57` all hit
`api.typesafe.ai/v1/systemone` / `TypeSafeJev`).

- **Builder's Guide**: host-owned route menu, host re-check, abstain fallback, receipts, pinned
  routes bypass auto-choice — all already mh doctrine. Guide itself admits "we haven't
  demonstrated that payoff with a coding benchmark." Nothing to install. Score 3.0.
- **jev-model-router**: per-request dynamic model/effort routing via Jev, on
  `prompt.submit`/`turn.step`/`agent.spawn` hooks. `agent.spawn`'s `route()`/`allowed()` never
  preserve a pinned model — it can silently downgrade an `opus`-pinned reviewer (e.g.
  `blind-spot-hunter`) to a smaller one, exactly the failure mh's `CLAUDE_CODE_SUBAGENT_MODEL`
  ban exists to prevent. Score 5.0.
- **jev-review**: local MCP server, one tool, returns 1-10 scores + confidence with no prose
  evidence ("does not generate a prose explanation of why a score is low"). Overlaps
  `mattpocock-skills:code-review`/`codex-review:code`/`mh:blind-spot-hunter`/`mh:deep-audit` in
  name only — mh's judgment schemas require an `evidence`/`checked[]` field with `minItems: 1`.
  Score 3.8.

All three fail mh's 6/10 pass bar. **Confidence: high** — code read directly, and this is the
4th consecutive Jev round to land on "no" (see `jev-adoption-revisit-2026-09-20.md`, 2.45/10). If
role-tagging instrumentation is ever restored, jev-model-router is a useful *reference build* —
but only with a pin-preserving fix.

## 3. agent-beacon (Asymptote-Labs) — don't adopt, 2.3/10

Not a stuck/stalled-agent detector despite the name. It's: (1) full session capture into
OpenTelemetry logs forwarded to Splunk/Datadog, via 10 Claude Code hook events written into
`~/.claude/settings.json` (`cli/beacon/internal/endpoint/hooks/claude.go`); (2) ~50 YAML
after-the-fact security rules (`posture: detect`); (3) an opt-in memory loop that scores traces
via hosted TypeSafe Jev before turning them into memory/skills.

Every function is already covered here, more strongly: (1) Claude Code's own transcripts +
`hooks/stop/cost-tracker.sh` + `hooks/session/skill-usage-telemetry.sh`; (2) `hooks/gates/*`
block *before* the command runs, Beacon's rules only report after; (3) `mh:learn`/auto-memory,
and the memory feature depends on hosted Jev (rejected 4x). Interactive install preselects hosted
forwarding — fails mh's vendor-trust bar on its own.

**One real, unfixed gap surfaced**: neither mh nor Beacon detects a subagent stuck mid-run — all
existing checks (`hooks/gates/subagent-verdict-gate.py` on SubagentStop/SubagentHandback) run at
completion, not during. Not something to build from Beacon's code; flagged as an open question,
not actioned.

## 4. Contrastive-LM/CLM — not relevant (no case to score)

Real repo, not the unrelated ML-research artifact the name suggested: an open-weights,
self-hosted, contrastive-trained "System One" decision model from Kwok/Ré/Mirhoseini/Pavone et
al., with a TypeSafe-compatible `POST /v1/systemone` API, pitched as a 9x-faster self-hosted Jev
replacement. Fails the same two walls that sank Jev: (1) returns only probabilities/scores, never
free-text evidence, so it cannot populate mh's judgment schemas; (2) requires a GPU (vLLM Qwen3-8B
server) — mh is shell/Python/markdown hooks with no GPU anywhere. Best-of-N verifier pitch (new
vs. prior Jev rounds) has nothing in `skills/`/`agents/` to plug into.

## 5. LinkedIn post (alexxubyte) — not relevant

Not a system-design/interview-tips post despite the hashtags — a TypeSafe Jev vendor promo ("Top
9 places to use Jev instead of an LLM"). No benchmark, no adopter, no new evidence beyond
repeating vendor framing. Doesn't meet either reopen condition on file (role-tagging restored, or
a measured mh skill-routing wrong-load rate).

## Overall

| Source | Verdict | Score |
|---|---|---|
| PR #1120 | Adopt, deferred to mh's next plugin update | 7.5/10 |
| jev-model-router | Don't adopt | 5.0/10 |
| jev-review | Don't adopt | 3.8/10 |
| Builder's Guide | Don't adopt | 3.0/10 |
| agent-beacon | Don't adopt | 2.3/10 |
| Contrastive-LM/CLM | Not relevant | unscored |
| LinkedIn post | Not relevant | unscored |

Only actionable item is PR #1120, and it's blocked on upstream shipping 1.3.0. Everything else is
either already covered by an installed skill/gate, reconfirms a settled Jev verdict, or is out of
scope for a Claude Code harness plugin. Nothing in this repo was changed by this drill-down.

## Sources

- PR: `github.com/mattpocock/skills/pull/1120` (diff, changesets, local clone git log)
- Jev: `llm-wiki/raw/How to Build Agentic Harness using Jev (Builder's Guide).md`,
  `github.com/davila7/claude-code-templates` (`cli-tool/components/mods/productivity/jev-model-router`),
  `github.com/NiazMorshed2007/jev-review`, installed `typesafe:typesafe-ai` skill
- `github.com/Asymptote-Labs/agent-beacon`
- `github.com/Contrastive-LM/CLM`
- `linkedin.com/posts/alexxubyte_systemdesign-coding-interviewtips-share-7508552419711266817-cQYu`
- mh repo: `CLAUDE.md`, `docs/reference/{mattpocock,codex}-integration-map.md`,
  `hooks/gates/*`, `hooks/stop/cost-tracker.sh`, `skills/meta/harness-audit/scripts/checks/{70,71}*`,
  `docs/research/jev-adoption-revisit-2026-09-20.md`
