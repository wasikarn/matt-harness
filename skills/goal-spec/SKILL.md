---
name: goal-spec
description: "Before a multi-step loop: writes PROMPT.md goal spec (Goal, Done-when, Never-touch, Stop-if) to anchor agent behavior. Use when starting a multi-iteration job or loop with persistence (e.g. /ship-task). Don't use for single-step interactive work."
metadata:
  origin: kbg-native
---

# Goal Spec

Write a `PROMPT.md` goal specification to disk before starting a multi-step agent loop. Without a spec on disk, agents re-plan the same step on every resume (Ralph Wiggum loop, arXiv 2606.10209).

## When to activate

- User is about to run `/ship-task`, a multi-iteration job, or a loop with persistence
- User says "write a spec", "write goal", "spec ก่อน", "let's plan first"
- User is starting work that will span multiple sessions or agent hand-offs
- A loop failed and needs a restart anchor

## Where to write

Write to `PROMPT.md` in the root of the active repo or working directory. If a `PROMPT.md` already exists, read it first and offer to update rather than overwrite.

## Template

Fill in every section. Vague goals produce fake-done completions.

```markdown
# Goal

<One sentence: what the agent should produce or change. Be concrete — name files, APIs, commands.>

## Done when

- [ ] <Verifiable exit criterion 1 — something the agent can check mechanically>
- [ ] <Verifiable exit criterion 2>
- [ ] <Add one per distinct deliverable>

## Never touch

- <File, directory, or surface that must not change>
- (e.g. `package-lock.json`, `docs/`, production config)

## Stop if

- <Condition that indicates the agent is stuck or going wrong>
- (e.g. "any test suite drops below 100% pass rate", "you need credentials not in .env")
```

## Writing good "Done when" criteria

Each criterion must be **mechanically verifiable** — the agent can run a command or read a file to confirm it, not just assert "I finished":

| Weak (fake-done risk) | Strong (verifiable) |
|---|---|
| "Feature is implemented" | "`npm test` exits 0 with coverage ≥ 80%" |
| "All files updated" | "`/usr/bin/grep -r 'oldName' src/` returns empty" |
| "Docs are written" | "`docs/api.md` exists and contains ## Endpoints section" |
| "Tests pass" | "`cargo test 2>&1 \| grep 'test result: ok'"` |

## After writing

Tell the user: "PROMPT.md written. Start your loop with `/ship-task` or your preferred orchestrator — it will read this file on resume to prevent re-planning."
