# Hook Lifecycle Contracts

Per-event **behavior contract** for the 7 hook events / 12 hooks kbg registers, separated
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
| **Feedback** (observe after) | `cost-tracker` (Stop, metrics journal — not enforcement) + `learn-nudge` (SessionEnd, turn-count volume proxy — not enforcement) | *(none currently wired)* |

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
| UserPromptSubmit (*) | `flow-nudge.sh` | FF / inferential | Advisory: when the prompt looks like non-trivial engineering work, nudge `kbg:grilling` → `kbg:to-spec` → `kbg:to-tickets` → `/ship`. Never blocks. |
| PreToolUse (Bash) | `irrecoverable.sh` | FF / computational | Deny irrecoverable Bash patterns (`rm -rf`, `push --force`, `--no-verify`, `reset --hard`, `clean -f`, `git worktree add -b <new-branch>` when sentinel is present). Emit `permissionDecision`. |
| PreToolUse (Write\|Edit\|MultiEdit) | `path-hardcode.sh` | FF / computational | Deny hardcoded `/Users/<name>` paths in `.sh`/`.py` content. Emit `permissionDecision`. |
| PreToolUse (Write\|Edit\|MultiEdit) | `verifier-protect.sh` | FF / computational | `ask` edits to BOTH non-model verifiers — `hooks/gates/**` + `hooks/hooks.json` (the deny-gates + wiring) AND `skills/harness-audit/scripts/audit.sh` + `checks/**` (the audit grader). Tamper-resistance: the model cannot edit the code that judges it. Both verifiers guarded — a half-protected perimeter is worse than none. `--health` reporter (`harness-health.py`/`health.sh`) is NOT a grader, stays unguarded. No env-var bypass. |
| PreToolUse (TaskUpdate) | `task-complete-separation.sh` | FF / computational | Deny `TaskUpdate(status="completed")` when `agent_type` is present (any subagent) — maker≠checker: a subagent cannot mark its own task completed. The main session (no `agent_type`) owns completion; validator subagents return verdicts to main. Enforces the orchestrate validation chain's B-pass-before-completion computationally. Exit 2 + stderr; fail-safe allow on parse error. (Uses PreToolUse on `TaskUpdate`, not the `TaskCompleted` event, because PreToolUse input is docs-confirmed to carry `tool_input.status` + `agent_type`.) |
| Stop | `cost-tracker.sh` | FB / computational | Track cumulative token/cost metrics per session; append to `~/.local/share/kbg/metrics/costs.jsonl`. Async; no enforcement. |
| SessionEnd | `learn-nudge.sh` | FB / computational (volume proxy, not content judgment) | Advisory: remind the operator `kbg:learn` exists when the transcript's `"type":"user"` turn count (includes tool-result turns) is ≥3 (`KBG_LEARN_NUDGE_MIN_TURNS` override). Skips `reason: resume` (docs: session is suspending for later resumption, not closing out) and `reason: clear` (frequent mid-work housekeeping — nudging every `/clear` is nag-fatigue noise, not signal). Emits to **stderr** — SessionEnd stdout is discarded by Claude Code and SessionEnd has no `additionalContext`/decision-control mechanism at all (unlike SessionStart), so stderr is the only channel that reaches the user (confirmed against the hooks reference: `SessionEnd` → "Shows stderr to user only"). Not the retired learn-capture/learn-drain-nudge design (no queue, no state file, no confidence scoring, no python) — it judges nothing about content, only whether the session had enough activity to plausibly be worth a look. |
| WorktreeCreate | `worktree-create-block.sh` | FF / computational | Deny when `/.kbg-no-worktree` sentinel is present in the resolved repo root (`CLAUDE_PROJECT_DIR` env first, then walk-up to `.git` or sentinel, max 16 levels) **and** `tool_input.branch` is set **and** `branch != "develop"` **and** the request is NOT the review-pr allowlist shape (`detach=true` AND `path` matches `review-pr-<N>` AND no `-b` flag). Defensive `git rev-parse --verify develop` runs when `branch == "develop"`; a typo'd branch name like `developp` is denied. Fail-safe allow on parse error / unresolved root. Exit 2 + stderr. Matcher-less (silently ignored per CC docs). The companion `Bash` `git worktree add` deny is enforced by `irrecoverable.sh` above (the WorktreeCreate event does not fire for Bash-invoked worktree creation). |
| WorktreeRemove | `worktree-create-block.sh` | FF / computational (observer) | No-op allow. Symmetric with `WorktreeCreate` so future audit checks can verify both events are wired. CC docs confirm `WorktreeRemove` has no decision control. |

**No `TaskCompleted` or `PostToolUse` hooks are registered.** The retired F7 TaskCompleted gate
and the SessionEnd inferential-FB sensors (`inferential-structural-judge`, `verification-gate`,
`fabrication-verdict-log`) were removed in the v0.6.0 cut; the `PostToolUse` `observe.sh`
sensor (retired-L4 residue that wrote `observations.jsonl` for the removed `/learn` command) was removed in
v0.6.7. The maker≠checker enforcement the F7 gate failed to provide is now carried by
`gate:task:complete-separation` on `PreToolUse:TaskUpdate` (above) — a deterministic shell gate, not a
model-as-gate, so it does not re-arm the autonomy invariant the v0.6.0 cut retired. `SessionEnd` itself
was re-wired 2026-07-06 with `learn-nudge.sh` — a computational volume-proxy nudge, not a re-arm of the
retired inferential-FB sensors above (those judged session *content*; this judges nothing beyond a raw
turn count, and never emits a decision). `hooks/hooks.json` wires only the 7 events above.

The audit checks are `skills/harness-audit/scripts/audit.sh` (run on demand, not as a hook).