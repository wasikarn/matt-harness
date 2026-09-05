# mattpocock-skills integration map

Which installed `mattpocock-skills` skill each mh surface routes to, and which are deliberately
unrouted. Column 2 is `model` (model-invocable) or `user` (`disable-model-invocation: true`,
cited as the literal slash form `/mattpocock-skills:<name>` the user types). Re-verify whenever
the `mattpocock-skills` cache version changes. No check parses this table.

| skill | invocation | mh touchpoint or deferral |
|---|---|---|
| ask-matt | user | the routing layer for "which matt skill" questions; mh ships no router of its own |
| code-review | model | the review surface. Main session only: its internal Standards/Spec fan-out spawns subagents, which native `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` denies from inside a dispatched subagent. Shares its bare name with Claude Code's built-in `/code-review`; the namespaced form is unambiguous |
| codebase-design | model | `agents/code-architect.md`, `agents/backend-architect.md` boundary lines (deep-module vocabulary mid-blueprint) |
| diagnosing-bugs | model | METHODOLOGY Rule 4; `skills/workflow/post-mortem/SKILL.md` input contract |
| tdd | model | METHODOLOGY Rule 4 |
| domain-modeling | model | `CLAUDE.md` Agent skills section (root `CONTEXT.md` + `docs/adr/`, created lazily) |
| grill-with-docs, improve-codebase-architecture | user | paths into domain-modeling; unrouted from mh prose |
| grilling | model | `README.md`; escalation beyond `advisor()` for a contested call. Main session only (its research step dispatches a subagent) |
| grill-me, to-questionnaire | user | `agents/requirement-analyst.md` boundary line (live interview vs analyzing a written requirement) |
| research | model | `CLAUDE.md` research section defers to it after qmd/context7. Main session only |
| resolving-merge-conflicts | model | adjacent to `gate:bash:irrecoverable`: its "stage everything" step is why `git add -A` is allowed while `MERGE_HEAD` exists |
| setup-matt-pocock-skills | user | `README.md` Install section. Re-running regenerates its output files from scratch |
| implement, to-spec, to-tickets | user | the spec-to-ship chain; mh names no step of it |
| prototype | model | deferred: no mh surface produces throwaway spikes |
| triage | user | deferred: mh no longer ships a triage-labels doc |
| wayfinder, handoff, teach, wait-what | user | deferred: their former mh touchpoints were deleted in the v1.0.0 rebuild |
| wizard | model | deferred |
| writing-for-agents | model | `CLAUDE.md` Skill authoring doctrine; `docs/reference/skill-authoring-conventions.md` |

## Reverse handoffs

Gaps matt names in his own docs that an mh mechanism happens to answer. Partial answers written
up as partial.

1. **research's no cross-session reuse** ("Does a later session reuse what an earlier run found?
   No.") vs mh's qmd-first rule in `CLAUDE.md`: a standing semantic-search-first step. Caveat:
   `qmd` is operator-environment, not bundled.
2. **improve-codebase-architecture's CDN-fragile HTML report** (Tailwind and Mermaid from CDNs,
   breaks silently offline) vs the operator's `diagram-design` skill, whose output is a
   self-contained HTML file. Caveat: third-party, and it replaces only the diagram half.

## Upstream watch list

Unregistered in matt's own `plugin.json` (`skills/in-progress/*`, `skills/misc/*` in the local
clone); can vanish or reshape without warning.

- `implement-spec`, `retro`: delegation-pattern designs; the principle worth keeping regardless
  is that coding standards belong to the reviewer, not the implementer.
- `setup-ts-deep-modules`: prove the rules bite, do not just document them.
- `git-guardrails-claude-code`: study only; `docs/reference/branching-model.md` forbids running
  its setup here.
