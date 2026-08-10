---
name: decide
description: "Doctrine-backed decision support for hard/contested-diagnosis choices past advisor()-level pressure-testing. Trigger on 'stuck between'/'hard call', Thai 'ตัดสินใจยาก'/'เลือกไม่ลง'. Don't use for routine decisions: default triad + advisor()."
metadata:
  origin: kbg
  references:
    - docs/reference/judgment-ladder.md
    - docs/reference/decision-doctrine-map.md
    - docs/reference/strategic-judgment.md
---

# decide

Structured decision support built on the Judgment Ladder (Decision Quality tradition).
Five modes — pick by reversibility, diagnosis clarity, and whether the reasoning
already exists or still needs to be built.

## Mode selection

Rows are checked top-to-bottom; apply the **first** row that matches — this is what
resolves an apparent conflict between rows, not a judgment call made fresh each time.

Run the decision-sizing triad first (METHODOLOGY Rule 1, injected each session):
one-way door? → blast radius → riskiest assumption. The triad sizes the stakes; it
does not bypass the table. A one-way door pulls toward `strategize`, but only once
the rows above it don't match first — scope still unstated routes to `clarify` (you
can't judge "one-way door?" without knowing scope first), and an existing plan/ADR
routes to `critique` (auditing what's on the table beats re-deriving it from scratch,
even when that plan reads as hard to reverse).

| Situation | Mode |
|---|---|
| Chaos or incident | Stop — use `kbg:incident` instead |
| A pile of competing tasks/asks, not yet one bounded question | Stop — use `kbg:orchestrate` first to triage effort and execution shape; come back here once triage lands on a single decision to size against the rows below |
| Scope or assumptions still unstated | `clarify` |
| Read-only: understand before committing | `probe` |
| Reversible choice, analyzable trade-offs | `decide` (default — Judgment Ladder) |
| Reasoning/plan/ADR already exists **from outside this session** — stress-test it | `critique` |
| Disprove a confident output **this session already produced** | Stop — spawn an external fresh-context skeptic that has not seen the work (`doubt-driven` pattern; canonical instance is the adversarial pass in `kbg:review-pr`) — not a mode here, because the skeptic must not share this context; `critique`'s own confirmation-bias guard can't substitute for genuine context separation on this session's own output |
| Irreversible / long-horizon / contested diagnosis | `strategize` |
| Decision already made, needs a record | `mattpocock-skills:domain-modeling` directly (owns the ADR rule) |

