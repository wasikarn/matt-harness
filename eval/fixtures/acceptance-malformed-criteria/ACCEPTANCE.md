# Malformed-criteria acceptance fixture

Regression fixture for `run-acceptance.py` exit-code contract. This file has a
`## Criteria` section the author clearly intended to fill, but every line under
it is prose — there is not a single `- [ ]` checkbox the runner can parse. The
runner must return exit code 3 (parse error / malformed ACCEPTANCE.md), NOT
exit 0. Before the malformed guard, a zero-checkbox `## Criteria` block parsed
to an empty criteria list and main() returned exit 0 — a malformed contract
silently scored as PASS.

## Criteria

The build must pass and the tests should be green before shipping.
No destructive commands. Reviewer sign-off required.
