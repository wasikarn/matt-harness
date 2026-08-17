#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in test payload strings is intentional
# Gate unit tests: simulates PreToolUse JSON payloads and asserts allow/deny/ask.
# Each test_deny call expects exit 2; test_allow expects exit 0 + empty stdout;
# test_ask expects exit 0 + a permissionDecision: ask JSON on stdout.
# Run standalone: bash tests/hooks/test-gates.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IRRECOVERABLE="$ROOT/hooks/gates/irrecoverable.sh"
VERIFIER_PROTECT="$ROOT/hooks/gates/verifier-protect.sh"
TASK_COMPLETE="$ROOT/hooks/gates/task-complete-separation.sh"
DB_WRITE_GATE="$ROOT/hooks/gates/db-write-gate.sh"

pass=0
fail=0

# Build a minimal Bash tool payload. Uses json.dumps (not printf %s) so
# commands containing quotes/backslashes (e.g. mysql -e "DROP TABLE...",
# find -exec ... \;) don't produce malformed JSON that silently degrades
# to an empty command downstream.
bash_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"; }

# Build a Write tool payload. Uses json.dumps (see bash_payload above) so
# content containing quotes/backslashes doesn't produce malformed JSON.
write_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' "$1" "$2"
}

# Build an Edit tool payload. Same json.dumps rationale as write_payload.
edit_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": sys.argv[1], "new_string": sys.argv[2]}}))' "$1" "$2"
}

# Build a TaskUpdate payload. $1=status (or empty to omit the field),
# $2=agent_type (or empty = main session, field omitted). Uses json.dumps so
# the agent_type string is safely encoded.
taskupdate_payload() {
  python3 -c '
import json, sys
status, agent = sys.argv[1], sys.argv[2]
ti = {"taskId": "T1"}
if status:
    ti["status"] = status
d = {"tool_name": "TaskUpdate", "tool_input": ti}
if agent:
    d["agent_type"] = agent
print(json.dumps(d))
' "$1" "$2"
}

# Build an MCP tool-call payload with a SQL statement in .query (a common
# execute_sql MCP convention; db-write-gate.sh also checks .sql/.statement/.text).
mcp_sql_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"query": sys.argv[2]}}))' "$1" "$2"
}

