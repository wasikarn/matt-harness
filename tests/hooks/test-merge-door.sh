#!/usr/bin/env bash
# Behavioral tests for hooks/gates/merge-door.sh. Covers the ask-on-match
# case, the operator-window/prefix-wrapper/whitespace shapes the argv-based
# classifier is supposed to catch, and the false-positive/negative shapes
# named by the adversarial plan review that sank the original word-boundary-
# regex design: a HEREDOC/commit-message mention of "gh pr merge" as prose
# must NOT ask, and the `gh api .../merge` REST equivalent is a documented,
# deliberate non-goal (also must not ask). Also covers the sudo -u/-g
# value-taking-flag bypass (issue #115, fixed 2026-08-28): before the fix,
# `sudo -u alice gh pr merge` was misread as argv0="alice", not "gh".
# Run standalone: bash tests/hooks/test-merge-door.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/merge-door.sh"

pass=0
fail=0

payload_bash() { # payload_bash <command>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== merge-door gate ==="
cd "$ROOT" || exit 1

BATTERY=(
  "plain gh pr merge -> ask|gh pr merge 123|ask"
  "gh pr merge, no PR number -> ask|gh pr merge|ask"
  "extra internal whitespace -> ask (argv-tokenized, not regex)|gh  pr   merge 123|ask"
  "sudo-wrapped -> ask (prefix-wrapper unwrap)|sudo gh pr merge 123|ask"
  "sudo -u <user>-wrapped -> ask (issue #115 fix)|sudo -u alice gh pr merge 123|ask"
  "sudo --user=<user>-wrapped -> ask (issue #115 fix, = form)|sudo --user=alice gh pr merge 123|ask"
  "sudo -g <group>-wrapped -> ask (issue #115 fix)|sudo -g admins gh pr merge 123|ask"
  "second command in an operator chain -> ask|echo hi && gh pr merge 123|ask"
  "gh pr view -> noask (not a merge)|gh pr view 123|noask"
  "git merge -> noask (argv0 is git, not gh)|git merge feature-branch|noask"
  "gh api REST merge endpoint -> noask (documented non-goal)|gh api -X PUT repos/o/r/pulls/123/merge|noask"
)

for row in "${BATTERY[@]}"; do
  desc="${row%%|*}"
  rest="${row#*|}"
  cmd="${rest%|*}"
  expect="${rest##*|}"
  out=$(payload_bash "$cmd" | bash "$GATE" 2>/dev/null)
  got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
  ok=1
  if [ "$expect" = "ask" ] && [ "$got_ask" -eq 0 ]; then ok=0; fi
  if [ "$expect" = "noask" ] && [ "$got_ask" -eq 1 ]; then ok=0; fi
  check "battery: $desc" "$ok"
done

# HEREDOC/commit-message prose mention must NOT ask — the exact false-positive
# class a naive regex design would have hit, and the reason irrecoverable.sh's
# own _strip_heredocs exists.
heredoc_cmd=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nRun gh pr merge after this lands\nEOF\n)"')
out=$(payload_bash "$heredoc_cmd" | bash "$GATE" 2>/dev/null)
got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
ok=1; [ "$got_ask" -eq 1 ] && ok=0
check "HEREDOC commit message mentioning 'gh pr merge' as prose -> noask" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
