# Official Anthropic docs vs. kbg-harness — best-practices / prompt-library / costs (2026-08-20)

**Sources:** `code.claude.com/docs/en/best-practices.md`, `code.claude.com/docs/en/prompt-library.md`,
`code.claude.com/docs/en/costs.md` — all fetched live 2026-08-20. Different from this session's
prior 4 audits (llm-wiki articles, single-author, unreproduced): these are Anthropic's own live
platform docs, one of which (`costs.md`) had never been checked against this repo before, and the
other two had only been checked narrowly — against exactly 2 files — by
`task-prep-audit-v0355-2026-07-07.md`. That closed audit's 8 findings are **not** re-derived here;
this cycle scopes to project-wide coverage those 2 files didn't reach.

**Verdict: mixed, not "nothing to build."** Unlike this session's 4 prior article audits, this one
produced real, small, well-evidenced fixes — implemented in this same pass — plus one corrected
memory, plus two items that are genuine trade-offs and are deferred to the user rather than decided
unilaterally.

## What was fixed in this pass

| # | File | Fix | Evidence |
|---|---|---|---|
| 1 | `commands/deep-audit.md` | Added a "zero/few findings is a valid outcome" caution after Objective 4, matching `agents/code-reviewer.md`'s "It Is Acceptable And Expected To Return Zero Findings" and `agents/blind-spot-hunter.md`'s severity-earning discipline. Framed as **parity with siblings**, not incident-driven — this session's own deep-audit run (cycle G, commit `da1e9b94`) found 4 real, verifier-confirmed citation errors, so nothing here suggests the command manufactures findings. `deep-audit.md` was simply the one report-generating surface in the fleet without this caution already stated. |  `agents/code-reviewer.md:69-77`, `agents/blind-spot-hunter.md:93-97` |
| 2 | `docs/reference/env-vars.md` | Added an `ENABLE_PROMPT_CACHING_1H` row to the Token-optimization table. Verified directly against `costs.md`'s "Why usage climbs" section before writing (see correction note below — the first draft of this row was wrong). | `code.claude.com/docs/en/costs.md`, "Cache misses" bullet |
| 3 | `docs/METHODOLOGY.md` Rule 13 | Added a bullet naming `/btw`, `/rewind`, `/compact <instructions>` as zero-context-cost native tools the context-economy rule should point to. Confirmed zero mentions of `/btw`/`/rewind` anywhere in tracked repo content (`.scratch/` hits excluded — gitignored, not doctrine) before writing. | `code.claude.com/docs/en/best-practices.md`, "Manage context aggressively" section |
| 4 | `CLAUDE.md` | Added a `# Compact instructions` block (costs.md names this exact heading/location, not METHODOLOGY.md, as the mechanism Claude Code actually looks for) — content tailored to what this session's own working pattern needs preserved: staged/committed file state, version-bump status, open plan-mode approval, verified citations. | `code.claude.com/docs/en/costs.md`, "Add custom compaction instructions" section |
| 5 | Memory `anthropic-doc-default-to-action-divergence-2026-07-06.md` | Corrected — not deleted. See "Stale memory correction" below. | — |

**Correction made mid-pass, not just reported:** the first draft of fix #2's row claimed a flat
"unset = 5-min TTL" default. Re-fetching `costs.md` directly before shipping (per this session's own
"verify technical claims before shipping" rule) found that's wrong — the lifetime is
**billing-mode-dependent**: 1 hour by default on a subscription plan, dropping to 5 minutes once
that session draws on usage credits, and 5 minutes by default on an API key or cloud provider.
`ENABLE_PROMPT_CACHING_1H=1` keeps the 1-hour lifetime while drawing on usage credits. Fixed before
commit, not after — no version of the wrong claim shipped.

## Stale memory correction (not a new finding — a correction to an existing one)

`anthropic-doc-default-to-action-divergence-2026-07-06.md` claimed Anthropic's `best-practices.md`
"biases toward action" (default-to-action framing) and that kbg's near-zero `IMPORTANT`/`YOU MUST`
usage already satisfies the doc's "dial back emphasis" advice. Neither claim survives a direct
re-read of the doc's current text:

- No "default to action" framing exists anywhere in the current doc. The closest matching passage
  argues the opposite: *"Claude stops when the work looks done... you become the verification
  loop"* — a caution about acting without a check, not a bias toward acting.