# Expect the gate to BLOCK (exit 2).
test_deny() {
  local gate="$1" desc="$2" payload="$3"
  local rc
  rc=$(echo "$payload" | bash "$gate" 2>/dev/null; echo $?)
  if [[ "$rc" == "2" ]]; then
    echo "  ✅ DENY: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ DENY EXPECTED but got exit $rc: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the gate to ALLOW (exit 0 + empty stdout — no permissionDecision JSON).
test_allow() {
  local gate="$1" desc="$2" payload="$3" envvar="${4:-}"
  local rc
  if [ -n "$envvar" ]; then
    rc=$(echo "$payload" | env "$envvar" bash "$gate" 2>/dev/null; echo $?)
  else
    rc=$(echo "$payload" | bash "$gate" 2>/dev/null; echo $?)
  fi
  if [[ "$rc" == "0" ]]; then
    echo "  ✅ ALLOW${envvar:+ (env)}: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ ALLOW EXPECTED but got exit $rc: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the gate to ASK (exit 0 + permissionDecision: ask JSON on stdout).
test_ask() {
  local gate="$1" desc="$2" payload="$3"
  local out rc
  out=$(echo "$payload" | bash "$gate" 2>/dev/null); rc=$?
  if [[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"'; then
    echo "  ✅ ASK: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ ASK EXPECTED but got exit $rc out='$out': $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== irrecoverable gate ==="
test_deny  "$IRRECOVERABLE" "rm -rf"                    "$(bash_payload 'rm -rf /tmp/test')"
test_deny  "$IRRECOVERABLE" "rm -fr variant"            "$(bash_payload 'rm -fr /tmp/test')"
test_deny  "$IRRECOVERABLE" "git push --force"          "$(bash_payload 'git push --force origin develop')"
test_deny  "$IRRECOVERABLE" "git push -f"               "$(bash_payload 'git push -f origin develop')"
test_deny  "$IRRECOVERABLE" "--no-verify"               "$(bash_payload 'git commit --no-verify -m msg')"
test_deny  "$IRRECOVERABLE" "git reset --hard"          "$(bash_payload 'git reset --hard HEAD~1')"
test_deny  "$IRRECOVERABLE" "git clean -f"              "$(bash_payload 'git clean -f')"
test_deny  "$IRRECOVERABLE" "git clean -fd"             "$(bash_payload 'git clean -fd')"
test_allow "$IRRECOVERABLE" "safe rm (no -rf)"          "$(bash_payload 'rm /tmp/file.txt')"
test_allow "$IRRECOVERABLE" "git push no force"         "$(bash_payload 'git push origin develop')"
test_allow "$IRRECOVERABLE" "git reset soft"            "$(bash_payload 'git reset --soft HEAD~1')"
test_allow "$IRRECOVERABLE" "normal bash command"       "$(bash_payload 'ls -la')"

# 2026-07-01 constitution audit: raw-substring matching produced both false
# positives (blocked safe commands merely mentioning a pattern in quoted
# text) and bypasses (quoted/tokenization tricks slipped past the regex).
# Fixed via shlex-based tokenization; these lock the fix in place.
test_allow "$IRRECOVERABLE" "grep for rm -rf text (was a false positive)" \
  "$(bash_payload 'grep -rn "rm -rf" scripts/')"
test_allow "$IRRECOVERABLE" "commit msg mentioning rm -rf (was a false positive)" \
  "$(bash_payload 'git commit -m "docs: warn against rm -rf usage"')"
test_deny  "$IRRECOVERABLE" "quoted rm word (was a bypass)" \
  "$(bash_payload "'rm' -rf /tmp/x")"
test_deny  "$IRRECOVERABLE" "find -exec rm (was a bypass)" \
  "$(bash_payload 'find /tmp/x -exec rm {} \;')"
test_deny  "$IRRECOVERABLE" "git checkout -- discards changes (was a bypass)" \
  "$(bash_payload 'git checkout -- .')"
test_deny  "$IRRECOVERABLE" "git switch --force (was a bypass)" \
  "$(bash_payload 'git switch --force main')"
test_deny  "$IRRECOVERABLE" "git commit --amend (was a bypass)" \
  "$(bash_payload 'git commit --amend')"
test_deny  "$IRRECOVERABLE" "dd to raw device (was a bypass)" \
  "$(bash_payload 'dd if=/dev/zero of=/dev/disk2')"
test_deny  "$IRRECOVERABLE" "SQL DROP TABLE (was a bypass)" \
  "$(bash_payload 'mysql -e "DROP TABLE users"')"
test_deny  "$IRRECOVERABLE" "git add -A (was prose-only)" \
  "$(bash_payload 'git add -A')"
test_deny  "$IRRECOVERABLE" "git add . (was prose-only)" \
  "$(bash_payload 'git add .')"
test_allow "$IRRECOVERABLE" "git add named file (must not over-block)" \
  "$(bash_payload 'git add foo.txt')"
test_allow "$IRRECOVERABLE" "git checkout branch (must not over-block)" \
  "$(bash_payload 'git checkout main')"
test_allow "$IRRECOVERABLE" "git checkout -b new branch (must not over-block)" \
  "$(bash_payload 'git checkout -b new-branch')"
# 2026-08-17 bug sweep: the force check only matched the exact token "-f"/
# "--force", missing a bundled short-flag cluster like "-qf" (quiet+force).
# Live-verified bypass: this discarded uncommitted work with no gate block.
test_deny "$IRRECOVERABLE" "git checkout -qf bundled force flag (was a bypass)" \
  "$(bash_payload 'git checkout -qf other-branch')"
test_deny "$IRRECOVERABLE" "git switch -fq bundled force flag (was a bypass)" \
  "$(bash_payload 'git switch -fq other-branch')"
# The fix scans bundled clusters for "f" but must stop at a value-taking flag
# letter (checkout's -b/-B, switch's -c/-C) so the branch-name argument
# itself isn't misread as more bundled flags.
test_allow "$IRRECOVERABLE" "git checkout -bfoo (branch name starting with f, must not over-block)" \
  "$(bash_payload 'git checkout -bfoo')"
test_allow "$IRRECOVERABLE" "git switch -cfoo (branch name starting with f, must not over-block)" \
  "$(bash_payload 'git switch -cfoo')"
test_allow "$IRRECOVERABLE" "git checkout -Bfoo (uppercase stop-char variant, must not over-block)" \
  "$(bash_payload 'git checkout -Bfoo')"
test_allow "$IRRECOVERABLE" "git switch -Cfoo (uppercase stop-char variant, must not over-block)" \
  "$(bash_payload 'git switch -Cfoo')"
# 2026-08-06: a HEREDOC-authored commit message (this repo's own documented
# convention) that merely mentions "git checkout X Y" in prose was tokenized
# as a real command and falsely denied -- reproduced live during this
# repo's own commit for v0.68.205. The first fix (strip quoted-delimiter
# heredoc bodies before scanning) introduced its own regression, caught by
# the second test below: a heredoc feeding an interpreter (bash <<EOF) is
# executable code, not inert prose, and must stay scannable.
test_allow "$IRRECOVERABLE" "quoted-delimiter heredoc body mentioning checkout no longer false-blocks" \
  "$(bash_payload $'git commit -m "$(cat <<\'EOF\'\nthis mentions git checkout old new extra in prose\nEOF\n)"')"
test_deny "$IRRECOVERABLE" "dangerous cmd inside a heredoc feeding an interpreter still blocked" \
  "$(bash_payload $'bash <<EOF\nrm -rf /tmp/danger\nEOF')"
# 2026-07-03 audit: newline and '&' are command separators in bash but shlex
# ate newline as whitespace and '&' wasn't in OPERATORS — a dangerous command
# after either hid inside the first command's window. Also --force-with-lease
# (the safe variant) was caught by the --force prefix match.
test_deny  "$IRRECOVERABLE" "dangerous cmd after newline" \
  "$(bash_payload $'echo hi\nrm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "dangerous cmd after & (background)" \
  "$(bash_payload 'echo done & rm -rf /tmp/x')"
test_allow "$IRRECOVERABLE" "git push --force-with-lease (safe variant)" \
  "$(bash_payload 'git push --force-with-lease origin develop')"
test_allow "$IRRECOVERABLE" "git push --force-with-lease with refspec (still safe)" \
  "$(bash_payload 'git push --force-with-lease=main:12345 origin develop')"
test_allow "$IRRECOVERABLE" "git push normal (no force)" \
  "$(bash_payload 'git push origin develop')"

# v0.36.0 audit: a leading git GLOBAL flag (-C/-c/--git-dir/--work-tree/
# --config-env, bare or combined -Cpath/--git-dir=path) set sub to the flag
# itself, so the push/worktree/--no-verify gates were bypassable by prefixing
# it. Also --no-verify was checked outside the per-window loop against the
# loop-leak `tokens` (last line only), so a multi-line --no-verify on an
# earlier line slipped past. And git restore (.) / checkout <tree> <file>
# had no destructive-form coverage.
test_deny "$IRRECOVERABLE" "git -C /repo push --force (global-flag bypass)" \
  "$(bash_payload 'git -C /repo push --force origin develop')"
test_deny "$IRRECOVERABLE" "git -Cpath push --force (combined -C)" \
  "$(bash_payload 'git -C/repo push --force origin develop')"
test_deny "$IRRECOVERABLE" "git --no-pager push --force (non-value global)" \
  "$(bash_payload 'git --no-pager push --force origin develop')"
test_deny "$IRRECOVERABLE" "git -C . worktree add -b feature (global-flag bypass)" \
  "$(bash_payload 'git -C . worktree add -b feature /tmp/wt-feature')"
test_deny "$IRRECOVERABLE" "git -c key=val push --force (value global -c)" \
  "$(bash_payload 'git -c core.foo=bar push --force origin develop')"
test_allow "$IRRECOVERABLE" "git -C /repo status (global flag, safe sub)" \
  "$(bash_payload 'git -C /repo status')"
test_allow "$IRRECOVERABLE" "git -C /repo log (no sub after globals→no-op safe)" \
  "$(bash_payload 'git -C /repo')"
test_deny "$IRRECOVERABLE" "--no-verify on earlier line (multiline bypass)" \
  "$(bash_payload $'echo staging\ngit commit --no-verify -m msg')"
test_allow "$IRRECOVERABLE" "echo --no-verify (git-specific, no false positive)" \
  "$(bash_payload 'echo --no-verify is a git flag')"
test_deny "$IRRECOVERABLE" "git restore . (discards worktree)" \
  "$(bash_payload 'git restore .')"
test_deny "$IRRECOVERABLE" "git restore -- file (discards worktree)" \
  "$(bash_payload 'git restore -- file.txt')"
test_deny "$IRRECOVERABLE" "git restore file (pathspec, no branch ambiguity)" \
  "$(bash_payload 'git restore src/index.ts')"
test_deny "$IRRECOVERABLE" "git restore --worktree file (explicit worktree mode)" \
  "$(bash_payload 'git restore --worktree file.txt')"
test_deny "$IRRECOVERABLE" "git restore --staged --worktree file (worktree touched)" \
  "$(bash_payload 'git restore --staged --worktree file.txt')"
test_allow "$IRRECOVERABLE" "git restore --staged file (index-only, recoverable)" \
  "$(bash_payload 'git restore --staged file.txt')"
test_allow "$IRRECOVERABLE" "git restore --staged . (un-stage all, recoverable)" \
  "$(bash_payload 'git restore --staged .')"
test_allow "$IRRECOVERABLE" "git restore --staged (no pathspec, no-op)" \
  "$(bash_payload 'git restore --staged')"
test_deny "$IRRECOVERABLE" "git checkout HEAD~1 file (tree-ish + path)" \
  "$(bash_payload 'git checkout HEAD~1 src/index.ts')"
test_allow "$IRRECOVERABLE" "git checkout main (1 nonflag = branch switch)" \
  "$(bash_payload 'git checkout main')"

echo ""
echo "=== verifier-protect Bash gate (redirect/tee/sed-i writes to verifier surfaces) ==="
VP_BASH="$ROOT/hooks/gates/verifier-protect.sh"
test_ask   "$VP_BASH" "redirect > into hooks/gates/" \
  "$(bash_payload 'echo neutered > hooks/gates/irrecoverable.sh')"
test_ask   "$VP_BASH" "append >> into hooks/hooks.json" \
  "$(bash_payload 'echo x >> hooks/hooks.json')"
test_ask   "$VP_BASH" "sed -i on an audit check" \
  "$(bash_payload 'sed -i s/a/b/ skills/harness-audit/scripts/checks/01-fleet-count.sh')"
test_ask   "$VP_BASH" "tee into a gate file" \
  "$(bash_payload 'echo x | tee hooks/gates/verifier-protect.sh')"
test_ask   "$VP_BASH" "cp over an audit check (dest is verifier path)" \
  "$(bash_payload 'cp foo skills/harness-audit/scripts/checks/05-frontmatter-completeness-skills.sh')"
test_ask   "$VP_BASH" "mv into hooks/gates/ via absolute path" \
  "$(bash_payload "mv x $ROOT/hooks/gates/irrecoverable.sh")"
# v0.36.0 audit: cp/mv/install -t <dir> made nonflag[-1] a SOURCE, so the real
# destination was lost and a verifier-surface write went unasked. dd of= had no
# verifier-protect coverage at all.
test_ask   "$VP_BASH" "cp -t into hooks/gates/ (dest via -t, not source)" \
  "$(bash_payload 'cp -t hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "mv -t into audit checks/ (--target-directory=)" \
  "$(bash_payload 'mv --target-directory=skills/harness-audit/scripts/checks/ evil.sh')"
test_ask   "$VP_BASH" "install -t into hooks/gates/" \
  "$(bash_payload 'install -t hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "dd of= a gate file (was no coverage)" \
  "$(bash_payload 'dd if=/dev/zero of=hooks/gates/irrecoverable.sh bs=1 count=1')"
test_allow "$VP_BASH" "dd of= a normal project file" \
  "$(bash_payload 'dd if=/dev/zero of=src/index.ts bs=1 count=1')"
test_allow "$VP_BASH" "cp -t into a normal source dir" \
  "$(bash_payload 'cp -t src/ foo.sh')"
test_allow "$VP_BASH" "redirect into a normal source file" \
  "$(bash_payload 'echo x > skills/foo/SKILL.md')"
test_allow "$VP_BASH" "cat a gate file (read, not write)" \
  "$(bash_payload 'cat hooks/gates/irrecoverable.sh')"
test_allow "$VP_BASH" "git apply a patch to a non-verifier path" \
  "$(bash_payload 'git apply --check foo.patch')"
test_allow "$VP_BASH" "sed -i on a normal project file" \
  "$(bash_payload 'sed -i s/a/b/ src/index.ts')"
test_allow "$VP_BASH" "ls a gate file (no write)" \
  "$(bash_payload 'ls hooks/gates/irrecoverable.sh')"

# v0.36.0-fix follow-up audit: -t joined to its value (-tDIR) or bundled with
# other short flags (-rtDIR) still bypassed the just-shipped -t fix. rsync,
# tar -x -C, patch, and git apply/am had zero verifier-protect coverage at all.
test_ask   "$VP_BASH" "cp -t joined to its value (-thooks/gates/)" \
  "$(bash_payload 'cp -thooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "cp -t bundled with -r (-rthooks/gates/)" \
  "$(bash_payload 'cp -rthooks/gates/ evil.sh')"
test_allow "$VP_BASH" "cp -t joined to a normal dir" \
  "$(bash_payload 'cp -t/tmp/ x')"

# compliance-audit adversarial pass: -tDIR and -rtDIR (joined) were closed
# above, but -rt DIR (bundled, value in the NEXT token) still fell through to
# nonflag[-1] and was silently allowed.
test_ask   "$VP_BASH" "cp -rt into hooks/gates/ (bundled, space-separated target)" \
  "$(bash_payload 'cp -rt hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "mv -vt into hooks/gates/ (bundled, space-separated target)" \
  "$(bash_payload 'mv -vt hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "install -vt into hooks/gates/ (bundled, space-separated target)" \
  "$(bash_payload 'install -vt hooks/gates/ evil.sh')"
test_allow "$VP_BASH" "cp -rt into a normal source dir (bundled, space-separated)" \
  "$(bash_payload 'cp -rt /tmp/safe/ myfile.txt')"
test_ask   "$VP_BASH" "rsync into hooks/gates/" \
  "$(bash_payload 'rsync evil.sh hooks/gates/x.sh')"
test_allow "$VP_BASH" "rsync into a normal dir" \
  "$(bash_payload 'rsync a.sh b.sh')"
test_ask   "$VP_BASH" "tar -x -C into hooks/gates/" \
  "$(bash_payload 'tar -xf evil.tar -C hooks/gates/')"
test_allow "$VP_BASH" "tar -x -C into a normal dir" \
  "$(bash_payload 'tar -xf evil.tar -C /tmp')"
test_ask   "$VP_BASH" "patch a gate file via stdin redirect" \
  "$(bash_payload 'patch hooks/gates/irrecoverable.sh < evil.patch')"
test_allow "$VP_BASH" "patch a normal project file" \
  "$(bash_payload 'patch README.md < ok.patch')"

VP_DIFF_BAD="$(mktemp -t kbg-vp-test-bad.XXXXXX)"
VP_DIFF_OK="$(mktemp -t kbg-vp-test-ok.XXXXXX)"
cat > "$VP_DIFF_BAD" <<'EOF'
--- a/hooks/gates/irrecoverable.sh
+++ b/hooks/gates/irrecoverable.sh
@@ -1,1 +1,1 @@
-old
+new
EOF
cat > "$VP_DIFF_OK" <<'EOF'
--- a/README.md
+++ b/README.md
@@ -1,1 +1,1 @@
-old
+new
EOF
test_ask   "$VP_BASH" "git apply a diff whose +++ b/ target is a gate file" \
  "$(bash_payload "git apply $VP_DIFF_BAD")"
test_allow "$VP_BASH" "git apply a diff targeting a normal file" \
  "$(bash_payload "git apply $VP_DIFF_OK")"
rm -f "$VP_DIFF_BAD" "$VP_DIFF_OK"

echo ""
echo "=== path-hardcode deny (folded into verifier-protect Write branch) ==="
# ponytail: split to avoid triggering the pre-commit /Users/<name>/ grep on test source
# These run against verifier-protect.sh (the deny folded in 2026-07-03); the
# file_paths are normal (non-verifier) so the ask branch does not fire -- only
# the path-hardcode deny is exercised. $_UD avoids a literal /Users/<name> in
# this test source (which the gate would otherwise block).
_UP="/Users" _UN="testuser" _UD="$_UP/$_UN"
test_deny  "$VERIFIER_PROTECT" "hardcoded /Users/ in .sh" \
  "$(write_payload 'script.sh' "export PATH=$_UD/bin:\$PATH")"
test_deny  "$VERIFIER_PROTECT" "hardcoded /Users/ in .py" \
  "$(write_payload 'setup.py' "BASE = $_UD/data")"
test_deny  "$VERIFIER_PROTECT" "Edit new_string with /Users/ in .sh" \
  "$(edit_payload 'deploy.sh' "cd $_UD/app")"
test_allow "$VERIFIER_PROTECT" "\$HOME reference in .sh" \
  "$(write_payload 'script.sh' 'export PATH=$HOME/bin:$PATH')"
test_allow "$VERIFIER_PROTECT" "~ reference in .sh" \
  "$(write_payload 'script.sh' 'cd ~/projects')"
test_allow "$VERIFIER_PROTECT" "/Users/ in .md file (not gated)" \
  "$(write_payload 'README.md' "see $_UD for example")"
test_allow "$VERIFIER_PROTECT" "/Users/ in .json file (not gated)" \
  "$(write_payload 'config.json' "{\\\"path\\\":\\\"$_UD\\\"}")"
test_allow "$VERIFIER_PROTECT" "normal .sh content" \
  "$(write_payload 'run.sh' 'set -uo pipefail\necho hello')"

echo ""
echo "=== verifier-protect gate (tamper-resistance: human approves each verifier-surface edit) ==="
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/irrecoverable.sh" \
  "$(write_payload 'hooks/gates/irrecoverable.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Edit to hooks/gates/verifier-protect.sh (self)" \
  "$(edit_payload 'hooks/gates/verifier-protect.sh' 'exit 0')"
test_ask   "$VERIFIER_PROTECT" "Write to hooks/hooks.json (the wiring)" \
  "$(write_payload 'hooks/hooks.json' 'neutered-wiring')"
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/ via absolute path" \
  "$(write_payload "$ROOT/hooks/gates/task-complete-separation.sh" 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Write to audit.sh (non-model verifier runner)" \
  "$(write_payload 'skills/harness-audit/scripts/audit.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Edit to a check file (grading logic)" \
  "$(edit_payload 'skills/harness-audit/scripts/checks/05-frontmatter-completeness-skills.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Write to a check via absolute path" \
  "$(write_payload "$ROOT/skills/harness-audit/scripts/checks/01-fleet-count.sh" 'echo neutered')"
test_allow "$VERIFIER_PROTECT" "Write to --health reporter (NOT a grader, out of scope)" \
  "$(write_payload 'skills/harness-audit/scripts/harness-health.py' 'print(1)')"
test_allow "$VERIFIER_PROTECT" "Write to health.sh (NOT a grader, out of scope)" \
  "$(write_payload 'skills/harness-audit/scripts/health.sh' 'echo ok')"
test_allow "$VERIFIER_PROTECT" "Write to a skill (normal work)" \
  "$(write_payload 'skills/foo/SKILL.md' '# ok')"
test_allow "$VERIFIER_PROTECT" "Write to a command (normal work)" \
  "$(write_payload 'commands/pr.md' '# ok')"

echo ""
echo "=== task-complete-separation gate (maker≠checker: subagent cannot self-complete) ==="
# maker self-completion is the one thing the harness forbids — a subagent
# (agent_type present) calling TaskUpdate(completed) is blocked at exit 2.
# The main session (no agent_type) and any non-completion status pass.
test_deny  "$TASK_COMPLETE" "subagent marks completed (maker self-grade)" \
  "$(taskupdate_payload completed kbg:build-error-resolver)"
test_allow "$TASK_COMPLETE" "main session marks completed (no agent_type)" \
  "$(taskupdate_payload completed '')"
test_allow "$TASK_COMPLETE" "subagent sets in_progress (not completion)" \
  "$(taskupdate_payload in_progress kbg:build-error-resolver)"
test_allow "$TASK_COMPLETE" "subagent sets pending (not completion)" \
  "$(taskupdate_payload pending kbg:build-error-resolver)"
test_allow "$TASK_COMPLETE" "subagent subject/desc update (no status field)" \
  "$(taskupdate_payload '' kbg:build-error-resolver)"
test_allow "$TASK_COMPLETE" "malformed stdin (fail-safe allow)" \
  '{not valid json'
test_allow "$TASK_COMPLETE" "non-TaskUpdate tool with agent_type (out of scope)" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"ls"},"agent_type":"kbg:build-error-resolver"}))')"

echo ""
echo "=== db-write-gate (ask on non-SELECT execute_sql-shaped MCP calls, any server) ==="
test_ask   "$DB_WRITE_GATE" "DELETE on production" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'DELETE FROM users WHERE id=1')"
test_ask   "$DB_WRITE_GATE" "DROP TABLE on staging" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_staging' 'DROP TABLE sessions')"
test_ask   "$DB_WRITE_GATE" "comment-then-DELETE (comment-strip order)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' $'-- note\nDELETE FROM users')"
test_ask   "$DB_WRITE_GATE" "WITH-CTE whose outer statement writes" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'WITH t AS (SELECT 1) DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "SELECT is read-only" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT * FROM users')"
test_allow "$DB_WRITE_GATE" "WITH-CTE that only reads" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'WITH t AS (SELECT 1) SELECT * FROM t')"
test_allow "$DB_WRITE_GATE" "EXPLAIN is read-only" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN SELECT * FROM users')"
test_allow "$DB_WRITE_GATE" "comment-only statement is a no-op" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '-- just a comment')"
# compliance-audit adversarial pass: a write stacked after a lead SELECT
# classified by leading-verb-only as a read and slipped through.
test_ask   "$DB_WRITE_GATE" "write stacked after a lead SELECT" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1; DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "two stacked SELECTs stay read-only" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1; SELECT 2')"
test_ask   "$DB_WRITE_GATE" "leading block comment before a write verb" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/* comment */ DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "leading block comment before a read stays allowed" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/* comment */ SELECT * FROM users')"
# v0.49.0: quote-aware comment stripping — two silent-allow bypasses that shipped
# in v0.40.0's regex stripper, caught exercising kbg:review-pr. String-literal
# blindness: a /* (or --) inside one string literal paired with a */ in a later
# literal erased a stacked write. MySQL /*! ... */ executable comments: the body
# runs on the server but was deleted as if inert. (SQL uses "..." literals so the
# single-quote-heavy cases stay expressible inside the test file's '...' args.)
test_ask   "$DB_WRITE_GATE" "block-comment lookalike across two string literals hides a stacked write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT "/*", 1; DELETE FROM users WHERE x = "*/"')"
test_allow "$DB_WRITE_GATE" "a /* inside a string literal is not a comment (no over-ask)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT "/*" AS a')"
test_ask   "$DB_WRITE_GATE" "-- lookalike inside string literals hides a stacked write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT "--", 1; DELETE FROM x')"
test_ask   "$DB_WRITE_GATE" "MySQL /*! executable-comment body is a real write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!50000 DELETE */ FROM t')"
# Under the ask-by-default inversion (v0.49.0) a /*! ... */ hint that prepends a
# non-read token (SQL_NO_CACHE) to the statement no longer leads with a read verb,
# so it asks. Over-ask on an exotic read hint is the intended safe direction.
test_ask   "$DB_WRITE_GATE" "MySQL /*! read hint prepends a non-read token -> safe over-ask" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!40101 SQL_NO_CACHE */ SELECT 1')"
# The /*! body is real SQL to MariaDB: its closing */ is found respecting inner
# strings and nested /* */ comments. The first cut of this fix sliced the body
# with a raw find("*/"), which closed early on an inner */ and left the write verb
# non-leading -> silent allow. Caught against a live MariaDB while exercising
# kbg:review-pr on the fix itself; these lock the second-order fix in.
test_ask   "$DB_WRITE_GATE" "/*! body with a nested block comment before the write verb" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!50000 /* x */ DELETE FROM t2 */')"
test_ask   "$DB_WRITE_GATE" "/*! body with a */ hidden inside a string literal" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!00000 SELECT "*/-- x" */ ; DELETE FROM t')"
test_allow "$DB_WRITE_GATE" "/*! body that is read-only stays allowed (no over-ask)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!50000 /* x */ SELECT 1 */')"
test_ask   "$DB_WRITE_GATE" "unterminated block comment keeps the trailing write for classification" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1; /* trap; DELETE FROM t')"
# v0.49.0 ask-by-default inversion: the gate now ALLOWs only proven simple reads
# and ASKs on everything else, so verb-list gaps and lexer desyncs fall to a safe
# false-ask instead of a false-allow. All four caught against a live MariaDB in
# round 3 of the review exercise; the last is the -- needs-whitespace lexer rule.
test_ask   "$DB_WRITE_GATE" "LOAD DATA is a write not on any leading-verb list" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'LOAD DATA LOCAL INFILE "/x" INTO TABLE t')"
test_ask   "$DB_WRITE_GATE" "PREPARE/EXECUTE hides the write verb in a string literal" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'PREPARE s FROM "DELETE FROM t"; EXECUTE s')"
test_ask   "$DB_WRITE_GATE" "SELECT ... INTO OUTFILE writes to disk despite the SELECT lead" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT * FROM t INTO OUTFILE "/tmp/x"')"
test_ask   "$DB_WRITE_GATE" "-- without trailing whitespace is arithmetic, not a comment (1--1)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1--1;DELETE FROM t')"
test_ask   "$DB_WRITE_GATE" "SET GLOBAL is a server-config write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SET GLOBAL x = 1')"
test_allow "$DB_WRITE_GATE" "SHOW is a proven read" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SHOW TABLES')"
test_allow "$DB_WRITE_GATE" "plain EXPLAIN never executes what it analyzes (read)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN SELECT 1')"
# MariaDB honors a SECOND executable-comment form, /*M! ... */, alongside /*! ... */
# (the M form is designed to read as inert to non-MariaDB parsers). Missing it was
# a live silent-allow bypass found in the final round of the review exercise.
test_ask   "$DB_WRITE_GATE" "MariaDB /*M! executable comment runs a write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*M!100000 DELETE FROM t */')"
test_ask   "$DB_WRITE_GATE" "MariaDB /*M! with no version digits still runs" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*M!DELETE FROM t */')"
test_allow "$DB_WRITE_GATE" "MariaDB /*M! body that is a read stays allowed" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*M!100000 SELECT 1 */')"
# scope expansion (user-approved): CALL invokes a stored procedure that can
# write internally; EXPLAIN ANALYZE (unlike plain EXPLAIN) actually executes
# the analyzed statement on MySQL/MariaDB.
test_ask   "$DB_WRITE_GATE" "CALL a stored procedure" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'CALL delete_all_users()')"
test_ask   "$DB_WRITE_GATE" "EXPLAIN ANALYZE of a write executes it" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN ANALYZE DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "EXPLAIN ANALYZE of a read stays allowed" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN ANALYZE SELECT * FROM users')"
test_allow "$DB_WRITE_GATE" "unrelated MCP tool (mongodb) out of scope" \
  "$(mcp_sql_payload 'mcp__mongodb__find' 'DELETE')"
