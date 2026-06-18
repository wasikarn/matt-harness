---
name: agent-teams-setup-notes
description: One-stop setup reference for the 4 vendor configuration knobs that affect how kbg-harness agent teams behave. Not a plugin file — the harness cannot set these for you — but a checklist to verify before running /team-plan or /team-build.
---

# Agent Teams Setup Notes

The kbg-harness plugin provides 21 commands, 38 skills, and 29 agents for multi-agent workflows, but **4 vendor-side settings** control whether the runtime actually permits agent spawning, subagent model selection, and teammate isolation. This doc is the setup checklist — verify these once per machine (or per `~/.claude/` directory).

---

## 1. Enable Agent Teams — `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

**Article:** `agent-teams-setup`  
**What it does:** Unlocks the `TeammateIdle`, `TaskCreated`, and `TaskCompleted` hook events, plus the `--agent` debug flag.

**Set it:**
```bash
# macOS / Linux (add to ~/.zshrc or ~/.bash_profile)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Or prefix the claude invocation every time
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude
```

**Verify it:**
```bash
claude --version  # must be ≥ 2.1.170 (June 2026) for full hook support
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS  # must print 1
```

**If missing:** `/team-build` and `/team-plan` still work (they are command files), but the lifecycle hooks in `hooks/lifecycle/task-lifecycle.sh` never fire — no board auto-update, no F7 test-claim gate, no stale-heartbeat detection.

---

## 2. Subagent Model Default — `CLAUDE_CODE_SUBAGENT_MODEL`

**Article:** `sub-agent-best-practices`  
**What it does:** Sets the default model for all `Task(...)` spawns. The harness recommends `sonnet` for teammates (cost) and `opus` for the lead (judgment).

**Set it:**
```bash
export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-5-20250929
```

**Per-agent override:** The harness agents that need `opus` already declare `model: opus` in their frontmatter (`backend-engineer`, `frontend-engineer`, `code-architect`, `security-reviewer`). This env var is the fallback for agents without an explicit model.

**Verify it:**
```bash
grep -E "^model:" "${KBG_PLUGIN_ROOT}/agents"/*.md | sort  # confirm 23 sonnet + 4 opus
```

---

## 3. Teammate Mode — `teammateMode: "in-process"` in settings.json

**Article:** `agent-teams-setup`  
**What it does:** Controls whether subagents run in the same Claude Code process (`in-process`) or in isolated processes. `in-process` is required for the harness's `PreToolUse` hooks (`validator-bash-guard.sh`, `block-dangerous-git.sh`, etc.) to fire on subagent tool use.

**Set it:**
```bash
# In the active Claude Code project directory
claude config set teammateMode in-process
```

**Verify it:**
```bash
claude config get teammateMode  # should print "in-process"
```

**If set to `out-of-process`:** Subagent Bash/Read/Edit calls bypass the parent session's `PreToolUse` hooks — the validator Bash guard cannot block mutations.

---

## 4. `~/.claude/teams/{name}/config.json` — Team-specific overrides

**Article:** `agent-teams-setup`  
**What it does:** Per-team configuration files that the vendor runtime reads. The harness does not write here, but you can place team-specific constants (e.g., default test command, project language) so `/team-build` picks them up without plan repetition.

**Example:**
```json
{
  "default_test_command": "pytest tests/ -v",
  "language": "python",
  "framework": "fastapi",
  " preferred_builder": "backend-engineer",
  "ci_provider": "github-actions"
}
```

**Harness integration:** `/team-build` Step 5 (plan approval filter) can read this file and auto-fill `validation_command:` placeholders if the plan omits them. This is a future enhancement (P2.5); the harness currently expects the plan file to be self-contained.

---

## Quick-start Checklist (copy-paste)

```bash
# 1. Env var
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-5-20250929

# 2. Config
claude config set teammateMode in-process

# 3. Verify
echo "Agent Teams: $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
echo "Subagent model: $CLAUDE_CODE_SUBAGENT_MODEL"
claude config get teammateMode

# 4. Smoke test — spawn one agent
claude --agent code-explorer -- "List the 5 most recently modified files in this repo"
```

**Done-when:** All 4 checks above print the expected values and the smoke test returns a file list without errors.

---

## See also

- `docs/adr/0002-autonomy-invariant.md` — why the harness stays at L2 (human-gated) and does not attempt L3/L4 autonomous loops
- `commands/team-plan.md` — Step 1-3 of the 7-step pipeline
- `commands/team-build.md` — Step 4-7, including the F10 plan approval filter
- `skills/orchestrate/SKILL.md` — F9 spawn-prompt template and validation chain
- `hooks/gates/validator-bash-guard.sh` — runtime enforcement of read-only validator doctrine
