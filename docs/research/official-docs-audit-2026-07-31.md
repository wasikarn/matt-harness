---
title: Full-project official-docs accuracy audit — 2026-07-31
status: findings persisted, remediation in progress
---

# Full-project official-docs accuracy audit — 2026-07-31

Workflow-driven sweep (`kbg-official-docs-audit`, 2 runs, ~9M subagent tokens) checked 218
concrete technical claims across 13 domains against live primary sources (Anthropic's own
Claude Code docs, TypeScript/Drizzle/gRPC/MySQL/GitHub/OWASP official docs, Martin Fowler's
site) — not training-data recall. Every claim flagged wrong got a second, independent
recheck agent before landing here.

**Result:** 164 confirmed accurate, 37 double-confirmed wrong (0 reversed on recheck, 0
recheck agents failed), 17 unverifiable (no primary source resolves them either way).

Raw workflow output: `wr1d9zsaw.output` task result (session-scoped, not repo-persisted —
this file is the durable record). Script: `kbg-official-docs-audit-wf_df50fb68-66b.js`.

## How to read this

Findings are grouped into 3 buckets by **does the fix change runtime behavior**, not by
abstract severity — that's the dimension that actually decides how carefully each one needs
handling.

- **(a) Behavior** — fixing this changes what the harness *does*, not just what it *says*.
  Small set, high stakes, some need explicit go-ahead before touching.
  - **CRITICAL — worktree gate breaks legitimate worktree creation.** See "Worktree gate"
    below; the confirmed-inaccuracies detail is under `hooks/gates/worktree-create-block.sh`.
  - `hooks/tests/test-worktree-create.sh` — all 34 tests validate against the same invented
    payload shape the gate uses; self-consistent, reality-disconnected, can't catch the bug.
  - `hooks/stop/cost-tracker.sh` — Haiku/Opus/Sonnet rate table is stale (see "Cost-tracker
    pricing" below).
  - `skills/pr/SKILL.md:188` — `gh pr checks --json status,conclusion` is a shipped command
    that errors when actually run (`Unknown JSON field`), silently swallowed by
    `2>/dev/null || true`.
- **(b) Prose/doc accuracy** — no runtime effect, but the doc asserts something false. Mostly
  `docs/reference/hook-lifecycle-contracts.md` (5 findings), `env-vars.md`,
  `context-budget/SKILL.md`, `command-authoring-conventions.md`, 2 harness-audit check
  comments, `hooks.json`'s dead `MultiEdit` alternation (behaviorally inert, fold into
  another commit rather than its own version bump), README.md's 2 citation errors.
- **(c) Domain-skill content** — factual drift in framework/library guidance:
  `nextjs-reviewer` (×3), `frontend-patterns` (Zustand curried-create), `drizzle-patterns`
  (×2), `grpc-node-patterns` (Bun compat overstated), `mysql-patterns` (MariaDB var name),
  `typescript-patterns` (×2), `cost-aware-llm-pipeline` (cost ratios + cache-token minimum),
  `performance-optimizer` (readFileSync mis-categorized as CPU-bound), `security-auditor`
  (OWASP 2021→2025 edition — **judgment call, not a defect**, see below).

**3 unverifiable findings are actually hard doc-accuracy bugs, not soft/no-action** — same
defect class as the confirmed `docs/agent-tool-patterns.md:62` citation-URL bug (true claim,
wrong/unconfirmable source citation), just not independently re-checked a second time:
`docs/reference/hook-lifecycle-contracts.md:44` (claims "docs-confirmed" for a field name
that isn't), `hooks/gates/atlassian-mcp-gate.sh:44-47` (same "confirmed against docs..."
phrasing, unconfirmable). Treat these as bucket (b), not bucket-17-soft.

## CRITICAL: worktree-create gate has been breaking legitimate worktree creation, not just failing to deny

Two things are true at once, confirmed against raw Claude Code doc HTML (not a WebFetch
summary — one recheck agent's claimed schema turned out to be fabricated by a summarizer;
caught by fetching raw HTML and grepping for the claimed field names, which returned zero
hits for `git_root`/`source_branch`/`isolation_id` anywhere on the real page):

1. **The deny logic is dead code.** `worktree-create-block.sh:80` reads `tool_name` to
   detect the event. WorktreeCreate/WorktreeRemove never send `tool_name` or `tool_input` —
   only `{session_id, transcript_path, cwd, hook_event_name, name}` for Create (`name` = an
   auto-slug like `bold-oak-a3f2`) and `{..., worktree_path}` for Remove. So
   `d.get("tool_name", "")` is always `""`, the `if tool not in (...)` branch always fires,
   and the script exits 0 before ever reaching the sentinel/branch-deny logic — verified live
   by piping a docs-shaped payload into the script from this exact repo (sentinel present):
   `rc=0`, empty stdout/stderr.
2. **Independent of bug #1, the gate's allow path was never going to work anyway.** Per the
   docs: "Configuring a WorktreeCreate hook replaces that default git behavior... Because the
   hook replaces the default behavior entirely... The hook must return the path to the
   created worktree directory... If the hook fails or produces no path, worktree creation
   fails with an error." Registering *any* hook on WorktreeCreate hands Claude Code's default
   `git worktree` creation entirely to that hook — it must create the worktree itself and
   emit `{"hookSpecificOutput": {"hookEventName": "WorktreeCreate", "worktreePath": "..."}}`.
   This gate's allow path is a bare `sys.exit(0)`, no stdout. Both `hooks.json` entries
   (`gate:worktree:develop-only` on WorktreeCreate, `gate:worktree:develop-only-remove` on
   WorktreeRemove) fire unconditionally — no repo-scoping at the hooks.json level — so this
   applies to **every install of this plugin**, not just kbg-harness.

