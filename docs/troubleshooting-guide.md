# Troubleshooting agent-team execution failures

**Status:** Runbook reference. Adapted from the claudefa.st *Agent Teams Best Practices & Troubleshooting* article for the kbg-harness plugin.  
**Last verified:** 2026-06-12

This guide covers the eight most common failure modes when running multi-agent builds with `/team-build`, `/validate-and-fix`, and the agent-team lifecycle hooks. Each scenario includes the symptom you see, the likely cause, the exact fix, and how to prevent it next time.

---

## 1. Teammate goes idle unexpectedly

**Symptom:** A teammate stops producing output mid-task. The lead's wave stalls. `/wave-status` shows the teammate's last heartbeat is older than 5 minutes while the task is still `in_progress`. The vendor's Ctrl+T panel shows the teammate as idle or missing.

**Likely cause:** The teammate session was evicted (context budget exhausted, runtime error, or user-side Ctrl+C), or the heartbeat file stopped updating because the agent crashed silently. This is the vendor "No session resumption" limitation: in-process teammates are not restored when using `/resume` or `/rewind`.

**Fix:**

1. Check heartbeats with `/wave-status`:
   ```bash
   /wave-status health-endpoint
   ```
   Look for "Stale heartbeats" section. Note the `agent_id` and `current_task`.

2. If the heartbeat is stale and the task is `in_progress`, the task is orphaned. Re-claim it via `/team-build` or reset the task to `pending` so another agent can pick it up:
   ```bash
   python3 -c "
   import sys, json
   from pathlib import Path
   plan_dir = Path.home() / '.claude/tasks/health-endpoint'
   board = json.loads((plan_dir / 'board.json').read_text())
   for tid, t in board['tasks'].items():
       if t.get('status') == 'in_progress' and t.get('claimed_by') == 'agent-7':
           t['status'] = 'pending'
           t['claimed_by'] = None
           t['claimed_at'] = None
   (plan_dir / 'board.json').write_text(json.dumps(board, indent=2))
   print('Task reset to pending')
   "
   ```
   Replace `health-endpoint` and `agent-7` with the actual values from `/wave-status`.

3. Re-dispatch the task in the next wave via `/team-build <plan-file>`. The lead will see the task as `pending` and spawn a replacement teammate.

**Prevention:** Use the F8.5 bounded fan-out cap so no single wave is so large that teammate eviction stalls the whole build. Keep teammate count at 3-5 (F8 doctrine). If a task is long-running, split it into smaller tasks with observable done-when checkpoints.

---

## 2. Merge conflicts between teammates

**Symptom:** Two teammates edited the same file. The second teammate's edit overwrote the first's, or git shows a merge conflict when the lead tries to integrate. Wave verification fails because the file on disk does not match either teammate's claimed output.

**Likely cause:** The plan assigned the same file to multiple tasks, or the file ownership boundary was implicit ("edit the auth module") rather than explicit ("edit `src/auth/users.py`, not `src/auth/tokens.py`"). The claudefa.st article names this as the single most important rule for implementation tasks.

**Fix:**

1. Check file ownership uniqueness with the plan linter:
   ```bash
   python3 scripts/plan-linter.py .claude/tasks/health-endpoint.md
   ```
   Look for the error: `File '<path>' owned by multiple tasks: ...`

2. If the plan is already in flight, stop the build. Edit the plan file to assign each file to exactly one task. If a file truly must be touched by two tasks, split it: task A writes the schema, task B writes the consumer — the orchestrator (lead) merges the contracts, not the teammates.

3. Re-run `/team-build` with the revised plan.

**Prevention:** Enforce single-owner-per-file at plan time. The plan linter's `_check_file_ownership()` (in `scripts/plan-linter.py`) blocks any plan where a file appears in more than one task's `Files` column. Run the linter before `/team-build`:

```bash
python3 scripts/plan-linter.py .claude/tasks/health-endpoint.md --strict
```

The F9 spawn-prompt template also requires `## FILES YOU OWN` — a teammate with a single-file boundary cannot conflict with another teammate that owns a different file.

