# shellcheck disable=SC1090,SC1091,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-gates.sh — standalone suite run by test-critical-hooks.sh
# Covers: PreToolUse gates, task-lifecycle F7, task board integration,
#         db-write-gate, bypass contract, and syntax smoke.

# --- block-dangerous-git: deny destructive, ask on develop, allow safe/fix ---
check gates/block-dangerous-git.sh deny "blocks reset --hard"        "$(bash_event 'git reset --hard HEAD~1')"
check gates/block-dangerous-git.sh deny "blocks force push main"     "$(bash_event 'git push --force origin main')"
check gates/block-dangerous-git.sh deny "blocks branch -D"           "$(bash_event 'git branch -D feature')"
check gates/block-dangerous-git.sh deny "blocks bare force-w-lease"  "$(bash_event 'git push --force-with-lease')"
check gates/block-dangerous-git.sh ask  "asks on force push develop" "$(bash_event 'git push --force origin develop')"
check gates/block-dangerous-git.sh none "allows force push feature/" "$(bash_event 'git push --force-with-lease origin feature/x')"
check gates/block-dangerous-git.sh none "allows git status"          "$(bash_event 'git status')"
# Adversarial — git global options (-c / --no-pager / -C) between `git` and the
# subcommand must NOT bypass the gate (pre-fix: `git -c x=y push --force` slipped).
check gates/block-dangerous-git.sh deny "blocks force-push w/ -c global opt"  "$(bash_event 'git -c protocol.version=2 push --force origin main')"
check gates/block-dangerous-git.sh deny "blocks reset --hard w/ --no-pager"   "$(bash_event 'git --no-pager reset --hard origin/main')"
check gates/block-dangerous-git.sh deny "blocks branch -D w/ -C global opt"   "$(bash_event 'git -C /tmp branch -D main')"
check gates/block-dangerous-git.sh none "allows log w/ -c global opt (no FP)" "$(bash_event 'git -c x=y log --oneline')"

# --- doctrine-edit-gate: ask on doctrine files under .claude/, kbg-harness/, or claude/, allow others ---
check gates/doctrine-edit-gate.sh ask  "asks on METHODOLOGY.md"   "$(edit_event '/x/.claude/METHODOLOGY.md')"
check gates/doctrine-edit-gate.sh ask  "asks on settings.json"    "$(edit_event '/x/.claude/settings.json')"
check gates/doctrine-edit-gate.sh ask  "asks on ACLI.md"          "$(edit_event '/x/.claude/ACLI.md')"
check gates/doctrine-edit-gate.sh ask  "asks on DBGATE.md"        "$(edit_event '/x/.claude/DBGATE.md')"
check gates/doctrine-edit-gate.sh ask  "asks on kbg-harness ACLI.md" "$(edit_event '/x/kbg-harness/ACLI.md')"
check gates/doctrine-edit-gate.sh ask  "asks on kbg-harness METHODOLOGY.md" "$(edit_event '/x/kbg-harness/METHODOLOGY.md')"
check gates/doctrine-edit-gate.sh none "allows non-doctrine file" "$(edit_event '/x/.claude/foo.py')"
check gates/doctrine-edit-gate.sh none "ignores not-kbg-harness lookalike" "$(edit_event '/x/not-kbg-harness/METHODOLOGY.md')"
check gates/doctrine-edit-gate.sh none "ignores file outside .claude" "$(edit_event '/x/src/METHODOLOGY.md')"

# --- secret-read-guard: deny secret reads (Read + Bash), allow normal/template ---
check gates/secret-read-guard.sh deny "blocks Read .env"         "$(read_event '/x/.env')"
check gates/secret-read-guard.sh deny "blocks Read id_rsa"       "$(read_event '/home/u/.ssh/id_rsa')"
check gates/secret-read-guard.sh deny "blocks cat .env via bash" "$(bash_event 'cat .env')"
check gates/secret-read-guard.sh none "allows Read README"       "$(read_event '/x/README.md')"
check gates/secret-read-guard.sh none "allows Read .env.example" "$(read_event '/x/.env.example')"
check gates/secret-read-guard.sh none "allows cat README"        "$(bash_event 'cat README.md')"

# --- secret-scan: deny secret patterns in written content, allow benign ---
# Fakes are built at runtime so this test file holds NO secret-shaped literal —
# otherwise secret-scan blocks the very Edit that writes this test (it scans
# Edit/Write content regardless of target). The split/expansion also doubles as
# good hygiene: a test file should never carry a real-looking token.
fake_aws="AKIA$(printf 'A%.0s' $(seq 1 16))"            # AKIA + 16 upper = AWS shape
fake_ghp="ghp_$(printf '0%.0s' $(seq 1 36))"           # ghp_ + 36 = GitHub PAT shape
fake_pk="-----BEGIN RSA PRIVATE ""KEY-----"            # split literal; joins at runtime
check gates/secret-scan.sh deny "blocks AWS key in Write"     "$(write_event /x/a.txt "key=$fake_aws here")"
check gates/secret-scan.sh deny "blocks GitHub PAT in Write"  "$(write_event /x/a.txt "token=$fake_ghp")"
check gates/secret-scan.sh deny "blocks private key in Edit"  "$(edit_new_event /x/a.txt "$fake_pk")"
check gates/secret-scan.sh none "allows benign Write"         "$(write_event /x/a.txt 'just some normal config text')"
check gates/secret-scan.sh none "ignores secret in Bash (not its tool)" "$(bash_event "echo $fake_ghp")"

