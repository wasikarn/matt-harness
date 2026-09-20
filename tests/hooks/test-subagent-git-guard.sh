#!/usr/bin/env bash
# Behavioral tests for hooks/gates/subagent-git-guard.sh (issue #135).
# Run standalone: bash tests/hooks/test-subagent-git-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Isolate the gate-verdict journal (hooks/gates/_journal.py) from this file's
# deny assertions -- run standalone (this file's own header invites it), it
# would otherwise silently append rows to the operator's real
# ~/.local/share/kbg/metrics/gate-decisions.jsonl.
_JOURNAL_TMP="$(mktemp -d)"
trap 'trash "$_JOURNAL_TMP" 2>/dev/null || true' EXIT
export MH_GATE_JOURNAL_PATH="$_JOURNAL_TMP/gate-decisions.jsonl"
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

# payload_forced_id <command> <agent_id_raw>: agent_id KEY always present,
# even at "" or the literal __NULL__ (JSON null) -- payload() above treats a
# falsy $2 as "omit the key" (main session shape), which cannot express
# "key present but empty/null" (the same GH #154/#155 truthiness gap fixed
# elsewhere: `if not agent_id` treats presence-with-empty/null as absence).
payload_forced_id() {
  python3 -c '
import json, sys
cmd, agent_id_raw = sys.argv[1], sys.argv[2]
d = {"tool_name": "Bash", "tool_input": {"command": cmd}}
d["agent_id"] = None if agent_id_raw == "__NULL__" else agent_id_raw
d["agent_type"] = "general-purpose"
print(json.dumps(d))
' "$1" "$2"
}

run_gate_forced_id() { # run_gate_forced_id <command> <agent_id_raw>
  echo "$(payload_forced_id "$1" "$2")" | bash "$GATE" 2>/dev/null
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

# --- (7) global-flag bypass fix (2026-09-04, verifier-found): a git global
# flag between "git" and the subcommand used to slip the subcommand check
# entirely (dm was tried against "-C"/"--no-pager"/etc instead of the real
# verb). Must all deny now. --- #
for cmd in \
  "git -C /repo stash" \
  "git --no-pager clean -d" \
  "git -c core.x=y reset" \
  "git --git-dir=.git stash"
do
  run_gate "$cmd" "agent1"; rc=$?
  ok=1; [ "$rc" -eq 2 ] && ok=0
  check "global-flag bypass fixed, now denied: $cmd" "$ok"
done

# --- (8) sudo/xargs wrapper (2026-09-04, verifier-found second half of the
# same bug): deliberately fixed rather than left as a documented non-goal --
# the anchor now walks past an optional leading sudo/xargs wrapper too. --- #
for cmd in \
  "sudo git stash" \
  "xargs git stash" \
  "sudo -u someuser git stash"
do
  run_gate "$cmd" "agent1"; rc=$?
  ok=1; [ "$rc" -eq 2 ] && ok=0
  check "sudo/xargs wrapper fixed, now denied: $cmd" "$ok"
done

# --- (8b) 2026-09-20 audit: the sudo/xargs wrapper fix above was single-level
# and had a narrower wrapper vocabulary than irrecoverable.py's. A chained
# wrapper (env sudo git ...) or a backslash-escaped \git bypassed the anchor
# live, and the wrapper set didn't include env/command/nohup/nice/time. --- #
for cmd in \
  "env git stash" \
  "env sudo git stash" \
  "\git stash" \
  "nohup git stash" \
  "nice git stash" \
  "time git stash" \
  "command git stash"
do
  run_gate "$cmd" "agent1"; rc=$?
  ok=1; [ "$rc" -eq 2 ] && ok=0
  check "wrapper-chain bypass fixed, now denied: $cmd" "$ok"
done

# --- (8c) compliance-audit fix-round 2, 2026-09-20: a first fix bounded the
# wrapper chain at depth<=3 to dodge a catastrophic-backtracking shape; an
# independent verifier chained 13 wrappers and got past that cap live. --- #
long_chain="$(python3 -c 'print("env sudo nohup nice time command " * 13 + "git reset --hard")')"
run_gate "$long_chain" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "13-deep wrapper chain past the old depth<=3 bound, now denied" "$ok"

run_gate "env -u A -u B git reset --hard" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "env with its own -u flags before git reset, now denied" "$ok"

# --- (9) missing re.MULTILINE fix (2026-09-04, verifier-found): a genuine
# multi-line Bash command (heredoc/multi-line script) puts "git reset" at
# the start of its OWN line, not absolute string offset 0 -- the old
# anchor only matched offset 0 and silently allowed this. Uses printf for
# a real embedded newline, not echo, since echo's backslash-escape
# behavior differs across shells (zsh interprets \n by default; bash does
# not -- caught live while verifying this fix). --- #
run_gate "$(printf 'ls\ngit reset')" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "multi-line command: git reset at start of its own line now denied" "$ok"

# --- (10) quote-aware anchor fix (2026-09-04, verifier-found false
# positive): a `;`/`&`/`|`/`(` sitting INSIDE a quoted argument used to be
# treated as a real command-separator anchor, wrongly denying an ordinary
# safe command. Must now allow. --- #
run_gate 'git commit -m "fix; git reset was wrong"' "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "false positive fixed: separator inside quotes no longer anchors" "$ok"

run_gate 'echo "a; git stash"' "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "false positive fixed: quoted prose with a git verb allowed" "$ok"

# --- (10b) 2026-09-20 audit: agent_id truthiness bug -- an empty-string or
# null agent_id (key present, value falsy) was treated as "not a subagent"
# by `agent_id = d.get("agent_id"); if not agent_id: sys.exit(0)`, letting a
# destructive git command through unguarded. Must deny like any other
# subagent call. --- #
run_gate_forced_id "git stash" ""; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "agent_id truthiness bug: empty-string agent_id still denied" "$ok"

run_gate_forced_id "git stash" "__NULL__"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "agent_id truthiness bug: JSON null agent_id still denied" "$ok"

# --- (11) malformed/non-JSON stdin: fail-safe allow --- #
out=$(echo "not json" | bash "$GATE" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "malformed stdin: fail-safe allow, exit 0, no stdout" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