---

## 3. Validation fails but task claims "done"

**Symptom:** A teammate reports "tests pass" or "implementation complete," but the validation command exits non-zero or the acceptance criterion is not satisfied. The task board shows `status: completed`, yet the artifact is broken.

**Likely cause:** The teammate claimed completion without running the validation command, or it ran the command in a different environment (wrong working directory, missing env vars). The F7 gate in `hooks/task-lifecycle.sh` is designed to catch this, but it only fires when the claim text includes test keywords without a `validation_command:` field.

**Fix:**

1. Run `/validate-and-fix` on the task:
   ```bash
   /validate-and-fix API-1 health-endpoint
   ```
   This invokes the `B → V1 → F → V2` chain: a `code-reviewer` validates the builder's output, findings are presented to the user, a fixer agent applies fixes, and a re-validator confirms the fix.

2. If the task board is already in `completed` state but you know it is wrong, reset it to `pending` manually (same Python snippet as scenario 1) and re-dispatch.

3. Check the hook journal for the blocked claim:
   ```bash
   tail -20 ~/.claude/team-events/$(date -u +%Y-%m-%d).jsonl | jq -r 'select(.event == "TaskCompleted") | .payload.task_subject'
   ```

**Prevention:** The F7 gate (`hooks/task-lifecycle.sh`) blocks TaskCompleted events that contain test keywords (`pytest`, `npm test`, `cargo test`, etc.) but lack a `validation_command:` field. Ensure every spawn prompt from `/team-build` includes the validation command in the task description body, e.g.:

```markdown
validation_command: pytest tests/test_api.py -v
```

The F9 template enforces this by convention; the F7 hook enforces it by runtime block.

---

## 4. Plan too big / too small

**Symptom:** A plan has 15 tasks and 8 teammates. The lead's context is saturated by Wave 2, and coordination overhead exceeds implementation work. Alternatively, a plan has 1 task and 1 teammate — the agent-team machinery is more expensive than inline coding.

**Likely cause:** The plan author did not size tasks to the "self-contained unit that produces a clear deliverable" rule. The claudefa.st article recommends 5-6 tasks per teammate (roughly 3-5 teammates total) as the sweet spot.

**Fix:**

1. Re-plan with `/team-plan`. Split oversized tasks into smaller ones with explicit file boundaries and done-when criteria. Merge trivial tasks into a single coherent task.

2. Run the plan linter to check team-member count:
   ```bash
   python3 scripts/plan-linter.py .claude/tasks/health-endpoint.md
   ```
   The linter errors if team members are outside 3-5.

3. If the plan is already in flight and the lead is saturated, abort the build (`/team-cleanup`), revise the plan, and restart with `/team-build`.

**Prevention:** Task sizing guidance is load-bearing in the F8 lead doctrine (`skills/orchestrate/SKILL.md` § Lead-coordinator doctrine). The lead refuses to build plans outside the 3-5 teammate range. Future work will add a `skills/task-sizing` skill that estimates task granularity from the brain dump; for now, the linter and the F8 doctrine are the guards.

---

## 5. Context budget exhausted mid-build

**Symptom:** The lead starts Wave 3 and responses become slower, shorter, or start losing track of earlier wave contracts. Token usage spikes. The vendor's context window is approaching its limit.

**Likely cause:** The lead is running in the same session that planned the work. Planning context (brain dump, Q&A log, team member table) consumes budget before the first teammate is spawned. By Wave 3, the lead has retained the full plan plus all wave-1 and wave-2 outputs.

**Fix:**

1. The fresh-session recommendation is in `/team-build` Step 4 (`commands/team-build.md` § Step 4 — Fresh context). If the lead detects a mid-session build, it surfaces an `AskUserQuestion`:
   - `Start a fresh session and /exit first (Recommended)`
   - `Continue in the current session`

2. Choose the fresh session. The plan file (`.claude/tasks/<slug>.md`) is the session-resettable interface (D10). A new session reads the plan cold and resumes from the same `board.json` state.

