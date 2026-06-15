---
article: martinfowler.com/articles/harness-engineering.html
author: Birgitta Böckeler (Thoughtworks)
published: 2026-04-02
reviewed: 2026-06-15
comparison-target: kbg-harness-0.1.18
sources-distilled:
  - harness-angle-1-maintainability.md
  - harness-angle-2-architecture.md
  - harness-angle-3-behaviour.md
  - harness-angle-4-meta.md
  - harness-critique-cost.md
  - harness-critique-gaps.md
  - harness-apply-gap.md
lenses: 4 angles + 2 adversarial + 1 comparison
---

# Böckeler (2026): "Harness engineering for coding agent users" — 1-pager

## The mental model in 5 lines

A **harness** is everything in an AI agent except the model. A **user harness** wraps a *coding agent* (which already has a *builder harness*: system prompt, code retrieval, orchestration) with **guides** (feedforward controls) and **sensors** (feedback controls). Each control is **computational** (deterministic, fast, cheap — linters, type-checkers, tests) or **inferential** (semantic, slower, expensive, non-deterministic — AI review, "LLM as judge"). A good harness **does not aim to eliminate human input**; it directs it where it matters most. Regulation falls into three dimensions: **maintainability** (easiest, lots of pre-existing tooling), **architecture fitness** (fitness functions for non-functional shape), **behaviour** (the elephant — almost unsolved).

## The 2×2 — Böckeler's load-bearing grid

| | **Computational** | **Inferential** |
|---|---|---|
| **Feedforward** (steer *before* the act) | Linters, type-checks, codemods, hooks that deny a destructive command | `AGENTS.md`, skills, doctrine injection, ambient affordances |
| **Feedback** (observe *after* the act) | Structural tests (ArchUnit), regression tests, mutation testing, dep scanners | Code-review agents, AI judges, "response-quality-sampling" |

The article's warning: **one without the other is broken**. Feedback-only = "agent that keeps repeating the same mistakes" (L345). Feedforward-only = "agent that encodes rules but never finds out whether they worked" (L345).

## Three regulation axes — what each catches

- **Maintainability** (L437–449): computational sensors catch structural defects reliably (duplication, complexity, coverage, style). Inferential sensors catch semantic defects partially and expensively (semantic duplication, redundant tests, over-engineering). **Neither catches** misdiagnosis, misunderstood instructions, or correctness when the spec is vague (L448) — the article's deepest honesty.
- **Architecture fitness** (L451–463): fitness functions for performance, observability, module boundaries. **Bounded by ambient affordances** (Ned Letcher, L488–498): strongly-typed language, defined module boundaries, framework abstractions *implicitly* make the codebase more governable. **Greenfield has the advantage** — legacy code is hardest to harness where it's most needed (L501).
- **Behaviour** (L465–479): spec as feedforward + AI-generated test suite as feedback. **OpenAI tests are not good enough yet** (L476); approved-fixtures (Lexler) is selective, not wholesale. **Human review is the dominant sensor** (L481 figure). Article is honest: *"we still have a lot to do"* (L478).

## Top 5 lines worth memorising

