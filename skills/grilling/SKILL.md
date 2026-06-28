---
name: grilling
description: Relentless interview to stress-test a plan or design. Modes: basic (default, interview only) or with-docs (also produces ADRs + domain glossary).
---

Interview the user relentlessly about every aspect of the plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback before continuing. Asking multiple questions at once is bewildering.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Modes

**basic (default):** Interview only — no artifacts produced.

**with-docs:** Same interview, and also run the `domain-modeling` skill in parallel to produce ADRs and a domain glossary as the session progresses.
