# Hook Lifecycle Contracts

Per-event **behavior contract** for the 9 hook events / 24 hooks kbg registers, separated
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

Hooks degrade around the CLI tools they actually depend on, but the mechanism differs per
tool — not a single uniform pattern. `python3`, `jq`, and `git` are each guarded by an explicit
`command -v` check in the hook script itself: `python3`-dependent deny gates (`irrecoverable.sh`,
`db-write-gate.sh`, `verifier-protect.sh`, `atlassian-mcp-gate.sh`, `worktree-guard-dispatch.sh`,
`task-complete-separation.sh`, `doctrine-bootstrap.sh`, `memory-health-nudge.sh`) fail OPEN with a
per-call stderr note when it's missing (announced once, up front, by `doctrine-bootstrap.sh`'s
portability preflight — see #93); `jq`-dependent advisory nudges and the cost tracker
(`stale-task-nudge.sh`, `flow-nudge.sh`, `cost-tracker.sh`, `doctrine-bootstrap.sh`) skip
themselves silently per event; `git`-dependent hooks (e.g. `memory-audit-commit.sh`) exit 0
silently. `trash` is different: there's no `command -v` guard in a hook script — `irrecoverable.sh`
detects it from inside its python3 payload via `shutil.which()`, picking whichever of
`trash`/`trash-put` exists (#93) to name in its deny message, and denies (asks the user first)
rather than silently degrading when neither is present. `jira-acli` is different again: it's a
Claude Code plugin, not a shell binary, so nothing checks for it with `command -v`.
`atlassian-mcp-gate.sh` doesn't feature-detect its installation at all — it only tracks whether a
`jira-acli:*` skill has loaded this session (a session marker file). The only installation-level
feature-detection is in the advisory `jira-route-nudge.sh`, which checks for the plugin's cache
directory (`~/.claude/plugins/cache/wasikarn/jira-acli`, override via `MH_JIRA_ACLI_CACHE`) and
exits silently if absent, added ticket 94. `rtk` and `code-review-graph` have zero call sites in
any shipped hook — they're operator-environment tools referenced only in doctrine prose (CLAUDE.md's
env-quirk notes), never something a hook checks for. `qmd` likewise has no hook call site; it's an
MCP tool referenced only in skill/command doctrine (hedged to "if configured" per ticket 94), not
something any hook invokes or guards.

## Audit-trail substrates are split, not unified

"The audit trail" spans two separate substrates answering two different questions, not one
store — worth naming explicitly since a single-database design (SQLite, one events table)
was evaluated against this split and rejected as not unifying anything real:

- **Categorical, append-only JSONL** — `hooks/gates/` and `hooks/advisory/` write per-install
  runtime journals under `$HOME` (gate-decisions, costs, instructions-loaded, skill-usage,
  nudge-compliance, precompact-snapshots). These answer "how often, and which category" —
  they carry no free-text field, so there is nothing in them for full-text search to index.
- **Prose, git-committed markdown** — decisions, research, and post-mortems as `docs/`
  content and this repo's own memory store, both full-text-and-semantically searchable via
  the `qmd` MCP. These answer "what happened and why."

