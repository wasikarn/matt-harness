#!/usr/bin/env bash
# Behavioral tests for hooks/gates/main-exec-guard.sh. Covers the three
# MH_MAIN_EXEC_GUARD modes (unset/off, log, 1/enforce), the agent_id
# discriminant (a subagent is never touched; a Write whose CONTENT contains
# the text "agent_id" is still main), the three Write carve-outs, the Bash
# read-only allowlist (allow + deny lists), the deny contract (exit 2 +
# stderr, never JSON), and the fail-direction asymmetry (malformed payload /
# missing python3 -> allow; untokenizable command -> deny). Every run sets
# HOME to a throwaway fixture so carve-out paths and the log file never touch
# the operator's real ~/.claude or ~/.local.
# Run standalone: bash tests/hooks/test-main-exec-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/main-exec-guard.sh"

pass=0
fail=0

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== main-exec-guard gate ==="
cd "$ROOT" || exit 1
unset MH_MAIN_EXEC_GUARD 2>/dev/null || true

FIXDIR="$(mktemp -d)"
trap 'trash "$FIXDIR" 2>/dev/null || true' EXIT
LOG="$FIXDIR/.local/share/kbg/metrics/main-exec-guard.jsonl"

# Payload builders (jq so quotes/backslashes in commands are escaped correctly).
bash_payload() { jq -nc --arg c "$1" '{session_id:"sid",tool_name:"Bash",tool_input:{command:$c}}'; }
write_payload() { # write_payload <tool_name> <path> [extra top-level json]
  jq -nc --arg t "$1" --arg p "$2" --argjson x "${3:-{\}}" \
    '({session_id:"sid",tool_name:$t,tool_input:(if $t=="NotebookEdit" then {notebook_path:$p} else {file_path:$p,content:"x"} end)}) + $x'
}

ERR="$FIXDIR/stderr"
run() { # run <mode|""> <payload> -> sets rc, OUT, ERRTXT
  if [ -n "$1" ]; then
    OUT=$(HOME="$FIXDIR" MH_MAIN_EXEC_GUARD="$1" bash "$GATE" <<<"$2" 2>"$ERR"); rc=$?
  else
    OUT=$(HOME="$FIXDIR" bash "$GATE" <<<"$2" 2>"$ERR"); rc=$?
  fi
  ERRTXT=$(cat "$ERR")
}
denied()  { [ "$rc" -eq 2 ] && [ -z "$OUT" ] && /usr/bin/grep -q 'main-exec-guard' <<<"$ERRTXT"; }
allowed() { [ "$rc" -eq 0 ] && [ -z "$OUT" ]; }

# --- 1. Gate off (env unset / other value) -> allow everything, no stdin cost.
run "" "$(write_payload Write "$ROOT/CLAUDE.md")"
ok=1; allowed && ok=0
check "env unset -> Write to repo file allowed" "$ok"
run "" "$(bash_payload 'rm -rf /')"
ok=1; allowed && ok=0
check "env unset -> Bash 'rm -rf /' allowed (gate off)" "$ok"
run 0 "$(bash_payload 'git commit -m x')"
ok=1; allowed && ok=0
check "env=0 -> allowed (gate off)" "$ok"

# --- 2. log mode: never deny, one row per call.
run log "$(bash_payload 'sed -i s/x/y/ f')"
ok=1; allowed && [ -f "$LOG" ] && ok=0
check "env=log -> would-deny Bash exits 0 and creates the jsonl log" "$ok"
ok=1
jq -e 'select(.tool_name=="Bash" and .agent_id_present==false and .would_deny==true and (.ts|test("^[0-9]{4}-")) and .session_id=="sid" and .agent_type==null and (.reason|length>0))' \
  <"$LOG" >/dev/null 2>&1 && ok=0
check "log row: sed -i from main -> agent_id_present=false, would_deny=true, ts/session_id/reason present" "$ok"
run log "$(write_payload Write "$ROOT/CLAUDE.md" '{"agent_id":"a-1","agent_type":"general-purpose"}')"
ok=1
allowed && [ "$(wc -l <"$LOG")" -eq 2 ] && tail -n1 "$LOG" | jq -e '.agent_id_present==true and .would_deny==false and .agent_type=="general-purpose"' >/dev/null && ok=0
check "log row: subagent Write -> agent_id_present=true, would_deny=false, agent_type recorded" "$ok"
run log "$(write_payload Write "$ROOT/CLAUDE.md")"
ok=1; allowed && tail -n1 "$LOG" | jq -e '.tool_name=="Write" and .would_deny==true' >/dev/null && ok=0
check "log row: main Write to repo file -> would_deny=true, still exit 0" "$ok"
# Rotation: >25000 lines -> keep last 20000 (+ the new row).
{ for i in $(seq 1 25001); do echo "{\"n\":$i}"; done; } >"$LOG"
run log "$(bash_payload 'git status')"
ok=1; allowed && [ "$(wc -l <"$LOG")" -eq 20001 ] && [ "$(head -n1 "$LOG")" = '{"n":5002}' ] && ok=0
check "log rotation: 25001 lines -> last 20000 kept + new row" "$ok"
# Symlinked log -> refuse to append, still exit 0.
trash "$LOG" 2>/dev/null || true
ln -s "$FIXDIR/elsewhere" "$LOG"
run log "$(bash_payload 'git status')"
ok=1; allowed && [ ! -e "$FIXDIR/elsewhere" ] && ok=0
check "log file is a symlink -> no append through it, exit 0" "$ok"
trash "$LOG" 2>/dev/null || true

