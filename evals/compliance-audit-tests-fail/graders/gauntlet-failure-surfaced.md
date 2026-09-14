---
type: regex
pattern: 'FAIL|AssertionError|exit code 1|non-?zero'
flags: i
match: contains
target: last_message
---
`double()` is implemented correctly (`x * 2`, matching the plan exactly); the test that exists for
it asserts the wrong expected value (`7` instead of `6`), so only running the suite reveals the
failure — a checklist-only read finds nothing to flag. The report must surface the real test
failure, not just the requirement checklist.
