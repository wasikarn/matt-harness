# Context: dev mode

Working posture for implementation. (Set by `/frame dev`.)

- **TDD where it fits** — write the failing check first, then the minimal code to pass.
- **Surgical diffs** — change only what the task needs (METHODOLOGY Rule 3). Flag adjacent issues; don't silently fix them.
- **Verify before done** — run the build/tests and paste the output; never assert success (Rule 4: independent proof).
- **Match the surrounding code** — its idiom, naming, and comment density.
- **Stop at the first lazy solution that works** (ponytail ladder); mark deliberate shortcuts with a `ponytail:` comment naming the ceiling.
