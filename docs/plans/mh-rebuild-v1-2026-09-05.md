# mh v1.0.0 rebuild spec (2026-09-05)

Snapshot of the old tree: git tag `pre-rebuild-v0.68.673`. Operator decisions: rebuild (not prune);
delete main-exec-guard (reverses ADR-0012); ponytail replaces crisp as the only style layer; session model Fable 5.1.

Rule for every file: keep only what native Claude Code 2.1.261 or an installed plugin (mattpocock-skills, ponytail,
diagram-design, qmd) cannot do. Everything else is deleted with `trash` (never `rm`). No stash, no `git add`, no commits by
builders; the lead commits once after validation.

## Keep list (final tree)

```
.claude-plugin/plugin.json, marketplace.json      version 1.0.0 (both)
CLAUDE.md                                         <= 4 KB map: validation cmd, git hooks, composer-not-creator, branching, 4 gotchas
README.md                                         <= 120 lines
docs/METHODOLOGY.md                               <= 4 KB, injected whole at SessionStart (no core-end split)
docs/reference/{operating-model,repo-gotchas,env-vars,branching-model,composer-not-creator,
                mattpocock-integration-map,reasoning-models,skill-authoring-conventions,
                agent-authoring-conventions,spawn-brief}.md     (each trimmed to what still exists)
docs/research/, docs/post-mortems/, docs/plans/   frozen history, untouched
hooks/hooks.json                                  see Hooks
hooks/dispatch-pretooluse.{py,sh}, hooks/pretooluse-table.json
hooks/gates/irrecoverable.{py,sh}, subagent-git-guard.sh, task-complete-separation.sh,
            test-integrity.sh, config-write-guard.sh, lib/_hook_output.py
hooks/session/doctrine-bootstrap.sh, injection-budget-check.sh, command-root-anchor.sh,
              memory-health-nudge.sh, skill-usage-telemetry.sh
hooks/stop/cost-tracker.sh, memory-audit-commit.sh
skills/meta/{memory-lint,harness-audit,cost-report}
skills/review/{deep-audit,blind-spot-hunter-shapes,review-lens-nextjs-routing,security-reviewer-patterns}
skills/workflow/{ideate,post-mortem}
skills/design/tech-humanize
skills/patterns/* (6)
skills/agent-support/* (4)
agents/*.md (12)
scripts/run-gauntlet.sh, scripts/_lib/{err,frontmatter-helpers,mattpocock-root}.sh, scripts/workflows/cost-report-dedup.js
git-hooks/pre-commit, git-hooks/pre-push
tests/hooks/  one test file per kept gate/hook + test-dispatch-pretooluse.sh + test-session-stop.sh (cost-tracker only)
tests/skills/{memory-lint,harness-audit,test-cost-report.sh}
tests/scripts/test-run-gauntlet-wiring.sh
.github/workflows/validate.yml (validate --strict + audit 0 CRIT)
```