# Generalization proof: the matcher/regex is server-name-agnostic now
# (^mcp__.*__execute_sql) — a completely different server name must still ask
# on a write, with zero config. This is the whole point of the de-clienting.
test_ask   "$DB_WRITE_GATE" "a different server name entirely still gates a write (generic match)" \
  "$(mcp_sql_payload 'mcp__postgres__execute_sql' 'DELETE FROM users')"
# hooks.json's matcher ("mcp__.*__execute_sql.*") is zero-or-more on the server
# segment; the script's own check must match that scope exactly, or a
# degenerate empty-server tool name that trips the outer trigger would fall
# through the inner check unclassified -> silent exit 0, no ask (a real
# never-silently-allow violation, even though no live MCP server ever emits
# an empty name). Confirmed live-fire during the compliance audit: `^mcp__.+`
# left this asking nothing; `^mcp__.*` closes it.
test_ask   "$DB_WRITE_GATE" "empty server-name segment still gates a write (outer/inner scope parity)" \
  "$(mcp_sql_payload 'mcp____execute_sql' 'DELETE FROM users')"
test_ask   "$DB_WRITE_GATE" "malformed stdin (fail-safe ask)" \
  '{not valid json'

echo ""
echo "=== atlassian-mcp-gate (cold-start guard: Skill(jira-acli:*) must load before Atlassian MCP) ==="
ATLASSIAN_GATE="$ROOT/hooks/gates/atlassian-mcp-gate.sh"

