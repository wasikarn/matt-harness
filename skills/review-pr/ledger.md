# Rejection-Rate Ledger — Spec

The ledger records **per-question rejection counts** for every `kbg:review-pr` run. It is the state variable that lets SCRUTINIZE-4 **tighten over time** (when a question is being abused as a rubber stamp) without changing the rubric in code — the policy reads the ledger, the SKILL.md just respects what the policy says.

## Path

Per-session, ephemeral, sibling of `rejected.md`:

```
.scratch/review-pr-<UTC-timestamp>/ledger.md
```

Example: `.scratch/review-pr-2026-06-08T15-30Z/ledger.md`. Same scratch dir as `rejected.md` (Phase 3); they belong together (one is the dropped-findings log, the other is the aggregated counter).

## Format

One file per session, append-only. Markdown with a 4-row table — one row per SCRUTINIZE-4 question:

```markdown
# Rejection-Rate Ledger — 2026-06-08T15-30Z

| Q  | Rejected | Survived | Rejection % |
|----|----------|----------|-------------|
| Q1 | 0        | 2        | 0%          |
| Q2 | 1        | 3        | 25%         |
| Q3 | 2        | 2        | 50%         |
| Q4 | 1        | 3        | 25%         |

- **Total findings**: 7
- **Dropped**: 4 (Q1: 0, Q2: 1, Q3: 2, Q4: 1)
- **Agents dispatched**: code-reviewer, silent-failure-hunter
- **PR/scope**: PR #4821 / current branch
- **Tightening policy check**: see `policy.md` § Threshold
```

## Counters

- **Rejected**: findings that failed this Q's falsifiable check (and were written to `rejected.md`).
- **Survived**: findings that passed this Q and entered the tiered list (Critical/Important/Minor).
- **Rejection %**: `Rejected / (Rejected + Survived)`, integer round. Skip if denominator = 0 (write `n/a`).

A finding that fails *multiple* Qs is counted once per Q (e.g. a finding that lacked `file:line` evidence AND only traced the happy path = 1 rejected on Q3 + 1 rejected on Q4). The `Total findings` line in the footer counts unique findings, not Q-failures.

## Retention

- **Cap**: 200 session ledger files. FIFO prune (oldest first) when the count exceeds 200.
- **Per-session TTL**: ledger files in `.scratch/` are local-only and ephemeral (same as `rejected.md`); they do **not** persist across worktrees.
- **Pruning trigger**: on every session start, before writing the new ledger, count existing `.scratch/review-pr-*/ledger.md` files. If ≥ 200, delete oldest by mtime until count is 199, then write the new one (count = 200).

## Aggregation (for Phase 6 trend line)

Phase 6 reads the **last 10 session ledgers** (most recent by mtime) and computes a rolling rejection rate per Q:

```markdown
**Trend (last 10 sessions)**:
Q1: 12% (was 8%) — stable
Q2: 18% (was 22%) — improving
Q3: 67% (was 45%) — WORSENING → see `policy.md` § Threshold
Q4: 8% (was 6%) — stable
```

The trend line is the *only* output the user sees from the ledger during a session. The full ledger files are local-only and not surfaced.

## Aggregation helper

A small `awk` snippet in `policy.md` (next to the spec) computes the rolling rate from a directory of ledger files. No code, no new hook — just a one-liner the orchestrator can run with `awk` + a `find` pipe. This keeps the ledger dependency-free: no new binary, no install step.
