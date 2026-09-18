# Claude Haiku 4.5 as a Jev-style decision primitive — feasibility, design, and build plan

Date: 2026-09-18. Method: primary-source Anthropic API docs (`platform.claude.com`) fetched
directly for pricing, tool-use forcing, strict tool use, the Haiku 4.5 model page, the
latency-reduction guide, and the Messages API reference; cross-checked against this repo's own
implementation by reading `skills/review/deep-audit/references/checker-output-schema.json`,
`skills/workflow/idea-audit/references/attacker-brief.md` and its output schema,
`docs/reference/spawn-brief.md`, `docs/reference/codex-integration-map.md`, and every file under
`hooks/`. Builds on this repo's two prior Jev research notes; does not re-derive their claims.

Companion notes (same subject, do not repeat their ground):
`typesafe-ai-system-one-jev-2026-09-18.md` (source/claims check on TypeSafe's launch),
`jev-architecture-unmasked-archerhume-2026-09-18.md` (independent black-box reconstruction).
Both already concluded: no Jev adoption, mh has a schema-constrained equivalent. This note asks a
narrower, different question — not "should mh adopt Jev" (settled), but "is a Haiku-backed
decision primitive, inspired by Jev's shape, worth building inside mh, and if so how."

## TL;DR

- **Feasible for the half of Jev's promise that's structural** (output can't leave a declared
  schema): Claude's `strict: true` tool mode uses "grammar-constrained sampling" to guarantee
  schema-valid tool `input`, the same category of guarantee TypeSafe describes for
  Choice/Score/Noul, just implemented differently (constrained decoding on a generative model,
  vs. TypeSafe's claimed non-autoregressive parallel head).
- **Not feasible for the half that's calibration-shaped.** The Claude Messages API has no
  logprobs or token-probability field of any kind — confirmed by direct inspection of the API
  reference. A Haiku "confidence" field would have to be the model *self-reporting* a number in
  its own JSON output, which is a strictly weaker and less trustworthy claim than even Jev's own
  confidence field — and the Archer Hume audit already showed Jev's confidence field is itself
  just an arithmetic rescale of max softmax probability, not a learned calibration. Don't build
  a "confidence" output for a Haiku primitive; it would be inventing an unverified number in a
  repo whose own doctrine (Rule 14) requires **ข้อมูลไม่เพียงพอ** instead of a guessed score.
- **mh's existing "schema-constrained equivalent"** (`codex exec --output-schema` in
  `idea-audit`/`deep-audit`/`compliance-audit`, and the Claude-fallback output contracts in
  `spawn-brief.md`/`attacker-brief.md`) is real but a different shape than what a "Jev clone"
  would be: it's heavyweight, per-run, subagent-dispatch-only, and always paired with a large
  adversarial-review prompt. There is **no lightweight, inline, single-call classification
  primitive anywhere in this repo** — confirmed by grep: zero LLM calls exist in any of the 10
  gate scripts under `hooks/gates/` (all deterministic Python), and no `skills/**/scripts/*`
  wraps a bare Anthropic API call for a yes/no or pick-one decision.
- **That gap is real but currently has no named consumer.** Building a new skill or gate around
  it now would be speculative under this repo's own skill-authoring rule ("if Claude already
  clears the task without the skill, the skill should not exist") and under YAGNI. Recommend
  documenting the pattern (Option A below), not shipping a new skill or gate, until a real skill
  in this repo names an inline cheap-classification call in a `Done-when`.
- **On speed/cost, a Haiku primitive will not, and should not be marketed to, match Jev's
  numbers.** Jev is non-generative and priced accordingly ($0.042/MTok in, $0 out, per the
  companion notes — vendor-set, unverified independently). Haiku 4.5 is a full generative model
  billed at $1/MTok in, $5/MTok out (confirmed at `platform.claude.com/docs/en/about-claude/pricing`)
  — about 24x Jev's input price before any output cost at all, because it's a different kind of
  product, not a worse implementation of the same one.

## 1. What mh already has, read directly from the code

| Surface | What it actually is | Where |
|---|---|---|
| `codex exec --output-schema` | External CLI subprocess (Codex, not Claude), dispatched per full audit run, read-only or worktree-scoped, always for a large adversarial-review task | `docs/reference/codex-integration-map.md` rows for `/mh:deep-audit`, `/mh:idea-audit`, `/mh:compliance-audit`; schema files `skills/review/deep-audit/references/checker-output-schema.json`, `skills/workflow/idea-audit/references/attacker-output-schema.json` |
| Claude-side fallback contract | A `general-purpose` subagent dispatch with an explicit `## Output` contract in the brief (`Return ONLY JSON matching ...`), used only when Codex is rate-limited/absent | `skills/workflow/idea-audit/references/attacker-brief.md:64-75`; `docs/reference/spawn-brief.md`'s validator return shape `{pass, findings[], scope_ok, unexpected_files[]}` |
| Gates (`hooks/gates/*.py`) | Deterministic Python only — `irrecoverable.py`, `config-write-guard.py`, `subagent-git-guard.py`, `subagent-spawn-guard.py`, `task-complete-separation.py`, `test-integrity.py`, `codex-setup-guard.py`. Zero LLM calls (grepped for `anthropic\|haiku\|claude` across all of `hooks/`; the only hit is `hooks/stop/cost-tracker.sh`, which only *parses model names out of transcript JSON for cost accounting*, never calls a model) | `hooks/gates/`, `hooks/hook-registry.json` |
| `mh:ideate`'s novelty/viability/fit scores | LLM-produced raw scores, but run through a **deterministic** ranker afterward — `scripts/rank.py`, described in its own SKILL.md as "the deterministic ranker both scoring paths run" | `skills/workflow/ideate/SKILL.md:132` |

None of these is a lightweight, inline, single-round-trip decision call a skill or script could
make mid-flow without dispatching a full subagent. The closest analog, the Claude-fallback
contract, still goes through the Agent tool as a `general-purpose` dispatch with a multi-page
brief — proportionate for an adversarial audit, disproportionate for "is this string profane"
or "pick one of these five categories."

## 2. Primary-source check: can Haiku 4.5 actually do Choice/Noul-shaped output?

Fetched directly from `platform.claude.com` on 2026-09-18 (all URLs below):

| Jev primitive/claim | Claude API mechanism | Source | Verdict |
|---|---|---|---|
| `Choice`/`Noul`: output structurally can't leave a declared enum | `tool_choice: {"type": "tool", "name": "..."}` forces a specific tool call; `strict: true` on the tool definition adds "grammar-constrained sampling" that "guarantees Claude's tool inputs match your JSON Schema" | [Forcing tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#forcing-tool-use), [Strict tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use) | **Confirmed available.** Same *category* of guarantee TypeSafe claims (structural, not just prompted), different *mechanism* (constrained decoding at sample time on a still-autoregressive model, not a claimed non-autoregressive parallel head). |
| Manual extended thinking blocks forced tool use | `tool_choice: {type: "any"}` and `{type: "tool", ...}` **fail** when `thinking: {type: "enabled"}` is set manually; use `auto`/`none` instead, or don't enable thinking | [Forcing tool use — restrictions table](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#forcing-tool-use) | **Confirmed, and directly relevant to Haiku.** Haiku 4.5's own model page states: "Claude Haiku 4.5 uses manual extended thinking (`thinking.type: 'enabled'`), not adaptive thinking" — i.e., thinking is off by default and must be explicitly turned on. A Haiku-based decision primitive must leave `thinking` unset/disabled to keep forced `tool_choice` working; this is a real design constraint, not a hypothetical one. |
| `Score`/confidence: a calibrated probability per option | No equivalent. The Messages API has **no logprobs or token-probability field of any kind** in request or response | [Messages API reference](https://platform.claude.com/docs/en/api/messages) (direct inspection, 2026-09-18) | **Not available at any layer.** Any "confidence" a Haiku tool call reports would be the model writing a number into its own JSON output — self-reported, not measured — which is a *weaker* claim than even Jev's own confidence field (itself shown by the Archer Hume audit to be a deterministic rescale of `p_max`, not a trained calibration). |
| Latency: "70–500ms" | No absolute latency figures published for any model. Only a **qualitative, relative** ranking: Haiku 4.5 = "Fastest" in the current lineup; Anthropic's own latency-reduction guide gives techniques (pick Haiku, shorten prompt/output, stream) but no ms numbers | [Models overview](https://platform.claude.com/docs/en/about-claude/models/overview), [Reducing latency](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-latency) | **Not independently comparable to Jev's number**, and Anthropic doesn't publish one to compare against — consistent with the companion notes' point that no apples-to-apples Haiku-vs-Jev benchmark exists anywhere. |
| Pricing: $0.042/MTok in, $0 out (Jev, vendor-set, from the companion notes) | Haiku 4.5: $1/MTok in, $5/MTok out; batch: $0.50/$2.50; cache read: $0.10/MTok | [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) | **~24x Jev's input price before counting any output tokens at all** — even a one-token classification answer costs real output-token money on Haiku, where Jev's is advertised as free. This gap is architectural (generative vs. non-generative), not closeable by prompt engineering. |
| Context/output limits | 200K context, 64K max output, no `effort` parameter support | [Haiku 4.5 model page](https://platform.claude.com/docs/en/models/haiku-4-5/overview) | Plenty for any classification-shaped decision task; not a constraint. |

## 3. What a Haiku primitive would actually be, positioned honestly

A Haiku-based `Choice`/`Noul` tool call, done right (forced `tool_choice`, `strict: true`,
`thinking` left off, a tight `max_tokens`, a narrow enum `input_schema`), gives you:

- **A real structural guarantee** that the answer is one of N declared options — not "the model
  was told to only answer X or Y," but the same class of sampling-time enforcement Jev claims.
- **A faster, cheaper call than a normal unconstrained Claude request** for the same task, for
  the ordinary reason forcing a short structured answer is always faster/cheaper than an
  open-ended one (Anthropic's own latency-reduction guide says as much) — not because it stops
  being autoregressive. It still attends over the full input context before emitting its (short)
  answer; it does not skip that step the way TypeSafe describes Jev doing.
- **No calibrated confidence.** If a "confidence" field is wanted, it must be labeled clearly as
  model self-report, not measurement — and per this repo's own Rule 14, a component that can't
  back a score with real data should return `ข้อมูลไม่เพียงพอ` rather than manufacture one.

This is a legitimate, buildable thing. It is not "a Jev clone" in the sense of matching Jev's
architecture or its headline economics — it's "a cheap, schema-locked Claude call," which is a
narrower and more honest description.

## 4. Design options

**Option A — Document the pattern, ship no code.** A short reference doc
(e.g. `docs/reference/haiku-decision-calls.md`) that states: when a skill needs an inline
yes/no or pick-one decision mid-flow, dispatch a fresh Agent with `model: "haiku"` (or the raw
Messages API if outside Claude Code), `tool_choice` forcing a single tool, `strict: true`, no
`thinking`, and cites the caveats above (thinking-mode restriction, no confidence field, real
cost/latency positioning vs. a plain call). No new runtime surface; nothing to maintain; nothing
enforces its use, so a skill author has to know to look it up.
- Cost: near-zero to build. Risk: low. Payoff: only realized once someone reads and uses it.

**Option B — A reusable schema/brief library.** Add a small directory (parallel to
`skills/workflow/idea-audit/references/`) with a couple of pre-built `input_schema` JSON files
(`choice.schema.json`, `noul.schema.json`) and a short brief template mirroring
`attacker-brief.md`'s `## Output` section, that any skill's brief can reference by path instead
of re-deriving the schema each time.
- Cost: moderate (a handful of small, reviewable files). Risk: low-moderate — dead code if no
  skill references it. Payoff: real, but still needs a consumer to justify existing; per
  `docs/reference/skill-authoring-conventions.md`'s no-op test, a reusable artifact nothing
  references is prunable regardless of how well-built it is.

**Option C — A new thin skill (e.g. `mh:decide`).** Exposes "make a fast, schema-locked Haiku
decision call" as an invocable capability, callable the way `codex:rescue` is invoked from
another skill's brief.
- Cost: highest — a new skill needs the evals-first justification this repo's own authoring
  doctrine requires ("before drafting a body, run the task without the skill and write down 3
  concrete requests it should handle. If Claude already clears all 3, the skill should not
  exist" — `docs/reference/skill-authoring-conventions.md`). **No such consumer exists in this
  repo today.** Building this now would be the exact kind of speculative surface the
  composer-not-creator and skill-authoring docs argue against.

## Recommendation

Ship **Option A only**, now. Do not build Option B or C speculatively — there is currently no
skill in this repo whose `Done-when` names "an inline cheap classification call," and mh's own
doctrine (evals-first skill authoring, YAGNI) says don't build for a consumer that doesn't exist
yet. Revisit B/C the first time a real skill's design names this need concretely; at that point,
build the narrowest option that unblocks it (most likely B, a reusable schema/brief pair scoped
to that skill's actual shape, not a general-purpose new skill).

## Staged plan for Option A

1. Write `docs/reference/haiku-decision-calls.md`: states the pattern (forced `tool_choice` +
   `strict: true` + `thinking` off + tight `max_tokens`, dispatched via a fresh Agent with
   `model: "haiku"`), the two hard caveats (thinking-mode restriction breaks forced tool use;
   no logprobs/confidence field exists — self-reported "confidence" must be labeled as such or
   omitted per Rule 14), and one minimal worked example (a schema + `tool_choice` JSON snippet,
   not a runnable script). Cites the primary sources in the table above.
   Done-when: the file exists, every claim in it traces to a URL fetched in this pass or to a
   file read directly in this repo (no restated vendor claim treated as fact).
2. No step 2. Do not wire it into any skill, gate, or `CLAUDE.md` map entry in this pass — that
   would be building the consumer speculatively too. Leave it as a reference doc future skill
   authors can cite, the same role `spawn-brief.md` plays for subagent dispatch shape.

## Sources

- [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) — Haiku 4.5 $1/$5 MTok,
  batch $0.50/$2.50, cache read $0.10/MTok, tool-use system-prompt token overhead table
- [Define tools — Forcing tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#forcing-tool-use) —
  `tool_choice` types (`auto`/`any`/`tool`/`none`), the manual-extended-thinking restriction table
- [Strict tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use) —
  grammar-constrained sampling guarantee, `strict: true`, JSON Schema subset
- [Models overview](https://platform.claude.com/docs/en/about-claude/models/overview) — lineup
  comparison table, comparative latency, context/output limits
- [Claude Haiku 4.5 model page](https://platform.claude.com/docs/en/models/haiku-4-5/overview) —
  model ID `claude-haiku-4-5-20251001`, "manual extended thinking, not adaptive," specs
- [Reducing latency](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-latency) —
  model choice / output length / streaming as the only documented latency levers; no absolute
  ms figures published
- [Messages API reference](https://platform.claude.com/docs/en/api/messages) — confirmed no
  logprobs/token-probability parameter or field exists
- This repo: `skills/review/deep-audit/references/checker-output-schema.json`,
  `skills/workflow/idea-audit/references/attacker-brief.md`,
  `skills/workflow/idea-audit/references/attacker-output-schema.json`,
  `docs/reference/spawn-brief.md`, `docs/reference/codex-integration-map.md`,
  `docs/reference/skill-authoring-conventions.md`, `docs/reference/composer-not-creator.md`,
  `hooks/gates/*.py`, `hooks/stop/cost-tracker.sh`, `skills/workflow/ideate/SKILL.md`
- Companion notes: `docs/research/typesafe-ai-system-one-jev-2026-09-18.md`,
  `docs/research/jev-architecture-unmasked-archerhume-2026-09-18.md`