# Build a Skill tool payload.
skill_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Skill", "tool_input": {"skill": sys.argv[1]}, "session_id": sys.argv[2]}))' "$1" "$2"
}

# Build an MCP tool-call payload keyed to a session_id.
mcp_session_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": {}, "session_id": sys.argv[2]}))' "$1" "$2"
}

AG_COLD="test-atlassian-gate-cold-$$"
AG_ENGAGED="test-atlassian-gate-engaged-$$"
AG_WRONGSKILL="test-atlassian-gate-wrongskill-$$"
AG_OTHER="test-atlassian-gate-other-$$"
AG_ESCAPE="test-atlassian-gate-escape-$$"

test_deny  "$ATLASSIAN_GATE" "cold connector-family MCP call (mcp__claude_ai_Atlassian_Rovo__*), no skill loaded" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' "$AG_COLD")"
test_deny  "$ATLASSIAN_GATE" "cold plugin-family MCP call (mcp__plugin_atlassian_atlassian__*), no skill loaded" \
  "$(mcp_session_payload 'mcp__plugin_atlassian_atlassian__editJiraIssue' "$AG_COLD")"
test_allow "$ATLASSIAN_GATE" "Skill(jira-acli:acli) load is never itself blocked" \
  "$(skill_payload 'jira-acli:acli' "$AG_ENGAGED")"