# --- config-protection: ask on edit of EXISTING config, allow create/non-config ---
check gates/config-protection.sh ask  "asks on existing .eslintrc"    "$(write_event "$FIXTURE/.eslintrc" 'x')"
check gates/config-protection.sh none "allows new .eslintrc (create)" "$(write_event "$FIXTURE/new/.eslintrc" 'x')"
check gates/config-protection.sh none "ignores non-config file"       "$(write_event "$FIXTURE/foo.txt" 'x')"
# narrow (2026-06-16): full Write of an existing config still asks (above); an
# Edit only asks when the change shows a rule-relaxation signal — a benign tweak doesn't.
check gates/config-protection.sh ask  "Edit relaxes a rule -> ask"     "$(edit_new_event "$FIXTURE/.eslintrc" '"no-console": "off"')"
check gates/config-protection.sh none "Edit benign bump -> none"       "$(edit_new_event "$FIXTURE/.eslintrc" '"version": "9.2.0"')"

# --- block-bash-doctrine-write: deny shell writes to doctrine (all roots), allow reads/non-doctrine ---
check gates/block-bash-doctrine-write.sh deny "blocks > redirect to CLAUDE.md" "$(bash_event 'echo hacked > /repo/claude/CLAUDE.md')"
check gates/block-bash-doctrine-write.sh deny "blocks sed -i on settings.json" "$(bash_event 'sed -i s/a/b/ /home/u/.claude/settings.json')"
check gates/block-bash-doctrine-write.sh deny "blocks tee to ACLI.md"          "$(bash_event 'echo x | tee /repo/claude/ACLI.md')"
check gates/block-bash-doctrine-write.sh deny "blocks cp to DBGATE.md"         "$(bash_event 'cp /tmp/x /home/u/.claude/DBGATE.md')"
check gates/block-bash-doctrine-write.sh deny "blocks > to kbg-harness DBGATE.md" "$(bash_event 'echo x > /x/kbg-harness/DBGATE.md')"
check gates/block-bash-doctrine-write.sh none "allows reading doctrine (cat)"  "$(bash_event 'cat /repo/claude/CLAUDE.md')"
check gates/block-bash-doctrine-write.sh none "allows write to non-doctrine"   "$(bash_event 'echo x > /tmp/foo.txt')"

# --- block-alias-shadowing: ask on alias/function shadow of safety binary ---
check gates/block-alias-shadowing.sh ask  "asks on alias git="       "$(bash_event "alias git='git --no-verify'")"
check gates/block-alias-shadowing.sh ask  "asks on git() function"   "$(bash_event 'git() { command git --no-verify "$@"; }')"
check gates/block-alias-shadowing.sh ask  "asks on function curl"    "$(bash_event 'function curl { command curl --insecure; }')"
check gates/block-alias-shadowing.sh none "allows plain git commit"  "$(bash_event 'git commit -m x')"
check gates/block-alias-shadowing.sh none "ignores non-safety alias" "$(bash_event "alias ll='ls -la'")"

