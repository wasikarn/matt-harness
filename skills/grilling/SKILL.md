---
name: grilling
description: "Socratic grilling — walks the design tree, sharpens terms. Use to stress-test any plan, design, or assumption before committing. Don't use for already-decided or back-of-napkin sketches."
---

Interview the user relentlessly about every aspect of the plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback before continuing. Asking multiple questions at once is bewildering.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Modes

> kbg fold: this skill ships as the silent merge of matt's `grilling` + `grill-me` + `grill-with-docs`. One body, two modes; user-facing name stays `grilling`.

**basic (default):** Interview only — no artifacts produced. Covers both stateless (no codebase) and live-code sessions; flips to `with-docs` when state retention is wanted.

**with-docs:** Same interview, and also run the `domain-modeling` skill in parallel to produce ADRs and a domain glossary as the session progresses.