# --- 3. Enforce mode, subagent (agent_id present) -> untouched.
for c in 'sed -i s/x/y/ f' 'git commit -m x'; do
  run 1 "$(jq -c '. + {agent_id:"a-1"}' <<<"$(bash_payload "$c")")"
  ok=1; allowed && ok=0
  check "env=1 + agent_id -> Bash '$c' allowed" "$ok"
done
run 1 "$(write_payload Write "$ROOT/CLAUDE.md" '{"agent_id":"a-1"}')"
ok=1; allowed && ok=0
check "env=1 + agent_id -> Write to repo file allowed" "$ok"
# agent_type alone is NOT the discriminant (top-level `claude --agent` sets it too).
run 1 "$(write_payload Write "$ROOT/CLAUDE.md" '{"agent_type":"some-agent"}')"
ok=1; denied && ok=0
check "env=1 + agent_type but no agent_id -> still main, denied" "$ok"

# --- 4. Enforce mode, main (no agent_id): Write leg.
for t in Write Edit MultiEdit NotebookEdit; do
  run 1 "$(write_payload "$t" "$ROOT/CLAUDE.md")"
  ok=1; denied && ok=0
  check "env=1 main $t to repo path -> DENY (exit 2, stderr names main-exec-guard)" "$ok"
done
run 1 "$(write_payload Write "$FIXDIR/.claude/settings.json")"
ok=1; denied && ok=0
check "env=1 main Write to ~/.claude/settings.json -> DENY" "$ok"
run 1 "$(write_payload Write "$FIXDIR/.claude/plans/../settings.json")"
ok=1; denied && ok=0
check "env=1 main Write to ~/.claude/plans/../settings.json -> DENY (.. resolved)" "$ok"
run 1 "$(jq -c '.tool_input.content = "{\"agent_id\": \"fake\"}"' <<<"$(write_payload Write "$ROOT/CLAUDE.md")")"
ok=1; denied && ok=0
check "env=1 main Write whose CONTENT contains \"agent_id\" -> still DENY (jq path, not substring)" "$ok"
run 1 "$(write_payload Write "$FIXDIR/.claude/plans/my-plan.md")"
ok=1; allowed && ok=0
check "env=1 main Write under ~/.claude/plans/ -> allow" "$ok"
run 1 "$(write_payload Write "~/.claude/plans/tilde.md")"
ok=1; allowed && ok=0
check "env=1 main Write under ~/.claude/plans/ via literal ~ -> allow (expanduser)" "$ok"
run 1 "$(write_payload Edit "$FIXDIR/.claude/projects/-Users-x-proj/memory/MEMORY.md")"
ok=1; allowed && ok=0
check "env=1 main Edit under ~/.claude/projects/*/memory/ -> allow" "$ok"
run 1 "$(write_payload Write "/tmp/claude-501/-Users-x-proj/abc-123/scratchpad/notes.md")"
ok=1; allowed && ok=0
check "env=1 main Write under /tmp/claude-*/*/*/scratchpad/ -> allow (/private prefix tolerated)" "$ok"
run 1 "$(write_payload Write "/private/tmp/claude-501/-Users-x-proj/abc-123/scratchpad/notes.md")"
ok=1; allowed && ok=0
check "env=1 main Write under /private/tmp/claude-*/scratchpad/ -> allow" "$ok"
run 1 "$(write_payload Write "/tmp/claude-501/-Users-x-proj/abc-123/notes.md")"
ok=1; denied && ok=0
check "env=1 main Write under /tmp/claude-*/ but NOT scratchpad/ -> DENY" "$ok"

# --- 5. Enforce mode, main: Bash allowlist.
ALLOW_CMDS=(
  'git status' 'git diff -- somefile' 'git diff --stat' 'git log --oneline -5'
  'git hash-object somefile' 'git config core.hooksPath' 'git config --get user.name'
  'git branch --list' 'git stash list' '/usr/bin/grep -c x somefile' 'cat somefile | head -3'
  'jq -r --arg v 1 .version somefile' "sed -n '1,5p' somefile" "find . -name '*.sh'"
  'wc -l somefile' 'test -d "$(git config core.hooksPath)"' 'gh pr view 1' 'gh api repos/x/y'
  'gh run list' 'gh run watch 123'
  'rtk git status' 'rtk gain' 'echo hi >/dev/null' 'git status 2>&1' 'claude --version'
  'env | grep X' 'date' 'shasum somefile' 'git status && git diff --stat' "sed 's/w/x/' f"
  'FOO=bar git status' 'ls -la 2>/dev/null' $'# comment\ngit status' 'claude plugin list'
)
for c in "${ALLOW_CMDS[@]}"; do
  run 1 "$(bash_payload "$c")"
  ok=1; allowed && ok=0
  check "Bash ALLOW: ${c//$'\n'/\\n}" "$ok"
done

# --- 6. Enforce mode, main: Bash deny list.
DENY_CMDS=(
  'sed -i s/x/y/ f' 'sed --in-place s/x/y/ f' "sed -n 'w out' f" "sed -ne 's/a/b/w f' x"
  "awk 'BEGIN{print \"x\" > \"f\"}'" "awk 'BEGIN{system(\"x\")}'" 'echo x > f' 'tee f'
  'git add p' 'git commit -m x' 'git push' 'git stash' 'git stash push' 'git checkout -- f'
  'git tag v1' 'git remote add o u' 'git branch -D b' 'git branch newbranch' 'git config a b'
  'git config --unset a' 'git hash-object -w f' 'git -c core.pager=rm log' 'git log --output=f'
  'gh pr merge 1' 'gh api -X POST x' 'gh api --raw-field a=b x' 'bash tests/x.sh' 'bash -n f'
  'gh run cancel 123'
  'shellcheck f' 'python3 -c x' $'python3 - <<EOF\nprint(1)\nEOF' 'claude plugin validate .'
  'claude plugin update mh@wasikarn' 'claude -p x' 'mkdir -p d' 'trash f' 'cp a b' 'find . -delete'
  'find . -exec rm {} \;' 'sort -o f' 'xargs rm' 'eval x' 'source f' 'a $(rm x)' 'cat <(rm x)'
  'npm test' 'ls; rm f' 'sudo ls' 'echo "$(rm x)"' 'rtk proxy rm x' 'echo a#; rm x'
  'cat <<EOF' 'echo "unbalanced' 'cat f | tee g' 'git status | xargs rm'
)
for c in "${DENY_CMDS[@]}"; do
  run 1 "$(bash_payload "$c")"
  ok=1; denied && ok=0
  check "Bash DENY: ${c//$'\n'/\\n}" "$ok"
done

# --- 7. Deny contract details.
run 1 "$(bash_payload 'git commit -m x')"
ok=1; denied && /usr/bin/grep -q 'MH_MAIN_EXEC_GUARD=0' <<<"$ERRTXT" && /usr/bin/grep -q 'Attempted: git commit -m x' <<<"$ERRTXT" && ok=0
check "deny stderr contains MH_MAIN_EXEC_GUARD=0 and the attempted command" "$ok"
run 1 "$(bash_payload "$(printf 'git commit -m \x1b[2K%0100d' 0)")"
ok=1; denied && ! /usr/bin/grep -q $'\x1b' <<<"$ERRTXT" && [ "$(/usr/bin/grep -o 'Attempted: [^.]*' <<<"$ERRTXT" | wc -c)" -lt 100 ] && ok=0
check "deny stderr: control chars stripped and attempted text clipped to 80" "$ok"

# --- 8. Fail direction: malformed payload -> allow with a notice.
for p in 'not json' '[]' '{"tool_input":{"command":"rm -rf /"}}'; do
  run 1 "$p"
  ok=1; allowed && /usr/bin/grep -q 'main-exec-guard' <<<"$ERRTXT" && ok=0
  check "env=1 malformed payload '$p' -> allow (exit 0) + stderr notice" "$ok"
done

# --- 9. python3 missing -> announced fail-open (PATH emptied; /bin/bash by absolute path).
OUT=$(HOME="$FIXDIR" PATH=/nonexistent MH_MAIN_EXEC_GUARD=1 /bin/bash "$GATE" <<<"$(bash_payload 'git commit -m x')" 2>"$ERR"); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$OUT" ] && /usr/bin/grep -q 'python3 not found' "$ERR" && ok=0
check "python3 missing -> allow (exit 0) + stderr notice" "$ok"

# --- 10. Other tool names pass through untouched (matcher parity is the table's job).
run 1 '{"session_id":"sid","tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}'
ok=1; allowed && ok=0
check "env=1 tool_name=Read -> allow (not this gate's tool)" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
