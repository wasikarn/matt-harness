---
name: task-prep
description: "Prep-map a draft task against the handoff template; fill gaps; verify fresh-context; emit paste-ready. Use when tackling non-trivial tasks; don't use for ideas or one-liners."
argument-hint: "[draft prompt or 'interview me']"
allowed-tools: AskUserQuestion Agent Read Glob Grep
metadata:
  origin: kbg-native
---

## Design checks (matt-pocock authoring doctrine)

Run before publishing. Each item must be checkable. See CLAUDE.md § "Skill authoring doctrine".

- [x] **Leading word** — "Prep-map" recruits the map-against-structure prior.
- [x] **≤25 words** in description (25).
- [x] **One trigger** per branch in description (use: non-trivial task; don't: idea, one-liner).
- [x] **Completion criterion** — "a paste-ready prompt whose `<done-when>` a context-poor reader can name + a check Claude can run."
- [x] **No-op test** — a genuinely gap-free draft → no manufactured or padding edits; emit unchanged. Field-complete isn't gap-free — Step 3.5 or the Step 9 checker surfacing a real latent gap on a 9-field-filled draft is the skill working as intended, not a broken guarantee.
- [x] **Two-cut check** — routing gate (router-first) + template-fill are sequential cuts that each earn their keep; not split by invocation.
- [x] **Failure mode** named inline at the drift step (padding, idea-forcing, re-asking filled fields).
- [x] **Provenance** — `metadata.origin: kbg-native` (ECC `prompt-optimizer` contributed the Phase-0 stack-sniff skeleton + consult-only invariant; adapted, not copied).
- [x] **Named Model footer** — load-bearing reasoning (gap prioritization, done-when shape synthesis); footer below.
- [x] **Suggested next step** — workflow skill run as a discrete step; passive footer below.

# Task Prep

Map a draft task prompt against the 9-field handoff template (`docs/reference/task-handoff-template.md`), ask the user for any load-bearing gap, verify the assembled prompt with a fresh-context agent, then emit a paste-ready prompt. The point is to front-load the context Claude Code can't infer on the first pass — fewer "I forgot to mention…" rounds, less context pollution.

**When to use:** before sending a non-trivial task (multi-file, unfamiliar code, uncertain approach, feature spec) to a Claude Code turn. User invokes `/kbg:task-prep <draft>` or `/kbg:task-prep` then pastes.

**When NOT to use:** ideas / tech-choices without a task ("we should add X", "I want to use Effect-TS for…") → `mattpocock-skills:grilling`. ≥2 unrelated tasks in one prompt → `kbg:orchestrate`. A review request → `kbg:review-pr`. A ship request → `/ship`. A one-line fix you could describe the diff of in one sentence → skip the scaffold entirely (a precise sentence beats a filled scaffold). A hypothesis-as-task with no repro ("I think there's a race, fix it") → `mattpocock-skills:diagnosing-bugs`.

This skill **routes first, fills second.** ~7 of 30 real-world cases never enter the 9-field flow — they want a different surface. Detect them at the gate and redirect; don't cram an idea through the template.

---

## Procedure

### Step 1 — Read input

Read `$ARGUMENTS`. If empty, `AskUserQuestion`: "Paste your draft task prompt, or say 'interview me' if you want me to surface the questions first."

**Success criterion:** you have a block of draft text (or an explicit "interview me") to work from.

### Step 2 — Routing gate (run BEFORE the template)

Evaluate the draft's shape. If any of these match, **stop and redirect** via the Suggested next step footer — do not proceed to Step 3:

- **Idea-shape** — no outcome, "we should…", a tech-choice with no task → `mattpocock-skills:grilling`.
- **≥2 unrelated tasks** — "add X + fix Y + update Z" → `kbg:orchestrate`.
- **Review-shape** — "review the PR…", "look at the diff for…" → `kbg:review-pr`.
- **Ship-shape** — "ship the…", "merge the…" → `/ship`.
- **Hypothesis-as-task, no repro** — "I think there's a race/bug, fix it" with no repro or artifact → surface the no-repro-no-fix gate; suggest `mattpocock-skills:diagnosing-bugs`.
- **Trivial / describable diff in one sentence** — "rename FooBar to FooBaz in src/types.ts" → tell the user a one-line precise sentence beats the scaffold; stop.
- **TDD-shape** — "write a failing test that reproduces X, then fix it" → note `mattpocock-skills:tdd` owns the `<done-when>` shape; continue prep but shape done-when as red→green→regression, and suggest `mattpocock-skills:tdd` for the implementation turn.

**Failure mode at this step:** forcing an idea or a trivial fix through the 9-field scaffold — that's the "kitchen-sink session" / over-processing the template exists to prevent. Route, don't fill.

**Success criterion:** either redirected (done), or the draft is a genuine single non-trivial task and you proceed.

### Step 3 — Phase 0: stack sniff

Read the nearest manifest present (`package.json` / `go.mod` / `pyproject.toml` / `pubspec.yaml` / `Cargo.toml`) — `CLAUDE.md` (project + global) is already in your session context from SessionStart injection, so don't re-Read it. Note the detected stack (AdonisJS, Drizzle, Effect-TS, Hono, Flutter, LangGraph, gRPC, MySQL/MariaDB…). This informs reference-finding (Step 5) and done-when shape (Step 6).

**Success criterion:** you can name the stack in one phrase, or "generic / no manifest."

### Step 3.5 — Requirement cross-check (opt-in — Jira ticket, or a real feature/behavior requirement)

Two independent detect paths (METHODOLOGY Rule 3 — interrogate the claim, not just the prompt shape). Neither blocks Step 4 if it doesn't fire.

**Jira path — detect**: the draft contains the case-insensitive substring `jira` **and** a ticket-key-shaped token (`[A-Z][A-Z0-9]*-\d+`, e.g. `TP-871`) — requiring both avoids false-triggering on unrelated tokens shaped like `UTF-8`/`ISO-8601`. If detected:
1. Fetch the ticket via the **`jira-acli:acli` skill** — never a raw `acli` command or a direct `mcp__*atlassian*`/`mcp__*Rovo*` call (CLAUDE.md's global routing rule). `jira-acli` is a separate plugin; if it isn't installed, treat that the same as a fetch failure below — note it, don't fall back to a raw call. Fetch failure (bad key, no access, plugin missing) → note it inline and skip to Step 4 unaffected; an unresolved ticket reference never blocks task prep.
2. **Topical sanity check**: does the fetched summary plausibly match what the draft says the ticket is about? A wrong-but-valid key (typo, copy-paste from another task) fetches cleanly and looks like success — nothing else catches this. Mismatch → treat the same as a fetch failure: note it inline, skip dispatch, and add "ticket key resolves but its content doesn't match the draft" to Step 6's `open_questions` batch directly — there's no requirement-analyst report to draw from since dispatch was skipped, but Step 6 treats this one ad-hoc note the same as a dispatched `open_questions` entry. Soft check, not a hard gate — a false positive just falls back to draft-only prep, same cost as any other fetch failure.
3. Match confirmed (or no mismatch found) → dispatch `requirement-analyst` (Agent tool) with the fetched body as its prompt. Capture: `business_trace`, `functional_requirements`, `non_functional_requirements`, `acceptance_criteria`, `edge_cases_missing`, `open_questions`.

**Non-Jira path — detect**: no ticket reference, but the draft states a real feature or behavior requirement (new user-facing capability, a rule the system must enforce, a workflow to support) — not a purely mechanical change (rename, typo, config bump, dependency version). **Bias toward skip on any doubt** — this path spawns a second Opus agent on top of Step 6's verifier, so it only earns its cost when there's an actual requirement to interrogate, not just a task to execute. If detected: dispatch `requirement-analyst` (Agent tool) with the **draft text itself** as its prompt (no fetch — the draft is the source). Capture the same fields as the Jira path.

Either path: hold the report for Step 4/5/6 below — it supplies **candidate** values, it does not fill anything by itself (Step 7's "never overwrite a filled field" still applies).

**Success criterion:** either skipped (no ticket reference and no standalone feature requirement), or you're holding a requirement-analyst report to draw on below.

### Step 4 — Map to the 9 fields

The 9 fields and their intent (canonical source: `docs/reference/task-handoff-template.md` § "The template" in the plugin cache — read it only if you need the worked example; the one-liners below are enough to map):

- `<task>` — the outcome in one sentence, not the steps.
- `<context>` — why this matters / the situation (lets Claude generalize, skip dead ends).
- `<scope>` — files/areas in + explicitly out + `@`-refs to target files.
- `<reference>` — an existing file/test/pattern to match.
- `<artifacts>` — paste the error/log/screenshot directly, or `@file` (don't describe).
- `<done-when>` — the check Claude can run itself + a measurable target when perf/coverage is the goal. **The one field that always costs if missing.**
- `<constraints>` — only rules that differ from defaults (rest is noise).
- `<output>` — format/length/audience for the answer.
- `<edge-cases>` — gotchas you foresee, or "interview me for edge cases first."

For each field, mark: **present** (in the draft) / **derivable** (from code or CLAUDE.md) / **absent** (a real gap). **Present** doesn't mean adequate — whether a present field is too thin to act on is Step 9's call, not this step's; the assembler is the wrong reader to catch its own vagueness.

**Success criterion:** a 9-row map with present/derivable/absent per field.

### Step 5 — Auto-fill where cheap (don't ask what you can find)

- `<reference>`: `Glob` for an existing pattern (a sibling migration, an existing middleware, a parallel route) and **propose it** rather than asking. If Glob finds a strong candidate, mark `<reference>` derivable and cite the path.
- `<scope>`: pull in/out from `@`-refs already in the draft.
- `<context>` / `<constraints>`: if obvious from CLAUDE.md or the draft, mark derivable; do not ask.
- **If Step 3.5 ran**: `<context>` derives from `business_trace`; `<edge-cases>` derives from `edge_cases_missing`; `<done-when>` candidates derive from `acceptance_criteria` entries marked `testable`/`testable_with_assumption` (state the assumption inline if present) — check these before falling through to Step 6's ask.

**Failure mode at this step:** asking the user what the codebase already answers — wastes their time and signals you didn't look. Read first, ask second (same rule as `mattpocock-skills:grilling`).

**Success criterion:** every field that can be derived without the user is derived; only true gaps remain.

### Step 6 — Ask for load-bearing gaps (`AskUserQuestion`, batched ≤4 option-sets)

Ask only for **absent** fields that actually cost the user. Priority order — `<done-when>` is the single most expensive gap (a missing check makes the user the verification loop):

1. **`<done-when>` missing → ask for a runnable check, and synthesize a shape by task type:**

   | Task type | done-when shape | Example |
   |---|---|---|
   | Test-authoring | passes + covers the named branch | "test fails on the bug, passes on the fix; covers the retry-transient branch" |
   | Perf / size | a measurable number | "bundle < 200KB; show the diff of what you removed" |
   | Bug with repro | reproducible-repro → green | "write a failing repro, fix, run `npm test -- src/auth`, confirm green" |
   | Behavior change | distinguishes-or-it-doesn't | "transient errors stop retrying after N; persistent errors still retry — the test must change result when the fix is reverted" |
   | Doc / explanation | colleague-test | "a reader unfamiliar with the pipeline can trace a video end-to-end from this doc" |

   If none of the above fits, ask the user directly for "the check Claude can run itself to know it's done."

2. **`<scope>` in/out missing → ask.**
3. **`<reference>` missing and Glob found none → ask** ("an existing file/test/pattern to match?").
4. **`<artifacts>` missing on a bug/error task → ask** for a paste or `@file` (stack trace, log, screenshot).

**If Step 3.5 ran**, its `open_questions` are load-bearing gap candidates too — a ticket ambiguity a downstream implementer would hit is exactly the class of gap this step exists to surface before send, not after. Fold them into this batch alongside the four above. **If that pushes the total past 4 ask-worthy fields** (the four above, plus Step 3.5's `open_questions` and `<edge-cases>` below), the ≤4 batch cap forces a cut. Extend the priority order past `<artifacts>`: Step 3.5 `open_questions` next (a concrete, ticket-sourced ambiguity outranks generic foresight-gathering), then `<edge-cases>` last. Ask the top 4, note in the emitted prompt that N more remain open, and pick them up in the re-verify pass (Step 10) — don't silently drop them.

**Skip** `<context>`/`<constraints>`/`<output>`/`<edge-cases>` if obvious from input or CLAUDE.md — don't pad. Listing rules Claude already follows makes them noise it learns to ignore (failure mode: over-specified constraints).

**`<edge-cases>`:** if the user can't name any, offer "interview me for edge cases first" as an `AskUserQuestion` option — surfacing them before coding is cheaper than discovering them after a wrong implementation.

**Failure mode at this step:** padding obvious fields to seem thorough — the template's §"don't pad" rule. Empty fields are fine; a missing `<done-when>` is the one that costs.

**Success criterion:** every load-bearing gap has a user answer or a derived value; no field was re-asked that the user already filled.

### Step 7 — Respect filled fields

Never re-ask a field the user already provided. Never overwrite their wording. If they pasted a full template, the only thing you add is what Step 5 derived and what Step 6 explicitly asked for.

### Step 8 — Assemble the prompt

Assemble in the 9-field XML shape (the field intents are in Step 4; full worked example in `docs/reference/task-handoff-template.md`). Use the **minimal 2-field version** (`<task>` + `<done-when>`) when scope is obvious and the fix is small. Keep empty fields out rather than padding them with "[optional]".

**Success criterion:** a single code-block prompt in the template's XML shape, minimal or full as appropriate.

### Step 9 — Dispatch the verifier (fresh context)

Dispatch the `task-prep-checker` agent (Agent tool) with the assembled prompt as its input. It runs the golden-rule colleague test from a fresh context and returns a structured gap list. **Await its result** — do not emit until it returns.

The maker never grades its own work: this skill assembled the prompt; the checker grades it from a clean context (verifier-separation). A self-review here would be "two optimists agreeing."

### Step 10 — Handle the verdict

- `verdict: ready` → proceed to Step 11.
- `verdict: gaps` → `AskUserQuestion` to fill each returned gap (use the checker's `suggested_question_for_user`), re-assemble, dispatch one re-verify. One re-verify is enough; if gaps persist after that, emit with the remaining gaps flagged for the user rather than loop indefinitely.

**Success criterion:** the verifier's last verdict is `ready`, or remaining gaps are explicitly flagged in the output.

### Step 11 — Emit the paste-ready prompt

Emit the final prompt as a code block. **No file write** — the user pastes it into their next Claude Code turn. Do not auto-invoke any downstream skill with it (no-model-self-start); the Suggested next step footer tells the user what to run, passively.

**Success criterion:** the user has a copy-pasteable prompt in chat.

### Step 12 — Pre-send checklist

State the 4 golden-rule questions (template § "Pre-send checklist") and confirm each is answerable from the emitted prompt:

1. What does "done" look like? (a check in `<done-when>`)
2. Which files are in / out of scope? (`<scope>`)
3. Do they have the actual artifact, or only a description? (`<artifacts>`)
4. Do they know what pattern to follow? (`<reference>`)

Any "no" → that field should have been filled in Step 6; surface it now rather than ship a prompt that makes the user the verification loop. The most expensive "no" is #1.

---

## Failure Modes to Avoid

- **Forcing an idea through the template.** "We should add notifications" is an idea, not a task. Route to `mattpocock-skills:grilling`; don't fill 9 fields of a thing that hasn't been decided yet.
- **Padding obvious fields.** Empty fields are fine. A `<constraints>` that restates rules Claude already follows is noise it learns to ignore.
- **Re-asking filled fields.** If the user pasted a full template, respect it — add only derivations and explicitly-asked gaps.
- **Treating the verifier as an editor.** The checker returns gaps; it never edits, never invents. If it returns `ready`, emit unchanged — do not "improve" a clean prompt.
- **Infinite prep.** One re-verify max. A prompt can always be tightened further; ship it with remaining gaps flagged rather than loop forever.
- **Auto-chaining downstream.** This skill emits a prompt; it does not invoke `/fix-bug` / `mattpocock-skills:tdd` / etc. with it. The user pastes it; the footer suggests next steps passively.

---

## Named Model

Load-bearing reasoning in this skill: **gap prioritization** (which absent field actually costs the user — `<done-when>` ranks above `<output>`) and **done-when shape synthesis** (mapping a task type to a check shape). The lenses it draws on (cc-thinking-skills):

- *steel-manning* — assemble the strongest version of the user's intent before probing gaps, not the laziest reading.
- *socratic* — the gap questions expose what the user hadn't yet realized was load-bearing.
- *debiasing* — the fresh-context checker is the bias control: the assembler's "looks complete to me" is exactly the optimism a separate context must check.

Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`. The footer is a scaffold + catalog pointer, not proof of correctness.

---

## Suggested next step:

- Idea-shape detected at the gate → `mattpocock-skills:grilling` (stress-test the idea before it becomes a task).
- ≥2 unrelated tasks detected → `kbg:orchestrate` (route the request stack).
- Review-shape / Ship-shape / no-repro detected → `kbg:review-pr` / `/ship` / `mattpocock-skills:diagnosing-bugs` respectively.
- Prompt emitted and `verdict: ready` → paste it into a fresh Claude Code turn (this skill does not auto-invoke the downstream task).
- Task is TDD-shaped → `mattpocock-skills:tdd` for the implementation turn (the emitted `<done-when>` already carries the red→green shape).