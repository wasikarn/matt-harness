---
name: task-prep
description: "Prep-map a draft task against the handoff template; fill gaps; verify fresh-context; emit paste-ready. Use when tackling non-trivial tasks; don't use for ideas or one-liners."
bucket: workflow
argument-hint: "[draft prompt or 'interview me']"
allowed-tools: AskUserQuestion Agent Read Glob Grep
metadata:
  origin: kbg-native
model: inherit
effort: high
---

## Design checks (matt-pocock authoring doctrine)

Run before publishing. Each item must be checkable. See CLAUDE.md § "Skill authoring doctrine".

- [x] **Leading word** — "Prep-map" recruits the map-against-structure prior.
- [x] **≤25 words** in description (25).
- [x] **One trigger** per branch in description (use: non-trivial task; don't: idea, one-liner).
- [x] **Completion criterion** — "a paste-ready prompt whose `<done-when>` a context-poor reader can name + a check Claude can run."
- [x] **No-op test** — a genuinely gap-free draft → no manufactured/padding edits; emit unchanged. Field-complete is not gap-free — Step 3.5/9 surfacing a real latent gap on a filled draft is the skill working as intended, not a broken guarantee.
- [x] **Two-cut check** — routing gate (router-first) + template-fill are sequential cuts, each earning its keep; not split by invocation.
- [x] **Failure mode** named inline at the drift step (padding, idea-forcing, re-asking filled fields).
- [x] **Provenance** — `metadata.origin: kbg-native` (ECC `prompt-optimizer`: Phase-0 stack-sniff skeleton + consult-only invariant, adapted not copied).
- [x] **Named Model footer** — load-bearing reasoning (gap prioritization, done-when shape synthesis); footer below.
- [x] **Suggested next step** — workflow skill run as a discrete step; passive footer below.

# Task Prep

Map a draft task against the 9-field handoff template (`docs/reference/task-handoff-template.md`), ask for load-bearing gaps, verify with a fresh-context agent, emit a paste-ready prompt — front-loads context Claude Code can't infer on the first pass, for fewer "I forgot to mention…" rounds.

**When to use:** before sending a non-trivial task (multi-file, unfamiliar code, uncertain approach, feature spec). Invoke `/kbg:task-prep <draft>` or `/kbg:task-prep` then paste.

**When NOT to use:** an idea, ≥2 unrelated tasks, a review/ship request, a no-repro bug hypothesis, or a one-line fix — Step 2's routing gate below covers each redirect in full.

This skill **routes first, fills second.** ~7 of 30 real-world cases never enter the 9-field flow — they want a different surface. Detect them at the gate and redirect; don't cram an idea through the template.

---

## Procedure

### Step 1 — Read input

Read `$ARGUMENTS`. If empty, `AskUserQuestion`: "Paste your draft task prompt, or say 'interview me' to surface the questions first."

**Success criterion:** you have a block of draft text (or an explicit "interview me") to work from.

### Step 2 — Routing gate (run BEFORE the template)

Evaluate the draft's shape. If any of these match, **stop and redirect** via the Suggested next step footer — do not proceed to Step 3:

- **Idea-shape** — no outcome, "we should…", a tech-choice with no task → `mattpocock-skills:grilling`.
- **≥2 unrelated tasks** — "add X + fix Y + update Z" → `kbg:orchestrate`.
- **Review-shape** — "review the PR…", "look at the diff for…" → `kbg:review-pr`.
- **Ship-shape** — "ship the…", "merge the…" → `/ship`.
- **Hypothesis-as-task, no repro** — "I think there's a race/bug, fix it" with no repro or artifact → surface the no-repro-no-fix gate; suggest `mattpocock-skills:diagnosing-bugs`.
- **Trivial / describable diff in one sentence** — "rename FooBar to FooBaz in src/types.ts" → tell the user a one-line precise sentence beats the scaffold; stop.
- **TDD-shape** — "write a failing test that reproduces X, then fix it" → `mattpocock-skills:tdd` owns the `<done-when>` shape; continue prep, shape it red→green→regression, suggest `mattpocock-skills:tdd` for the implementation turn.

**Failure mode at this step:** forcing an idea or a trivial fix through the 9-field scaffold — that's the "kitchen-sink session" / over-processing the template exists to prevent. Route, don't fill.

**Success criterion:** either redirected (done), or the draft is a genuine single non-trivial task and you proceed.

### Step 3 — Phase 0: stack sniff

Read the nearest manifest present (`package.json` / `go.mod` / `pyproject.toml` / `pubspec.yaml` / `Cargo.toml`) — `CLAUDE.md` (project + global) already in context from SessionStart, don't re-Read. Note the stack (AdonisJS, Drizzle, Effect-TS, Hono, Flutter, LangGraph, gRPC, MySQL/MariaDB…); informs Step 5 reference-finding, Step 6 done-when shape.

**Success criterion:** you can name the stack in one phrase, or "generic / no manifest."

### Step 3.5 — Requirement cross-check (opt-in — Jira ticket, or a real feature/behavior requirement)

See `references/requirement-cross-check.md` for the full procedure (Jira-path and
non-Jira-path detect conditions, the topical sanity check, and what each path
captures for Step 4/5/6 below).

### Step 4 — Map to the 9 fields

The 9 fields and their intent (canonical: `docs/reference/task-handoff-template.md` § "The template" — read only for the worked example; the one-liners below are enough to map):

- `<task>` — the outcome in one sentence, not the steps.
- `<context>` — why this matters / the situation (lets Claude generalize, skip dead ends).
- `<scope>` — files/areas in + explicitly out + `@`-refs to targets.
- `<reference>` — an existing file/test/pattern to match.
- `<artifacts>` — paste the error/log/screenshot directly, or `@file` (don't describe).
- `<done-when>` — the check Claude can run itself + a measurable target when perf/coverage is the goal. **The one field that always costs if missing.**
- `<constraints>` — only rules that differ from defaults (rest is noise).
- `<output>` — format/length/audience.
- `<edge-cases>` — gotchas you foresee, or "interview me for edge cases first."

For each field, mark: **present** (in draft) / **derivable** (from code or CLAUDE.md) / **absent** (a real gap). Present is not adequate — a too-thin field is Step 9's call, not this step's; the assembler can't catch its own vagueness.

**Success criterion:** a 9-row map with present/derivable/absent per field.

### Step 5 — Auto-fill where cheap (don't ask what you can find)

- `<reference>`: `Glob` for an existing pattern (sibling migration, middleware, parallel route), **propose it** rather than asking. Strong candidate → mark derivable, cite the path. Multiple → name the pick and why (recent, closer in tree, better coverage) — don't silently take the first hit.
- `<scope>`: pull in/out from `@`-refs already in the draft.
- `<context>` / `<constraints>`: if obvious from CLAUDE.md or the draft, mark derivable; do not ask.
- **If Step 3.5 ran**: `<context>`←`business_trace`, `<edge-cases>`←`edge_cases_missing`, `<done-when>` candidates←`acceptance_criteria` entries marked `testable`/`testable_with_assumption` (state the assumption inline) — check before Step 6's ask.

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

**If Step 3.5 ran**, fold `open_questions` into this batch; a flagged `riskiest_assumption` outranks the generic four. Past 4 fields: `<artifacts>` → `riskiest_assumption` → `open_questions` → `<edge-cases>`. Ask the top 4, note N remain open, pick up in Step 10's re-verify — don't silently drop them. Rationale: `references/requirement-cross-check.md`.

**Skip** `<context>`/`<constraints>`/`<output>`/`<edge-cases>` if obvious from input or CLAUDE.md — don't pad. Rules Claude already follows become noise it learns to ignore (over-specified constraints).

**`<edge-cases>`:** if the user can't name any, offer "interview me for edge cases first" as an `AskUserQuestion` option, effect stated in the text (e.g. "one short Q&A round before assembly — catches gotchas before code, costs one turn"). Surfacing them before coding beats a wrong implementation.

**Failure mode at this step:** padding obvious fields to seem thorough — the template's §"don't pad" rule. Empty fields are fine; a missing `<done-when>` is the one that costs.

**Success criterion:** every load-bearing gap has a user answer or a derived value; no field was re-asked that the user already filled.

### Step 7 — Respect filled fields

Never re-ask a field the user already provided. Never overwrite their wording. If they pasted a full template, the only thing you add is what Step 5 derived and what Step 6 explicitly asked for.

### Step 8 — Assemble the prompt

Assemble in the 9-field XML shape (field intents in Step 4; worked example in `docs/reference/task-handoff-template.md`). Use the **minimal 2-field version** (`<task>` + `<done-when>`) when scope is obvious, fix is small. Keep empty fields out — don't pad with "[optional]".

**Success criterion:** a single code-block prompt in the template's XML shape, minimal or full as appropriate.

### Step 9 — Dispatch the verifier (fresh context)

Dispatch the `task-prep-checker` agent (Agent tool) with the assembled prompt as input. It runs the golden-rule colleague test from a fresh context, returns a structured gap list. **Await its result** — don't emit until it returns.

The maker never grades its own work: this skill assembled the prompt; the checker grades it from a clean context (verifier-separation). A self-review here would be "two optimists agreeing."

### Step 10 — Handle the verdict

- `verdict: ready` → proceed to Step 11, emitting unchanged. The checker returns gaps; it never edits or invents — don't treat it as an editor and "improve" a clean prompt.
- `verdict: gaps` → `AskUserQuestion` to fill each gap (checker's `suggested_question_for_user`), re-assemble, dispatch one re-verify. One re-verify is enough; if gaps persist, emit with remaining gaps flagged rather than loop indefinitely.

**Success criterion:** the verifier's last verdict is `ready`, or remaining gaps are explicitly flagged in the output.

### Step 11 — Emit the paste-ready prompt

Emit the final prompt as a code block. **No file write** — the user pastes it into their next turn. Don't auto-invoke any downstream skill with it (no-model-self-start); the Suggested next step footer tells the user what to run, passively.

**Success criterion:** the user has a copy-pasteable prompt in chat.

### Step 12 — Pre-send checklist

State the 4 golden-rule questions (template § "Pre-send checklist") and confirm each is answerable from the emitted prompt:

1. What does "done" look like? (a check in `<done-when>`)
2. Which files are in / out of scope? (`<scope>`)
3. Do they have the actual artifact, or only a description? (`<artifacts>`)
4. Do they know what pattern to follow? (`<reference>`)

Any "no" → that field should have been filled in Step 6; surface it now rather than ship a prompt that makes the user the verification loop. The most expensive "no" is #1.

---

## Named Model

Load-bearing reasoning: **gap prioritization** (which absent field costs the user — `<done-when>` ranks above `<output>`) and **done-when shape synthesis** (mapping task type to check shape). Lenses drawn on (cc-thinking-skills):

- *steel-manning* — assemble the strongest version of the user's intent before probing gaps, not the laziest read.
- *socratic* — the gap questions expose what the user hadn't realized was load-bearing.
- *debiasing* — the fresh-context checker is the bias control: the assembler's "looks complete to me" is exactly the optimism a separate context must check.

Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`. Scaffold + catalog pointer, not proof of correctness.

---

## Suggested next step:

- Idea-shape → `mattpocock-skills:grilling`.
- ≥2 unrelated tasks → `kbg:orchestrate`.
- Review-shape / Ship-shape / no-repro → `kbg:review-pr` / `/ship` / `mattpocock-skills:diagnosing-bugs`.
- Prompt emitted, `verdict: ready` → paste into a fresh turn (no auto-invoke).
- TDD-shaped → `mattpocock-skills:tdd` for the implementation turn (done-when already carries red→green).
