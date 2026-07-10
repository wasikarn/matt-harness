---
name: to-tickets
description: Break a plan, spec, or conversation into tracer-bullet tickets, each declaring its blocking edges. Use when work is ready to publish as ticket-size tasks. Don't use for status updates.
metadata.origin: matt-pocock
disable-model-invocation: true
disable-model-invocation-reason: publishes new issues to the project tracker — user-driven decomposition, not model-self-issued
---

# To Tickets

Break a plan into independently-grabbable tickets using vertical slices (tracer bullets).

The issue tracker and triage label vocabulary should have been provided to you — run `kbg:setup-matt-pocock-skills` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an issue reference (issue number, URL, or path) as an argument, fetch it from the issue tracker and read its full body and comments.

**done when:** the full source plan + every referenced context is in your window. If anything is unreachable, **stop and ask the user** — never invent issue content. Failure mode to avoid: quoting the issue title only and treating it as the brief — that produces slices detached from the actual decision context.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

**done when:** you can name the modules the slices will touch and the vocabulary they must use. Failure mode to avoid: scoping into a hard problem ("re-architect the state machine") instead of prefactoring it — pre-factored code makes a thin slice; un-factored code makes a thick one.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

<vertical-slice-rules>

- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Any prefactoring should be done first

</vertical-slice-rules>

A **wide refactor** (one mechanical change whose blast radius fans across the codebase — rename a column, retype a shared symbol) is the exception: no vertical slice can land green, so sequence it by **expand–contract** instead. See **Wide refactors** in the Reference section below.

**done when:** every slice is a vertical path (schema → API → UI → tests), not a horizontal layer (all schemas, then all APIs, then all UI). Failure mode to avoid: producing a layer-by-layer split that delivers no end-to-end behaviour — AFK agents cannot start a slice that doesn't compile or render. Premature completion here = "they can be re-ordered later"; honour the slice today.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?

Iterate until the user approves the breakdown.

**done when:** the user signs off on the slice list and dependencies; if a user story is uncovered, it is named and absorbed into a slice before you proceed. Failure mode to avoid: presenting one slice and racing into publish — premature completion = publishing with uncovered stories or wrong dependencies.

### 5. Publish the tickets to the configured tracker

Publish the approved tickets. **How** depends on the tracker `kbg:setup-matt-pocock-skills` configured — the tickets are the same either way, only the shape of the blocking edges changes:

- **Local files** → write one `tickets.md` in the repo root, all tickets in dependency order (blockers first), each with its "Blocked by" listing the titles it depends on. Use the file template below.
- **A real issue tracker** → publish one issue per ticket in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field. Use the issue body template below. These issues are considered ready for AFK agents, so publish them with the correct triage label unless instructed otherwise.

Where the tracker supports it, link each slice to its parent as a native **sub-issue** and wire each blocker as a native **blocking edge**; the `## Parent` and `## Blocked by` body sections are the fallback otherwise.

**done when:** every approved slice has a real issue id (or a `tickets.md` entry) on the tracker; the dependency graph matches what the user approved; the parent issue is untouched. Failure mode to avoid: re-opening scope mid-publish (adding a slice the user did not approve) — that's premature completion on the gathering path: the user trusted the approved set, and silent expansion corrodes that trust.

<tickets-file-template>

# Tickets: <short name of the work>

A one-line summary of what these tickets build. Reference the source spec if there is one.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

## <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective — not a layer-by-layer implementation list.

**Blocked by:** the titles of the tickets that gate this one, or "None — can start immediately".

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

## <Ticket title>

...

</tickets-file-template>

<issue-template>
## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced code that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), add a context pointer to where that prototype code lives rather than inlining it.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

</issue-template>

## Reference

### Wide refactors

A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own issue blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in an issue blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify issue — green is promised only there.

Do NOT close or modify any parent issue.

## Suggested next step

- Tickets split → `/ship` per ticket, each in a fresh session.
- Publish to Jira instead → `jira-acli:jira-content` (reshape each ticket to the canonical Task/Sub-task template; don't hand-build ADF).
