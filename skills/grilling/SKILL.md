---
name: grilling
description: "Grill-me: walk the design tree one question at a time, each with a recommended answer. Use when stress-testing a plan. Don't use for implementation."
metadata.origin: matt-pocock
---

Interview the user relentlessly about every aspect of the plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

**done when:** you can state the agreed decision in one sentence, name the seams that decision touches, and the user confirms there is nothing left to resolve. Premature completion here = declaring the tree walked when one branch is still open — the next implementer will re-open it.

Ask the questions one at a time, waiting for feedback before continuing. Asking multiple questions at once is bewildering.

Failure mode to avoid: firing a batch of questions in one turn — the user picks the easiest to answer, not the most important. One question, one answer, then proceed.

If a question can be answered by exploring the codebase, explore the codebase instead.

Failure mode to avoid: asking the user what the codebase already answers — that wastes the user's time AND signals you didn't look. Read first, ask second.

## Modes

> kbg fold: this skill ships as the silent merge of matt's `grilling` + `grill-me` + `grill-with-docs`. One body, two modes; user-facing name stays `grilling`.

**basic (default):** Interview only — no artifacts produced. Covers both stateless (no codebase) and live-code sessions; flips to `with-docs` when state retention is wanted.

**with-docs:** Same interview, and also run the `domain-modeling` skill in parallel to produce ADRs and a domain glossary as the session progresses.

1. confirm the user's answers actually constrain the design — each question should narrow the space, not restate it.
   If the interview drifts into generic Q&A or the answers don't reduce ambiguity, stop: grilling that doesn't converge never produces a buildable spec.

---

## Named Model

This skill is a convergence surface, not a correctness oracle. The lenses it draws on (cc-thinking-skills):

- *debiasing* — each recommended answer is a hypothesis to test, not a sales pitch.
- *socratic* — the question sequence exposes contradictions the user already holds.
- *steel-manning* — state the strongest version of the user's position before probing it.

Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
