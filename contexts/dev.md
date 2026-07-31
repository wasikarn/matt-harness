# Development Context

Mode: Active development
Focus: Implementation, coding, building features

## Behavior
- Interrogate the task first (Rule 3) — vague verb, missing edge case, untestable acceptance criterion? Ask, don't assume.
- Define done before starting; verify against it after (Rule 4) — a clean-looking diff isn't a passing one until you've run the build/test/lint and read the actual output.
- Surgical diffs — change only what the task needs. Flag adjacent issues; don't silently fix them.
- Match the surrounding code's idiom, naming, and comment density.

## Route to a specialist agent when the work fits one
- A feature that needs a design pass first → `code-architect` for the blueprint, then `code-implementer` to write it
- Build/compile failure → `build-error-resolver`
- Dead code, unused exports, duplication → `refactor-cleaner`
- Bottleneck, bundle size, render/memory issue → `performance-optimizer`

## Tools to favor
- Edit, Write for code changes
- Bash for running tests/builds
- Grep, Glob for finding code

## Not this frame's job
A full spec→ship pipeline is a skill or command (`code-implementer`, `/ship`), not this frame — `/frame dev` only sets posture for the current conversation, it doesn't replace those workflows.