**This already happened, live, once.** `recursive-improve-fixture-incident-2026-07-28.md`
(memory) records `isolation: "worktree"` on the Agent tool failing with `WorktreeCreate hook
failed` in this exact repo on 2026-07-28 — at the time attributed to "the doctrine gate
correctly refusing," but per the verified schema above the gate never even reached the
doctrine check; it failed because it never emits a `worktreePath`. Every `isolation: worktree`
Agent/Workflow call, `claude --worktree`, and background-session worktree in any repo running
this plugin has been failing since v0.29.0. The `review-pr` worktree flow is unaffected only
because it creates worktrees via raw `git worktree add --detach` in Bash, which — per docs —
never fires WorktreeCreate at all.

**Recommended fix (not yet applied — needs explicit go-ahead, wide blast radius across every
install):** deregister both `WorktreeCreate`/`WorktreeRemove` entries from `hooks.json`
rather than re-architecting the hook to the path-return contract. The doctrine this gate was
meant to enforce (no non-develop branch worktrees) is still covered by the
`git worktree add -b` block in `gate:bash:irrecoverable` (`PreToolUse:Bash`) for the only path
that's actually exercised — `review-pr` uses raw Bash and never touches the doctrine-violating
shape anyway. Re-architecting to the real path-return contract is a separate, later decision,
not a prerequisite for stopping the bleeding.

## Cost-tracker pricing (bucket a, forward-fix ≠ historical-data fix)

`hooks/stop/cost-tracker.sh` rates are stale on all 3 tiers, confirmed live against
`platform.claude.com/docs/en/about-claude/pricing`:

| Tier | Coded rate (i/o/cache-w/cache-r, $/MTok) | Actual current rate | Effect |
|---|---|---|---|
| Haiku | 0.80/4.0/1.00/0.08 | 1.00/5.0/1.25/0.10 (Haiku 4.5) | underprices by 20% |
| Opus | 15.0/75.0/18.75/1.50 | 5.00/25.0/6.25/0.50 (Opus 5/4.8) | overprices by 3x |
| Sonnet | 3.0/15.0/3.75/0.30 | 2.00/10.0/2.50/0.20 (Sonnet 5 introductory, through 2026-08-31) | overprices by 50% until 2026-08-31, then matches |

The coded Haiku/Opus rows match now-retired/deprecated model pricing, not the current models
(`claude-haiku-4-5-*`, `claude-opus-5`/`claude-opus-4-8`) the tracker's substring-match regex
(`test("haiku")` etc., no version discrimination) actually prices. **Open decision, not yet
made:** a forward fix corrects future `costs.jsonl` rows; it does not touch history. Every
past Haiku/Opus row in `costs.jsonl` (v0.68.79–81 all touched this exact file) is wrong by
these same factors. Whether to re-derive historical rows or just annotate a pricing-change
discontinuity date is the user's call, not something to decide silently.

---

## Confirmed inaccuracies (37, double-confirmed)

### skills/context-budget/SKILL.md:70
**Claim:** Context window: 200K (Sonnet)
**Correct:** As of the current Claude Code docs, Sonnet 5 — the default model on Pro, Team Standard, and Enterprise seats — "always runs with the 1M context window" on the Anthropic API: "There is no 200K variant, no [1m] suffix to select, and no usage credits required on any plan." The 200K figure only applies in two exception cases: an LLM gateway that can't verify 1M support, or explicit `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`. This same stale 200K assumption underlies harness-audit check 47's "platform default of 1% of a 200K-token window (≈8000 chars)" and env-vars.md's "your 200k context window" line — all three should be re-checked against the live default.
**Source:** https://code.claude.com/docs/en/model-config, "Sonnet 5 context window" and "Extended context" sections

### skills/context-budget/SKILL.md:24, 57
**Claim:** MCP tool schema: ~500 tokens per tool
**Correct:** As of the current docs, MCP tool search is enabled by default: "Only tool names and server instructions load at session start, so adding more MCP servers has minimal impact on your context window. Claude Code doesn't impose a fixed per-server tool cap; the practical limit is your context window budget." Full tool schemas (where a flat ~500-tokens/tool cost would apply) are deferred and loaded on demand, not upfront. The flat-per-tool-cost model this claim assumes describes the pre-tool-search-default architecture.
**Source:** https://code.claude.com/docs/en/mcp, "Scale with MCP tool search" section

### docs/reference/env-vars.md:64-70
**Claim:** Limits to stay under: 10 MCP servers active, 80 tools total active — token cost scales linearly with tool count
**Correct:** Same finding as above: with tool search on by default, Claude Code explicitly does not impose a fixed tool-count cap, and cost no longer scales linearly with the number of connected tools/servers because full schemas stay deferred until actually needed. This section is honestly labeled as "sourced from ECC token-optimization guide" rather than Anthropic's own guidance, but the specific numeric limits are stale against the current default architecture.
**Source:** https://code.claude.com/docs/en/mcp, "Scale with MCP tool search" section

### docs/command-authoring-conventions.md:73-77
**Claim:** Confirmed recognized and functional: name, description, argument-hint, disable-model-invocation / disable-model-invocation-reason, allowed-tools, model, agent
**Correct:** `disable-model-invocation-reason` is not part of the official frontmatter schema at all — only `disable-model-invocation` (boolean) is documented. Grouping the two together under "confirmed recognized and functional" overstates it; CLAUDE.md's own later line (139) correctly calls `disable-model-invocation-reason` a "non-standard-but-harmless kbg convention" that Claude Code merely tolerates, which contradicts this earlier framing in the same doc family.
**Source:** https://code.claude.com/docs/en/skills, Frontmatter reference table

### docs/agent-tool-patterns.md:62
**Claim:** the vendor schema explicitly supports [disallowedTools] (it does — see code.claude.com/docs/en/agents)
**Correct:** That URL resolves to a real but different page, "Run agents in parallel" (a comparison of subagents/agent-view/agent-teams/workflows) — it does not document the `tools:`/`disallowedTools:` frontmatter fields. The content actually cited lives at https://code.claude.com/docs/en/sub-agents. The underlying claim (disallowedTools is a real, vendor-supported field) is still true; only the citation URL is wrong.
**Source:** https://code.claude.com/docs/en/agents (fetched directly)

