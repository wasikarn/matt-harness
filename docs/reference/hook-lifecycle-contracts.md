# Hook Lifecycle Contracts

Per-event **behavior contract** for the 14 hook events kbg registers, separated
from **execution** (`hooks/hooks.json` dispatch → which script fires on which
event/matcher). This is the contract layer ECC separates as `memory-persistence/`
(lifecycle definitions) from `hooks.json` (execution). kbg's nearest analog
`hooks/JOURNAL-SCHEMA.md` is the *evidence* schema; this file is the *behavior*
contract — what each event promises to do and NOT do.

## Two hook conventions (from CLAUDE.md)

1. **PreToolUse gates** — emit JSON `permissionDecision` (`deny`/`ask`/`none`) on
   stdout; must exit 0 (exit 2 discards the JSON). Assert the emitted decision.
2. **TaskCompleted enforcement** (`task-lifecycle.sh` F7) — uses exit 2 + stderr
   feedback (different convention). F7 tests assert exit code + stderr substring.

All hooks degrade gracefully when external tools (`rtk`, `qmd`,
`code-review-graph`) are absent (`command -v` guard, silent no-op).

## The 2×2 cell each event populates

| Direction × Execution | Computational (deterministic) | Inferential (semantic) |
|---|---|---|
| **Feedforward** (steer before) | PreToolUse gates that deny/ask | doctrine injection + skill `description:` triggers |
| **Feedback** (observe after) | PostToolUse audits, critical-hooks, `audit.sh` | `verification-gate.sh`, `fabrication-verdict-log.sh` (advisory) |

**Invariant — inferential FB is advisory only.** No inferential-FB sensor may emit
a `permissionDecision` (LLM-judge circularity: same model class judging its own
generation; a model-driven mutation gate violates the autonomy invariant). The
computational-FB column does the enforcement.

## Per-event contract

| Event | Direction/Type | Contract | Advisories journal (never block) |
|---|---|---|---|
| SessionStart | FF / inferential | inject L1 doctrine (METHODOLOGY/RTK/ACLI/DBGATE) matcher-less | — |
| PreToolUse (Bash) | FF / computational | `block-dangerous-git`, `secret-scan`, `block-bash-doctrine-write`, `db-write-gate`, `config-protection`, `secret-read-guard` — emit permissionDecision | — |
| PreToolUse (Edit/Write) | FF / computational | `doctrine-edit-gate` (ask), `block-bash-doctrine-write` | — |
| PreToolUse (Agent spawn) | FF / computational | `agent-spawn-gate` — bound un-stoppable fan-out | — |
| PostToolUse | FB / computational | `post-edit-audit.sh`, `security-diff-review.py` | — |
| TaskCompleted | FB / computational | `task-lifecycle.sh` F7 — exit 2 + stderr | — |
| SessionEnd | FB / inferential | — | `verification-gate.sh`, `inferential-structural-judge`, `fabrication-verdict-log.sh` |
| Stop | FB / inferential | — | `fabrication-verdict-log.sh` |

The computational-FB enforcement suite is `tests/hooks/runners/test-critical-hooks.sh`
(critical-hooks); the audit checks are `skills/harness-audit/scripts/audit.sh`.