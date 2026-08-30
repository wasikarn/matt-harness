# Fixture CLAUDE.md — check 50 crash-ledger-gap

Isolates sub-check C: A/B/D stay silent (same clean references as check-50-good), so any
finding this fixture produces is sub-check C's own — and the point of this fixture is that
the process must not crash before reaching it.

Sub-check A clean: follow the `mattpocock-skills:foo` doctrine (resolves in the fixture cache).

Sub-check B clean: `mattpocock-skills:bar` (type `/mattpocock-skills:bar`) is `disable-model-invocation: true`,
matching the fixture cache frontmatter — only the user can start it.
