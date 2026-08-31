# Fixture CLAUDE.md — check 50 sub-check E (bare token)

Sub-check E backtick violation: run `foo` first (not namespaced — reads as a
callable identifier but resolves to nothing).

Sub-check E slash violation: type /bar to start it (not namespaced — the
correct form is /mattpocock-skills:bar).

Sub-check E adversarial-clean: `mattpocock-skills:foo` (correctly namespaced
inside backticks) must never fire E, and neither must the properly slashed
`/mattpocock-skills:bar`.