3. For deterministic replay, use `--spec` (future P2.4 enhancement). The dispatcher renders the wave plan from a YAML spec:
   ```bash
   python3 scripts/orchestrate-dispatch.py skills/orchestrate/examples/ship-merge.yml --emit-plan
   ```

**Prevention:** Always run `/team-build` in a fresh Claude Code session. The plan file decouples state from session context; do not carry planning context into execution context. The lead's Step 4 soft-warn gate reminds you if you forget.

---

## 6. Agent spawn fails (rate limit / model unavailable)

**Symptom:** A `Task` spawn returns an error: rate limit exceeded, model identifier not found, or API provider environment variable missing (Bedrock/Vertex/Foundry). The wave stalls because one teammate never started.

**Likely cause:** The wave exceeded the runtime's parallel spawn limit, or the model string in the spawn prompt was invalid for the current API provider. This is the vendor "teammates on Bedrock/Vertex/Foundry fail" issue, fixed in Claude Code v2.1.45+.

**Fix:**

1. Check the vendor version:
   ```bash
   claude --version
   ```
   If below v2.1.45, update. Earlier versions had missing API provider env var propagation to tmux sessions.

2. The F8.5 bounded fan-out cap (`skills/orchestrate/SKILL.md` § Bounded fan-out) clamps total spawned agents to 16 per wave. If a wave has >16 tasks, `/team-build` MUST split it: spawn 16, queue the rest in `deferred-<date>.md`, dispatch the next batch after the first finishes.

3. If a spawn still fails, queue the deferred task:
   ```bash
   echo "- API-1: implement auth middleware" >> .claude/tasks/health-endpoint/deferred-$(date -u +%Y-%m-%d).md
   ```
   Re-dispatch manually after the rate limit clears.

**Prevention:** Respect the F8.5 cap in plan design. The `/team-build` command enforces it at Step 6: "A wave with >16 tasks MUST be split." The cap is on total spawned agents across the plan lifetime (worklist + audit + verify), not just the work-list size.

---

## 7. Hook blocks legitimate action

**Symptom:** A PreToolUse hook (`validator-bash-guard`, `task-lifecycle`, `block-dangerous-git`, `secret-read-guard`) blocks an action you intended to allow. The agent receives a deny decision and stops, or the TaskCompleted gate rejects a completion you believe is valid.

**Likely cause:** The hook's pattern match is overly broad, or the task description formatting does not match the hook's expected field syntax (e.g., `validation_command:` with a space instead of an underscore). Hooks are regex-based and cannot reason about intent.

**Fix:**

1. Bypass the specific hook for the current session:
   ```bash
   export CLAUDE_DISABLED_HOOKS=validator-bash-guard
   # or multiple hooks:
   export CLAUDE_DISABLED_HOOKS="validator-bash-guard,task-lifecycle"
   ```

2. Alternatively, disable the entire hook profile:
   ```bash
   export CLAUDE_HOOK_PROFILE=off
   ```
   This bypasses ALL hooks. Use only for debugging, and re-enable immediately after.

3. For the F7 TaskCompleted gate specifically, you can downgrade it to log-only without disabling the hook entirely:
   ```bash
   export KBG_ENFORCE_TASK_COMPLETED=0
   ```
   This preserves journaling but removes the exit 2 block. Documented in `hooks/task-lifecycle.sh` § Phase 2.3 escape hatch.

4. After bypassing, re-run the blocked action. Then fix the underlying issue (update the hook regex, or correct the task description format) so the bypass is no longer needed.

**Prevention:** Hooks are deterministic regex guards, not semantic reasoners. Write task descriptions that match the expected patterns exactly. If a hook blocks legitimately often, the regex is the bug — file a harness-audit ticket to tighten or broaden the pattern. Never leave `CLAUDE_HOOK_PROFILE=off` in your shell profile; it disables the entire safety layer.

---

## 8. Stale locks preventing task claim

**Symptom:** A teammate tries to claim a task and fails with "lock held by another agent" or a timeout on `lock_acquire`. The task stays `pending` even though no visible agent is working on it. The board shows `claimed_by: agent-X` but the agent is dead.