test_allow "$ATLASSIAN_GATE" "same-session MCP call allowed once jira-acli:acli loaded" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' "$AG_ENGAGED")"
test_allow "$ATLASSIAN_GATE" "same-session confluence-content fallback (page create) also allowed once engaged" \
  "$(mcp_session_payload 'mcp__plugin_atlassian_atlassian__createConfluencePage' "$AG_ENGAGED")"
test_allow "$ATLASSIAN_GATE" "Skill(other:x) load is never itself blocked" \
  "$(skill_payload 'kbg:decide' "$AG_WRONGSKILL")"
test_deny  "$ATLASSIAN_GATE" "a non-jira-acli skill does not engage the session" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__getJiraIssue' "$AG_WRONGSKILL")"
test_deny  "$ATLASSIAN_GATE" "a different, still-cold session stays blocked (marker is per-session)" \
  "$(mcp_session_payload 'mcp__plugin_atlassian_atlassian__editJiraIssue' "$AG_OTHER")"
test_allow "$ATLASSIAN_GATE" "unrelated MCP tool (mongodb) out of scope" \
  "$(mcp_session_payload 'mcp__mongodb__find' "$AG_COLD")"
test_allow "$ATLASSIAN_GATE" "unrelated MCP tool (code-review-graph) out of scope" \
  "$(mcp_session_payload 'mcp__code-review-graph__query_graph_tool' "$AG_COLD")"