Nothing currently joins the two — reading "how often" and "why" together means querying
both substrates separately by hand. That is a real gap, but it is a query-surface gap, not
a storage gap: merging both into one SQLite database would not unify anything the two
substrates don't already cover between them, just add a sync burden neither currently has.

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
| SessionStart | `doctrine-bootstrap.sh` | FF / inferential | Inject the core of `docs/METHODOLOGY.md` (everything above the `<!-- core-end -->` marker: decision-sizing triad + reasoning scaffold) into session context; the rest stays on disk behind pointer + `Read`. Matcher-less. |
| SessionStart | `command-root-anchor.sh` | FF / computational | Bridge hook-only `${CLAUDE_PLUGIN_ROOT}` into the session as `${MH_PLUGIN_ROOT}` (via `CLAUDE_ENV_FILE`) so command markdown can reference bundled scripts portably. Matcher-less. |
| UserPromptSubmit (*) | `flow-nudge.sh` | FF / inferential | Advisory: when the prompt looks like non-trivial engineering work, nudge `mattpocock-skills:grilling`, then the user types `/mattpocock-skills:to-spec` → `/mattpocock-skills:to-tickets` → `/mattpocock-skills:implement`. Never blocks. |
| PreToolUse (Bash) | `irrecoverable.sh` | FF / computational | Deny irrecoverable Bash patterns (`rm -rf`, `push --force`, `--no-verify`, `reset --hard`, `clean -f`, `git worktree add -b <new-branch>` when sentinel is present). This is the sole enforcement point for the develop-only branching doctrine — see the WorktreeCreate note below. Emit `permissionDecision`. |
| PreToolUse (Write\|Edit\|NotebookEdit) | `verifier-protect.sh` | FF / computational | `ask` edits to BOTH non-model verifiers — `hooks/gates/**` + `hooks/advisory/**` + `hooks/hooks.json` (the deny-gates + advisory sensors + wiring) AND `skills/meta/harness-audit/scripts/audit.sh` + `checks/**` (the audit grader). Tamper-resistance: the model cannot edit the code that judges it. Both verifiers guarded — a half-protected perimeter is worse than none. `--health` reporter (`harness-health.py`/`health.sh`) is NOT a grader, stays unguarded. Also denies hardcoded `/Users/<name>` paths in `.sh`/`.py` content (folded in from the former standalone `path-hardcode.sh`, deleted 2026-07-03). No env-var bypass. |
| PreToolUse (Bash) | `verifier-protect.sh` | FF / computational | The Bash leg of verifier-protect: `ask` on Bash-mediated writes (`tee`, `sed -i`, `cp`, `mv`, redirect) to the same verifier surfaces — closes the Write/Edit matcher's blind spot. Emits `permissionDecision: ask`. |
| PreToolUse (Write\|Edit) | `config-write-guard.sh` | FF / computational | `ask` before creating a brand-new Claude Code settings file (`.claude/settings.json`, `.claude/settings.local.json`); `ask` on an edit to an existing one only when it changes the `hooks`, `enabledPlugins`, or `env` key (the last because Claude Code injects a settings file's `env` block into hook subprocess environments too, and this repo's own gates honor escape-hatch env vars like `MH_ALLOW_MAIN_EDIT`) — reconstructs the edit (`content` for Write, `old_string`→`new_string` for Edit, honoring `replace_all`) and compares parsed JSON against the on-disk original, every other key stays frictionless. Fail-toward-ask when either side can't be read or parsed (dangling symlink, malformed JSON, non-UTF-8 content). Basename/parent match is case-insensitive (macOS/APFS is case-insensitive but case-preserving). #98. Scope: Write/Edit only — MultiEdit and Bash-mediated writes bypass it, same accepted gap as `credential-guard.sh`'s Bash-mediated-reads gap (#96). |
| PreToolUse (`mcp__.*__execute_sql.*`) | `db-write-gate.sh` | FF / computational | `ask` on any non-proven-read SQL statement on any MCP SQL server — a read-allowlist, not a write-blocklist (an unrecognized statement asks, it does not slip). Fail-safe `ask` on a missing/malformed `tool_input` (isinstance guard). No-op when no such MCP server is configured (matcher never fires). Restored after the v0.6.0 reset deleted the prior version. |
| PreToolUse (TaskUpdate) | `task-complete-separation.sh` | FF / computational | Deny `TaskUpdate(status="completed")` when `agent_id` is present (any subagent) — maker≠checker: a subagent cannot mark its own task completed. The main session (no `agent_id`, `--agent` or not) owns completion; validator subagents return verdicts to main. Enforces the orchestrate validation chain's B-pass-before-completion computationally. Exit 2 + stderr; fail-safe allow on parse error. Uses `PreToolUse` on `TaskUpdate` rather than the native `TaskCompleted` event; `TaskCompleted` also ships its own decision control (exit 2 blocks completion) and would likely fit this gate too — the choice was implementation history, not a documented limitation of `TaskCompleted`, and isn't planned to change without a concrete reason. **Discriminant corrected 2026-08-31:** originally keyed on `agent_type`, which is also set for a top-level `claude --agent <name>` main session (not a subagent) — an adversarial security review of the sibling `agent-recursion-guard.sh` gate caught the same flaw there and it turned out to be pre-existing here too. `agent_id` is present only for an actual subagent call (code.claude.com/docs/en/hooks, confirmed 2026-08-31). |
| PreToolUse (Agent) | `agent-recursion-guard.sh` | FF / computational | Deny `Agent(...)` when `agent_id` is present (any subagent) — only the main session dispatches (CLAUDE.md "Task Dispatch": a sub-agent owns one bounded deliverable, it does not re-orchestrate). Keyed on the CALLER's `agent_id`, not the requested `subagent_type` — closes a real gap found 2026-08-31 where a rogue fork, blocked by the host's own fork→fork guard ("Fork is not available inside a forked worker"), simply requested `subagent_type: general-purpose` instead and succeeded, spawning 4 real background agents the parent session never saw. Exit 2 + stderr; fail-safe allow on parse error; no env-var bypass — same tamper-resistance posture as `task-complete-separation.sh`, its closest sibling. An adversarial security review the same day caught two more real issues before ship: (1) the first cut keyed on `agent_type`, which over-blocks a top-level `--agent` main session — fixed to `agent_id`, the documented subagent-only discriminant; (2) a subagent-controlled `subagent_type` value was interpolated unbounded/unsanitized into the stderr deny message, letting a crafted value forge an extra fake gate-verdict line in the merged multi-gate rejection the model reads back — fixed with newline-stripping + an 80-char clip. **Confirmed collision, resolved as by-design (2026-09-01, issue #118):** `mattpocock-skills:code-review` fans out its own internal sub-reviews as parallel sub-agents (its own SKILL.md, around lines 11 and 58); reproduced live — Skill-calling it from inside an already-dispatched mh subagent has BOTH internal Standards/Spec dispatches denied by this gate (the caller already carries `agent_id`), so the skill produces no report at all from a subagent context. Deliberately NOT carved out: the gate cannot distinguish a skill's documented internal fan-out from the rogue re-orchestration it exists to block (same `agent_id`, same `Agent(...)` shape), and any discriminant would be forgeable by model output. Standing rule instead: **invoke `mattpocock-skills:code-review` from the main session only, never from inside a dispatched subagent** — the ledger's `mattpocock-skills:code-review` row carries the same rule. |
| PreToolUse (Bash) | `agent-recursion-guard.sh` (Bash leg) | FF / computational | Companion to the row above, same script and file: deny a Bash-mediated `claude -p`/`--print`/`--agent`/`--bg` invocation when `agent_id` is present. Closes a coverage gap the same security review found — a subagent retains Bash access, so spawning a nested `claude` session bypasses the Agent-tool leg entirely, and that nested session is its own fresh main session (no `agent_id` of its own) free to dispatch further agents unrestricted. Coarse command-pattern match on the raw string, not an adversarial sandbox — same accepted non-goal as `irrecoverable.sh` (no command-substitution/eval unwrapping, no defeat of deliberate quote-splitting). **Anchored on command position, 2026-08-31:** a fresh adversarial pass reproduced the un-anchored version denying `git commit -m "mention claude -p in docs"`, `echo "claude -p"`, and `grep -r "claude -p" docs/` — real false positives a subagent could trip just documenting this gate. Requires `claude` to sit right after a command-start position (string start, `\|`/`;`/`&`/`(`, `&&`, `\|\|`) or a `VAR=val` prefix chain, which real invocations always look like and prose almost never does; `(` stays an anchor char so `$(claude -p evil)` command substitution is still caught. The same pass also tightened `clip()` to strip all non-printable bytes (was newline/CR only), closing an ANSI-cursor-code terminal-line-overwrite path. **Flag search made quote-aware, 2026-08-31 (second pass):** the flat `[^\|;&]*` exclusion after the anchor treated any `&`/`;`/`\|` as end-of-invocation even inside a quoted prompt argument (`claude "fix A & B" -p`), silently defeating detection — a false negative. Replaced with a scan that consumes a whole quoted span as one token, so an in-quote separator no longer ends the match early while an unquoted one still correctly bounds it (cross-segment separation, e.g. `claude --version ; othertool -p` not matching, verified unchanged). Exit 2 + stderr; fail-safe allow on parse error; no env-var bypass. |
| PreToolUse (Bash) | `subagent-git-guard.sh` | FF / computational | Deny a subagent (`agent_id` present) running `git stash`/`reset`/`clean` via Bash — the bare/non-force forms `gate:bash:irrecoverable` does not already cover unconditionally. Added 2026-09-04, issue #135: two real incidents in one session on a shared working tree — a dispatched builder swept a peer's `CLAUDE.md` into a commit, and a separate dispatched subagent raced `git stash`/`stash pop` over a peer's mid-edit files — both exactly the "No repo-wide git in a concurrent wave" rule `skills/workflow/orchestrate/f9-template.md` already states in prose. Same discriminant as the two sibling gates above (`agent_id`, not `agent_type` — a top-level `--agent` main session legitimately needs these subcommands). Deliberately does NOT re-check `checkout --`/`restore`: `irrecoverable.sh`, read fresh at build time, already denies their destructive forms (`checkout --`/`.`/`-f`/2+ non-flag args; `restore <pathspec>` targeting the worktree) unconditionally for every session, main included — duplicating an existing unconditional deny was rejected as adding a second place to keep in sync for zero behavior change. Fixed 2026-09-04 after an independent verifier live-probed real gaps: walks past git global flags (`-C`/`-c`/`--git-dir`/`--work-tree`/`--config-env`/etc) and a bare `sudo`/`xargs` wrapper before checking the subcommand, anchors `re.MULTILINE` so each line of a multi-line command anchors on its own, and the anchor search is quote-aware so a `;`/`&`/`|`/`(` inside a quoted argument no longer false-positives (as a side effect, a heredoc BODY line that happens to start with `git stash`/`reset`/`clean` as plain text now also anchors and denies — not attempting to parse heredoc boundaries). Coarse command-pattern match, not an adversarial sandbox: this gate's own non-goal is deliberate quote-splitting/variable-indirection/command-substitution obfuscation of the literal word "git" itself (e.g. `g''it stash`, `$(echo git) stash`) — same category the sibling gates disclaim for `claude`/`rm`/etc, no ranking implied between them. Ordinary global flags and quoted-argument punctuation are NOT in this gate's non-goal. Exit 2 + stderr; fail-safe allow on parse error; no env-var bypass. |
| PreToolUse (Skill) | `atlassian-mcp-gate.sh` | FF / computational | Marks the session jira-acli-engaged when a `jira-acli:*` skill loads (writes a session marker), so the companion `mcp__.*` cold-start gate below can allow-list it. Never blocks Skill itself. |
| PreToolUse (`mcp__.*`) | `atlassian-mcp-gate.sh` | FF / computational | Cold-start guard: block a direct Atlassian/Jira/Confluence MCP call before a `jira-acli:*` skill loaded this session — forces routing through jira-acli's templates. Allows every later call once the session is marked engaged (confluence-content page create/update + acli's "When acli can't" fallback legitimately use this same MCP). Escape: `MH_ALLOW_DIRECT_ATLASSIAN_MCP=1`. |
| PreToolUse (Write\|Edit\|NotebookEdit + Bash) | `worktree-guard.py` | FF / computational | Redirect Write/Edit on a guarded sub-repo main checkout into a session worktree under `~/.worktrees`; deny (not redirect) the Bash-mediated equivalent (a raw shell target can't be rewritten via `updatedInput`). **Status of this claim, corrected 2026-08-20: likely outdated, not vendor-confirmed either way.** This is an internal engineering assumption dated 2026-07-16 (this file's own row), never checked against a primary source until a same-day plan to build a second Bash-`updatedInput` hook prompted the check. That check first produced a fabricated vendor quote (a `WebFetch` call invented specific "does not work for Bash" restriction text that a raw-content re-fetch confirmed does not exist on the page), then, after correcting that, a full raw read of `code.claude.com/docs/en/hooks.md` found: (1) the `updatedInput` field description is fully generic, no tool-type restriction stated anywhere on the page; (2) the `PermissionRequest` event's own official example rewrites a `command` field (`"updatedInput": {"command": "npm run lint"}`) — real vendor evidence of `updatedInput` touching a command-shaped field, though under `PermissionRequest` specifically, not the `PreToolUse` event this gate and `costs.md`'s worked example both use. Evidence now leans toward this working, not against it — but this file's own Bash-branch deny behavior was never empirically re-tested against a live session, so it stays in place pending that test. Full writeup: `docs/research/official-docs-best-practices-prompt-library-costs-audit-2026-08-20.md`. Opt-in and OFF by default — no-op everywhere unless `MH_GUARDED_WORKSPACE` is set (no workspace path ships in this public plugin). Bash early-exit skips the python3 cold-start when the var is unset or the project dir is outside the guarded workspace. |
| PreToolUse (Write\|Edit\|MultiEdit\|NotebookEdit) | `main-exec-guard.sh` | FF / computational | Deny-tier, not ask: with `MH_MAIN_EXEC_GUARD=1`, denies the top-level session's own file writes — exit 2 + stderr — so main plans, dispatches, verifies, decides, and never holds the keyboard (ADR 0012). Carve-outs stay writable from main: plan files, the memory store, the session scratchpad. `MH_MAIN_EXEC_GUARD=log` evaluates every call but never denies, appending would-be denies to `~/.local/share/kbg/metrics/main-exec-guard.jsonl` for calibration. Opt-in and OFF by default: unset (or any other value) = total no-op. Set through the interactive `csp`/`cspr` shell alias, deliberately NOT settings.json's `env` block — that would also gate background/Superset worker sessions, which are their own top-level sessions. Subagent writes (`agent_id` present) are unaffected. Supersedes `main-write-budget.sh` (ask-tier write-count nudge, retired) — see `docs/reference/env-vars.md`'s Main-exec guard section. |
| PreToolUse (Bash) | `main-exec-guard.sh` (Bash leg) | FF / computational | Same script, same env var, same three modes: denies a defined set of mutating Bash commands issued by the top-level session (exit 2 on deny; `log` mode journals instead of denying). Same carve-outs as the Write leg. Coarse command-pattern match on the raw string, not a sandbox — same accepted non-goal as `irrecoverable.sh`. |
| PostToolUse (Skill) | `skill-usage-telemetry.sh` | FB / computational | Journal every skill invocation (skill, plugin, timestamp) to `~/.local/share/kbg/metrics/skill-usage.jsonl` — usage evidence for the future matt-skill vs harness-skill overlap cull (#90/T11). Invocation counts only, no outcome/success field. No decision control. |

**No skill-completion nudge hook.** Considered and declined 2026-08-30 while normalizing the
"Suggested next step" footer convention (`docs/skill-authoring-conventions.md`). `PostToolUse
(Skill)` — the only event a completion-time nudge could ride — fires when a skill's
instructions *load* into context, not when its work finishes; a nudge built on it would fire at
the start of the skill, not the end. It also cannot read a success signal: `tool_response` for
a Skill call is unevidenced in this repo (`skill-usage-telemetry.sh`'s own header documents its
author looking and declining to assume it exists, rather than fabricating an outcome field). No
outcome-based trigger is buildable on this event as it stands. Separately, `skill-usage.jsonl`
(40 rows at time of writing) contains no invocation of any footer-carrying skill, so there is no
evidence the footer text fails to reach the user in the first place — the decline rests on the
event being the wrong shape, not on unconfirmed suspicion of a real gap. The mechanism instead
stays purely in-band: the footer text embedded in a skill's own Output/Summary phase, which the
model naturally emits as part of executing the skill.
| PostToolUse (*) | `loop-repeat-nudge.sh` | FB / computational | Advisory (#99): warns when a tool is called with identical parameters 3+ times in the last 5 calls. Hash-based, purely mechanical, never judges "is this productive." Never blocks. |
| PostToolUse (Bash) | `compliance-audit-nudge.sh` | FF / inferential | Advisory: after a `git commit`, if a plan was approved earlier this session (bash grep-prefilter on the transcript, then a precise python structural check for an `ExitPlanMode` tool_use with a non-empty plan — "grep gates, python confirms", avoids a python spawn on the common non-commit case), remind the model to tell the user `/mh:compliance-audit` exists. `compliance-audit` is `disable-model-invocation: true`, so the nudge text instructs relay-to-user, never self-dispatch — confirmed against `skills/review/compliance-audit/SKILL.md`'s own frontmatter, not assumed. Never blocks. Retired 2026-08-24 (#80), restored 2026-08-25 alongside the skill it relays. |
| PostToolUse (ExitPlanMode) | `plan-review-nudge.sh` | FF / inferential | Advisory: fires only on plan approval (a manual reject/cancel never reaches `PostToolUse` — the tool never "completes successfully" on a deny). Reads `tool_response.plan` directly off stdin, no transcript re-read needed. Nudges considering `mh:plan-reviewer` for a consequential plan before implementing — `plan-reviewer` carries no `disable-model-invocation`, so unlike the row above, "consider dispatching" is the correct verb here. Retired 2026-08-24 (#78), restored 2026-08-25 alongside the agent it nudges. |
| PostToolUseFailure (*) | `mcp-failure-nudge.sh` | FB / computational | Advisory (#97): warns when an MCP server fails 3+ times within 300s. Purely observational — never probes, reconnects, or blocks. |
| PreCompact | `precompact-state-flush.sh` | FB / computational | Flushes in-flight journal/review state to disk before compaction can destroy it. Async; no enforcement. |
| Stop | `cost-tracker.sh` | FB / computational | Track cumulative token/cost metrics per session; append to `~/.local/share/kbg/metrics/costs.jsonl`. Async; no enforcement. |
| Stop | `memory-audit-commit.sh` | FB / computational | If the project's memory store is already a git repo (opt-in, never auto-`init`s), commit any dirty changes for an audit trail. No-op otherwise. Async; no enforcement. |
| Stop | `stale-task-nudge.sh` | FB / computational, model-facing | If a task created this session (`TaskCreate`) still shows `status: in_progress` with no `TaskUpdate` call for it since, emit `hookSpecificOutput.additionalContext` naming it before the turn ends. **Synchronous, not async** — `Stop` has no passive "show text, turn ends normally" lever at all (confirmed against `hooks.md` before building, not assumed): every field that reaches the model here (`decision: block`, `additionalContext`) forces one more visible agent turn, and an async hook's `additionalContext` only lands on the *next* turn — too late once this turn has already ended. Deduped to one nudge per task per session (`~/.local/share/kbg/task-nudge-sessions/<session_id>-<taskId>` marker) so a task legitimately left `in_progress` across several real turns doesn't re-nag every Stop. Guards on `stop_hook_active` to avoid re-triggering itself. Known gap, not hidden: "untouched since" is a mechanical last-write-wins check on `TaskUpdate` calls, not semantic judgment — it cannot distinguish "forgot to close" from "genuinely still working," so the dedup exists specifically to bound the false-positive cost to one nudge, not to eliminate it. |
| SessionEnd | `learn-nudge.sh` | FB / computational (volume proxy, not content judgment) | Advisory: remind the operator `mh:learn` exists when the transcript's `"type":"user"` turn count (includes tool-result turns) is ≥3 (`MH_LEARN_NUDGE_MIN_TURNS` override). Skips `reason: resume` (docs: "Session switched via interactive `/resume`" — the session ended because the user left it for a possibly-different one, not that this session is pausing to continue later) and `reason: clear` (frequent mid-work housekeeping — nudging every `/clear` is nag-fatigue noise, not signal). Emits to **stderr** — SessionEnd stdout is discarded by Claude Code and SessionEnd has no `additionalContext`/decision-control mechanism at all (unlike SessionStart), so stderr is the only channel that reaches the user (confirmed against the hooks reference: `SessionEnd` → "Shows stderr to user only"). Not the retired learn-capture/learn-drain-nudge design (no queue, no state file, no confidence scoring, no python) — it judges nothing about content, only whether the session had enough activity to plausibly be worth a look. |
| InstructionsLoaded | `instructions-loaded-journal.sh` | FB / computational | Appends a JSONL record (`~/.local/share/kbg/metrics/instructions-loaded.jsonl`) each time an instruction file loads into context — which file, when, why. Async; no enforcement. Ships from the plugin cache; landed in `b048052e` (v0.68.399), so it fires under the version a session is actually running, not necessarily this repo's checkout. |

**No `TaskCompleted` hooks are registered.** The retired F7 TaskCompleted gate
and the SessionEnd inferential-FB sensors (`inferential-structural-judge`, `verification-gate`,
`fabrication-verdict-log`) were removed in the v0.6.0 cut; the `PostToolUse` `observe.sh`
sensor (retired-L4 residue that wrote `observations.jsonl` for the removed `/learn` command) was removed in
v0.6.7 — `PostToolUse` itself was re-wired 2026-07-22 (v0.68.3) with `plan-review-nudge.sh`, a
different, unrelated advisory hook, then `compliance-audit-nudge.sh` (v0.68.138) joined the same
event 2026-08-03 with a different matcher (`Bash`). Both hooks, and the two surfaces they relayed
(the `plan-reviewer` agent, the `compliance-audit` command), were retired 2026-08-24 (#78, #80) on
the mistaken premise that `mattpocock-skills:grilling` and `mattpocock-skills:code-review`
covered the same job — neither does (see `decision-doctrine-map.md`'s "Plan → implement" and
"Implementation → verify" rows) — and all four were restored 2026-08-25. **Four PostToolUse hooks
are live today** (`skill-usage-telemetry.sh` on `Skill`, `loop-repeat-nudge.sh` on `*` — added
later, #90/T11 and #99 respectively, unrelated to the plan-review/compliance-audit lineage above —
plus the two restored hooks) — see the table rows above. The maker≠checker
enforcement the F7 gate failed to provide is now carried by
`gate:task:complete-separation` on `PreToolUse:TaskUpdate` (above) — a deterministic shell gate, not a
model-as-gate, so it does not re-arm the autonomy invariant the v0.6.0 cut retired. `SessionEnd` itself
was re-wired 2026-07-06 with `learn-nudge.sh` — a computational volume-proxy nudge, not a re-arm of the
retired inferential-FB sensors above (those judged session *content*; this judges nothing beyond a raw
turn count, and never emits a decision). `hooks/hooks.json` wires 9 events total: SessionStart,
UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop, PreCompact, SessionEnd,
InstructionsLoaded.

**The three `PreToolUse (Bash)` deny/ask gates above** (`irrecoverable.sh`,
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

The audit checks are `skills/meta/harness-audit/scripts/audit.sh` (run on demand, not as a hook).