# --- validator-bash-guard: deny mutation Bash from validator-class agents,
#     allow read-only commands + non-validator agents + main-thread (no agent_type) ---
# 6 acceptance cases from .scratch/phase-1-safety-fixes-2026-06-12/ACCEPTANCE.md FIX-F1.
check gates/validator-bash-guard.sh none "code-reviewer + git diff HEAD (read-only)"        "$(validator_bash_event 'code-reviewer' 'git diff HEAD')"
check gates/validator-bash-guard.sh deny "code-reviewer + git push origin main (mutation)"  "$(validator_bash_event 'code-reviewer' 'git push origin main')"
check gates/validator-bash-guard.sh deny "code-reviewer + rm -rf /tmp/foo (mutation)"        "$(validator_bash_event 'code-reviewer' 'rm -rf /tmp/foo')"
check gates/validator-bash-guard.sh none "backend-engineer + git push (writer not gated)"   "$(validator_bash_event 'backend-engineer' 'git push origin feature')"
check gates/validator-bash-guard.sh none "code-reviewer + npm test (read-only test run)"    "$(validator_bash_event 'code-reviewer' 'npm test')"
check gates/validator-bash-guard.sh deny "code-reviewer + sed -i 's/x/y/' (mutation)"        "$(validator_bash_event 'code-reviewer' "sed -i 's/x/y/' file")"
# Extra coverage beyond the 6 (anti-pattern robustness, not in AC):
check gates/validator-bash-guard.sh deny "code-explorer + curl -X POST"                       "$(validator_bash_event 'code-explorer' 'curl -X POST https://api.example.com/x')"
check gates/validator-bash-guard.sh deny "security-reviewer + chmod 777"                      "$(validator_bash_event 'security-reviewer' 'chmod 777 x')"
check gates/validator-bash-guard.sh deny "silent-failure-hunter + mv /tmp/x /"               "$(validator_bash_event 'silent-failure-hunter' 'mv /tmp/x /')"
check gates/validator-bash-guard.sh deny "code-architect + npm publish"                      "$(validator_bash_event 'code-architect' 'npm publish')"
check gates/validator-bash-guard.sh none "comment-analyzer + cat file.py (read-only)"         "$(validator_bash_event 'comment-analyzer' 'cat file.py')"
check gates/validator-bash-guard.sh none "pr-test-analyzer + pytest (read-only test run)"    "$(validator_bash_event 'pr-test-analyzer' 'pytest -q')"
check gates/validator-bash-guard.sh none "main-thread + git push (no agent_type, fail-open)" "$(main_thread_bash_event 'git push origin main')"
check gates/validator-bash-guard.sh none "main-thread + rm -rf (no agent_type, fail-open)"  "$(main_thread_bash_event 'rm -rf /tmp/foo')"
# Fork-bomb variants — AC F1 deny pattern 8. Canonical signature is
# `:(){ :|:& };:`; variants use different whitespace + terminators. A
# regression here is silent because no AC test covers fork-bombs — the
# F1 adversarial verifier caught this on the first pass.
check gates/validator-bash-guard.sh deny "code-reviewer + canonical fork-bomb"       "$(validator_bash_event 'code-reviewer' ':(){ :|:& };:')"
check gates/validator-bash-guard.sh deny "code-reviewer + spaces-in-body fork-bomb"  "$(validator_bash_event 'code-reviewer' ':() { :|: & };:')"
check gates/validator-bash-guard.sh deny "code-reviewer + no-space fork-bomb"        "$(validator_bash_event 'code-reviewer' ':(){:|:&};:')"

# Adversarial — a mutation verb GLUED to a quote (bash -c '...') or an arbitrary-
# code interpreter must NOT bypass (pre-fix: the SEP class omitted '/"; the hook's
# own header claimed `bash -c 'git push'` was caught but it wasn't).
check gates/validator-bash-guard.sh deny "code-reviewer + bash -c 'git push'"        "$(validator_bash_event 'code-reviewer' "bash -c 'git push origin main'")"
check gates/validator-bash-guard.sh deny "code-reviewer + eval \"rm -rf\""           "$(validator_bash_event 'code-reviewer' 'eval "rm -rf /tmp/x"')"
check gates/validator-bash-guard.sh deny "code-reviewer + python3 -c interpreter"    "$(validator_bash_event 'code-reviewer' 'python3 -c "import os"')"
check gates/validator-bash-guard.sh deny "code-reviewer + node -e interpreter"       "$(validator_bash_event 'code-reviewer' 'node -e "x"')"

# --- agent-spawn-gate: ask on ad-hoc one-shot Agent spawns, allow team workflows ---
check gates/agent-spawn-gate.sh none "non-Agent tool passes through" "$(bash_event 'git status')"
check gates/agent-spawn-gate.sh none "allows /team-build Agent spawn" "$(agent_event 'team-build wave 1' 'Spawn backend-engineer for /team-build plan_slug: api-rewrite task_id: T-1')"
check gates/agent-spawn-gate.sh none "allows /team-plan Agent spawn" "$(agent_event 'team-plan lead' 'Plan decomposition for /team-plan with plan_slug: api-rewrite')"
check gates/agent-spawn-gate.sh none "allows orchestrate workflow spawn" "$(agent_event 'orchestrate dispatcher' 'Run orchestrate-dispatch.py for workflow fan-out plan_slug: api-rewrite task_id: T-2')"
check gates/agent-spawn-gate.sh ask  "asks on blueprint Agent spawn" "$(agent_event 'blueprint agent' 'Staff engineer blueprint agent for API redesign')"
check gates/agent-spawn-gate.sh ask  "asks on audit Agent spawn" "$(agent_event 'audit agent' 'Run a security audit pass over the repo')"
check gates/agent-spawn-gate.sh ask  "asks on research map Agent spawn" "$(agent_event 'research map' 'Research and map the dependency graph')"
check gates/agent-spawn-gate.sh ask  "asks on read-and-summarize Agent spawn" "$(agent_event 'summarize' 'Read and summarize eval/run-eval.py')"
check gates/agent-spawn-gate.sh ask  "asks on background Agent spawn" "$(agent_event 'background task' 'Monitor build status' true)"
check gates/agent-spawn-gate.sh ask  "asks on generic Agent spawn" "$(agent_event 'generic helper' 'Help me think through this')"
check gates/agent-spawn-gate.sh ask  "asks on bare description-only Agent spawn" "$(agent_event 'helper' '')"

