# Hook Lifecycle Contracts

Per-event **behavior contract** for the 7 hook events / 23 hooks kbg registers, separated
from **execution** (`hooks/hooks.json` dispatch → which script fires on which event/matcher).
This is the contract layer ECC separates as `memory-persistence/` (lifecycle definitions)
from `hooks.json` (execution): this file is the *behavior* contract — what each event
promises to do and NOT do.

## Hook convention (from CLAUDE.md)

**PreToolUse gates** — emit JSON `permissionDecision` (`allow`/`deny`/`ask`/`defer`) on stdout and exit
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
| **Feedback** (observe after) | `cost-tracker` + `memory-audit-commit` (Stop, async — journal/commit only, `additionalContext` on an async hook delivers next turn not this one, so neither attempts model-facing feedback) + `learn-nudge` (SessionEnd, turn-count volume proxy — not enforcement) | `stale-task-nudge` (Stop, synchronous — the one Stop hook that IS model-facing; see its own row below for why it can't be async) |

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
| UserPromptSubmit (*) | `flow-nudge.sh` | FF / inferential | Advisory: when the prompt looks like non-trivial engineering work, nudge `mattpocock-skills:grilling`, then the user types `/mattpocock-skills:to-spec` → `/mattpocock-skills:to-tickets` → `/ship`. Never blocks. |
| PreToolUse (Bash) | `irrecoverable.sh` | FF / computational | Deny irrecoverable Bash patterns (`rm -rf`, `push --force`, `--no-verify`, `reset --hard`, `clean -f`, `git worktree add -b <new-branch>` when sentinel is present). This is the sole enforcement point for the develop-only branching doctrine — see the WorktreeCreate note below. Emit `permissionDecision`. |
| PreToolUse (Bash) | `convergence-merge-gate.sh` | FF / computational | Block a raw `gh pr merge` on a non-clean review-pr state (`clean != true`); on `clean == true` require CI green — the merge one-way door gates on BOTH clean AND CI-green. Bash fast-path exits 0 on non-merge commands (no python cold-start). Fail-closed on unreadable/missing-`clean` state; no state file → allow (unreviewed is ship-merge's concern). Closes the raw-`gh pr merge` bypass (ship-merge is `disable-model-invocation`, so the convergence gate's enforcement point was never reached). |
| PreToolUse (Write\|Edit\|NotebookEdit) | `verifier-protect.sh` | FF / computational | `ask` edits to BOTH non-model verifiers — `hooks/gates/**` + `hooks/advisory/**` + `hooks/hooks.json` (the deny-gates + advisory sensors + wiring) AND `skills/harness-audit/scripts/audit.sh` + `checks/**` (the audit grader). Tamper-resistance: the model cannot edit the code that judges it. Both verifiers guarded — a half-protected perimeter is worse than none. `--health` reporter (`harness-health.py`/`health.sh`) is NOT a grader, stays unguarded. Also denies hardcoded `/Users/<name>` paths in `.sh`/`.py` content (folded in from the former standalone `path-hardcode.sh`, deleted 2026-07-03). No env-var bypass. |
| PreToolUse (Bash) | `verifier-protect.sh` | FF / computational | The Bash leg of verifier-protect: `ask` on Bash-mediated writes (`tee`, `sed -i`, `cp`, `mv`, redirect) to the same verifier surfaces — closes the Write/Edit matcher's blind spot. Emits `permissionDecision: ask`. |
| PreToolUse (`mcp__.*__execute_sql.*`) | `db-write-gate.sh` | FF / computational | `ask` on any non-proven-read SQL statement on any MCP SQL server — a read-allowlist, not a write-blocklist (an unrecognized statement asks, it does not slip). Fail-safe `ask` on a missing/malformed `tool_input` (isinstance guard). No-op when no such MCP server is configured (matcher never fires). Restored after the v0.6.0 reset deleted the prior version. |
| PreToolUse (TaskUpdate) | `task-complete-separation.sh` | FF / computational | Deny `TaskUpdate(status="completed")` when `agent_type` is present (any subagent) — maker≠checker: a subagent cannot mark its own task completed. The main session (no `agent_type`) owns completion; validator subagents return verdicts to main. Enforces the orchestrate validation chain's B-pass-before-completion computationally. Exit 2 + stderr; fail-safe allow on parse error. Uses `PreToolUse` on `TaskUpdate` rather than the native `TaskCompleted` event; `TaskCompleted` also ships its own decision control (exit 2 blocks completion) and would likely fit this gate too — the choice was implementation history, not a documented limitation of `TaskCompleted`, and isn't planned to change without a concrete reason. |
| PreToolUse (Skill) | `atlassian-mcp-gate.sh` | FF / computational | Marks the session jira-acli-engaged when a `jira-acli:*` skill loads (writes a session marker), so the companion `mcp__.*` cold-start gate below can allow-list it. Never blocks Skill itself. |
| PreToolUse (Skill) | `review-pr-loop-gate.sh` | FF / computational | `ask` (never deny) when `kbg:review-pr` is invoked while the persisted loop verdict says the bounded auto-loop already stopped exhausted (`loop_reason` in ceiling/regressed/churning/stalled, or `force_human=true`) on this exact HEAD + branch — ADR 0009's deliberate human checkpoint against unattended round-burn. Bash fast path exits 0 on non-review-pr skills. Fail-open (allow) on missing/malformed state, git error, moved HEAD, or other branch. Escape: `KBG_SKIP_LOOP_GATE=1` (headless). |
| PreToolUse (`mcp__.*`) | `atlassian-mcp-gate.sh` | FF / computational | Cold-start guard: block a direct Atlassian/Jira/Confluence MCP call before a `jira-acli:*` skill loaded this session — forces routing through jira-acli's templates. Allows every later call once the session is marked engaged (confluence-content page create/update + acli's "When acli can't" fallback legitimately use this same MCP). Escape: `KBG_ALLOW_DIRECT_ATLASSIAN_MCP=1`. |
| PreToolUse (Write\|Edit\|NotebookEdit + Bash) | `worktree-guard.py` | FF / computational | Redirect Write/Edit on a guarded sub-repo main checkout into a session worktree under `~/.worktrees`; deny (not redirect) the Bash-mediated equivalent (a raw shell target can't be rewritten via `updatedInput`). **Status of this claim, corrected 2026-08-20: likely outdated, not vendor-confirmed either way.** This is an internal engineering assumption dated 2026-07-16 (this file's own row), never checked against a primary source until a same-day plan to build a second Bash-`updatedInput` hook prompted the check. That check first produced a fabricated vendor quote (a `WebFetch` call invented specific "does not work for Bash" restriction text that a raw-content re-fetch confirmed does not exist on the page), then, after correcting that, a full raw read of `code.claude.com/docs/en/hooks.md` found: (1) the `updatedInput` field description is fully generic, no tool-type restriction stated anywhere on the page; (2) the `PermissionRequest` event's own official example rewrites a `command` field (`"updatedInput": {"command": "npm run lint"}`) — real vendor evidence of `updatedInput` touching a command-shaped field, though under `PermissionRequest` specifically, not the `PreToolUse` event this gate and `costs.md`'s worked example both use. Evidence now leans toward this working, not against it — but this file's own Bash-branch deny behavior was never empirically re-tested against a live session, so it stays in place pending that test. Full writeup: `docs/research/official-docs-best-practices-prompt-library-costs-audit-2026-08-20.md`. Opt-in and OFF by default — no-op everywhere unless `KBG_GUARDED_WORKSPACE` is set (no workspace path ships in this public plugin). Bash early-exit skips the python3 cold-start when the var is unset or the project dir is outside the guarded workspace. |
| PostToolUse (ExitPlanMode) | `plan-review-nudge.sh` | FF / inferential | Advisory: after a plan is approved, nudge dispatching `kbg:plan-reviewer` for consequential plans before implementing. Never blocks. |
| PostToolUse (Bash) | `compliance-audit-nudge.sh` | FF / inferential | Advisory: after a `git commit`, if a plan was approved earlier this session (bash grep-prefilter on the transcript, then a precise python structural check for an `ExitPlanMode` tool_use with a non-empty plan — "grep gates, python confirms", avoids a python spawn on the common non-commit case), remind the model to tell the user `/kbg:compliance-audit` exists. `compliance-audit` is `disable-model-invocation: true`, so the nudge text instructs relay-to-user, never self-dispatch — confirmed against `commands/compliance-audit.md`'s own frontmatter, not assumed. Never blocks. |
| Stop | `cost-tracker.sh` | FB / computational | Track cumulative token/cost metrics per session; append to `~/.local/share/kbg/metrics/costs.jsonl`. Async; no enforcement. |
| Stop | `memory-audit-commit.sh` | FB / computational | If the project's memory store is already a git repo (opt-in, never auto-`init`s), commit any dirty changes for an audit trail. No-op otherwise. Async; no enforcement. |
| Stop | `stale-task-nudge.sh` | FB / computational, model-facing | If a task created this session (`TaskCreate`) still shows `status: in_progress` with no `TaskUpdate` call for it since, emit `hookSpecificOutput.additionalContext` naming it before the turn ends. **Synchronous, not async** — `Stop` has no passive "show text, turn ends normally" lever at all (confirmed against `hooks.md` before building, not assumed): every field that reaches the model here (`decision: block`, `additionalContext`) forces one more visible agent turn, and an async hook's `additionalContext` only lands on the *next* turn — too late once this turn has already ended. Deduped to one nudge per task per session (`~/.local/share/kbg/task-nudge-sessions/<session_id>-<taskId>` marker) so a task legitimately left `in_progress` across several real turns doesn't re-nag every Stop. Guards on `stop_hook_active` to avoid re-triggering itself. Known gap, not hidden: "untouched since" is a mechanical last-write-wins check on `TaskUpdate` calls, not semantic judgment — it cannot distinguish "forgot to close" from "genuinely still working," so the dedup exists specifically to bound the false-positive cost to one nudge, not to eliminate it. |
| SessionEnd | `learn-nudge.sh` | FB / computational (volume proxy, not content judgment) | Advisory: remind the operator `kbg:learn` exists when the transcript's `"type":"user"` turn count (includes tool-result turns) is ≥3 (`KBG_LEARN_NUDGE_MIN_TURNS` override). Skips `reason: resume` (docs: "Session switched via interactive `/resume`" — the session ended because the user left it for a possibly-different one, not that this session is pausing to continue later) and `reason: clear` (frequent mid-work housekeeping — nudging every `/clear` is nag-fatigue noise, not signal). Emits to **stderr** — SessionEnd stdout is discarded by Claude Code and SessionEnd has no `additionalContext`/decision-control mechanism at all (unlike SessionStart), so stderr is the only channel that reaches the user (confirmed against the hooks reference: `SessionEnd` → "Shows stderr to user only"). Not the retired learn-capture/learn-drain-nudge design (no queue, no state file, no confidence scoring, no python) — it judges nothing about content, only whether the session had enough activity to plausibly be worth a look. |
| InstructionsLoaded | `instructions-loaded-journal.sh` | FB / computational | Appends a JSONL record (`~/.local/share/kbg/metrics/instructions-loaded.jsonl`) each time an instruction file loads into context — which file, when, why. Async; no enforcement. Ships from the plugin cache; landed in `b048052e` (v0.68.399), so it fires under the version a session is actually running, not necessarily this repo's checkout. |

