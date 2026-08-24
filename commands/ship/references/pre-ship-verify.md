# Pre-ship verification

Detailed reference for the deterministic verification gate `/ship` runs in Phase 5. It was formerly the standalone `/pre-ship-verify` command.

## When this runs

`/ship` Phase 5 invokes this gate after Phase 4 (Implement) completes. The gate reports GREEN / AMBER / RED; RED stops the pipeline before Phase 6.

## Core principles

- **Done is deterministic.** The project's test suite + type-check are the machine-checkable signal; the Phase 3 criteria are cross-checked against them.
- **Machine-checkable first.** Test exits, type-check, file states are verified automatically. Prose/manual criteria are surfaced for human judgment.
- **Never auto-ship.** This gate reports; it does not merge, push, or release.
- **One task at a time.** A single criteria set per `/ship` invocation.

## Step 1 — Run the deterministic gates

1. **Test suite** — auto-detect the runner and run it from the repo root:

   | Signal | Detected via | Command |
   |--------|--------------|---------|
   | npm | `package.json` + `scripts.test` | `npm test` |
   | pnpm | `pnpm-lock.yaml` | `pnpm test` |
   | yarn | `yarn.lock` | `yarn test` |
   | python | `pyproject.toml`/`pytest.ini`/`setup.cfg` | `pytest` |
   | go | `go.mod` | `go test ./...` |
   | rust | `Cargo.toml` | `cargo test` |

   If the project has no test runner, state that and rely on the type-check + manual verification.

2. **Type-check** if the stack has one:

   | Stack | Command |
   |-------|---------|
   | TypeScript | `tsc --noEmit` (or `vue-tsc --noEmit`) |
   | Python | `mypy .` (if configured) |
   | Go | `go vet ./...` |
   | Rust | `cargo check` |

## Step 2 — Cross-check the outer `/ship` Phase 3 criteria

For each Phase 3 criterion, confirm a deterministic signal satisfies it (a test that passed, a clean type-check, a file now present). Mark each PASS / MANUAL / FAIL:

- **PASS**: a machine signal confirms it.
- **MANUAL**: the criterion is inherently human (visual/UX, a runbook step, a doc review) — surfaced for the user.
- **FAIL**: a signal contradicts it (a test failed, the type-check errors, the expected file is absent).

## Step 3 — Report + gate

```markdown
## Pre-Ship Verification: <task-name>

Tests: <runner result — pass/fail counts>
Type-check: <clean / N errors>

Criteria: <PASS N · MANUAL N · FAIL N>

**Result**: [GREEN / AMBER / RED]
- GREEN: tests pass + type-check clean + every criterion PASS (FAIL=0).
- AMBER: tests + type-check pass, but some criteria are MANUAL (no failures).
- RED: any test fails, type-check errors, or a criterion FAILs.
```

**RED:** list each failure with the failing test/command and exit code. Recommend fixing before re-running Phase 5. Do NOT proceed to Phase 6.

**AMBER:** list the MANUAL criteria and ask the user to confirm them before proceeding — confirming
moves to Phase 6 (Review); declining means treating the criterion as unmet, same as a FAIL: go
back to Phase 4 or explicitly accept the risk and note it in the audit trail.

**GREEN:** state the change is verified. Suggest next step:
- Not pushed yet → push the branch, then proceed to Phase 6 (`mattpocock-skills:code-review`).
- Proceed to Phase 6 regardless of whether a PR exists — `mattpocock-skills:code-review`
  diffs against a fixed point (e.g. the merge-base), not a PR, so it doesn't need one. **A PR is not required
  until Phase 8** (`/ship-merge` hard-requires one); if none exists yet, that's handled there
  via `kbg:pr`, not here.

## Step 4 — Audit trail

Append to `.scratch/<slug>/verification-log.jsonl`:

```json
{"timestamp":"<ISO>","command":"/ship Phase 5","slug":"<slug>","tests":"pass","typecheck":"clean","criteria":{"pass":N,"manual":N,"fail":N},"result":"green|amber|red","note":"<optional — why a MANUAL criterion was accepted as risk, when applicable>"}
```

## Anti-patterns

- Running without the project test suite when one exists.
- Ignoring a failing type-check ("just types, not a real bug").
- Auto-proceeding on AMBER without manual confirmation.