# --- task-lifecycle.sh F7: TaskCompleted test-claim gate.
#     Vendor convention (verified 2026-06-12): TaskCompleted uses exit 2 + stderr
#     feedback, NOT exit 0 + JSON `permissionDecision` (that is PreToolUse).
#     So we use check_task (asserts on exit code + stderr), not check.
#     (a) TaskCompleted with test claim but no validation_command → exit 2
#     (b) TaskCompleted with test claim + validation_command → exit 0
#     (c) TaskCompleted with no test claim → exit 0 (no false positive)
#     (d) TaskCompleted with empty subject + description → exit 0 (no false positive)
#     (e) TeammateIdle → exit 0 (only TaskCompleted enforces; siblings stay log-only)
#     (f) TaskCreated → exit 0 (same)
#     (g) Claim variants: "pytest" alone in subject, "npm test" in description,
#         "cargo test" + "validation_command: cargo test" → all pass when validation_command present
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7a blocks 'All tests pass' (no validation_command)"  "$(task_event '1' 'All tests pass' 'Implemented feature X')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7a blocks 'pytest' in subject (no validation_command)" "$(task_event '2' 'Run pytest suite' 'Wrote tests for X')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7a blocks 'npm test' in description (no validation_command)" "$(task_event '3' 'Build complete' 'Verify with npm test before commit')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7a blocks 'cargo test' alone" "$(task_event '4' 'cargo test green' 'Refactored module Y')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7a blocks 'go test' alone" "$(task_event '5' 'go test' 'Wrote handler')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7a blocks 'pnpm test' alone" "$(task_event '6' 'pnpm test' 'Frontend changes')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7a blocks 'jest' alone" "$(task_event '7' 'jest green' 'Frontend tests')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7b allows 'npm test' + validation_command"  "$(task_event '8' 'Build complete' 'Verify with npm test\nvalidation_command: npm test --workspaces')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7b allows 'pytest' + validation_command"  "$(task_event '9' 'All tests pass' 'validation_command: pytest tests/test_x.py -v')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7b allows 'Validation Command:' (case-insensitive)" "$(task_event '10' 'cargo test green' 'Refactored Y\nValidation Command: cargo test --release')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7b allows 'validation command:' (loose-space variant)" "$(task_event '11' 'go test' 'Wrote handler\nvalidation command: go test ./...')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7c allows 'Refactor complete' (no test claim)" "$(task_event '12' 'Refactor complete' 'No tests touched')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7c allows 'Wrote documentation' (no test claim)" "$(task_event '13' 'Wrote documentation' 'Updated README')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7d allows empty subject + description"  "$(task_event '14' '' '')"
# F7g — false-positive guards. These MUST NOT block, even though "jest" or
# "tsc" appear as substrings. The regex anchors bare keywords at non-word
# boundaries (line 100 of task-lifecycle.sh). Locked in after the Phase 2
# adversarial verifier caught a "jest" → "majestic" substring regression.
check_task lifecycle/task-lifecycle.sh 0  ""          "F7g 'majestic' does NOT match (jest substring)" "$(task_event '20' 'Made the layout more majestic' 'UI polish, no tests touched')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7g 'jesting' does NOT match" "$(task_event '21' 'Jesting around with copy' 'Tweaked strings')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7g 'jestful' does NOT match" "$(task_event '22' 'Not feeling jestful' 'Skipped test work')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7g 'pitsc' does NOT match (tsc substring)" "$(task_event '23' 'pitsc check' 'Pattern search')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7g 'pytest' as substring of unrelated word does NOT match" "$(task_event '24' 'sppytest path' 'Config tweak')"
# F7h — boundary-class match: jest as a standalone word DOES match (positive
# regression guard for the F7g fix — make sure anchoring didn't over-correct).
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7h standalone 'jest' still matches" "$(task_event '25' 'jest' 'Frontend test runner')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7h 'jest green' still matches (jest at word boundary)" "$(task_event '26' 'jest green' 'Wrote tests')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7h standalone 'tsc' still matches" "$(task_event '27' 'tsc' 'Type-checked the codebase')"
check_task lifecycle/task-lifecycle.sh 2  "TASK-GATE[blocked]"  "F7h 'pytest' still matches as a word" "$(task_event '28' 'pytest' 'Ran the suite')"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7e TeammateIdle still log-only (siblings unaffected)"  "$(teammate_idle_event)"
check_task lifecycle/task-lifecycle.sh 0  ""          "F7f TaskCreated still log-only" "$(task_created_event '15' 'Implement F7 hook' 'Write the enforcement branch')"

