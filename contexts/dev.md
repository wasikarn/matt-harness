# Development Context

Mode: Active development
Focus: Implementation, coding, building features

## Behavior
- Interrogate the task first (Rule 3) — vague verb, missing edge case, untestable acceptance criterion? Ask, don't assume.
- Define done before starting; verify against it after (Rule 4) — a clean-looking diff isn't a passing one until you've run the build/test/lint and read the actual output.
- Surgical diffs — change only what the task needs. Flag adjacent issues; don't silently fix them.
- Match the surrounding code's idiom, naming, and comment density.

## Scope the solution before writing it

Read the code the change touches and trace the real flow first — never skip reading to get here
faster. Then stop at the first rung that holds:

1. Does this need to exist at all? Speculative need = skip it (Rule 2).
2. Already in this codebase? Reuse it — don't rewrite what's a few files over.
3. Stdlib covers it? Use it.
4. Native platform feature covers it? Use it.
5. Already-installed dependency solves it? Use it — don't add one for what a few lines can do.
6. Can it be one line? One line.
7. Only then: the minimum code that works.

Mark a deliberate shortcut that cuts a real corner (a global lock, an O(n²) scan, a naive
heuristic) with a `ponytail:` comment naming the ceiling and the upgrade trigger — e.g.
`# ponytail: global lock, per-account locks if throughput matters`. An unmarked shortcut is
invisible; a marked one is a decision, not debt nobody chose.

Bug fix = root cause, not symptom. A report names a symptom — before editing, grep every caller
of the function you're about to touch. A guard in the shared function is usually a smaller diff
than a guard in every caller, and it's the only fix that also closes the same bug in every
sibling caller the ticket didn't name.

Never simplify away input validation at trust boundaries, error handling that prevents data
loss, security, or accessibility — laziness stops there.

## Route to a specialist agent when the work fits one
- A feature that needs a design pass first → `code-architect` for the blueprint, then `/mattpocock-skills:implement` to write it
- Build/compile failure → `build-error-resolver`
- Dead code, unused exports, duplication → `refactor-cleaner`
- Bottleneck, bundle size, render/memory issue → `performance-optimizer`

## Tools to favor
- Edit, Write for code changes
- Bash for running tests/builds
- Grep, Glob for finding code

## Not this frame's job
A full spec→ship pipeline is a skill or command (`/mattpocock-skills:implement`), not this frame — `/frame dev` only sets posture for the current conversation, it doesn't replace those workflows.
