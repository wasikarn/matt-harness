# Common mistakes when building custom agents

**Status:** Convention reference. Adapted from the claudefa.st *Custom Commands* article for the kbg-harness plugin.  
**Last verified:** 2026-06-12

The claudefa.st corpus documents four mistakes that crop up when teams build custom agents. This document adds a fifth (plan-without-validation) that the harness's orchestrate workflow specifically guards against. Each section maps the vendor mistake to a harness-native fix, with a one-line self-check you can run to verify the guard is in place.

---

## Mistake 1 — Scope too broad

**Symptom:** The agent produces surface-level observations across every dimension. A "review this codebase for all issues" agent returns a shallow checklist that misses real problems because it spent its context window on breadth, not depth.

**Root cause:** The agent's `description`, prompt body, or spawn instructions do not define a narrow domain boundary. Without an explicit "Don't use for:" line, the orchestrator (or the user) dispatches it to tasks outside its competence.

**Harness fix:** Every agent file under `agents/` starts with a narrow `description:` in YAML frontmatter and a `## Domain focus` section in the body that names the single responsibility. The `## Cross-role boundaries` section explicitly lists what the agent does **not** do, so the orchestrator routes outbound work to the right specialist.

Example from `agents/code-reviewer.md`:

```markdown
---
description: "Review code changes for correctness, style, and regressions."
---

## Domain focus
Read-only inspection of diffs and source files. Verdicts are pass/minor/reject with file:line citations.

## Cross-role boundaries (defer instead of absorbing)
- Defer to security-reviewer for vulnerability analysis
- Defer to backend-engineer for API contract design
- Defer to devops-engineer for deployment pipeline changes
```

The orchestrate skill's routing table (`skills/orchestrate/SKILL.md` § Procedure step 4) reads this boundary list before dispatch. A task that touches auth/secrets is routed to `security-reviewer`, not `code-reviewer`, because the boundary says so.

**Self-check:**

```bash
grep -L "## Cross-role boundaries" "${KBG_PLUGIN_ROOT}/agents"/*.md
```

Any file that appears in the output is missing the boundary guard.

---

## Mistake 2 — Duplicating baseline capabilities

**Symptom:** You create a `/search` slash command or a `file-finder` agent, then discover that Claude Code's built-in `Explore` subagent already does the same thing faster and with better integration. The duplicate command sits unused in `.claude/commands/`, wasting frontmatter parsing time and confusing new team members.

**Root cause:** The builder did not read the vendor's baseline capability list or the harness's existing agent fleet before adding a new surface. Custom agents should encode *team-specific* expertise, not reimplement vendor primitives.

**Harness fix:** The `orchestrate` skill (`skills/orchestrate/SKILL.md` § Routing table) routes fast file lookup to the built-in `Explore` subagent, research synthesis to `/deep-dive`, and PR review to `kbg:review-pr`. Before creating a new command, check the routing table — if the task fits an existing bucket, use that bucket. The harness's 11 agents cover the common specializations; a new agent is justified only when the task is (a) recurring, (b) domain-specific, and (c) not handled by the current fleet.

The `orchestrate` skill also gates new-agent proposals: step 4 requires the lead to "analyze each task's blast radius and dependency chain" before dispatch. A task that is "look up where function X is defined" has zero blast radius and no dependencies — it routes to the built-in `Explore` subagent inline, not to a new agent.

**Self-check:**

```bash
grep -r "file finder\|search codebase\|where is" "${KBG_PLUGIN_ROOT}/commands" "${KBG_PLUGIN_ROOT}/skills" "${KBG_PLUGIN_ROOT}/agents" | grep -v "Explore\|deep-dive"
```

If the grep finds a command or agent whose description overlaps with an existing specialist, it is a candidate for consolidation.

---

## Mistake 3 — Giving write access to read-only agents

**Symptom:** A validator agent (e.g., `code-reviewer`) claims it is "fixing" issues during review. It edits files, reformats code, or pushes commits. The review is no longer independent — the validator became the builder, collapsing the maker≠checker separation that `METHODOLOGY.md` Rule 4 requires.

**Root cause:** The agent's YAML frontmatter grants `Edit` or `Write`, or it holds `Bash` and uses a mutation command (`sed -i`, `git commit`, `rm`, `mv`). The vendor's `allowedTools` list is the gate, but it is advisory unless paired with runtime enforcement.

**Harness fix:** Two layers:

1. **Allowlist frontmatter.** Every validator-class agent uses `tools:` (allowlist), not `disallowedTools:` (denylist). The read-only validator agents in the current fleet — `code-architect`, `code-reviewer`, `python-reviewer`, `typescript-reviewer`, `silent-failure-hunter`, `ideate-critic` — list `Read, Grep, Glob, Bash` at most (or just `Read`), never `Edit` or `Write`. See `docs/agent-tool-patterns.md` §1 for the convention.

2. **No runtime Bash guard today.** There is currently no `PreToolUse` hook that intercepts a validator's Bash commands and blocks mutation patterns at runtime — the allowlist frontmatter above is the only gate, and it is doctrine, not runtime-enforced. A validator that reformats code, runs `git commit`, or otherwise mutates state during review is a bug to file (fix the frontmatter or the prompt), not something a live hook currently catches.

