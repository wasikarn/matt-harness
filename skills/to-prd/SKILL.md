---
name: to-prd
description: "Synthesise-seam: turn a prior discussion into a published PRD without re-interviewing. Use when the user asks for a PRD. Don't use for undecided scope."
metadata.origin: matt-pocock
disable-model-invocation: true
disable-model-invocation-reason: publishes a PRD to the project issue tracker — user opts into the artifact
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know.

The issue tracker and triage label vocabulary should have been provided to you — run `kbg:setup-matt-pocock-skills` if not.

## Process

1. Sketch out the seams at which you're going to test the feature. Existing seams should be preferred to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can. The fewer seams across the codebase, the better - the ideal number is one.

**done when:** seams are explicit, the user has agreed them, and an agent can implement against them without further interview. Failure mode to avoid: publishing a PRD whose seams the agent will later re-litigate — that puts synthesis work on the implementer's shoulders instead of yours.

2. Write the PRD using the template below, then publish it to the project issue tracker. Apply the `ready-for-agent` triage label - no need for additional triage.

**Publishing to Jira specifically:** this skill's template is a synthesis format, not the tracker's canonical content shape. Never call `acli`/an Atlassian MCP tool directly with this PRD text. If the project has the `jira-acli` plugin available, hand off to `jira-acli:jira-content` to reshape this PRD's content into its Bug/Story/Task/Epic template before the write — that skill owns the ADF-safety plumbing and the template standard this one doesn't. If `jira-acli` isn't available, say so before publishing rather than hand-building ADF.

**done when:** the issue exists on the tracker with the agreed seams, user stories, and testing decisions; the body matches the template shape appropriate for that tracker (not just this skill's PRD shape); further cycles return to step 1 (seams) before step 2 (publish). Failure mode to avoid: silent re-opening of seams mid-publish — that is premature completion on the gathering path.

<prd-template>

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.

</prd-template>

## Suggested next step

- PRD ready → `kbg:to-issues` to split it into grabbable issues.
- Publish to the tracker instead → `jira-acli:jira-content` (reshape to the canonical Story/Task template; don't hand-build ADF).