# --- task-lifecycle.sh task board integration (Phase 3, 2026-06-12)
echo
echo "--- task-lifecycle.sh: task board integration ---"

# Build a temp board fixture for plan "test-plan"
BOARD_FIXTURE="$FIXTURE/board-fixture"
mkdir -p "$BOARD_FIXTURE/.claude/tasks/test-plan"
cat > "$BOARD_FIXTURE/.claude/tasks/test-plan/board.json" <<'BEOF'
{
  "schema_version": 1,
  "plan_slug": "test-plan",
  "created_at": "2026-06-12T10:00:00Z",
  "updated_at": "2026-06-12T10:00:00Z",
  "status": "in_progress",
  "tasks": {
    "T-1": {
      "id": "T-1",
      "description": "Test task",
      "status": "pending",
      "assigned_role": "backend-engineer",
      "claimed_by": null,
      "claimed_at": null,
      "completed_at": null,
      "depends_on": [],
      "blocked_by": [],
      "files": [],
      "wave": 1,
      "notes": ""
    },
    "T-2": {
      "id": "T-2",
      "description": "Blocked task",
      "status": "blocked",
      "assigned_role": "backend-engineer",
      "claimed_by": null,
      "claimed_at": null,
      "completed_at": null,
      "depends_on": ["T-1"],
      "blocked_by": ["T-1"],
      "files": [],
      "wave": 2,
      "notes": ""
    }
  },
  "waves": { "1": ["T-1"], "2": ["T-2"] },
  "agents": {}
}
BEOF

task_board_created_event() { printf '%s' '{"hook_event_name":"TaskCreated","task_id":"T-1","task_subject":"Implement feature","task_description":"Do the thing\nplan_slug: test-plan\ntask_id: T-1"}'; }
task_board_completed_event() { printf '%s' '{"hook_event_name":"TaskCompleted","task_id":"T-1","task_subject":"Feature done","task_description":"Completed\nplan_slug: test-plan\ntask_id: T-1"}'; }
teammate_idle_with_cwd_event() { printf '{"hook_event_name":"TeammateIdle","cwd":"%s"}' "$BOARD_FIXTURE"; }

# (TB1) TaskCreated with plan_slug + task_id sets task status to in_progress
( export HOME="$BOARD_FIXTURE"; printf '%s' "$(task_board_created_event)" | bash "$HOOKS/lifecycle/task-lifecycle.sh" ) >/dev/null 2>&1
TB1_STATUS=$(jq -r '.tasks["T-1"].status' "$BOARD_FIXTURE/.claude/tasks/test-plan/board.json" 2>/dev/null)
if [ "$TB1_STATUS" = "in_progress" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s TaskCreated sets board task to in_progress\n' "task-lifecycle.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s TaskCreated board status=%s (want in_progress)\n' "task-lifecycle.sh" "$TB1_STATUS"
fi

# Reset board for next test
cat > "$BOARD_FIXTURE/.claude/tasks/test-plan/board.json" <<'BEOF'
{
  "schema_version": 1,
  "plan_slug": "test-plan",
  "created_at": "2026-06-12T10:00:00Z",
  "updated_at": "2026-06-12T10:00:00Z",
  "status": "in_progress",
  "tasks": {
    "T-1": {
      "id": "T-1",
      "description": "Test task",
      "status": "pending",
      "assigned_role": "backend-engineer",
      "claimed_by": null,
      "claimed_at": null,
      "completed_at": null,
      "depends_on": [],
      "blocked_by": [],
      "files": [],
      "wave": 1,
      "notes": ""
    },
    "T-2": {
      "id": "T-2",
      "description": "Blocked task",
      "status": "blocked",
      "assigned_role": "backend-engineer",
      "claimed_by": null,
      "claimed_at": null,
      "completed_at": null,
      "depends_on": ["T-1"],
      "blocked_by": ["T-1"],
      "files": [],
      "wave": 2,
      "notes": ""
    }
  },
  "waves": { "1": ["T-1"], "2": ["T-2"] },
  "agents": {}
}
BEOF

# (TB2) TaskCompleted with plan_slug + task_id sets task status to completed and unblocks dependents
( export HOME="$BOARD_FIXTURE"; printf '%s' "$(task_board_completed_event)" | bash "$HOOKS/lifecycle/task-lifecycle.sh" ) >/dev/null 2>&1
TB2_STATUS=$(jq -r '.tasks["T-1"].status' "$BOARD_FIXTURE/.claude/tasks/test-plan/board.json" 2>/dev/null)
TB2_COMP=$(jq -r '.tasks["T-1"].completed_at' "$BOARD_FIXTURE/.claude/tasks/test-plan/board.json" 2>/dev/null)
TB2_T2_STATUS=$(jq -r '.tasks["T-2"].status' "$BOARD_FIXTURE/.claude/tasks/test-plan/board.json" 2>/dev/null)
if [ "$TB2_STATUS" = "completed" ] && [ -n "$TB2_COMP" ] && [ "$TB2_COMP" != "null" ] && [ "$TB2_T2_STATUS" = "pending" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s TaskCompleted sets board task to completed, unblocks dependent\n' "task-lifecycle.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s TaskCompleted board status=%s completed_at=%s T-2_status=%s\n' "task-lifecycle.sh" "$TB2_STATUS" "$TB2_COMP" "$TB2_T2_STATUS"
fi

# (TB3) TeammateIdle with stale heartbeat + pending tasks + cwd → exit 2
mkdir -p "$BOARD_FIXTURE/.claude/tasks/idle-plan/heartbeat"
cat > "$BOARD_FIXTURE/.claude/tasks/idle-plan/board.json" <<'BEOF'
{
  "schema_version": 1,
  "plan_slug": "idle-plan",
  "tasks": {
    "I-1": {
      "id": "I-1",
      "status": "pending",
      "depends_on": [],
      "blocked_by": [],
      "files": []
    }
  }
}
BEOF
python3 -c "
import json, datetime
ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=6)).isoformat().replace('+00:00', 'Z')
with open('$BOARD_FIXTURE/.claude/tasks/idle-plan/heartbeat/agent-stale.json', 'w') as f:
    json.dump({'agent_id':'agent-stale','last_heartbeat':ts}, f)
