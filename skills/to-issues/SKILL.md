---
name: to-issues
description: Slice a plan into vertical slices through every layer. Use when a plan is ready to publish as ticket-size tasks. Don't use for status updates.
metadata.origin: matt-pocock
disable-model-invocation: true
disable-model-invocation-reason: publishes new issues to the project tracker — user-driven decomposition, not model-self-issued
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

The issue tracker and triage label vocabulary should have been provided to you — run `/setup-matt-pocock-skills` if not.

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
- Any prefactoring should be done first

</vertical-slice-rules>

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

### 5. Publish the issues to the issue tracker

For each approved slice, publish a new issue to the issue tracker. Use the issue body template below. These issues are considered ready for AFK agents, so publish them with the correct triage label unless instructed otherwise.

Publish issues in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field.

**done when:** every approved slice has a real issue id on the tracker; the dependency graph matches what the user approved; the parent issue is untouched. Failure mode to avoid: re-opening scope mid-publish (adding a slice the user did not approve) — that's premature completion on the gathering path: the user trusted the approved set, and silent expansion corrodes that trust.

<issue-template>
## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- A reference to the blocking ticket (if any)

Or "None - can start immediately" if no blockers.

</issue-template>

Do NOT close or modify any parent issue.
