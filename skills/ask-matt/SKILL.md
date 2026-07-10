---
name: ask-matt
description: "Router over the matt-pocock flow: ask, grill, plan, slice, ship. Use when starting non-trivial work, unsure which skill fits. Don't use for known flows."
metadata.origin: matt-pocock
disable-model-invocation: true
disable-model-invocation-reason: router skill — the model should not auto-select a flow without the user's situation being asked
---

# Ask Matt

You don't remember every skill, so ask.

A **flow** is a path through the skills. Most paths run along one **main flow**, and two **on-ramps** merge onto it. Everything else is standalone.

## The main flow: idea → ship

The route most work travels. You have an idea and want it built.

1. **`kbg:grilling`** — sharpen the idea by interview. Start here when you **have a codebase**: pass `--with-docs` to make it stateful, retaining what it learns in `CONTEXT.md` and ADRs. (No codebase, stateless interview only? Default mode is fine.)
2. **Branch — can you settle every question in conversation?** If a question needs a runnable answer (state, business logic, a UI you have to see), detour through a prototype, bridged by **`kbg:handoff`** in both directions (see Crossing sessions):
   - **`kbg:handoff`** out, then open a fresh session against that file,
   - **`prototype`** to answer the question with throwaway code,
   - **`kbg:handoff`** back what you learned, and reference it from the original idea thread.
3. **Branch — is this a multi-session build?**
   - **Yes** → **`kbg:to-spec`** (turn the thread into a spec) → **`kbg:to-tickets`** (split the spec into independently-grabbable tickets). Because the tickets are independent, **clear context between each one**: start a fresh session per ticket and kick off **`/ship`** by passing it the spec and the single ticket to work on.
   - **No** → **`/ship`** right here, in the same context window. It reviews the diff via **`kbg:review-pr`** before merge. Reach for **`kbg:tdd`** on its own when you just want to build one behaviour test-first without the whole `/ship` machine, and **`kbg:code-review`** on its own whenever you want to review a branch or PR against an arbitrary fixed point.

### Context hygiene

Keep steps 1–3 in **one unbroken context window** — don't compact or clear until after `kbg:to-tickets` — so the grilling, spec, and tickets all build on the same thinking. Each `/ship` then starts fresh, working from the ticket.

The limit on this is the **[smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone)**: the window (~120k tokens on state-of-the-art models) within which the model still reasons sharply. If a session approaches it before `kbg:to-tickets`, don't push on degraded — `kbg:handoff` and continue in a fresh thread.

## On-ramps

A starting situation that generates work, then merges onto the main flow.

- **Bugs and requests piling up** → **`kbg:triage`**. It moves issues through triage roles and produces agent-ready issues, which **`/ship`** later picks up.

  Triage is only for issues **you didn't create** — bug reports, incoming feature requests, anything that arrives raw. Tickets that `kbg:to-tickets` produced are already agent-ready, so **don't triage them**.

- **Something's broken** → **`kbg:diagnosing-bugs`**. For the hard ones: the bug that resists a first glance, the intermittent flake, the regression that crept in between two known-good states. It refuses to theorise until it has a **tight feedback loop** — one command that already goes red on *this* bug — then fixes with a regression test. Its post-mortem hands off to **`kbg:improve-codebase-architecture`** when the real finding is that there's no good seam to lock the bug down.

- **A huge, foggy effort — a greenfield project or a huge feature build, too big for one session** → **`kbg:wayfinder`**. When the way from here to the destination isn't visible yet, it charts a **shared map** of investigation tickets on the issue tracker and resolves them one at a time — producing **decisions, not deliverables** — until the fog is pushed back and the way is clear. Then it merges onto the main flow at **`kbg:to-spec`** (or, if the effort turned out small enough, straight to **`/ship`**). Where **`kbg:grilling --with-docs`** sharpens an idea you can hold in one session, wayfinder is for the idea you can't.

## Codebase health

Not feature work — upkeep.

- **`kbg:improve-codebase-architecture`** — run whenever you have a spare moment to keep the codebase good for agents to operate in. It surfaces deepening opportunities; picking one _generates an idea_ you can take into the main flow at `kbg:grilling`.

## Vocabulary underneath

Two model-invoked references that run *beneath* the other skills — each the single source of truth for its vocabulary. Reach for them directly when the **words**, not the process, are the problem; or let the skills above pull them in.

- **`kbg:domain-modeling`** — sharpen the project's *domain* language: challenge a fuzzy term, resolve an overloaded word, record a hard-to-reverse decision as an ADR. It's the active discipline `kbg:grilling --with-docs` drives to keep `CONTEXT.md` a clean glossary.
- **`kbg:codebase-design`** — the deep-module vocabulary (module, interface, depth, seam, adapter, leverage, locality) for designing a module's *shape*. `kbg:tdd` and `kbg:improve-codebase-architecture` both speak it.

## Crossing sessions

- **`kbg:handoff`** — when a thread is full or you need to branch off (e.g. into a `prototype` session), this compacts the conversation into a markdown file. You don't continue in place — you **open a new session and reference that file** to carry the context across. It's the bridge between context windows, in either direction. Use it when you want a **fresh session** but need the **current conversation preserved**.
- **`/compact`** (built-in) — stay in the **same conversation**, letting the earlier turns be summarized. Use it at **intentional breaks between phases**, when you don't mind losing the verbatim history. Don't compact mid-phase — the agent can lose its way. `kbg:handoff` forks; `/compact` continues.

## Standalone

Off the main flow entirely.

- **`kbg:grilling`** (default mode) — the same relentless interview as `--with-docs`, but for when you have **no codebase**. Stateless: it saves nothing locally, builds no `CONTEXT.md`. Reach for it to sharpen any plan or design that doesn't live in a repo.
- **`prototype`** — a small, throwaway program that answers one design question: does this state model feel right, or what should this UI look like. Throwaway from day one — keep the answer, delete the code. It's the detour in step 2 of the main flow, but reach for it any time a design question is hard to settle on paper.
- **`kbg:research`** — delegate reading legwork to a background agent: it investigates a question against primary sources, then leaves a cited Markdown file in the repo. Keep working while it reads. The file it produces is something to take *into* the main flow at `kbg:grilling` — research feeds the thinking, it doesn't replace it.
- **`kbg:teach`** — learn a concept over multiple sessions, using the current directory as a stateful workspace.
- **`kbg:writing-great-skills`** — reference for writing and editing skills well.

## Precondition

**`kbg:setup-matt-pocock-skills`** — run before your first engineering flow to configure the issue tracker, triage labels, and doc layout the other skills assume. Custom issue trackers also work.

## Done when

The user is routed to the single correct next skill (or told none fits) — verify the chosen skill's trigger matches the user's actual ask.