**No `TaskCompleted` hooks are registered.** The retired F7 TaskCompleted gate
and the SessionEnd inferential-FB sensors (`inferential-structural-judge`, `verification-gate`,
`fabrication-verdict-log`) were removed in the v0.6.0 cut; the `PostToolUse` `observe.sh`
sensor (retired-L4 residue that wrote `observations.jsonl` for the removed `/learn` command) was removed in
v0.6.7 — but `PostToolUse` itself was re-wired 2026-07-22 (v0.68.3) with `plan-review-nudge.sh` (above), a
different, unrelated advisory hook; a second, `compliance-audit-nudge.sh` (v0.68.138, above), joined it on
the same event with a different matcher (`Bash` vs. `ExitPlanMode`) — **two PostToolUse hooks are
currently live.** The maker≠checker
enforcement the F7 gate failed to provide is now carried by
`gate:task:complete-separation` on `PreToolUse:TaskUpdate` (above) — a deterministic shell gate, not a
model-as-gate, so it does not re-arm the autonomy invariant the v0.6.0 cut retired. `SessionEnd` itself
was re-wired 2026-07-06 with `learn-nudge.sh` — a computational volume-proxy nudge, not a re-arm of the
retired inferential-FB sensors above (those judged session *content*; this judges nothing beyond a raw
turn count, and never emits a decision). `hooks/hooks.json` wires 7 events total: SessionStart,
UserPromptSubmit, PreToolUse, PostToolUse, Stop, SessionEnd, InstructionsLoaded.