3. **Orchestrate dispatch gate.** The `orchestrate` skill (`skills/orchestrate/SKILL.md` § Procedure step 4) gates any agent holding `Edit`, `Write`, or `Bash` behind an `AskUserQuestion`. Read-only agents (no mutation tools) dispatch without a gate; write-capable agents require explicit approval. This means even if a validator accidentally had `Edit` added to its frontmatter, the orchestrator would not dispatch it without user consent.

**Self-check:**

```bash
grep -l "tools:.*Edit\|tools:.*Write" \
  "${KBG_PLUGIN_ROOT}/agents"/{code-architect,code-reviewer,python-reviewer,typescript-reviewer,silent-failure-hunter,ideate-critic}.md 2>/dev/null
```

The grep should return no files — if it does, a validator-class agent picked up a mutation tool and the frontmatter needs fixing.

---

## Mistake 4 — No done-when criterion

**Symptom:** A subagent finishes its task and reports "I analyzed the auth module" or "The research is complete." The lead has no observable artifact to verify — no file path, no test output, no commit SHA. The task is marked complete by fiat, and downstream waves build on unverified sand.

**Root cause:** The spawn prompt describes a topic, not a deliverable. Without an explicit "done-when" checklist, the subagent substitutes prose for evidence and the lead has no gate to reject it.

**Harness fix:** The F9 spawn-prompt template (`skills/orchestrate/SKILL.md` § Spawn-prompt template) mandates a `## Done-when` section with three observable checks. Every `orchestrate` dispatch injects this template verbatim. The done-when items are concrete, not conceptual:

```markdown
## Done-when
- [ ] `POST /health` returns `{"status":"ok"}` with HTTP 200
- [ ] `pytest tests/test_health.py -v` exits 0
- [ ] No edit outside FILES YOU OWN
```

The orchestrator's verification step greps for these observables before starting the next wave. If a subagent returns prose instead of a checked done-when list, the lead re-dispatches or rejects the task.

**Self-check:**

```bash
grep -c "Done-when" "${KBG_PLUGIN_ROOT}/skills/orchestrate/SKILL.md"
```

The count should be > 0 — orchestrate's F9 template embeds the Done-when contract.

---

## Mistake 5 — Plan without validation

**Symptom:** The dispatch flow executes a plan, waves finish, and the user asks "does it work?" No one knows. Tests were mentioned in the plan but never run. A schema change went in without a migration. The integration validator (INT-*) was skipped because "everyone's code looked fine." The build ships with latent defects that a 5-minute validation command would have caught.

**Root cause:** The planning phase optimistically assumed correctness; the execution phase had no post-work gate. Quality was eyes-only, not command-verified.

**Harness fix:** Three gates, one pipeline:

1. **Pre-flight plan linter** — `scripts/plan-linter.py`. Before any agent is spawned, the lead runs the linter against the plan file (`.claude/tasks/<slug>.md`) to catch pre-execution risks: overlapping file ownership, missing migration tasks, auth/secrets without a security reviewer, and absent integration validators. Bad plans are rejected with reasons; the user revises and re-runs. The orchestrator's Step 4 blast-radius + dependency analysis is the dispatch-side companion gate (`skills/orchestrate/SKILL.md` § Procedure step 4).

2. **F7 test-claim gate** — in `hooks/lifecycle/task-lifecycle.sh` (Phase 2 F7, 2026-06-12). A subagent that claims "tests pass" or "pytest" in its task subject/description but does NOT include a runnable `validation_command:` field is blocked from completing (exit 2 + stderr feedback). The subagent must add the command and re-trigger completion. This is the post-execution half of the pipeline.

3. **Per-task validation chain** — for single-task validation after each wave completes. The lead runs the `B → V1 → F → V2` chain (builder → validator → fix → re-validator) from `skills/orchestrate/SKILL.md` § Validation chain inline on each completed task before starting the next wave.

The plan linter can pre-check a plan before `orchestrate` dispatch:

```bash
python3 "${KBG_PLUGIN_ROOT}/scripts/plan-linter.py" .claude/tasks/<slug>.md --strict
```

**Self-check:**

```bash
grep -c "validation_command\|F7" "${KBG_PLUGIN_ROOT}/hooks/lifecycle/task-lifecycle.sh"
grep -c "validation chain" "${KBG_PLUGIN_ROOT}/skills/orchestrate/SKILL.md"
test -x "${KBG_PLUGIN_ROOT}/scripts/plan-linter.py" && echo "plan-linter present"
```

All three should be non-zero / present. If any is missing, that gate is gone from the documented surface.

---

## Cross-references

- [`docs/agent-tool-patterns.md`](./agent-tool-patterns.md) — allowlist vs denylist convention, agent tool matrix
- `METHODOLOGY.md` Rule 8 + `CLAUDE.md` §The operating model — why maker≠checker separation is load-bearing
- [`skills/orchestrate/SKILL.md`](../skills/orchestrate/SKILL.md) — F9 spawn-prompt template, bounded fan-out, validation chain, routing table