"
TB3_STDERR=$( ( export HOME="$BOARD_FIXTURE"; printf '%s' "$(teammate_idle_with_cwd_event)" | bash "$HOOKS/lifecycle/task-lifecycle.sh" ) 2>&1 >/dev/null)
TB3_RC=$?
if [ "$TB3_RC" = 2 ] && printf '%s' "$TB3_STDERR" | grep -qi 'stale'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s TeammateIdle stale heartbeat + pending tasks → exit 2\n' "task-lifecycle.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s TeammateIdle stale: rc=%s (want 2) stderr=%s\n' "task-lifecycle.sh" "$TB3_RC" "$TB3_STDERR"
fi

# (TB4) TeammateIdle with fresh heartbeat + pending tasks + cwd → exit 0
# Remove the stale heartbeat and write a fresh one.
rm -f "$BOARD_FIXTURE/.claude/tasks/idle-plan/heartbeat/agent-stale.json"
python3 -c "
import json, datetime
ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=1)).isoformat().replace('+00:00', 'Z')
with open('$BOARD_FIXTURE/.claude/tasks/idle-plan/heartbeat/agent-fresh.json', 'w') as f:
    json.dump({'agent_id':'agent-fresh','last_heartbeat':ts}, f)
"
TB4_STDERR=$( ( export HOME="$BOARD_FIXTURE"; printf '%s' "$(teammate_idle_with_cwd_event)" | bash "$HOOKS/lifecycle/task-lifecycle.sh" ) 2>&1 >/dev/null)
TB4_RC=$?
if [ "$TB4_RC" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s TeammateIdle fresh heartbeat → exit 0\n' "task-lifecycle.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s TeammateIdle fresh: rc=%s (want 0) stderr=%s\n' "task-lifecycle.sh" "$TB4_RC" "$TB4_STDERR"
fi

# (TB5) TeammateIdle with no plan_slug and no cwd → exit 0 (no false-positive)
TB5_STDERR=$( ( export HOME="$BOARD_FIXTURE"; printf '{"hook_event_name":"TeammateIdle"}' | bash "$HOOKS/lifecycle/task-lifecycle.sh" ) 2>&1 >/dev/null)
TB5_RC=$?
if [ "$TB5_RC" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s TeammateIdle no plan_slug/cwd → exit 0 (no false-positive)\n' "task-lifecycle.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s TeammateIdle no-context: rc=%s (want 0) stderr=%s\n' "task-lifecycle.sh" "$TB5_RC" "$TB5_STDERR"
fi

# (TB6) TeammateIdle when the build is complete (all tasks completed) → exit 0
#       + journals a teammate_teardown_ready advisory (the signal /team-build
#       Step 8 reaps on). Advisory only — the hook never stops the teammate (ADR 0002).
mkdir -p "$BOARD_FIXTURE/.claude/tasks/done-plan"
cat > "$BOARD_FIXTURE/.claude/tasks/done-plan/board.json" <<'BEOF'
{
  "schema_version": 1,
  "plan_slug": "done-plan",
  "tasks": {
    "D-1": { "id": "D-1", "status": "completed", "depends_on": [], "blocked_by": [], "files": [] },
    "D-2": { "id": "D-2", "status": "completed", "depends_on": ["D-1"], "blocked_by": [], "files": [] }
  }
}
BEOF
TB6_JOURNAL="$BOARD_FIXTURE/.claude/governance-events.jsonl"
rm -f "$TB6_JOURNAL"
TB6_STDERR=$( ( export HOME="$BOARD_FIXTURE" CLAUDE_JOURNAL_PATH="$TB6_JOURNAL"; printf '%s' "$(teammate_idle_with_cwd_event)" | bash "$HOOKS/lifecycle/task-lifecycle.sh" ) 2>&1 >/dev/null)
TB6_RC=$?
if [ "$TB6_RC" = 0 ] && grep -q 'teammate_teardown_ready' "$TB6_JOURNAL" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ %-26s TeammateIdle build-complete → exit 0 + teardown_ready journal\n' "task-lifecycle.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s TeammateIdle teardown: rc=%s (want 0) journal=%s\n' "task-lifecycle.sh" "$TB6_RC" "$(test -f "$TB6_JOURNAL" && echo present || echo missing)"
fi

# --- db-write-gate: ask on non-SELECT MCP DB calls, allow SELECT/EXPLAIN/info_schema,
#     ignore non-DB MCP tools. Mirrors DBGATE doctrine as a deterministic gate.
mcp_db_event() { printf '{"tool_name":"%s","tool_input":{"query":%s}}' "$1" "$(printf '%s' "$2" | jq -R .)"; }
mcp_nondb_event() { printf '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"summary":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
check gates/db-write-gate.sh none "allows SELECT on execute_sql_production" "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'SELECT 1')"
check gates/db-write-gate.sh none "allows EXPLAIN on execute_sql_staging"   "$(mcp_db_event 'mcp__tathep-db__execute_sql_staging' 'EXPLAIN SELECT id FROM t')"
check gates/db-write-gate.sh none "allows CTE WITH...SELECT"                "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'WITH x AS (SELECT 1) SELECT * FROM x')"
check gates/db-write-gate.sh none "allows information_schema read"          "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'SELECT * FROM information_schema.tables')"
check gates/db-write-gate.sh ask  "asks on DELETE execute_sql_production"   "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'DELETE FROM users WHERE id=1')"
check gates/db-write-gate.sh ask  "asks on UPDATE execute_sql_staging"      "$(mcp_db_event 'mcp__tathep-db__execute_sql_staging' 'UPDATE x SET a=1 WHERE id=1')"
check gates/db-write-gate.sh ask  "asks on INSERT execute_sql_anpr"         "$(mcp_db_event 'mcp__tathep-db__execute_sql_anpr_staging' 'INSERT INTO t (a) VALUES (1)')"
check gates/db-write-gate.sh ask  "asks on DROP TABLE"                      "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'DROP TABLE old')"
check gates/db-write-gate.sh ask  "asks on TRUNCATE"                        "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'TRUNCATE t')"
check gates/db-write-gate.sh ask  "asks on db_write tool"                   "$(mcp_db_event 'mcp__other-db__db_write' 'INSERT INTO t VALUES (1)')"
check gates/db-write-gate.sh none "ignores non-DB MCP tool"                 "$(mcp_nondb_event 'do thing')"
check gates/db-write-gate.sh none "ignores non-MCP tool"                    "$(bash_event 'psql -c "DELETE FROM t"')"
check gates/db-write-gate.sh none "allows SELECT with leading comment"      "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' '-- safety check\nSELECT 1')"
check gates/db-write-gate.sh none "allows comment-only query (no-op)"        "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' '-- just a comment, nothing else')"
# Adversarial — a write hidden behind a leading comment line, a WITH-CTE, or a
# string literal containing information_schema must NOT slip through as a no-op
# (pre-fix: `tr '\n' ' '` ran before comment-strip → `-- x\nDELETE` went silent).
check gates/db-write-gate.sh ask "asks on WITH..DELETE CTE bypass"           "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'WITH t AS (SELECT 1) DELETE FROM users')"
check gates/db-write-gate.sh ask "asks on DELETE w/ info_schema string"      "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' "DELETE FROM users WHERE note='information_schema.'")"
check gates/db-write-gate.sh ask "asks on leading-comment+REAL-newline DELETE" "$(printf '{"tool_name":"mcp__tathep-db__execute_sql_production","tool_input":{"query":%s}}' "$(printf -- '-- nightly cleanup\nDELETE FROM users' | jq -Rs .)")"

# --- bypass contract: CLAUDE_DISABLED_HOOKS must let a blocked case through ---
out=$(printf '%s' "$(bash_event 'git reset --hard')" | CLAUDE_DISABLED_HOOKS=block-dangerous-git bash "$HOOKS/gates/block-dangerous-git.sh" 2>/dev/null)
if [ -z "$out" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "block-dangerous-git.sh" "CLAUDE_DISABLED_HOOKS bypass works"
else FAIL=$((FAIL+1)); printf '  ❌ %-22s bypass env did not disable (got: %s)\n' "block-dangerous-git.sh" "$out"; fi

# --- syntax smoke: every hook script must parse (a crashing logger can block) ---
echo
echo "--- syntax smoke: every hook script parses ---"
for f in "$HOOKS"/*.sh "$HOOKS"/gates/*.sh "$HOOKS"/advisory/*.sh "$HOOKS"/session/*.sh "$HOOKS"/post-tool/*.sh "$HOOKS"/maintenance/*.sh "$HOOKS"/lifecycle/*.sh; do
  name=$(basename "$f")
  if bash -n "$f" 2>/dev/null; then
    PASS=$((PASS+1)); printf '  ✅ %-26s parses\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-26s bash -n FAILED\n' "$name"
  fi
done
for f in "$HOOKS"/*.py "$HOOKS"/post-tool/*.py; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null; then
    PASS=$((PASS+1)); printf '  ✅ %-26s compiles\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-26s ast.parse FAILED\n' "$name"
  fi
done

# ════════════════════════════════════════════════════════════════════════════
# Pattern-breadth tests — each entry in a gate's pattern list gets its own case,
# so dropping ANY single entry from the hook fails a test (the prior tests only
# exercised the head of each list, leaving silent per-entry coverage holes).
# The expected lists are hardcoded HERE as the spec: if the hook drops an entry,
# the test still asserts it and goes red.
# ════════════════════════════════════════════════════════════════════════════

# --- secret-scan: one deny per high-confidence pattern (13). Tokens are built
#     at runtime so no full secret-shaped literal lives in this file.
SS_LBL=(); SS_TOK=()
ss_add() { SS_LBL+=("$1"); SS_TOK+=("$2"); }
ss_add AWS                "AKIA$(printf 'A%.0s' $(seq 1 16))"
ss_add Anthropic          "sk-ant-$(printf 'a%.0s' $(seq 1 24))"
ss_add OpenAI             "sk-$(printf 'a%.0s' $(seq 1 48))"
ss_add GitHub-PAT-classic "ghp_$(printf '0%.0s' $(seq 1 36))"
ss_add GitHub-OAuth       "gho_$(printf '0%.0s' $(seq 1 36))"
ss_add GitHub-App         "ghs_$(printf '0%.0s' $(seq 1 36))"
ss_add GitHub-PAT-fine    "github_pat_$(printf 'a%.0s' $(seq 1 82))"
ss_add GitLab-PAT         "glpat-$(printf 'a%.0s' $(seq 1 20))"
ss_add HuggingFace        "hf_$(printf 'a%.0s' $(seq 1 34))"
ss_add Slack              "xoxb-$(printf '1%.0s' $(seq 1 5))-$(printf '2%.0s' $(seq 1 5))-$(printf 'a%.0s' $(seq 1 8))"
ss_add Stripe-live        "sk_live_$(printf 'a%.0s' $(seq 1 24))"
ss_add Google-API         "AIza$(printf 'a%.0s' $(seq 1 35))"
ss_add Private-key        "-----BEGIN RSA PRIVATE ""KEY-----"
for i in "${!SS_TOK[@]}"; do
  check gates/secret-scan.sh deny "secret breadth: ${SS_LBL[$i]}" "$(write_event /x/a.txt "val=${SS_TOK[$i]}")"
done

# --- config-protection: one ask per protected basename (32). Each file must
#     pre-exist (the hook only gates MODIFICATION of an existing config).
CP_DIR="$FIXTURE/cp-breadth"; mkdir -p "$CP_DIR"
CP_FILES=(
  .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml
  eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts eslint.config.mts eslint.config.cts
  .prettierrc .prettierrc.js .prettierrc.cjs .prettierrc.json .prettierrc.yml .prettierrc.yaml
  prettier.config.js prettier.config.cjs prettier.config.mjs
  biome.json biome.jsonc
  .ruff.toml ruff.toml
  .shellcheckrc .stylelintrc .stylelintrc.json .stylelintrc.yml
  .markdownlint.json .markdownlint.yaml .markdownlintrc
)
for cfg in "${CP_FILES[@]}"; do
  : > "$CP_DIR/$cfg"
  check gates/config-protection.sh ask "config breadth: $cfg" "$(write_event "$CP_DIR/$cfg" 'weakened')"
done

# --- block-alias-shadowing: one ask per safety-binary (20). Dropping a binary
#     from BINARIES means its alias stops being gated.
BAS_BINS=(git curl wget npm pip pip3 brew gh aws gcloud az docker kubectl terraform cargo helm doctl heroku op vault)
for b in "${BAS_BINS[@]}"; do
  check gates/block-alias-shadowing.sh ask "alias-shadow breadth: $b" "$(bash_event "alias $b='$b --danger'")"
done