**The four `PreToolUse (Bash)` deny/ask gates above** (`irrecoverable.sh`, `convergence-merge-gate.sh`,
the Bash leg of `verifier-protect.sh`, `worktree-guard.py`'s Bash branch) **match `Bash` only, not
`PowerShell`.** `tools-reference.md:361` (confirmed 2026-08-20): "Match `Bash|PowerShell` in hooks
that inspect shell commands... matching `Bash` alone is not enough" — the PowerShell tool delivers
its command in the same `tool_input.command` field. Deliberately not widened: a matcher-only fix
would claim coverage the deny logic doesn't have (`irrecoverable.sh`'s pattern matching is
POSIX-specific and doesn't recognize `Remove-Item -Recurse -Force` etc.), and this repo's dev
environment can't exercise PowerShell to test a real fix. PowerShell is opt-in on macOS/Linux, on
by default on Windows without Git Bash — narrowing this claim rather than widening the gate matches
the correction made to the worktree-guard row above.

**No `WorktreeCreate`/`WorktreeRemove` hooks are registered either**, as of 2026-07-31. A prior
gate (`gate:worktree:develop-only`, `worktree-create-block.sh`) was removed: confirmed against
raw Claude Code doc HTML that those events never send `tool_name`/`tool_input` at all (only
`name` for Create, `worktree_path` for Remove), so the gate's deny logic — which read
`tool_input.branch` — was dead code. Independent of that bug, registering any hook on
`WorktreeCreate` replaces Claude Code's default worktree creation and requires the hook to
itself create the worktree and emit the resulting path, or "worktree creation fails with an
error" — this gate's allow path was a bare `sys.exit(0)` with no output, so it was silently
breaking every legitimate `WorktreeCreate`-triggered worktree (`isolation: "worktree"`
agents/workflows, `claude --worktree`, background sessions) in every repo running this plugin.
Full writeup: `docs/research/official-docs-audit-2026-07-31.md`. The Bash-invoked path (`git
worktree add -b`) was never part of this bug — `WorktreeCreate` doesn't fire for it — and
remains the sole enforcement point, per the PreToolUse (Bash) row above.

The audit checks are `skills/harness-audit/scripts/audit.sh` (run on demand, not as a hook).