- The doc doesn't advise dialing back emphasis. It says: *"You can tune instructions by adding
  emphasis (e.g., 'IMPORTANT' or 'YOU MUST') to improve adherence."* — the opposite advice.

**What this correction does NOT claim:** whether the doc's text changed since 2026-07-06, or the
original memory mischaracterized it from the start, is not determinable — no July snapshot exists
to diff against. Say so plainly rather than picking one explanation.

**What this correction leaves open, deliberately:** kbg's near-zero emphasis-word usage was
previously read as *compliance* with a dial-back recommendation that turns out not to exist. That
doesn't make the near-zero usage wrong — it just means the "already satisfied" resolution answered
a question the doc doesn't ask. Whether kbg should lean on the emphasis lever more (because the doc
frames it as an adherence tool for CLAUDE.md-style instructions) or whether it's fine as-is (because
kbg gets adherence through deterministic hooks/gates, not model compliance, so the lever matters
less here) is genuinely unresolved. Not decided in this pass — recorded as open.

The memory's actual load-bearing claim — kbg's no-model-self-start invariant deliberately diverges
from any reading of Anthropic doctrine that would suggest auto-chaining/auto-dispatch — is a claim
about kbg's own architecture, independently verifiable, and stands unchanged.

## What's confirmed as non-issues (checked, not rebuilt)

- **`prompt-library.md`'s ~45-prompt catalog** — already fully covered.
  `docs/reference/task-handoff-template.md` cites this doc by name since its first commit
  (`3fa9f0ff`, 2026-07-07), with field-by-field and source-mapping tables tracing all 9 handoff
  fields to named patterns from it, operationalized via `skills/task-prep/SKILL.md`. Role-based
  tagging (pm/design/marketing) doesn't apply — kbg's real analog is the 9-value `bucket:`
  taxonomy, a category match for a single-operator dev-tooling fleet, not a multi-role product.
  Skill-creation-prompt is a real, named divergence (kbg's actual path is 3 gated steps, not 1
  prompt) — worth stating precisely, not a gap to close.
- **Pricing accuracy in `hooks/stop/cost-tracker.sh`** — already correct, confirmed directly
  against the live script (Haiku/Opus/Sonnet rates, Sonnet's date-gated toggle for the 2026-09-01
  price change) — the 3 stale rates `docs/research/official-docs-audit-2026-07-31.md` flagged were
  fixed sometime between that date and now.
- **MCP overhead** — a justified divergence, not a gap. kbg's qmd-first rule (`CLAUDE.md` §
  "Research: check qmd before web search") is an accuracy requirement, not a cost oversight — the
  real `qmd` CLI binary is confirmed on disk and used correctly.
- **Deterministic hooks over classifier-model auto-mode** — a considered divergence.
  `hooks/gates/` (deny) vs. `hooks/advisory/` (journal) already matches — and, per CLAUDE.md's own
  "unifying crux," exceeds in rigor — the doc's framing of hooks as guaranteed vs. CLAUDE.md as
  advisory-only.
- **Rule 13 subagent delegation** ("Delegate verbose operations to subagents") — kbg's context
  economy block already covers this and goes further (reduce-before-synthesis, big-output-to-file).
- **Extended-thinking budget guidance** (`MAX_THINKING_TOKENS`) — `docs/reference/env-vars.md`
  already states the current default (10000) correctly; no fix needed there.

## Confirmed via this session's own tool schemas, not left as an open question

Agent-dispatched research (see "How this cycle was run" below) flagged uncertainty about whether
kbg's `Agent`/`Workflow` tools even expose an `effort` parameter to route by. Checked directly
against this session's own tool schemas rather than left hedged:

- The `Workflow` tool's `agent()` helper exposes `opts.effort` (`'low' | 'medium' | 'high' |
  'xhigh' | 'max'`), inheriting the session effort when omitted.
- The `Agent` tool (used for single-subagent dispatch outside a Workflow script) has **no** `effort`
  parameter at all — its schema is `description`, `isolation`, `model`, `prompt`, `subagent_type`
  only.
- Separately, `costs.md` names a session-level `/effort` slash command (and an `/effort` setting
  inside `/model`) for tuning the *interactive session's own* reasoning effort — a third, distinct
  mechanism from either tool parameter above.

So the actual gap is narrower and more specific than "kbg has no effort doctrine": no kbg surface
documents which of these three distinct effort-control mechanisms fits which situation, and no
`agents/*.md` file or `Workflow` script in this repo currently passes `opts.effort` at all. Not
built in this pass (Rule 2 — no observed incident of a wrongly-tiered dispatch costing something),
named here so a future pass doesn't have to re-derive the schema check.

## Presented to the user, both resolved

Two findings involved either a quality-affecting behavior change or a new surface with a real
design question — not the kind of thing to flip unilaterally. Both were put to the user directly
(`AskUserQuestion`) rather than decided in this pass:

1. **`agents/summarizer.md` (bucket: utility) — routed to `model: haiku`, then quality-tested.**
   `costs.md` explicitly recommends `model: haiku` for "simple subagent tasks." It was the
   strongest currently-mis-routed candidate in the fleet (0 of 20 agents on haiku before this: 13
   sonnet, 7 opus). Because `summarizer.md`'s actual job — BLUF structuring, source-fidelity,
   density calibration — is judgment work, the user's answer was to flip it AND verify quality, not
   flip and walk away. **Verification:** dispatched a `model: haiku` agent carrying the
   summarizer's own instructions against a real source built to stress the specific failure modes
   the agent's own Phase 6 fidelity check guards against — a billing-mode-dependent range
   ("1 hour on subscription, 5 minutes once drawing on usage credits") that must not collapse into
   one number, and an explicit epistemic hedge ("not determinable... no snapshot exists to diff
   against") that must not resolve into false certainty. The haiku output preserved both: the
   conditional range stayed intact, the hedge stayed a hedge, no fact was invented, and the
   `flagged_ambiguity` field correctly named the one genuine unresolved point in the source. Model
   changed in `agents/summarizer.md` (`model: opus` → `model: haiku`).
2. **A `PreToolUse:Bash` output-filtering hook** (costs.md's worked example: rewrite `npm test` to
   failure-only output via `updatedInput`) — kbg had zero equivalent. User's answer: design it via
   plan mode first rather than skip or build ahead of a plan. Plan built with a dispatched `Plan`
   agent, fixing 3 real correctness bugs the `costs.md` example itself has along the way
   (exit-code masking by `head`, a silent-failure ambiguity between "all green" and "the hook
   broke," and an unrewritten compound-command path closing an undocumented sibling-gate
   precedence risk). Then adversarially reviewed by `kbg:plan-reviewer` before any code was
   written (required — the plan touches `hooks/gates/**`, the verifier-protected surface). The
   reviewer flagged that this repo's own docs (`worktree-guard.py`'s header comment,
   `hook-lifecycle-contracts.md` line 49) assume a raw Bash command can't be rewritten via
   `updatedInput`, contradicting the plan's premise and `costs.md`'s own worked example — but had
   no live doc access to resolve which side was right. **I then resolved it wrong.** A `WebFetch`
   call I made to check `hooks.md` returned a specific, four-bullet "only works for file-path-based
   tools... does not work for Bash" quote that I treated as an authoritative vendor citation and
   used to kill the plan. It was fabricated by the fetch tool's own summarization step — a direct
   re-fetch of the raw content (see below) shows no such text exists anywhere on that page. The
   plan was killed on a citation that doesn't exist. **The hook still wasn't built in this pass**
   (Rule 2 — no proven cost incident, and the actual question is now open, not closed), but not for
   the reason originally recorded. See "The `updatedInput`-on-Bash question is actually unresolved"
   below for what's real, and "A fabricated citation shipped and was pushed" for how this happened
   and what it cost.

## The `updatedInput`-on-Bash question — evidence now leans toward "it works"

Three correction passes happened on this claim in one session: (1) a `WebFetch` call fabricated a
"does not work for Bash" quote that doesn't exist on the page, (2) correcting that, a re-check
described the page as "silent... appears twice, both times as a bare field name" — itself sourced
from a truncated `WebFetch` response, not the raw page, (3) this pass, based on a direct `curl`
fetch of the raw markdown (bypassing any summarizing model entirely) and a full read of the
relevant sections. What's actually on the page:

- **`updatedInput` appears 9 times** across the document, not twice — in the events-that-rewrite
  summary, the `PreToolUse` decision-control table, the `PermissionRequest` decision-control table,
  the `AskUserQuestion`/`ExitPlanMode` "allow-with-updatedinput" subsection, the `defer` round-trip
  walkthrough, and 3 JSON examples.
- **No restriction on tool type is stated anywhere.** The `PreToolUse` table's field description
  reads only: *"Modifies the tool's input parameters before execution. Replaces the entire input
  object... Combine with `\"allow\"` to auto-approve, or `\"ask\"` to show the modified input to the
  user."* Fully generic. The table's own JSON example uses a placeholder field name
  (`"field_to_modify": "new value"`), not a tool-specific one.
- **The `PermissionRequest` event's own official example rewrites a `command` field:**
  ```json
  "decision": {
    "behavior": "allow",
    "updatedInput": { "command": "npm run lint" }
  }
  ```
  This is real, current, vendor-authored evidence of `updatedInput` touching a command-shaped
  field with a shell-command value — under `PermissionRequest`, which is a **different event** from
  `PreToolUse` (the one `costs.md`'s worked example and the killed plan both used). Not fully
  conclusive for `PreToolUse` specifically, but it directly contradicts the idea that `updatedInput`
  is architecturally restricted to file-path tools — if it can rewrite a `command` field under one
  event, there's no documented reason `PreToolUse` would categorically differ.
- **`worktree-guard.py:23-26`** (commit `8818495a`, 2026-07-16) — a real, pre-existing, but
  **uncited** internal engineering assumption: *"a raw shell command's target can't be
  transparently rewritten via updatedInput."* Never checked against a vendor source when written.
  `hook-lifecycle-contracts.md:49` (commit `7ed97b22`, 2026-08-14) restates it during a
  documentation sweep, not an independent re-derivation — one origin, not two.
- **`costs.md`** — confirmed present verbatim: a worked example rewriting a Bash `command` field
  under `PreToolUse` specifically, plus a concrete verification method (`claude --debug`, look for
  `modified tool input keys: [command]` in the debug log).

Net: the only source suggesting this **doesn't** work is an uncited assumption from a month before
this session, never checked against the vendor docs. Every current vendor source either says
nothing restrictive or shows a directly analogous rewrite working. The evidence now leans toward
the mechanism working — but "leans toward" is still not "confirmed": the one thing that would
settle it is the live smoke test the original plan already specified as its own step 8 (wire the
hook behind `KBG_TEST_OUTPUT_FILTER`, run a deliberately-failing test command, check whether the
rewrite actually lands in a real session). That requires writing to `hooks/gates/**` — a decision
the user owns, not something to do unilaterally while correcting this record. **Not built in this
pass.** Rule 2 still applies (no proven cost incident) independent of how the mechanism question
resolves — but if the user wants to actually resolve it, the smoke test is now the clearly
favored next step, not a coin flip.

## A fabricated citation shipped and was pushed

The failure mode, precisely: `WebFetch`'s own tool description says it "processes the content with
a small, fast model" and returns that model's response, not raw page text. Asked whether `hooks.md`
restricts `updatedInput` to certain tool types, that intermediate model returned a specific,
well-formatted, plausible four-bullet answer — exact tool names (`Edit`, `Write`, `Delete`,
`Rename`, `Read`, `Glob`, `Grep`, `Notebook`), bold emphasis on the punchline, the shape of a real
vendor spec — that does not exist anywhere in the source document. I treated that answer as a
verbatim quote, without independently checking the raw page, and committed it into
`hook-lifecycle-contracts.md:49` as "vendor-confirmed, not just an inference." It was reviewed by
`advisor()` before that commit and endorsed as settled. It was then pushed to `origin/develop`,
publicly, in a plugin repo other people may install.

The compliance audit dispatched immediately after (see "Presented to the user" above) is what
caught it — a fresh-context verifier (`V2`) independently fetched the same page via a different
tool path (`firecrawl_scrape`, which returns raw content rather than a model summary) and found
the quote absent. I then re-fetched `hooks.md` myself with `WebFetch`, this time asking it to quote
every `updatedInput` occurrence verbatim rather than answer a yes/no question, and got a correctly
negative result on the fabricated-restriction question — but that same "verbatim quote" `WebFetch`
call *itself* under-reported the page (claimed 2 occurrences of "bare field name"; a direct `curl`
of the raw markdown, one more correction pass later, found 9, including a real `PermissionRequest`
example rewriting a `command` field that meaningfully changes the picture — see the section above).
Asking `WebFetch` for a verbatim quote caught the fabrication but not the truncation.

**The durable lesson, worth more than any version of the hook question:** a `WebFetch` answer is
not a primary-source quote, even when it's formatted like one and even when explicitly asked to
quote verbatim — it's a summarizing model's output over fetched (and sometimes silently truncated)
content, and it can fabricate specific, confident, well-shaped text, or under-report a long page,
without any visible sign either happened. Where a claim will be committed as a citation (not just
used to inform a judgment call), verify it through a raw-content path (`firecrawl_scrape`, or a
direct `curl`/fetch of the raw markdown) — not a `WebFetch` call at all, however it's phrased.
`advisor()`, dispatched subagents, and prior confidence in a claim don't substitute for this — the
fabricated quote passed through an `advisor()` review and a `kbg:plan-reviewer` pass (which
correctly flagged the underlying contradiction as unresolved and out of its own reach) before the
error was mine, in how I resolved it, and the truncation survived one full correction pass before
a second one caught it.

**No workaround was substituted for the hook feature itself**, independent of this correction. A
`permissionDecision: "deny"` pattern that tells Claude to re-run a filtered command itself was
considered and rejected — it would convert a silent optimization into a mandatory two-round-trip
interruption on every `npm test`/`pytest`/`go test` call, in a public plugin, for a Rule-2 item
with no observed cost incident behind it yet. The feature is dropped, not redesigned, and the
mechanism question stays open per the section above.

## How this cycle was run

3 fresh-context `general-purpose` agents dispatched in parallel, each scoped to one source doc and
given explicit "already known, don't re-derive" context (the closed task-prep audit's 8 findings,
the already-fixed pricing, the known 3-channel char-count baseline) to prevent wasted
re-investigation. `advisor()` consulted before writing this document — its 4 corrections (don't
overclaim what changed in the source doc; verify the `effort` finding against this session's own
tool schemas rather than ship the agent's hedge; trim the user-facing decision menu from 4 items to
the 2 genuine trade-offs; frame the deep-audit fix as sibling-parity, not incident-driven) are
incorporated directly into this document and the fixes above, not treated as a separate pass.

## Bottom line

Three of five candidate fixes were small, well-evidenced, and low-risk enough to implement
unilaterally (deep-audit parity caution, env-vars.md cache-lifetime row, Rule 13 + CLAUDE.md's
Compact instructions block). One existing memory needed correction, not deletion — its core claim
survives, its supporting citation didn't. Two items involved either unmeasured quality risk or
public-plugin blast-radius considerations wide enough to ask rather than decide — both were put to
the user rather than decided unilaterally. One shipped: `summarizer.md` on haiku, with a real
quality check behind it, not a flip-and-walk-away.

The other — the output-filter hook — did **not** ship, correctly, but the path there was not clean.
The plan-mode design process the user asked for worked on its first layer: adversarial
`kbg:plan-reviewer` review before any code existed caught a real contradiction between the plan's
premise and this repo's own docs, before a single line of hook code was written. It did **not**
work on its second layer: resolving that contradiction against a live vendor source took three
attempts. The first, via `WebFetch`, fabricated a "does not work for Bash" quote and shipped it as
"vendor-confirmed." The second, correcting that, relied on a `WebFetch` response that had silently
truncated the page and under-reported it. The third — a direct `curl` of the raw markdown, no
summarizing model in the loop — is what actually settled it: no restriction exists anywhere on the
page, and a real vendor example rewrites a `command` field under a sibling event. Net effect: the
*decision* not to build the hook stayed the same throughout (Rule 2 — no proven incident — was
never satisfied regardless of the mechanism question), but the *reasoning* recorded for it flipped
twice before landing on "the evidence leans toward this working, unconfirmed without a live test."
The actual load-bearing deliverable from this branch of work isn't the hook question at all — it's
"A fabricated citation shipped and was pushed" above, and the fact that catching it once (the
fabrication) wasn't enough to catch a second, quieter error (the truncation) in the same claim.
