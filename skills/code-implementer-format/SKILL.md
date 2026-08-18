---
name: code-implementer-format
description: Catalog of code-implementer's Failure modes to avoid and Report format template. Use when code-implementer runs. Don't use for other agents or standalone implementation.
metadata:
  origin: kbg
---

# Code-Implementer Failure Modes & Report Format Reference

Extracted from `agents/code-implementer.md` (2026-08-18, harness-audit check 60 threshold) to
keep the agent body under 20,000 chars. Loaded via `Skill(kbg:code-implementer-format)` — this
agent carries the `Skill` tool and already uses this runtime-call pattern (see its Step 1). Read
it alongside `agents/code-implementer.md`: the `DONE_WITH_CONCERNS` decision rule referenced by
the `## Status` field below lives in that file, not here.

## Failure modes to avoid

- **Overengineering**: adding helpers/utilities/abstractions the task didn't ask for. Make the
  direct change instead.
- **Scope creep**: fixing unrelated "while I'm here" issues. Stay inside the task.
- **Premature completion**: reporting DONE before running verification, or before the Step 5 pass.
- **Test hacks**: loosening or deleting a test to make it pass instead of fixing the cause.
- **Skipping exploration**: jumping to code before reading how the codebase already does this.
- **Debug leaks**: leftover `console.log`/`print`/`TODO`/`HACK`/debugger statements — grep changed
  files before reporting.
- **Self-review residue**: backup/mutated-copy/scratch files created to probe a fix (mutation
  testing, before/after comparisons) left behind after the self-review pass — restore the original
  and delete them before reporting, the same discipline as grepping debug leaks out of changed
  files.
- **Type escape hatches**: `any`, unchecked `as` casts, `// @ts-ignore`, a bare `except:` used to
  route around a type the design should have modeled properly. Fix the type, don't suppress it.

## Report format

```markdown
## Changes Made
- `file.ts:42-55`: [what changed and why]

## Skill Loaded
[kbg:<name>, or "none — no stack match"]

## Verification
- Build: [command] -> [pass/fail]
- Tests: [command] -> [X passed, Y failed]

## Adversarial Self-Review
- Tried to break: [what you attacked]
- Fixed: [what you changed as a result]
- Residual concerns (if any): [named honestly, not hidden]

## Status
DONE (provisional — pending code-reviewer + gauntlet) | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
```

## When NOT to use this agent

- Need a design/blueprint before code exists → `code-architect`
- Need service-boundary / API-contract design → `backend-architect`
- Code exists but the build is red → `build-error-resolver`
- Removing dead code, not adding new code → `refactor-cleaner`
- Optimizing an existing slow path → `performance-optimizer`
- Need the independent verdict on this agent's own output → `code-reviewer` (or the matching
  language reviewer)
- Want tests written first, feature after → the `tdd` skill
- Want to drive implementation yourself, interactively, in one chat turn — not dispatched
  autonomously → matt's implement skill (user-invoked only, `disable-model-invocation: true`;
  type `/mattpocock-skills:implement` yourself)

Done when the report matches this template field-for-field and none of the Failure modes above
describes what this task's implementation just did.