**Compound request, one table, multiple hits:** if a single request bundles two or more
distinct asks that land on different rows (e.g. "critique this ADR, then help me decide
whether to greenlight the follow-up"), run the table separately per clause and state each
mode's own banner separately, in the order the asks appear — don't force multiple distinct
asks under one banner just because they arrived in the same message.

**Handing off to the external skeptic:** when the "disprove a confident output this session
already produced" row fires, hand over the full reasoning/artifact produced — not a filtered
summary or just a closing assumptions table. A same-session summary is exactly the kind of
filtering the context-separation guard exists to route around; a brief that only carries
forward what this session already flagged as risky hands the skeptic this session's blind
spots along with its context. The full protocol for structuring the skeptic's actual review
lives in `kbg:review-pr`'s doubt-driven pattern — this note only covers what decide itself
hands off.

## Precedent check

Before any decision-producing mode runs (`decide` / `strategize` / `critique`), query `qmd`
(lex + vec) with the decision's scenario, scoped to the project's memory + research collections
(`kbg-memory` + `kbg-research` in kbg-harness; other projects' own collections per `qmd status`).
State the result in one line of the first response, **citing the query string actually run**:
the precedent found, or `no precedent found for "<query>"`. A bare "no precedent found" with no
query cited is unverifiable self-report and doesn't satisfy this check (a "nothing found" needs
one checkable fact). A hit showing the same decision already settled, with no new evidence in the current
ask, ends the run — cite the settled record instead of re-litigating it. If qmd is unavailable
in this context, say the check couldn't run; don't silently skip it. (Adapted from
semantica-agi/semantica's `find_precedents` lifecycle step — the store and the search already
existed here; this section wires the mandated query.)

## Announce the active mode

Before the analysis runs, the first line of the response states the active mode and its named principle(s) — one clause, no preamble:

| Mode | Banner |
|---|---|
| clarify | `**Mode: clarify** — socratic questioning (framing-bias guard)` |
| probe | `**Mode: probe** — systems-thinking + leverage-points` |
| decide | `**Mode: decide** — Judgment Ladder (5 rungs)` |
| critique | `**Mode: critique** — red-team + steel-manning` |
| strategize | `**Mode: strategize** — Rumelt kernel + real options + red-team + Lafley-Martin` |

---

## Mode: clarify

Resolve unstated scope or assumptions before any other mode runs. Analyze → recommend
→ ask — do not enumerate a long list of questions when a stated assumption will do.

1. **Analyze.** Name what's actually ambiguous: scope boundary, success criterion, or
   a load-bearing assumption the request leaves implicit.
2. **Recommend.** State your working interpretation as a default, not a question.
3. **Ask.** Only if the ambiguity is consequential enough that guessing wrong is
   expensive — use `AskUserQuestion` for a genuine fork, or a plain-text fork in the
   response if that tool isn't exposed in this context; otherwise proceed on the
   stated default and flag it. **One question max per turn** — clarify never emits a
   multi-question intake. Settled-ask check before asking: if the option you'd tag as
   the recommended default is one you'd proceed with anyway absent an answer, the ask
   is decoration — state it as the working default and move on (asking a question
   whose answer you already picked is the twice-confirmed 2026-07-02 consistency
   defect). Worked example: "add caching to the product API" → state the default
   ("in-process LRU on the hot read path, TTL 60s — say if you need cross-instance
   invalidation") and proceed; do **not** append a menu of cache backends each already
   tagged with your own pick.

**Bias to guard:** framing bias — a narrow first framing of the ask silently
constrains every option considered downstream. Reframe test: "if the literal request
did not exist, what problem is actually being solved?"

Output: scope is resolved, then hand off to `probe`, `decide`, or `strategize`.

---

## Mode: decide (default)

Interactive walk through the 5-rung Judgment Ladder. Pause with `AskUserQuestion`
only at a genuine fork where guessing wrong is expensive (same bar as `clarify`);
otherwise narrate the rungs straight through and flag open assumptions inline rather
than blocking on each one.

Match depth to stakes (reversibility, magnitude, time pressure, uncertainty,
precedent — judgment-ladder.md's Proportionality rule) — reversible low-stakes
choices need only rungs 1–2 (Recognize + Frame), not the full climb (completion
criterion below has the matching exception for what a rungs-1–2 response still owes).

Even a rungs-1–2 shortcut still owes one thing from rung 4/5's playbook: if the
request leans on an unverified quantitative or certainty claim (a stated cost, a
"zero risk," a time estimate), spot-check that specific claim before accepting it.
Skipping the full bias-guard checklist (reserved for rung 5's closing pass) is not
the same as skipping anchoring on a load-bearing number the request handed you — a
lightweight decision is exactly where an unverified number is most likely to just
get accepted at face value.

### 1. Recognize
Name the actual choice, its owner, its timing, and its trigger.
> Quick check: "What would happen if we did nothing for 30 days?"

### 2. Frame
Objectives, constraints (hard limits vs preferences), stakeholders, scope in/out.
> Reframe test: "If our favorite option did not exist, how would we solve this?"

### 3. Test assumptions
List load-bearing beliefs. For each: what evidence would refute it?
> "Who disagrees with us, and what do they know that we don't?"

### 4. Estimate risk
Express uncertainty as ranges, not point estimates. Name compound/tail scenarios.
> "What is the 90% confidence interval, and would we bet money on it?"

### 5. Decide, commit, follow through
Document chosen and rejected options, trade-offs, revisit trigger, progress metric.
> Bias guards before closing: framing, anchoring, confirmation, sunk-cost.
> "If we had not already started, would we start today?"

**Full rung detail and decision record template:** read via Bash — `cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"` (the bare repo-relative path resolves nowhere in a foreign-project CWD; the plugin cache is the stable anchor).

---

## Mode: probe

Systems-thinking analysis *before* committing to a frame. Use when the diagnosis
itself is contested or the problem space is complex/emergent.

1. Map the system: actors, flows, feedback loops, delays.
2. Name the leverage points — the highest-impact spots to intervene (catalog at
   `docs/reference/thinking-skills/skills/` — read via Bash, `cat
   "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/<file>"`; the bare
   repo-relative path resolves nowhere in a foreign-project CWD).
3. Stress-test the diagnosis: what would prove the current frame wrong? Cross-check
   against every actor named in step 1's map, not just the theories already on the
   table — a stated diagnosis only covers who spoke up, and the map often holds an
   unclaimed candidate cause nobody's blaming yet.
4. Output: a framing memo, not a decision — hand off to `decide` or `strategize`.

---

## Mode: strategize

For irreversible or long-horizon commitments where rivals adapt and resources are
constrained. Walks six steps, grounded in Rumelt's kernel plus real-options and
red-team discipline:

1. **Diagnosis** — simplified explanation of the actual challenge (not a goal).
2. **Guiding policy** — overall approach to the obstacles named in the diagnosis.
3. **Coherent actions** — steps that coordinate to carry out the policy.
4. **Map irreversibilities and real options** — per commitment, name whether it's an
   irreversible bet, a reversible probe, a stage gate, or an adaptive commitment (see
   "Real options and adaptive commitment" in the reference). Buy information before
   buying irreversibility.
5. **Red-team the strategy** — run the reference's "Strategic red-team" question set
   against the diagnosis, guiding policy, and coherent actions.
6. **Commit to the strategy loop** — cross-check with Lafley-Martin's five choices
   (winning aspiration → where to play → how to win → capabilities → management
   systems), then commit with a named revisit trigger.

A weak diagnosis produces a vague policy; a policy that fails the red-team is not
ready to commit. If the elements don't fit, loop back to Diagnosis.

**Full model detail:** read via Bash — `cat "${KBG_PLUGIN_ROOT}/docs/reference/strategic-judgment.md"`.

---

## Mode: critique

Adversarial stress-test of reasoning that **already exists** — a plan, an ADR, an RFC,
a proposal on the table. Not for generating a new decision from scratch (`decide`/
`strategize` do that); this mode only audits one that's already made.

1. **Skeptic.** Argue against the proposal on its own terms: what load-bearing
   assumption, if false, collapses it? What would a competent rival or reviewer
   attack first? (red-team)
2. **Steel-man.** State the strongest version of the opposing case, not the weakest —
   the version that would actually change the decision if true. (steel-manning)
3. **Synthesis.** Name any unconsidered alternative the Skeptic/Steel-man pass
   surfaced. If the proposal survives, say why the strongest objection doesn't hold.
   If it doesn't survive, name what changes.

**Bias to guard:** confirmation bias — the proposal's author is structurally
motivated to find it sound. If that author is this session itself (drafted or
reasoned through earlier in this conversation), the mode-selection table's skeptic
row applies instead — critique's own guard isn't strong enough for that case. Ask:
"what evidence would prove this proposal wrong, and did we look for it or just for
evidence it's right?"

Output: a verdict — the reasoning holds, holds with a named caveat, or needs rework —
plus the one assumption most worth re-verifying, and, when the verdict carries a
caveat or needs rework, what specifically would need to change (per step 3) — a
verdict without a concrete next step leaves the reader with a red flag and no path
forward.

---

## Output format

Produce a decision record at the end of any `decide` or `strategize` session:

```markdown
# Decision: <title>

- Date: YYYY-MM-DD
- Owner: @name
- Mode: decide | strategize

## Decision statement
<one sentence>

## Frame
- Objective:
- Constraints (hard):
- Scope in / out:
- Stakeholders:

## Key assumptions tested
| Assumption | Confidence | What would refute it |

## Decision
Selected: ... (driven by: <the 1–3 stated facts that decided it>)
Rejected: ... (reason)
Trade-offs accepted: ...
Confidence: high | medium | low — <the named evidence this rests on, and the
  load-bearing thing NOT verified>. Confidence is about the selected option itself,
  not a sub-assumption; a bare label with nothing behind it doesn't count.

## Commitment
- Action owner + due date:
- First reversible step:
- Progress metric:
- Revisit trigger:
- Bias guards applied: framing / anchoring / confirmation / sunk-cost
```

This is the compact default. For a one-way-door or high-stakes decision, use
`judgment-ladder.md`'s fuller template instead (adds `Consulted`, an `Evidence`
column on the assumptions table, a `## Scenarios` probability/impact table, and a
separate `Next check-in date`) — read via Bash,
`cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"`.

Persist via `mattpocock-skills:domain-modeling` (owns the ADR rule) when the decision warrants a durable ADR.

## Guardrails

- Do not run this skill in chaos or under active incident — stabilize first.
- `probe` output is a memo, not a decision. Do not skip to commitment from probe.
- Match effort to stakes: trivial reversible choices need only rungs 1–2 (Recognize
  + Frame), not the full climb — see "Match depth to stakes" under Mode: decide. This
  scales down tested assumptions and the formal progress metric (see the Completion
  criterion's `decide` exception below); it does not scale down the revisit trigger.
- A decision without a revisit trigger is not finished — this applies at every depth,
  including a rungs-1–2-only response.

## Completion criterion

This criterion applies per mode's own output shape, not one template for all five. Every
decision-producing mode (`decide` / `strategize` / `critique`) additionally owes the one-line
Precedent check result (see § Precedent check) — a run that never stated it is not finished:

- **`decide`** — verify the decision is recorded with its Frame, tested assumptions, an evidence-tied Confidence on the selected option, and Commitment (revisit trigger + progress metric); confirm a reader could re-derive the Decision from the Frame and assumptions. **Exception for a rungs-1–2-only response** (per the Proportionality guardrail above): tested assumptions, a formal progress metric, and the Confidence line are not required — Frame plus a named revisit trigger is sufficient. A response that stops at rungs 1–2 but skips even the revisit trigger is not finished; one that goes further than rung 2 owes the full record.
- **`strategize`** — same Output format template, mapped from its own step vocabulary: Diagnosis + Guiding policy fill the Frame section, the irreversibility map and red-team results are the tested assumptions, and Commitment's revisit trigger comes from step 6's strategy loop (progress metric = whatever the red-team/tripwire step names as the signal to watch).
- **`critique`** — verify the verdict (holds / holds with caveat / needs rework), the one assumption most worth re-verifying, and — when the verdict isn't a clean "holds" — what specifically would need to change are all stated. No Frame/Commitment record required; critique audits an existing plan rather than producing a new one.
- **`clarify` / `probe`** — completion is the stated handoff itself (resolved scope + working default, or a framing memo) — these modes never produce a decision record and aren't held to the Frame/Commitment bar.

For a numeric weighted verdict, apply the `kbg:score-decision` rubric (METHODOLOGY Rule 14) inline — its default criteria (Evidence/Doctrine/Net load/Risk-inverted/Proportionality/No-conflict) are shaped for a `decide`-style trade-off table; for a `strategize` output, adapt them to score the guiding policy's coherence and whether it survived the red-team rather than forcing a single-option comparison onto a qualitative kernel. `score-decision` itself is `disable-model-invocation: true`, so tell the operator to run `/kbg:score-decision` if a formal, on-demand artifact is what's actually needed.

If a `decide`/`strategize` session's reasoning drifts from the stated criteria or the revisit trigger is missing, it is not finished — never close a choice without a re-open condition.
