# Hook Lifecycle Contracts

Per-event **behavior contract** for the 4 hook events / 7 hooks kbg registers, separated
from **execution** (`hooks/hooks.json` dispatch → which script fires on which event/matcher).
This is the contract layer ECC separates as `memory-persistence/` (lifecycle definitions)
from `hooks.json` (execution): this file is the *behavior* contract — what each event
promises to do and NOT do.

## Hook convention (from CLAUDE.md)

**PreToolUse gates** — emit JSON `permissionDecision` (`deny`/`ask`/`none`) on stdout and exit
**0** so the decision is honored (exit 2 discards the JSON and falls through to the default).
The gate is a *verifier*: deterministic shell returning a branchable result. The model is the
*maker* and can never grade its own work — so gates deny the irrecoverable set computationally;
everything else is advisory.

All hooks degrade gracefully when external tools (`rtk`, `qmd`, `code-review-graph`) are
absent (`command -v` guard, silent no-op).

## The 2×2 cell each event populates

| Direction × Execution | Computational (deterministic) | Inferential (semantic) |
|---|---|---|
| **Feedforward** (steer before) | PreToolUse gates that deny/ask | doctrine injection (SessionStart) + `flow-nudge` (UserPromptSubmit) + skill `description:` triggers |
| **Feedback** (observe after) | `cost-tracker` (Stop, metrics journal — not enforcement) | *(none currently wired)* |

**Invariant — inferential FB is advisory only.** No inferential-FB sensor may emit a
`permissionDecision` (LLM-judge circularity: the same model class judging its own generation;
a model-driven mutation gate violates the autonomy invariant). The computational column does
the enforcement. The retired `inferential-structural-judge`, `verification-gate`, and
`fabrication-verdict-log` inferential-FB sensors were removed in the v0.6.0 cut; re-wiring any
of them requires a different model class than the maker and an advisory-only (never-gate) contract.

## Per-event contract

| Event | Hook(s) | Type | Contract |
|---|---|---|---|
| SessionStart | `doctrine-bootstrap.sh` | FF / inferential | Inject `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context. Matcher-less. |
| SessionStart | `command-root-anchor.sh` | FF / computational | Bridge hook-only `${CLAUDE_PLUGIN_ROOT}` into the session as `${KBG_PLUGIN_ROOT}` (via `CLAUDE_ENV_FILE`) so command markdown can reference bundled scripts portably. Matcher-less. |
| UserPromptSubmit (*) | `flow-nudge.sh` | FF / inferential | Advisory: when the prompt looks like non-trivial engineering work, nudge `kbg:grilling` → `kbg:to-prd` → `kbg:to-issues` → `/ship`. Never blocks. |
| PreToolUse (Bash) | `irrecoverable.sh` | FF / computational | Deny irrecoverable Bash patterns (`rm -rf`, `push --force`, `--no-verify`, `reset --hard`, `clean -f`). Emit `permissionDecision`. |
| PreToolUse (Write\|Edit\|MultiEdit) | `path-hardcode.sh` | FF / computational | Deny hardcoded `/Users/<name>` paths in `.sh`/`.py` content. Emit `permissionDecision`. |
| PreToolUse (Write\|Edit\|MultiEdit) | `verifier-protect.sh` | FF / computational | `ask` edits to BOTH non-model verifiers — `hooks/gates/**` + `hooks/hooks.json` (the deny-gates + wiring) AND `skills/harness-audit/scripts/audit.sh` + `checks/**` (the audit grader). Tamper-resistance: the model cannot edit the code that judges it. Both verifiers guarded — a half-protected perimeter is worse than none. `--health` reporter (`harness-health.py`/`health.sh`) is NOT a grader, stays unguarded. No env-var bypass. |
| Stop | `cost-tracker.sh` | FB / computational | Track cumulative token/cost metrics per session; append to `~/.local/share/kbg/metrics/costs.jsonl`. Async; no enforcement. |

**No `TaskCompleted`, `SessionEnd`, or `PostToolUse` hooks are registered.** The retired F7 TaskCompleted gate
and the SessionEnd inferential-FB sensors were removed in the v0.6.0 cut; the `PostToolUse` `observe.sh`
sensor (retired-L4 residue that wrote `observations.jsonl` for the removed `/learn` command) was removed in
v0.6.7. `hooks/hooks.json` wires only the 4 events above.

The audit checks are `skills/harness-audit/scripts/audit.sh` (run on demand, not as a hook).