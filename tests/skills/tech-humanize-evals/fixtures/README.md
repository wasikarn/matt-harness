# Eval fixtures

The 4 input drafts that `evals.json` evaluates the model against. Each fixture matches the `DRAFT:` block of its eval prompt verbatim, extracted into a standalone file so:

1. **Diffing inputs across versions is trivial** — `git diff fixtures/` shows exactly what changed.
2. **Eval runners can hydrate prompts at runtime** — load fixture, append humanize instruction, send to model.
3. **The fixture IS the audit record** — anyone reviewing the eval knows what the model saw. Inline DRAFTs in `evals.json` force reviewers to scroll a giant prompt string to find the test input.

## Mapping

| File | eval `id` | `eval_name` |
|------|-----------|-------------|
| `0-internal-standup.txt` | 0 | `internal-standup-report` |
| `1-ui-error.txt` | 1 | `user-facing-error-message` |
| `2-strategy-blog.txt` | 2 | `strategy-blog-prose` |
| `3-terminology-drift.txt` | 3 | `terminology-drift-calque-detection` |

## When to update

Update the fixture whenever you change the `DRAFT:` block of an eval prompt. Then update the eval's `expectations` if the new draft needs new asserts. Keep the two in lockstep — a fixture that disagrees with the inline prompt silently tests nothing.
