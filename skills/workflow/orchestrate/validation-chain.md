# Orchestrate — validation chain

On-demand companion to `SKILL.md`. Load right before running a Builder → Validator → Fixer → Re-validator chain. Split out of `reference.md` 2026-09-03 (`docs/research/orchestrate-cost-optimization-2026-09-03.md`, candidate #1).

## Validation chain (builder → validator → fix → re-validator) — full text

Supplementary detail for `SKILL.md`'s Validation chain (builder → validator → fix → re-validator) section.

The 4-step validation pipeline from article `team-orchestration`, adapted to the task board polyfill. Every non-trivial write should be a chain, not a single dispatch — **non-trivial** = ≥2 files changed OR ≥1 test file touched. Below that, run a single dispatch; the chain's coordination overhead isn't worth it (Rule 2). The board makes the ordering observable and resumable across sessions.

This is the file-based counterpart to the `TaskCreate + addBlockedBy` protocol earlier in this skill. `addBlockedBy` enforces ordering in an external task system; `depends_on` + `kbg_recompute_blocked` enforces it in the local `board.json`.

### Concept

1. **Step A — Builder implements.** A write-capable agent produces the artifact.
2. **Step B — Validator reviews.** A read-only agent (e.g. `typescript-reviewer`) checks quality; `security-reviewer` checks OWASP.
3. **Step C — Fixer repairs (conditional).** If the validator rejects, the builder (clarity-only scope) addresses the findings.
4. **Step D — Re-validator confirms.** The same or a different validator verifies the fix.

**Re-validator skip rule.** D runs only if C (the Fixer) ran, or if D's lens differs from B's (B = a language reviewer, D = `security-reviewer`, say). A clean B pass with no Fixer ends the chain at B: D is defined as verifying *the fix*, and with no fix a same-lens D only re-grades B's own verdict — a second dispatch that adds a check the chain doesn't need (Rule 2). Verifier separation is intact either way: B is still a separate fresh agent from A, and its structured verdict is still the score the lead branches on. (`docs/research/orchestrate-cost-optimization-2026-09-03.md`, candidate #2.)

**Fix retries are capped — 3, then escalate.** The chain above is a DAG (`A → B → F → D`), not a loop: D is terminal. If a Task 4 failure sends work back to the Fixer, that re-entry MUST carry a numeric cap — 3 fix attempts on the same finding set; the 4th is an escalation, not a round. Stop, hand the last verdict to the user, don't re-dispatch. This repo's own loop doctrine (`docs/reference/operating-model.md`'s "Loop design essentials" section) states failure-mode #3 as the standing requirement (retry cap N + escalate to a human when exceeded) and names 3 as the one retry-cap number ever written down. This chain is attended, which is why it escalates at all: the L5 "retry cap at 1" in `reference.md`'s Autonomous / Recurring Execution section is lower because there the human is unreachable by definition and exhaustion degrades to log-and-continue instead.

The chain is a DAG: `A → B → F → D`. The lead tracks ordering with the native `TaskCreate` + `addBlockedBy` protocol (or an inline checklist for a short chain) — the lead is the **sole writer** of the plan state, since sub-agent Write/Edit may be silently discarded (GitHub #9458). Spawn B blocked on A; if B rejects, spawn a fix task F blocked on B; D confirms the fix. Advance each edge only when the upstream task is verified `completed` against its done-when.

**Completion is owned by the main session, not the maker.** `addBlockedBy` gates *ordering*, but ordering alone does not stop a maker from marking its own task `completed` without B's pass — the maker-grading-its-own-work circularity. `gate:task:complete-separation` (`hooks/gates/task-complete-separation.sh`, wired on `PreToolUse:TaskUpdate`) closes that gap computationally: any subagent (`agent_type` present) that calls `TaskUpdate(status="completed")` is blocked at exit 2. So the maker (A) sets `in_progress` and **returns**; the validator (B) reviews and **returns its verdict to the main session**; the **main session** marks `completed` on B's pass. A subagent's `agent_type` is fixed at spawn and cannot be mutated, so a maker cannot forge completion — the only path is the main session (the operator proxy / trusted verifier of last resort). This is enforced at the hook, not by doctrine.

### Gating rules

| Role | Gated? | Why |
|------|--------|-----|
| Builder (A) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Validator (B) | **No** | Read-only; no AskUserQuestion |
| Fixer (C) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Re-validator (D) | **No** | Read-only; no AskUserQuestion |

**Validator safety:** Validators are ungated and hold `Bash`, so read-only is enforced by allowlist (no Edit/Write) plus prompt doctrine, not a runtime backstop. This carve-out applies only inside the 4-step chain, reviewing a Builder's already-produced artifact. A standalone/first-pass review with nothing yet produced — e.g. auditing existing, untouched-in-a-year code with no preceding Builder step — is **Gated** under the general Step 4 rule regardless of agent; the same agent (`security-reviewer`) can be either, depending on whether it's reviewing new output or auditing standing code. (A prior runtime Bash-stripping backstop was removed in the v0.6.0 reset and not rebuilt — `docs/agent-tool-patterns.md`'s Examples from this harness section.)

### Structured verdict — Validator/Re-validator output contract

`gate:task:complete-separation` already makes **who** can advance the chain computational — a subagent can't mark its own task `completed`, only the main session can. What it reads to make that call has, until now, had no shape: free prose in `.scratch/<task>/verdict.md`, graded by the lead's own reading. That's the maker's judge returning a vibe instead of a score a machine can branch on — the same crux CLAUDE.md's verifier-separation principle names everywhere else in this harness. Close the shape gap:

- **Required fields**, written as a fenced JSON block in the same `.scratch/<task>/verdict.md` location (no new file, no new tooling): `pass` (bool), `findings` (array of `{file, line, description, severity}`, empty when `pass: true`), `confidence` (0.0–1.0, a narrative signal for the lead — not a threshold this step branches on; see the scope note below for why), `scope_ok` (bool), `unexpected_files` (array of strings, empty when `scope_ok: true`).
- **File-scope conformance, checked mechanically, before the behavioral review.** The F9 template's Builder done-when already asks for "No edit to files outside FILES YOU OWN" — until now that line was self-reported by the Builder, never independently checked. The Validator (holds Bash — see "Validator safety" below) runs `git diff --name-only <base-ref>` against the Builder's declared `FILES YOU OWN` list, carried forward via UPSTREAM CONTRACTS, *before* reviewing quality. An out-of-scope edit is a scope failure regardless of how good the code is: `scope_ok: false` forces `pass: false` and adds a `severity: high` finding naming each file in `unexpected_files`. A clean scope sets `scope_ok: true`, `unexpected_files: []`, and the review proceeds normally.
- **Fail-closed disposition:** verdict file missing, unparseable, `pass` absent, `pass` present but not a literal boolean, `findings` not an array, `scope_ok` absent or not a literal boolean, `unexpected_files` not an array, or the fields disagreeing (`pass: true` alongside a non-empty `findings` array, or `scope_ok: true` alongside a non-empty `unexpected_files` array — both self-contradictory) → **not verified**. The lead does not advance the DAG edge — re-dispatch the Validator or escalate to the user. A missing or malformed verdict is never read as `pass` — an agent that returns nothing is not a clean pass. This is a shape check the lead applies before trusting the verdict at all, not a list to pattern-match exhaustively — the standing rule is: any verdict that doesn't cleanly assert `pass: true` with no contradicting field is not verified.
- **Scope, stated honestly:** this closes the *shape* gap (a machine can parse the verdict) — not the *truth* gap (a structured `pass` can still be wrong). The Validator/Re-validator here are **first-order** checks — the first and only look at the Builder's artifact, already independent by virtue of being a separate fresh-agent dispatch. There's no prior finding to refute, so a confidence-gated demotion pass doesn't apply — adding one would add a check this chain doesn't need (Rule 2).

### Upstream contract propagation

Each stage's prompt must carry the previous stage's concrete output forward into the next
stage's `UPSTREAM CONTRACTS` block — the exact files Task 1 touched, Task 2's verdict verbatim,
Task 3's final diff. Without these injections, each agent re-derives or assumes, producing latent
bugs and wasted work. The worked example below shows exactly which field and which command
populates each one.

**Cross-references:** this pattern uses the F9 spawn-prompt template in `f9-template.md`; enforce the ordering with the native `TaskCreate` + `addBlockedBy` protocol.

## Validation chain — worked example

Concrete 4-task chain for implementing `GET /health` — SKILL.md's Validation chain section, "Worked
example" summarizes the roles and gating and points here for the full spawn prompts below.

**Task 1 — Builder: implement endpoint**

```
# Task: Implement GET /health
[role: builder]

## What
Add a health check endpoint that returns 200 with JSON body.

## Where
`src/api/routes/health.py`

## Focus
Minimal blast radius — no new dependencies.

## Deliverable
`src/api/routes/health.py` exists and `GET /health` returns `{"status":"ok"}`.

## FILES YOU OWN
- src/api/routes/health.py

## UPSTREAM CONTRACTS
(Empty list — first task in chain.)

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/api/routes/health.py | exports `GET /health` handler | no new deps |

## Done-when
- [ ] `GET /health` returns HTTP 200 + `{"status":"ok"}`
- [ ] `bash -n src/api/routes/health.py` exits 0
- [ ] No edit to files outside FILES YOU OWN
```

Spawn with `AskUserQuestion` (gated — builder holds Edit/Write/Bash).

**Task 2 — Validator: review PR** (same template shape as Task 1, `[role: validator]`, abbreviated here)

What: first run `git diff --name-only` and compare against `tasks["T1"].files` (Task 1's declared `FILES YOU OWN`) to set `scope_ok`/`unexpected_files`; only then review `src/api/routes/health.py` for correctness, style, test coverage. Deliverable: verdict file at `.scratch/health-review/verdict.md`, a fenced JSON block matching SKILL.md's structured-verdict contract — `pass` (bool), `findings` (array of `{file, line, description, severity}`, empty when `pass: true`), `confidence` (0.0–1.0), `scope_ok` (bool), `unexpected_files` (array, empty when `scope_ok: true`). Upstream contract: reads `tasks["T1"].files` from the board. Done-when: verdict file exists, parses as valid JSON with `pass` present, every finding cites file:line, no file was edited.

Spawn **ungated** — validators are read-only by allowlist (see SKILL.md's "Validator safety" note, under Gating rules, for why there's no runtime backstop beyond the allowlist). If the lead can't parse the verdict or `pass` is absent, treat it as **not verified** — re-dispatch, don't advance to Task 3/4 on a guess.

**Task 3 — Fixer: address review findings** (`[role: fixer]`; conditional — only spawned if Task 2's verdict is `pass: false`)

What: address every T2 finding verbatim. The Fixer is the same builder role as Task 1 addressing its own upstream findings — not a fresh, context-free persona (superpowers' reverted-separate-Fixer-role finding doesn't apply here for that reason). Upstream contract: Task 1's files-touched list (`tasks["T1"].files`) plus the verbatim `findings` array from `.scratch/health-review/verdict.md`, reproduced in the fix commit message. Done-when: every T2 finding is fixed or explicitly rejected with reason, no new files outside FILES YOU OWN.

Spawn with `AskUserQuestion` (gated — fixer holds Edit/Write/Bash).

**Task 4 — Re-validator: OWASP scan** (`[role: re-validator]`; runs here because its lens — OWASP — differs from Task 2's, per the Re-validator skip rule)

What: check `scope_ok` against Task 1's `FILES YOU OWN` first (catches Fixer drift too, since Task 3 is bounded to the same file set), then run a security scan on the final `src/api/routes/health.py`. Deliverable: verdict file matching the same structured-verdict contract as Task 2 (`pass`, `findings`, `confidence`, `scope_ok`, `unexpected_files`). Upstream contracts: the final diff from Task 3 (lead runs `git diff` after Task 3 and pastes it in) plus Task 1's file (verify the final code doesn't re-introduce old patterns). Done-when: verdict file exists, parses with `pass: true`, no file was edited.

Spawn **ungated** — re-validators are read-only. Same fail-closed rule as Task 2: a missing or unparseable verdict is **not verified**, never read as `pass`.

**Lead check between waves**

After spawning Task 1, the lead verifies its done-when (`GET /health` returns 200) before proceeding to Task 2. After Task 2 completes, the lead parses `.scratch/health-review/verdict.md`: `pass: false` (or missing/unparseable — fail-closed) spawns Task 3 (Fixer); `pass: true` skips Task 3 and goes to Task 4 only because Task 4's lens differs (Re-validator skip rule); a same-lens Task 4 would be skipped too and the chain ends at Task 2. A Task 4 failure that sends work back to Task 3 counts against the Concept section's fix-retry cap — the lead keeps the count; the number lives in one place.