### skills/harness-audit/scripts/checks/06-frontmatter-completeness-commands.sh:3-8
**Claim:** name: frontmatter is NOT part of the slash-command schema — it's a plugin-root SKILL.md construct
**Correct:** `name` is a documented, valid optional field in the single unified frontmatter schema that now governs both skills and commands ("custom commands have been merged into skills"). It just doesn't determine the invoked command name for a file under `.claude/commands/` — that's filename-derived — but the field itself is part of the schema, contrary to the comment's phrasing. The check's functional behavior (not requiring `name:` for commands) is still correct; only the "not part of the schema" justification is inaccurate.
**Source:** https://code.claude.com/docs/en/skills, Frontmatter reference table and "How a skill gets its command name" table

### hooks/gates/worktree-create-block.sh:80-113
**Claim:** The gate reads `tool_name` from the WorktreeCreate/WorktreeRemove payload to detect the event, then reads `tool_input.branch` / `tool_input.path` / `tool_input.detach` to decide whether to deny the worktree creation (per the rule documented in hook-lifecycle-contracts.md:47 and hooks.json's own hook description).
**Correct:** WorktreeCreate/WorktreeRemove payloads never carry `tool_name` or `tool_input` at all — docs state plainly that 'The tool_name, tool_input, and tool_use_id fields are event-specific' (documented only for PreToolUse/PostToolUse-family events). WorktreeCreate's only event-specific field is `name` (an auto-generated slug like 'bold-oak-a3f2') — there is no `branch`, `path`, or `detach` field anywhere in its contract. Live proof: piping a docs-shaped payload (`{"hook_event_name":"WorktreeCreate","name":"feature-auth","cwd":"<kbg-harness path, sentinel present>"}`) into the script returns rc=0 with empty stdout/stderr — the deny branch never executes, even in the exact repo/condition it's supposed to fire in. Separately, and independent of the field-name bug: per docs, 'WorktreeCreate hooks don't use the standard allow/block decision model. Instead, the hook's success or failure determines the outcome' — registering ANY hook under WorktreeCreate replaces Claude Code's default `git worktree` creation outright, and the hook must itself perform the creation and print the resulting path on stdout, or 'worktree creation fails with an error.' Since this script's allow path is a bare `sys.exit(0)` with no stdout, even a version fixed to read `hook_event_name` would still break every legitimate WorktreeCreate case (develop-branch worktrees, `claude --worktree`, `isolation: worktree` subagents, background sessions) in any repo carrying `/.kbg-no-worktree` with this plugin installed — not scoped to kbg-harness, since hooks.json ships to every installer. The review-pr worktree flow is unaffected only because it creates worktrees via raw Bash `git worktree add --detach` (confirmed in the script's own comments), which — per docs — never triggers WorktreeCreate in the first place.
**Source:** code.claude.com/docs/en/hooks.md (raw fetch, 2026-07-31) — 'Common input fields' section + WorktreeCreate/WorktreeRemove input sections; empirically re-verified live against the actual script

### hooks/tests/test-worktree-create.sh:48
**Claim:** "WorktreeCreate event payload — {tool_name, tool_input: {path, branch?, detach?}, cwd?, agent_type?}" — asserted as the real payload shape and used to build every WorktreeCreate/WorktreeRemove test fixture in the file.
**Correct:** Same wrong shape as the implementation it tests (see worktree-create-block.sh finding above). All 34 test cases pass because the test and the code under test share one invented payload shape that Claude Code never actually sends — the suite is self-consistent, not reality-consistent, and cannot catch this class of bug by construction.
**Source:** code.claude.com/docs/en/hooks.md — WorktreeCreate/WorktreeRemove input sections

### docs/reference/hook-lifecycle-contracts.md:50
**Claim:** "No `TaskCompleted` or `PostToolUse` hooks are registered."
**Correct:** hooks.json registers a PostToolUse hook (`advisory:plan-review-nudge`, matcher `ExitPlanMode`) that dispatches `hooks/advisory/plan-review-nudge.sh` — a real, tested (`hooks/tests/test-plan-review-nudge.sh`), documented-elsewhere-in-this-same-repo hook. The per-event contract table in this same file (lines 36-48) never lists it either, so the gap is both an omission and a direct false statement.
**Source:** hooks/hooks.json (this repo)

### docs/reference/hook-lifecycle-contracts.md:3-4, 59
**Claim:** "7 hook events / 12 hooks kbg registers" ... "`hooks/hooks.json` wires only the 7 events above."
**Correct:** hooks.json currently wires 8 top-level events (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SessionEnd, WorktreeCreate, WorktreeRemove) totaling 18 individual hook-id registrations, not 7/12. The doc is stale relative to the current hooks.json.
**Source:** hooks/hooks.json (this repo, counted programmatically)

### docs/reference/hook-lifecycle-contracts.md:42
**Claim:** "PreToolUse (Write\|Edit\|MultiEdit) | `path-hardcode.sh` | ... | Deny hardcoded `/Users/<name>` paths in `.sh`/`.py` content. Emit `permissionDecision`." — listed as a live, standalone hook.
**Correct:** path-hardcode.sh was deleted and its logic folded into verifier-protect.sh's Write branch on 2026-07-03 (confirmed in verifier-protect.sh's own header and in hooks.json's `gate:write:verifier-protect` description: "Also folds the former path-hardcode deny ... since 2026-07-03"). It has not existed as a separate file or hooks.json entry for weeks; this doc row is stale.
**Source:** hooks/gates/verifier-protect.sh (this repo, header comment) + hooks/hooks.json (no path-hardcode.sh entry) + filesystem search (no such file exists)

### docs/reference/hook-lifecycle-contracts.md:11-12
**Claim:** "PreToolUse gates — emit JSON `permissionDecision` (`deny`/`ask`/`none`) on stdout ..."
**Correct:** The documented `permissionDecision` enum is `"allow" | "deny" | "ask" | "defer"` — four values. There is no literal `"none"` value, and the doc's parenthetical also omits the two real values `allow` and `defer`.
**Source:** code.claude.com/docs/en/hooks.md, line ~1550 (PreToolUse decision-control field table)

### docs/reference/hook-lifecycle-contracts.md:44
**Claim:** Implied rationale that PreToolUse:TaskUpdate was chosen over the native TaskCompleted event because TaskCompleted couldn't provide what was needed.
**Correct:** TaskCompleted is documented to fire "when any agent explicitly marks a task as completed through the TaskUpdate tool," ships native decision control purpose-built for this exact scenario ("When a TaskCompleted hook exits with code 2, the task is not marked as completed and the stderr message is fed back to the model as feedback"), and — like every event — inherits `agent_type` as a common field when it fires inside a subagent. It appears to be the better-fit native event for a maker≠checker completion gate, not an unsuitable one; the doc's implied justification for bypassing it doesn't hold up against the docs.
**Source:** code.claude.com/docs/en/hooks.md, TaskCompleted section

### hooks/advisory/learn-nudge.sh:27-28
**Claim:** "`reason` gate: skip `resume` (docs: \"session is being suspended for later resumption\" — not closing out ...)" — presented in quotes as if this exact phrase comes from the official docs.
**Correct:** The word "suspend"/"suspending" never appears anywhere on the hooks reference page. The actual documented description for SessionEnd `reason: "resume"` is: "Session switched via interactive `/resume`" — i.e. this session ended because the user left it via /resume to go to a (possibly different) session, not "this session is pausing to be continued later." The same misreading also appears, unquoted, in docs/reference/hook-lifecycle-contracts.md:46 ("docs: session is suspending for later resumption, not closing out").
**Source:** code.claude.com/docs/en/hooks.md — full-page grep for "suspend" returns zero matches

### skills/harness-audit/scripts/checks/22-hook-config-validity-settings-json-check.sh:3-4, 12
**Claim:** "Verified against code.claude.com/docs/en/hooks (31-event canonical set, fetched 2026-05-30)" / "Canonical event set — code.claude.com/docs/en/hooks 'Hook lifecycle' table."
**Correct:** The official canonical event list currently has exactly 30 events, not 31 — the comment's count is off by one. The DOC_EVENTS Python set actually coded in this check (lines 13-21) is itself fully accurate: it contains exactly 30 items and matches the current official list item-for-item (verified by direct set comparison), so the check's real behavior is correct and current — only the descriptive '31-event' comment is wrong.
**Source:** code.claude.com/docs/en/hooks.md, 'Complete List of Hook Events' — counted programmatically

### hooks/hooks.json:69, 141
**Claim:** matcher `"Write|Edit|MultiEdit"` (line 69, gate:write:verifier-protect) and `"Write|Edit|MultiEdit|NotebookEdit"` (line 141, gate:write:worktree-guard) — mirrored in docs/reference/hook-lifecycle-contracts.md:42-43's "PreToolUse (Write|Edit|MultiEdit)" rows — imply `MultiEdit` is a real, matchable built-in tool name.
**Correct:** There is no `MultiEdit` tool in Claude Code's current built-in tool list. The real editing tools are `Edit`, `Write`, and `NotebookEdit` only. `MultiEdit` is a dead alternation branch in these matchers — harmless at runtime (it simply never matches), but the documented tool-coverage claim is inaccurate. (This may be legacy naming from an older Claude Code version that did have a separate MultiEdit tool; either way it no longer exists in the current tool set.)
**Source:** code.claude.com/docs/en/tools-reference.md — full built-in tool table (43 tools)

### hooks/advisory/flow-nudge.sh:6-8
**Claim:** "UserPromptSubmit hook. Output → stdout (CC surfaces as a system-reminder); never blocks, always exits 0." (same claim in hooks/advisory/jira-route-nudge.sh:5-7)
**Correct:** Docs distinguish two separate mechanisms: "Plain stdout is shown as hook output in the transcript. The additionalContext value is injected as a system reminder that Claude reads without a visible transcript entry." flow-nudge.sh and jira-route-nudge.sh both emit plain (non-JSON) text via `cat <<EOF`, which the docs label 'hook output in the transcript' — the 'system reminder' wrapper is documented specifically for the JSON `hookSpecificOutput.additionalContext` path, which these two scripts don't use. Functionally low-impact (the content still reaches Claude as context either way) but the named mechanism is not the one actually used.
**Source:** code.claude.com/docs/en/hooks.md, UserPromptSubmit decision-control section

### hooks/stop/cost-tracker.sh:50
**Claim:** haiku rate: {i:0.80,o:4.0,cw:1.00,cr:0.08} (USD per million tokens)
**Correct:** This is the pricing for the RETIRED Claude Haiku 3.5 model (retired except on Bedrock/Google Cloud). The current model, Claude Haiku 4.5, is priced at input $1.00, output $5.00, 5-minute cache write $1.25, cache read $0.10 per MTok. The tracker's regex matches any model with 'haiku' in the name, including 'claude-haiku-4-5-20251001', so this rate table underprices current Haiku usage by 20% across every field.
**Source:** platform.claude.com/docs/en/about-claude/pricing (fetched live)

### hooks/stop/cost-tracker.sh:51
**Claim:** opus rate: {i:15.0,o:75.0,cw:18.75,cr:1.50} (USD per million tokens)
**Correct:** This is the pricing for the deprecated Claude Opus 4.1 (retiring 2026-08-05) / retired Claude Opus 4. The current models, Claude Opus 5 and Claude Opus 4.8, are priced at input $5.00, output $25.00, 5-minute cache write $6.25, cache read $0.50 per MTok — 3x lower than this rate table's opus row. Any current opus-tier usage (claude-opus-5, claude-opus-4-8, claude-opus-4-7, claude-opus-4-6) is overpriced 3x by this script.
**Source:** platform.claude.com/docs/en/about-claude/pricing (fetched live)

### hooks/stop/cost-tracker.sh:52
**Claim:** sonnet rate: {i:3.0,o:15.0,cw:3.75,cr:0.30} (USD per million tokens)
**Correct:** This exactly matches Claude Sonnet 4.6/4.5 pricing, and also matches Claude Sonnet 5's standard pricing that takes effect 2026-09-01. But Claude Sonnet 5 currently runs introductory pricing of $2.00 input / $10.00 output / $2.50 cache-write / $0.20 cache-read per MTok through 2026-08-31 (confirmed on the live pricing page). Since the session's own current date is 2026-07-31, this rate table currently overprices claude-sonnet-5 usage by 50% until the introductory window ends.
**Source:** platform.claude.com/docs/en/about-claude/pricing (fetched live; system date confirmed 2026-07-31)

### skills/cost-aware-llm-pipeline/SKILL.md:163-166
**Claim:** "Haiku-tier models run roughly 1x, Sonnet-tier ~4x, Opus-tier ~19x per token"
**Correct:** Against current pricing (Haiku 4.5 $1/$5, Sonnet 5 $2-3/$10-15, Opus 5 $5/$25 per MTok), the real ratios are roughly 1x / 2-3x / 5x, not 1x/4x/19x. The stated ~4x and ~19x figures exactly reproduce the ratio between the now-retired Haiku 3.5 ($0.80/$4) and the now-deprecated/retired Sonnet-tier ($3/$15) and Opus 4.1/4 ($15/$75) prices (3.75x and 18.75x) — i.e. the multipliers were computed from stale/retired-model prices, not from the current models (claude-sonnet-5, claude-haiku-4-5) this same file names two lines above.
**Source:** platform.claude.com/docs/en/about-claude/pricing (fetched live)

### skills/cost-aware-llm-pipeline/SKILL.md:175
**Claim:** "Use prompt caching for system prompts over 1024 tokens — saves both cost and latency"
**Correct:** The minimum cacheable prefix length is model-dependent, not a flat 1024 tokens: 512 tokens for Claude Opus 5, 1024 for Claude Sonnet 5/Sonnet 4.6/Opus 4.8, but 4,096 tokens for Claude Haiku 4.5 — the exact model this skill names as MODEL_HAIKU two lines above. A 1024-token prompt routed to Haiku per this skill's own routing logic would silently fail to cache (no error, cache_creation_input_tokens stays 0).
**Source:** platform.claude.com/docs/en/build-with-claude/prompt-caching (fetched live)

### docs/reference/env-vars.md:49
**Claim:** "Extended thinking reserves up to 31,999 output tokens for internal reasoning. 10k cuts hidden cost ~70% vs the default."
**Correct:** Per the current live Claude Code docs, MAX_THINKING_TOKENS' default is now 10,000, not 31,999 — 31,999 was the old 'ultrathink' legacy ceiling from an earlier Claude Code version. Since 10,000 is already the current default, setting MAX_THINKING_TOKENS=10000 today is a no-op, not an optimization that 'cuts hidden cost ~70% vs the default' — that framing describes a prior release's behavior, not the current one.
**Source:** code.claude.com/docs/en/env-vars.md (fetched live)

### skills/typescript-patterns/SKILL.md:37-38
**Claim:** the `@typescript/native-preview` package (binary `tsgo`) continues in parallel as the bleeding-edge nightly channel
**Correct:** As of GA, `@typescript/native-preview` is being wound down rather than continuing in parallel — nightly builds have moved to the main `typescript` npm package under the `next` dist-tag (confirmed live: `typescript@next` = 7.1.0-dev builds updating daily; `@typescript/native-preview` has had no new publish since 2026-07-07, just before GA).
**Source:** npm registry (registry.npmjs.org/@typescript/native-preview): last published version is 7.0.0-dev.20260707.2 (2026-07-07) — no publishes since, 24 days stale as of 2026-07-31. Meanwhile the main `typescript` package's `next` tag has continuous fresh nightly builds through 2026-07-30 (7.1.0-dev.20260730.1). This matches devblogs.microsoft.com 'Announcing TypeScript 7.0', which states verbatim: 'going forward, nightly builds will soon resume under the standard typescript package with the next tag.'

### skills/typescript-patterns/SKILL.md:63
**Claim:** `downlevelIteration` | error by default | moot | a modern `target` (ES2015+) makes it unnecessary
**Correct:** `downlevelIteration` is deprecated identically to the other rows — setting it at all (in either direction) is a hard error with no opt-out in 7.0, the same as the rest of the table. 'Moot' undersells it: it's not that the compiler silently ignores the flag, it's that setting it is itself a build error, same mechanism as the rest of the row set. The practical guidance (drop it, use a modern target) is still correct, just the 'Status in 7.0' cell's wording is inconsistent with how the option actually behaves.
**Source:** microsoft/TypeScript src/compiler/program.ts line 4559-4561: `if (options.downlevelIteration !== undefined) createDeprecatedDiagnostic("downlevelIteration")` — this fires the exact same TS5101 hard-error/no-opt-out deprecation as every other row in the table whenever the flag is explicitly set (true or false), it is not merely 'moot'.

### agents/performance-optimizer.md:63
**Claim:** readFileSync ... belongs on pooled worker_threads, not the main thread (grouped as 'CPU-bound work')
**Correct:** Node's own worker_threads docs state: "Workers (threads) are useful for performing CPU-intensive JavaScript operations. They do not help much with I/O-intensive work. The Node.js built-in asynchronous I/O operations are more efficient than Workers can be." readFileSync is a synchronous I/O call, not CPU-bound computation — Node's own 'Don't Block the Event Loop' guide explicitly treats File System and Encryption/Crypto as two separate categories (I/O-intensive vs CPU-intensive), not one. The correct fix for readFileSync is switching to the async fs.readFile()/fs.promises.readFile() (already backed by the libuv threadpool), not moving it to worker_threads.
**Source:** https://nodejs.org/api/worker_threads.html (Node.js official API docs) + https://nodejs.org/en/learn/asynchronous-work/dont-block-the-event-loop

### agents/nextjs-reviewer.md:119
**Claim:** an opt-in Node.js runtime became available (experimental.nodeMiddleware / export const runtime = 'nodejs')
**Correct:** The middleware-specific syntax is `export const config = { runtime: 'nodejs' }` (nested inside the middleware config object), not a bare top-level `export const runtime = 'nodejs'`. That bare top-level form is the Route Segment Config syntax used by Pages/Layouts/Route Handlers (per https://nextjs.org/docs/app/api-reference/file-conventions/route-segment-config), a different file convention than middleware.ts.
**Source:** https://nextjs.org/docs/15/app/api-reference/file-conventions/middleware ("Middleware defaults to using the Edge runtime. As of v15.5, we have support for using the Node.js runtime... set the runtime to nodejs in the config object: export const config = { runtime: 'nodejs' }"); https://nextjs.org/blog/next-15-5 shows the same nested syntax

### agents/nextjs-reviewer.md:143
**Claim:** a non-critical third-party script (analytics, chat widget) loaded with beforeInteractive blocks hydration; should default to afterInteractive or lazyOnload
**Correct:** Next.js's own docs explicitly state beforeInteractive scripts do NOT block hydration — they're injected into initial HTML and fetched early, but execution is documented as non-blocking for hydration. The overall guidance to prefer afterInteractive/lazyOnload for non-critical scripts is still reasonable practice, but the specific mechanism cited ("blocks hydration") contradicts the official docs' own explicit disclaimer.
**Source:** https://nextjs.org/docs/app/api-reference/components/script — "Scripts denoted with this strategy [beforeInteractive] are preloaded and fetched before any first-party code, but their execution does not block page hydration from occurring."

### agents/nextjs-reviewer.md:161-164
**Claim:** The next build output's route table (○ Static, ● SSG, λ Dynamic) is the ground truth for whether a route is actually being statically rendered
**Correct:** The current (and has been for several major versions) App Router build-output legend is just two symbols: ○ (Static) and ƒ (Dynamic). The ● (SSG) and λ (Server/Lambda) symbols are stale — from an older Pages Router-era build output — and don't appear in the current documented legend.
**Source:** https://nextjs.org/docs/app/api-reference/cli/next — current `next build` output legend: "○  (Static)   prerendered as static content / ƒ  (Dynamic)  server-rendered on demand" (only two symbols)

### skills/frontend-patterns/reference.md:321
**Claim:** export const useMarketStore = create<MarketStore>((set) => ({ ... })) — presented as the correct TypeScript pattern for a Zustand store
**Correct:** Zustand's own TypeScript guide recommends the curried syntax `create<MarketStore>()((set) => ({...}))` (note the extra `()`), not the single-call `create<MarketStore>((set) => ({...}))` shown in reference.md. The single-call form still runs, but per Zustand's own docs it degrades to a type assertion rather than a proper type annotation, which can silently hide shape mismatches — a real (if narrow) inaccuracy in code meant to be copy-pasted as the canonical pattern.
**Source:** Zustand official docs via context7 (/pmndrs/zustand), guides/advanced-typescript.md and guides/beginner-typescript.md — "The recommended way to use create is with the curried workaround pattern create<T>()(...) because it enables proper type inference... If you prefer not to use the curried workaround, you can pass type parameters directly to create, but note that in some cases this acts as a type assertion rather than annotation, which is why the curried approach is generally recommended for better type safety."

### skills/drizzle-patterns/SKILL.md:31-34
**Claim:** Table indexes/constraints declared via a third-argument callback returning an OBJECT: `(table) => ({ emailIdx: index(...).on(table.email), ... })`
**Correct:** Current official docs use the ARRAY-return form for the third pgTable/sqliteTable argument: `(t) => [index('users_email_idx').on(t.email), index('users_status_created_idx').on(t.status, t.createdAt)]`. The object-return form shown in SKILL.md still compiles/runs (backward-compat) but triggers a TS deprecation warning and is not what current docs teach — this is exactly the kind of API drift the file's own 'Verify before use' section warns about.
**Source:** https://orm.drizzle.team/docs/indexes-constraints ('New array form... replaced the deprecated object form'); https://github.com/drizzle-team/drizzle-orm/issues/3399 (confirms drizzle-orm emits a TypeScript deprecation warning for the object-return signature since v0.36.0)

### skills/grpc-node-patterns/SKILL.md:242, 245
**Claim:** `@grpc/grpc-js` works on Bun without modification. Use native Node.js imports ... no polyfills needed
**Correct:** Bun's own official Node.js-compatibility docs mark `node:http2` (which @grpc/grpc-js depends on) as only partial support ('Client & server are implemented, 95.25% of gRPC's test suite passes') — not full/green. Multiple real oven-sh/bun issues document protocol-level breakage specific to @grpc/grpc-js on Bun: a server-side malformed-HTTP/2-frames bug that broke Envoy (filed 2025-08-11, fixed only 2026-07-24 — about a week before this check ran, via PR #29075, and confirmed only for the unary case), an unresolved 'message.copy is not a function' compression-filter crash on Bun single-file executables (reported 2025-12-08, appears still open), and a missing-trailers issue affecting connect-es on Bun (reported 2025-11-04). The unqualified claim 'works without modification, no polyfills needed' overstates a genuinely partial, actively-being-patched compatibility surface — it should be hedged (e.g. 'mostly works, but check the current Bun version and known grpc-js/Bun issues, especially for streaming and large messages').
**Source:** https://bun.com/docs/runtime/nodejs-compat (Bun's own Node.js compat matrix, checked live); https://github.com/oven-sh/bun/issues/21759 (grpc-js server on Bun emits malformed HTTP/2 frames, Envoy PROTOCOL_ERROR); https://github.com/oven-sh/bun/issues/14249, /13175, /15786 (client premature-close, settings-timeout, EOF on 50kb+ responses)

### skills/mysql-patterns/SKILL.md:288
**Claim:** MariaDB uses slave_parallel_workers/slave_parallel_type
**Correct:** MariaDB's equivalent tunable is slave_parallel_mode (values: conservative/optimistic/aggressive/minimal/none), not slave_parallel_type — slave_parallel_type does not exist as a MariaDB system variable. slave_parallel_workers (alias of slave_parallel_threads) is correctly named.
**Source:** mariadb.com/docs/server/ha-and-performance/standard-replication/replication-and-binary-log-system-variables — MariaDB does have slave_parallel_workers (documented as an alias for slave_parallel_threads), but there is no slave_parallel_type variable in MariaDB. The variable controlling parallel-apply mode (optimistic/conservative/aggressive/minimal/none) is named slave_parallel_mode.

### skills/pr/SKILL.md:188
**Claim:** `gh pr checks --json name,status,conclusion 2>/dev/null || true`
**Correct:** `status` and `conclusion` are not valid JSON fields for `gh pr checks`. Running the command verbatim in this repo returns `Unknown JSON field: "status"` (exit 1). The real fields are: bucket, completedAt, description, event, link, name, startedAt, state, workflow. The doc's own `2>/dev/null || true` silently swallows this failure, so Phase 5 always falls through with no CI data instead of ever reporting real status — the intended field is `state` (pass/fail/pending) and/or `bucket`, not `status`/`conclusion`.
**Source:** live `gh pr checks --help` + live execution of the exact command in this repo

### skills/security-auditor/SKILL.md:27-37
**Claim:** Consolidate Findings — Classify by OWASP: A01 Broken Access Control, A02 Cryptographic Failures, A03 Injection, A04 Insecure Design, A05 Security Misconfiguration, A06 Vulnerable Components, A07 Authentication Failures, A08 Integrity Failures, A09 Logging Failures, A10 SSRF
**Correct:** This list is an exact match to OWASP Top 10:2021, but OWASP has since released Top 10:2025 (confirmed live and current at owasp.org — owasp.org/Top10/ now redirects there, and www-project-top-ten states '2025 is the most current released version'). The current official order/names are: A01 Broken Access Control, A02 Security Misconfiguration, A03 Software Supply Chain Failures (new), A04 Cryptographic Failures, A05 Injection, A06 Insecure Design, A07 Authentication Failures, A08 Software or Data Integrity Failures, A09 Security Logging & Alerting Failures, A10 Mishandling of Exceptional Conditions (new). SSRF is no longer a standalone Top-10 category — the A01:2025 page explicitly lists CWE-918 (SSRF) as one of the notable CWEs now folded into Broken Access Control. This file's classification list is stale by a full edition.
**Source:** https://owasp.org/Top10/2021/ and https://owasp.org/Top10/2025/ (+ https://owasp.org/Top10/2025/A01_2025-Broken_Access_Control/, https://owasp.org/www-project-top-ten/) — 3 independent fetches to owasp.org itself, cross-corroborated

### README.md:121
**Claim:** **Source:** Sarah Böckeler (Thoughtworks, via Martin Fowler's site, April 2026)
**Correct:** The article's author is Birgitta Böckeler (Distinguished Engineer, Thoughtworks), not Sarah Böckeler. Published date (2026-04-02, i.e. 'April 2026') is correct.
**Source:** Direct fetch of https://martinfowler.com/articles/harness-engineering.html — byline reads 'Birgitta Böckeler,' not 'Sarah Böckeler.' Also contradicted by this repo's own grounding doc, docs/research/harness-engineering-2026-04.md line 3: 'author: Birgitta Böckeler (Thoughtworks)'.

### README.md:125
**Claim:** Her core warning: an inferential judge (an LLM) grading work the same model class just produced is circular — "two optimists agreeing" — and should never be trusted to gate.
**Correct:** "Two optimists agreeing" is not a phrase from Böckeler's article — it does not appear in the source text at all. It reads as kbg-harness's own original synthesis/gloss on the LLM-judge-circularity idea (the phrase recurs across this repo's own docs — CLAUDE.md, agents/blind-spot-hunter.md, agents/plan-reviewer.md, docs/harness-decay-cadence.md, docs/onboarding.md, commands/compliance-audit.md — suggesting it originated inside kbg-harness, not from the cited source). The underlying circularity concern is real and consistent with the article's spirit, but attributing this specific quoted phrase to 'her core warning' misattributes kbg's own wording to the source.
**Source:** Two independent direct WebFetch checks of https://martinfowler.com/articles/harness-engineering.html, one specifically searching for the exact phrase 'two optimists agreeing' / 'optimists agreeing' — the phrase does not appear anywhere on the page. The article's own stated warning (confirmed present) is a different sentence: 'feedback-only = agent that keeps repeating the same mistakes... feedforward-only = agent that encodes rules but never finds out whether they worked.'

---

## Unverifiable (17, no primary source resolves either way)

### docs/command-authoring-conventions.md:33-36
**Claim:** getSkills reports a distinct N skill dir commands bucket separate from flat plugin skills (confirmed via a live --debug-file capture)
**Note:** No public Anthropic doc describes the internal `getSkills` debug-log bucket structure or its exact labels; this is an empirical, tool-observed claim (a live `--debug-file` capture) rather than one stated in primary documentation, so it can't be confirmed or refuted from docs alone.

### docs/reference/hook-lifecycle-contracts.md:44
**Claim:** "PreToolUse input is docs-confirmed to carry `tool_input.status` + `agent_type`" (given as the reason TaskUpdate is gated via PreToolUse rather than the native TaskCompleted event).
**Note:** Only the general PreToolUse `agent_type` behavior is docs-confirmed. The specific field name `status` on TaskUpdate's `tool_input` is not documented anywhere in the hooks or tools reference — tools-reference.md only says TaskUpdate "Updates task status, dependencies, details, or deletes tasks" in prose, never a field-level schema. The gate script's own comment concedes this ("status has no documented key-name alias"); the overclaim is in this doc's "docs-confirmed" phrasing, not in the code's actual behavior.

### hooks/gates/atlassian-mcp-gate.sh:44-47
**Claim:** "Subagents share the parent session_id in the hook payload (confirmed against docs.claude.com/docs/en/hooks.md, 2026-07-15)"
**Note:** unverifiable — no primary source resolved either way

### skills/typescript-patterns/SKILL.md:88-94
**Claim:** `tsgo`'s JavaScript support is intentionally trimmed relative to the JS-hosted compiler — Closure header support and much of the declaration-emit behavior for `.js` input differ on purpose
**Note:** unverifiable — no primary source resolved either way

### agents/performance-optimizer.md:63
**Claim:** one sync call >10ms blocks every concurrent request on the event loop (the specific '10ms' threshold)
**Note:** It's a reasonable community engineering heuristic, but not a number Node.js's official documentation states anywhere — treat it as the agent's own rule of thumb, not a sourced fact.

### agents/typescript-reviewer.md:88
**Claim:** Synchronous membership lookup inside a loop (arr.includes/Array.find nested in .filter/.map) is O(n*m)
**Note:** unverifiable — no primary source resolved either way

### agents/typescript-reviewer.md:n/a
**Claim:** No version-anchored Next.js/React caching, Server Actions, middleware, or cacheComponents claims found in this file — its React/Next.js section (lines 75-81) is generic idiom guidance (dependency arrays, key props, server/client boundary leaks) with no version-pinned or library-API-specific factual claims to check against primary docs.
**Note:** unverifiable — no primary source resolved either way

### skills/drizzle-patterns/SKILL.md:48-49
**Claim:** `const pool = new Pool({ connectionString: ... }); export const db = drizzle(pool, { schema })` — two-argument positional form (client, options)
**Note:** Not confirmed broken, but current official examples consistently favor `drizzle({ client: pool, schema })` over the two-arg positional form SKILL.md shows. Could not confirm from docs alone whether the positional overload is still supported or silently deprecated — flagging as a possible drift point worth a quick source-check rather than a hard defect.

### skills/mysql-patterns/SKILL.md:68
**Claim:** one covering composite beats two single-column indexes (avoids the slower index_merge)
**Note:** unverifiable — no primary source resolved either way

### skills/mysql-patterns/SKILL.md:345
**Claim:** <99% = grow the pool; >=99% = stop
**Note:** unverifiable — no primary source resolved either way

### agents/security-reviewer.md:49-68
**Claim:** Section header "2. OWASP Top 10 Check (with CWE references)" followed by an 11-item numbered list (Injection, Broken Auth, Sensitive Data, XXE, Broken Access, Misconfiguration, XSS, Insecure Deserialization, Known Vulnerabilities, Insufficient Logging, SSRF)
**Note:** This 11-item structure doesn't cleanly match any single official OWASP Top 10 edition: it keeps XXE as its own item (only true in the 2017 edition, where XXE was A4) while also appending SSRF as an 11th item (only added, as A10, in 2021 — and now folded into Broken Access Control in 2025). It reads as a hybrid checklist rather than a literal reproduction of one official edition, so this is a structural/currency observation rather than a strict right-or-wrong mapping claim the way the security-auditor A01-A10 list is.

### agents/security-reviewer.md:80
**Claim:** Plaintext password comparison | CWE-256
**Note:** MITRE's title and description for CWE-256 are about storing a password unencrypted, not about the comparison operation itself. It's a commonly used practical mapping (comparing plaintext implies a plaintext value exists somewhere), and no more precise single CWE exists for "insecure password comparison" specifically, so this isn't clearly wrong — but it's not a literal title match either.

### agents/security-reviewer.md:184-185
**Claim:** "SSRF (CWE-918) + cloud deployment → often escalates straight to instance-metadata credential theft (CWE-918 → CWE-522)"
**Note:** The underlying attack narrative (SSRF reaching a cloud instance-metadata endpoint to steal credentials, e.g. the Capital One 2019 breach) is real and well documented industry-wide, but MITRE's own CWE-918 page does not list CWE-522 as a related/chained weakness — this specific "CWE-918 → CWE-522" notation is the file's own interpretive framing, not a MITRE-sourced formal relationship.

### README.md:144-148
**Claim:** Sydney Runkle's "Art of Loop Engineering" (agent loop / verification loop / event-driven loop / hill-climbing loop)
**Note:** unverifiable — no primary source resolved either way

### README.md:147
**Claim:** @0xCodez's 14-step roadmap (harness → loop → self-improving system)
**Note:** unverifiable — no primary source resolved either way

### skills/tech-humanize/references.md:21
**Claim:** Piyangkool Thaweephol (2024) — Chulalongkorn thesis, Thai Gen-Y attitudes toward English-Thai code-switching
**Note:** unverifiable — no primary source resolved either way

### skills/tech-humanize/references.md:22
**Claim:** Umpornpun & Mongkolhutthi (2022) — Thai multilingual gamers on Discord (closest published setting to "dev chat")
**Note:** unverifiable — no primary source resolved either way

---

## Not a defect (explicitly flagged during the audit, not something to fix)

`skills/security-auditor/SKILL.md:27-37`'s OWASP Top 10:2021 classification list is accurate
to that edition — OWASP has since published Top 10:2025 (confirmed live, owasp.org now
redirects `/Top10/` there). Moving to the new edition is a genuine judgment call (edition
currency vs. stability of an established checklist other docs/training may still reference),
not obviously a defect — present as a decision to the user, don't auto-migrate.