1. **L345** — "feedback-only = agent that keeps repeating the same mistakes. feedforward-only = agent that encodes rules but never finds out whether they worked."
2. **L448** — "Correctness is outside any sensor's remit if the human didn't clearly specify what they wanted in the first place." (Maintenance section, but applies to behaviour.)
3. **L468** — Behaviour harness is "the elephant in the room."
4. **L518** — "Defining topologies is a variety-reduction move." (Ashby's Law applied to harness design.)
5. **L531** — "A good harness should not necessarily aim to fully eliminate human input, but to direct it to where our input is most important."

## Where the article is weak (adversarial summary)

- **LLM-judge circularity unaddressed.** Coding model, judging model, and meta-engineering model are all the same class (L356–L359, L393). A judge inherits the generator's blind spots. kbg's mitigation: inferential-feedback sensors (`verification-gate.sh`, `fabrication-verdict-log.sh`) are *advisory only* — they journal but **never** emit a `permissionDecision` (ADR 0002 §L112).
- **Behaviour is a cop-out.** The article classifies the problem, names one pattern (approved-fixtures), and admits defeat. Most of what humans bring *is* behavioural judgment (L527–L531) — the framework is structurally unequipped to deliver the autonomy the abstract promises.
- **Coherence tax under-acknowledged.** L553 raises "how do we keep a harness coherent" and drops it. N guides × M sensors is multiplicative; the article frames it additively.
- **Quality-left without trade-off analysis.** Stripe's "shift feedback left" (L544) is cited uncritically. The costs — reviewer fatigue, false positives, slow pre-commit, "tool said fine" stamp on Critical CVEs — are never acknowledged.
- **"Harness = configuration" framing.** The four open questions (L553) are consistency problems of a config, not engineering problems of a system. A harness with versioning, cost sensors, its own test suite, a sandbox, and a market is a different object.
- **Harnesses are mostly *additions* in the article**; real harness work is mostly *removal* (narrow what the agent can do). The article's guides/sensors are positive; the security-audit discipline is negative.

## Where the article is silent (gaps worth flagging)

1. **Versioning / install / rollback API** for harnesses (lines 506–521) — kbg's analog: the plugin cache + `claude plugin update` discipline.
2. **Cost / token budget as a regulation axis** — appears only as "fewer wasted tokens" (L326). kbg's analog: `METHODOLOGY.md:113-118` "Token Budgets Are Not Advisory" (4k/task, 30k/session).
3. **The harness's own test suite** — how you regression-test a non-deterministic harness. kbg's analog: `test-critical-hooks.sh` (204 assertions) + `audit.sh` 38 checks.
4. **Sandboxing** as a precondition for behaviour-harness feedback. Article never mentions Firecracker/nsjail/gVisor.
5. **Provenance / accountability** when AI iterates the harness itself (L393). kbg's analog: `kbg:recursive-improve` (6-step cycle, human `AskUserQuestion` at Step 3 — ADR 0002).
6. **Multi-agent / agent-team harnesses** — the article is single-agent throughout. A "harness for an agent team" is the obvious next article. kbg's analog: `orchestrate-dispatch.py` (deterministic DAG, does NOT spawn agents — that would be a covert L4 loop).
7. **Harness economy** — npm-like / Docker-Hub-like / GitHub-Actions-like? The "service templates" analogy (L507) is well-chosen; the market dynamics are unsolved.
8. **Local vs CI sensor split** — which inferential sensors are user-paid, which are CI-paid?

## kbg-harness: 5×2×2 scorecard (verified by comparison agent)

| Axis | Computational FF | Inferential FF | Computational FB | Inferential FB |
|---|---|---|---|---|
| **Maintainability** | ✅ PreToolUse gates (`block-dangerous-git.sh`, `secret-scan.sh`, `block-alias-shadowing.sh`, `block-bash-doctrine-write.sh`) | ✅ Doctrine injection (`doctrine-bootstrap.sh`, `iron-rule-reminder.sh`, `orchestrator-nudge.sh`) + 34 skill `description:` blocks | ✅ `post-edit-audit.sh`, `security-diff-review.py`, 204 critical-hooks tests, `audit.sh` 38 checks | 🟡 `kbg:code-reviewer` (8 sub-skills via `kbg:review-pr`); **advisory only by design** |
| **Architecture fitness** | ✅ JSONL `JOURNAL-SCHEMA.md` (logging contract); 14-event hook surface; 1536-char description budget | ✅ Token budgets (`METHODOLOGY.md:113-118`); `kbg:perf` skill | ✅ `BOUNDARY.md` auto-regen (module-boundary invariant); `last_permission_review` cadence | ❌ No inferential arch-review agent |
| **Behaviour** | ✅ `accept-task` → `ACCEPTANCE.md` (locked spec) | 🟡 `commands/pre-ship-verify.md` (spec → grader) | ✅ `eval/run-eval.py --gate`; 5-state `run-acceptance.py` | ❌ No LLM-judge for "is this over-engineered?"; **`kbg:review-pr` is a task, not a sensor** |
| **Sensors kbg is missing** | Property-based tests; mutation testing; SBOM/Syft/Grype | Inferential structural tests (arch-drift via LLM) | Sandbox layer (no Firecracker/nsjail) | Sensor-fire notification (audit reports staleness; no human is paged) |

**Steering loop:** `kbg:recursive-improve` (6-step, 5-iteration cap, human gate at Step 3) + `orchestrate-dispatch.py` (deterministic DAG, does NOT spawn agents — explicitly *not* an L4 loop per ADR 0002).

**Single divergent decision** the article would push back on: kbg uses `tools:` allowlists (add structure) rather than `disallowedTools:` (remove affordances) — `docs/agent-tool-patterns.md`. The cost-reviewer lens would call this inverted from real-world practice.

## Actionable changes (3 now, 3 later)

**Now (low-cost, high-signal):**

1. **Document the 2×2 grid in `CLAUDE.md`** as the mental model for *why* kbg has 14 hook events. Currently the hook architecture is described mechanically; the 2×2 framing makes the *purpose* of each event obvious.
2. **Add a `## Open questions` mirror to `docs/harness-decay-cadence.md`** for the harness's own LLM-judge-circularity concern — single paragraph explaining why `verification-gate.sh` is *advisory*. Today this is in ADR 0002 §L112 but isn't surfaced to harness-readers.
3. **Surface the behaviour-harness honesty.** Add a one-liner to `METHODOLOGY.md`: "Acceptance criteria are the upper bound on what the test gate can prove." This bakes the L448 lesson into doctrine.

**Later (require own design work):**

4. **Inferential structural-test layer** — an `agents/over-engineering-judge` or `agents/diff-arch-drift-judge` that runs on SessionEnd, is *advisory* like `verification-gate.sh`, and journals its verdicts. Closes the behaviour-harness gap the article punts on, but at *inferential cost* — needs cost-attribution per L326.
5. **Sensor-fire notification.** Audit.sh already reports staleness (`audit.sh:773-880`); a `hooks/notify-sensor-failures.sh` on SessionStart that surfaces "X sensors didn't fire in 90 days" would close L553 (silent-sensor blindness).
6. **Harness-coverage metric.** The hardest. A "harness coverage" tool analogous to test coverage — "what fraction of the harness's claimed sensors fired on the last N commits?" — is the meta-tool the article calls the right next question. Out of scope for a single iteration; worth a research follow-up.

## What to delete from the conversation

- The **"harness on a dog"** metaphor (L315). The author concedes it doesn't work. Use "steering loop" (L389) instead.
- The **"harness reduces review toil"** claim (L326) as-is. The "should" does all the work. Either quantify or drop.

## One sentence the user can quote

> "A good harness should not necessarily aim to fully eliminate human input, but to direct it to where our input is most important." — Böckeler, 2026, L531
