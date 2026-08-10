# Fixture CLAUDE.md — check 55 good

Sub-check A clean: follow the `mattpocock-skills:foo` doctrine (resolves in the fixture cache).

Sub-check B clean: `mattpocock-skills:bar` (type `/mattpocock-skills:bar`) is `disable-model-invocation: true`,
matching the fixture cache frontmatter — only the user can start it.

Sub-check B adversarial-clean: kbg's own surfaces carry `disable-model-invocation: true`
too — a generic flag mention with no matt token on the line must never fire B.