test_allow "$ATLASSIAN_GATE" "malformed stdin (fail-safe allow)" \
  '{not valid json'
test_allow "$ATLASSIAN_GATE" "escape hatch KBG_ALLOW_DIRECT_ATLASSIAN_MCP=1 bypasses a cold block" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' "$AG_ESCAPE")" \
  "KBG_ALLOW_DIRECT_ATLASSIAN_MCP=1"

rm -f "$HOME/.local/share/kbg/jira-acli-sessions/$AG_COLD" \
      "$HOME/.local/share/kbg/jira-acli-sessions/$AG_ENGAGED" \
      "$HOME/.local/share/kbg/jira-acli-sessions/$AG_WRONGSKILL" \
      "$HOME/.local/share/kbg/jira-acli-sessions/$AG_OTHER" \
      "$HOME/.local/share/kbg/jira-acli-sessions/$AG_ESCAPE" 2>/dev/null

echo ""
echo "=== fast-path (bash pre-filter that skips python3 on commands that cannot match, added 2026-08-14) ==="
# irrecoverable + verifier-protect gained a bash fast-path so a benign command
# skips the python3 cold-start. The fast-path only exits 0 (never 2), so a
# deny-case still exiting 2 / an ask-case still emitting stdout PROVES python ran
# and the fast-path did not short-circuit it. These guard the fast-path's own
# specific risks (the existing suite already covers the git-apply-with-verifier-
# diff fail-open at line ~314, which the carrier fall-through must preserve).
# irrecoverable: the quote-strip MUST expose a quote-concatenated `r""m` -> rm
# (the one shlex obfuscation the python catches that a naive substring misses).
test_deny  "$IRRECOVERABLE" "r\"\"m -rf (quote-concatenation -> fast-path quote-strip)" \
  "$(bash_payload 'r""m -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "r\\m -rf (backslash-concatenation -> fast-path strip)" \
  "$(bash_payload 'r\m -rf /tmp/x')"
# verifier-protect: a Write to a file_path containing "Bash" must NOT be
# mis-routed through the Bash fast-path (which would exit 0 and skip the Write
# ask) -- the tool_name peek matches the quoted value precisely.
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/Bash.sh (mis-route guard: file_path contains Bash)" \
  "$(write_payload 'hooks/gates/Bash.sh' 'echo neutered')"
# verifier-protect: write/carrier substrings with no verifier path fast-exit 0
# (the latency win); the fast-path must not deny (it never does) and python
# (if a carrier substring like 'tar' in 'start' reaches it) must allow.
test_allow "$VERIFIER_PROTECT" "npm install (write token 'install', no verifier path -> allow)" \
  "$(bash_payload 'npm install')"
test_allow "$VERIFIER_PROTECT" "npm start (carrier 'tar' in 'start', false-pos -> allow)" \
  "$(bash_payload 'npm start')"
test_allow "$VERIFIER_PROTECT" "ls (no write token -> fast allow)" \
  "$(bash_payload 'ls -la')"
test_allow "$VERIFIER_PROTECT" "echo > /tmp/x (redirect, no verifier path -> allow)" \
  "$(bash_payload 'echo x > /tmp/x')"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