**Likely cause:** An agent crashed or was killed while holding a lock. The lock file (mkdir-based lock in `~/.claude/locks/<team>/`) was never released because the agent did not reach its cleanup path. The lock has an `expires_at` field, but the expiration time is in the future or the field is missing.

**Fix:**

1. Run the lock reaper for the plan's team:
   ```bash
   bash scripts/locks/lock-reap.sh --team=health-endpoint --dry-run
   ```
   This previews which locks are broken (expired). If the output looks correct, remove `--dry-run`:
   ```bash
   bash scripts/locks/lock-reap.sh --team=health-endpoint
   ```
   The script breaks expired locks, logs via `journal_append`, and removes the lock directory.

2. If the lock is NOT expired but the agent is definitely dead, force-release it manually:
   ```bash
   rm -rf ~/.claude/locks/health-endpoint/API-1
   ```
   Then reset the task to `pending` (same Python snippet as scenario 1).

3. For a full cleanup of stale artifacts (locks, heartbeats, orphaned board entries), run:
   ```bash
   /team-cleanup health-endpoint --dry-run
   ```
   Review the preview, then run without `--dry-run` to execute.

**Prevention:** The lock reaper should be run periodically after builds, or wired into `/team-cleanup`. Every lock has an `expires_at` timestamp; the reaper checks it against the current time. Ensure locks are created with a reasonable expiration (e.g., 1 hour for short tasks, 4 hours for long tasks). The `task_board_lib.py` `lock_acquire()` helper sets a default expiration; if you create locks manually, include `expires_at` in the lock JSON.

---

## Quick-reference: bypass and diagnostic commands

| Goal | Command |
|------|---------|
| Check build status | `/wave-status health-endpoint` |
| Pre-flight plan check | `python3 scripts/plan-linter.py .claude/tasks/health-endpoint.md --strict` |
| Validate a completed task | `/validate-and-fix API-1 health-endpoint` |
| Clean up stale artifacts | `/team-cleanup health-endpoint --dry-run` |
| Reap expired locks | `bash scripts/locks/lock-reap.sh --team=health-endpoint` |
| Disable one hook | `export CLAUDE_DISABLED_HOOKS=hook-name` |
| Disable all hooks | `export CLAUDE_HOOK_PROFILE=off` |
| Downgrade F7 to log-only | `export KBG_ENFORCE_TASK_COMPLETED=0` |
| View today's task events | `tail ~/.claude/team-events/$(date -u +%Y-%m-%d).jsonl` |
| Render a spec plan | `python3 scripts/orchestrate-dispatch.py skills/orchestrate/examples/ship-merge.yml --emit-plan` |

---

## Cross-references

- [`docs/common-mistakes.md`](./common-mistakes.md) — the five root causes that produce these symptoms
- [`commands/team-build.md`](../commands/team-build.md) — F10 plan approval, wave execution, fresh-session gate
- [`commands/validate-and-fix.md`](../commands/validate-and-fix.md) — per-task B→V1→F→V2 validation chain
- [`commands/wave-status.md`](../commands/wave-status.md) — heartbeat and lock status report
- [`commands/team-cleanup.md`](../commands/team-cleanup.md) — stale artifact cleanup pipeline
- [`skills/orchestrate/SKILL.md`](../skills/orchestrate/SKILL.md) — F8 lead doctrine, F8.5 bounded fan-out, F9 spawn-prompt template
- [`hooks/task-lifecycle.sh`](../hooks/task-lifecycle.sh) — F7 TaskCompleted gate, TeammateIdle heartbeat check
- [`hooks/validator-bash-guard.sh`](../hooks/validator-bash-guard.sh) — PreToolUse Bash mutation guard
- [`scripts/plan-linter.py`](../scripts/plan-linter.py) — pre-flight plan validation (file ownership, team size, F10 risks)
- [`scripts/locks/lock-reap.sh`](../scripts/locks/lock-reap.sh) — expired lock reaper
