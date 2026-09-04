#!/usr/bin/env bash
# Behavioral tests for hooks/gates/subagent-git-guard.sh (issue #135).
# Run standalone: bash tests/hooks/test-subagent-git-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/subagent-git-guard.sh"

pass=0
fail=0

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

payload() { # payload <command> [agent_id]
  python3 -c '
import json, sys
d = {"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}
if len(sys.argv) > 2 and sys.argv[2]:
    d["agent_id"] = sys.argv[2]
    d["agent_type"] = "general-purpose"
print(json.dumps(d))
' "$1" "${2:-}"
}

run_gate() { # run_gate <command> [agent_id]
  echo "$(payload "$1" "${2:-}")" | bash "$GATE" 2>/dev/null
}

echo "=== subagent-git-guard gate ==="

# --- (1) main session (no agent_id) is untouched, even for the exact
# incident command --- #
run_gate "git stash" ""; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "main session: git stash allowed (no agent_id)" "$ok"

# --- (2) subagent: every uncovered destructive shape denies (exit 2) --- #
for cmd in \
  "git stash" \
  "git stash pop" \
  "git reset" \
  "git reset --soft HEAD^" \
  "git clean -n"
do
  run_gate "$cmd" "agent1"; rc=$?
  ok=1; [ "$rc" -eq 2 ] && ok=0
  check "subagent denied: $cmd" "$ok"
done

# --- (3) subagent: unrelated git/non-git commands allowed --- #
for cmd in \
  "git status" \
  "git diff" \
  "git add foo.txt" \
  'git commit -m "add feature"' \
  "ls"
do
  run_gate "$cmd" "agent1"; rc=$?
  ok=1; [ "$rc" -eq 0 ] && ok=0
  check "subagent allowed (unrelated): $cmd" "$ok"
done

# --- (4) false-positive guards: git verb text inside prose/quotes must not
# trip the gate --- #
run_gate 'git commit -m "explain why git stash is unsafe here"' "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "false positive: commit message mentioning git stash allowed" "$ok"

run_gate 'grep -r "git reset" docs/' "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "false positive: grep for \"git reset\" allowed" "$ok"

run_gate 'echo "git checkout -- x"' "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "false positive: echo of a checkout -- string allowed" "$ok"

# --- (5) checkout is intentionally NOT this gate's job: hooks/gates/irrecoverable.sh
# already denies the discard forms (--/./-f/2+ nonflag args) unconditionally for
# EVERY session, including main -- re-implementing that here would duplicate an
# existing unconditional deny. A plain branch-switch checkout stays allowed either
# way. Verified here in isolation (this gate alone), not through the full gate
# chain -- irrecoverable.sh is owned by a concurrent session and out of scope. --- #
run_gate "git checkout -- foo.txt" "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "checkout -- not handled by this gate (covered by gate:bash:irrecoverable instead)" "$ok"

run_gate "git checkout HEAD -- foo.txt" "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "checkout HEAD -- not handled by this gate (covered by gate:bash:irrecoverable instead)" "$ok"

run_gate "git checkout main" "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "plain branch-switch checkout allowed" "$ok"

# --- (6) restore is likewise NOT this gate's job for the same reason: irrecoverable.sh
# already denies any pathspec targeting the worktree, unconditionally, for every session.
run_gate "git restore foo.txt" "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "restore not handled by this gate (covered by gate:bash:irrecoverable instead)" "$ok"

# --- (7) malformed/non-JSON stdin: fail-safe allow --- #
out=$(echo "not json" | bash "$GATE" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "malformed stdin: fail-safe allow, exit 0, no stdout" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