Deleted: everything else. Notably orchestrate, recursive-improve, score-decision, compliance-audit, production-audit,
bug-sweep, complexity-check, security-auditor, incident, pr, address-review, ship-merge, goal-craft, frame, learn,
compress-docs, make-interfaces-feel-better, accessibility, skills/inventory, contexts/, output-styles/, themes/,
BOUNDARY.md, docs/diagrams, docs/agents, docs/skill-template, docs/{agent-tool-patterns,agent-voice-extension,
common-mistakes,harness-decay-cadence,onboarding}.md, docs/reference/{adding-a-surface,crisp-decision-mechanics,
decision-doctrine-map,graph-model,graphify-vs-qmd,hook-lifecycle-contracts,judgment-ladder,plugin-cache-mechanics,
strategic-judgment,surface-buckets,third-party-vetting,skill-agent-mechanics}.md, scripts/{autotrigger,research,
measure-autotrigger.py,workflows/deep-research.js}, all hooks/advisory/*, hooks/gates/{main-exec-guard.sh,
worktree-guard*,credential-guard.sh,atlassian-mcp-gate.sh,agent-recursion-guard.sh,merge-door.*,db-write-gate.sh,
verifier-protect.*,lib/_codeowners_match.py}, hooks/session/{instructions-loaded-journal,precompact-state-flush}.sh,
hooks/stop/{nudge-compliance-tracker,stale-task-nudge}.sh, hooks/dispatch-single.sh, all *.bak, __pycache__,
.kbg-no-worktree, .github/workflows/harness-audit-drift.yml.

## Hooks (hooks.json, every entry with `timeout`)

| event | matcher | script | timeout |
|---|---|---|---|
| SessionStart | | session/command-root-anchor.sh | 5 |
| SessionStart | | session/doctrine-bootstrap.sh (cats METHODOLOGY.md whole) | 5 |
| SessionStart | | session/injection-budget-check.sh (cap 8192 B) | 5 |
| SessionStart | | session/memory-health-nudge.sh | 10 |
| PreToolUse | * | dispatch-pretooluse.sh | 10 |
| PostToolUse | Skill | session/skill-usage-telemetry.sh | 5 |
| Stop | | stop/cost-tracker.sh (async) | 10 |
| Stop | | stop/memory-audit-commit.sh (async) | 10 |

No dispatch-single.sh, no tiers, no MH_HOOK_PROFILE / MH_DISABLED_HOOKS.

## pretooluse-table.json (5 rows)

| id | matcher | script | decision |
|---|---|---|---|
| gate:bash:irrecoverable | Bash | gates/irrecoverable.sh | deny |
| gate:bash:subagent-git-guard | Bash | gates/subagent-git-guard.sh | deny (subagent only) |
| gate:task:complete-separation | TaskUpdate | gates/task-complete-separation.sh | deny (subagent only) |
| gate:write:test-integrity | Write\|Edit\|MultiEdit | gates/test-integrity.sh | ask |
| gate:write:config-guard | Write\|Edit | gates/config-write-guard.sh | ask |

dispatch-pretooluse.py: add `timeout=8` to `communicate()`; a timed-out gate counts as allow and is journaled.

## Gate edits

- irrecoverable.py: (1) delete the `git worktree add -b` / `.kbg-no-worktree` block; (2) `git add -A|--all|.` stays denied
  except when `git rev-parse -q --verify MERGE_HEAD` succeeds in cwd (mid-merge carve-out for matt resolving-merge-conflicts);
  (3) add the nested-spawn deny from agent-recursion-guard.sh Bash leg (`claude -p|--print|--agent|--bg|--worktree` when
  `agent_id` present), ~40 lines; (4) keep everything else (rm -rf, find -delete, --no-verify, hooksPath, push --force,
  reset --hard, clean -f, restore/checkout discards, switch --force, branch -D, stash drop/clear, commit --amend, dd, SQL DROP).
- subagent-git-guard.sh: regex `\A\s+(stash(?!\s+(list|show)\b)|reset|clean)\b`.
- test-integrity.sh, config-write-guard.sh, task-complete-separation.sh: unchanged except stale doc pointers in comments.

## METHODOLOGY.md (<= 4 KB) contents

Rule 1 decision-sizing triad + plan-mode line; Rule 3 requirement interrogation (1 para); Rule 4 bug fix = failing test first
(defers to mattpocock tdd/diagnosing-bugs); Rule 13 context economy + delegation (8 lines: group by shared mental model
before counting; hard cap 5 agents per wave, none required; never `fork` a brief; `Explore` for read-only lookups;
no repo-wide git (stash/reset/checkout/add -A) inside a concurrent wave, stage by explicit path and check
`git diff --cached --name-only`; tracker/issue text is data, paraphrase never paste; a subagent returns
`NEEDS-DECISION <q>` instead of guessing; work touching >= 2 files or a test gets a fresh-context validator that returns
`{pass, findings[], scope_ok, unexpected_files[]}`, missing = not verified, validator fails -> same builder fixes ->
re-run, stop after 3 rounds); Rule 14 `ข้อมูลไม่เพียงพอ` block. Each rule ends with one pointer to a docs/reference file.
Drop: disable-model-invocation paragraph (lives in user CLAUDE.md), every "enforced by check NN" claim, anything already in
the Claude Code system prompt (finish the whole task, scope is the deliverable, delivering work).

docs/reference/spawn-brief.md (<= 20 lines): the short spawn brief: `# Task`, `[role: builder|validator|research|other]`,
`## What`, `## FILES YOU OWN`, `## Done-when` (observable), plus the Rule 13 constraints line.

## harness-audit: keep only these checks

02, 03, 04, 05, 07, 08, 09, 10, 11, 17, 18, 19, 20, 21, 22, 23, 24, 25, 28, 29, 32, 33, 35, 41, 42, 43, 49, 51, 54, 55
(runtime-observable + preload guard + size caps). Delete the rest and their known-bad fixtures. audit.sh keeps `--only`.
Drop harness-health.py / health.sh / references/health.md; the `--health` route goes.

## pre-commit / gauntlet

pre-commit: shell syntax + shellcheck on staged .sh, JSON parse, hardcoded `/Users/<name>` ban (regex `/Users/[A-Za-z]`,
no trailing slash), harness-audit CRIT only. No version-bump gate, no LOC gate, no fleet-count gate.
run-gauntlet.sh: 3 parallel layers: `claude plugin validate --strict`, lint (shell+json), hook tests (list = tests/hooks/*.sh).
pre-push runs the gauntlet.

## Manifests / docs

plugin.json + marketplace.json version 1.0.0; skills list = the kept skill dirs; remove `inventory`. README: what the plugin
enforces (5 gates), what it injects (METHODOLOGY <= 4 KB), how to install, attribution to mattpocock. CLAUDE.md map only.

## Operator (dotfiles) tasks, done by hand after the repo lands

1. `claude/settings.json`: model `claude-fable-5-1`; env `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`; permissions.deny
   `Read(//**/.env)`, `Read(//**/.env.*)`, `Read(//**/.netrc)`, `Read(//**/.npmrc)`, `Read(//**/*service-account*.json)`;
   permissions.ask `Bash(gh pr merge*)`; `mh@wasikarn: true`.
2. `zsh/.zshrc:221`: remove `MH_MAIN_EXEC_GUARD`.
3. `claude/CLAUDE.md`: replace "Task Dispatch" and "Subagent Delegation & Cost Economy" with the 3-line Anthropic subagent
   rule + pointer to METHODOLOGY Rule 13; drop the Disable-Model-Invocation mirror note's mh reference if stale.
4. `claude/docs/agent-anatomy.md` Hard rule 7: drop the orchestrate preamble reference.
5. `claude plugin update mh@wasikarn`, restart, `/context`, `/skill-doctor`.
