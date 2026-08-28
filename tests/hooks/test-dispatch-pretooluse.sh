#!/usr/bin/env bash
# Behavioral tests for hooks/dispatch-pretooluse.sh + dispatch-pretooluse.py
# (T12 #91). Two kinds of coverage:
#   1. PARITY: a real gate's output through the dispatcher must byte-match
#      (or field-match) the same gate invoked directly, for the cases that
#      matter most -- a denying gate, an asking gate, and an updatedInput
#      redirect. This is the bar that actually matters: profile-filter and
#      kill-switch tests alone would not have caught the systemMessage gap
#      found live while building this (worktree-guard.py's redirect message
#      was silently dropped by the merge on the first draft).
#   2. MERGE PRECEDENCE: synthetic fixture scripts (not real gates) exercise
#      the deny > ask > allow ordering, the "blocking suppresses
#      updatedInput" rule, the multi-updatedInput warning, and the
#      non-blocking-error handling for a nonzero-non-2 exit -- verified
#      against code.claude.com/docs/en/hooks-guide + hooks.md (2026-08-25),
#      not invented.
# Run standalone: bash tests/hooks/test-dispatch-pretooluse.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DISPATCH_SH="$ROOT/hooks/dispatch-pretooluse.sh"
DISPATCH_PY="$ROOT/hooks/dispatch-pretooluse.py"

pass=0
fail=0

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-pretooluse.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

bash_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"; }
write_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' "$1" "$2"; }
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
read_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Read", "tool_input": {"file_path": sys.argv[1]}}))' "$1"; }

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== silent case (no matcher hits) ==="
out=$(echo "$(read_payload /tmp/x)" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" bash "$DISPATCH_SH" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Read matches zero gates: exit 0, empty stdout" "$ok"

echo "=== deny parity (irrecoverable.sh via Bash) ==="
direct_rc=$(echo "$(bash_payload 'rm -rf /tmp/test')" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" bash "$ROOT/hooks/gates/irrecoverable.sh" >/dev/null 2>/dev/null; echo $?)
dispatch_rc=$(echo "$(bash_payload 'rm -rf /tmp/test')" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" bash "$DISPATCH_SH" >/dev/null 2>/dev/null; echo $?)
ok=1; [ "$direct_rc" -eq 2 ] && [ "$dispatch_rc" -eq 2 ] && ok=0
check "rm -rf: direct and dispatched both exit 2 (direct=$direct_rc dispatch=$dispatch_rc)" "$ok"

echo "=== ask parity (verifier-protect.sh via Write) ==="
direct_out=$(echo "$(write_payload "hooks/gates/foo.sh" "x")" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" bash "$ROOT/hooks/gates/verifier-protect.sh" 2>/dev/null)
dispatch_out=$(echo "$(write_payload "hooks/gates/foo.sh" "x")" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" bash "$DISPATCH_SH" 2>/dev/null)
ok=1
if echo "$direct_out" | /usr/bin/grep -q '"permissionDecision": "ask"' && \
   echo "$dispatch_out" | /usr/bin/grep -q '"permissionDecision": "ask"'; then
  ok=0
fi
check "Write to hooks/gates/foo.sh: both direct and dispatched ask" "$ok"

echo "=== deny parity (task-complete-separation.sh via TaskUpdate) ==="
direct_rc=$(echo "$(taskupdate_payload completed general-purpose)" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" bash "$ROOT/hooks/gates/task-complete-separation.sh" >/dev/null 2>/dev/null; echo $?)
dispatch_rc=$(echo "$(taskupdate_payload completed general-purpose)" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" bash "$DISPATCH_SH" >/dev/null 2>/dev/null; echo $?)
ok=1; [ "$direct_rc" -eq 2 ] && [ "$dispatch_rc" -eq 2 ] && ok=0
check "subagent TaskUpdate(completed): direct and dispatched both exit 2" "$ok"

echo "=== updatedInput parity (worktree-guard.py via Edit, real gate) ==="
WS="$TMP/ws"; WT="$TMP/wt"
mkdir -p "$WS" "$WT"
git init -q -b develop "$WS/repo1" >/dev/null
git -C "$WS/repo1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo x > "$WS/repo1/f.txt"; git -C "$WS/repo1" add f.txt
git -C "$WS/repo1" -c user.email=t@t -c user.name=t commit -q -m add-f
edit_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": sys.argv[1]}, "session_id": sys.argv[2]}))' "$1" "$2"; }
P=$(edit_payload "$WS/repo1/f.txt" sess1234)
direct_out=$(echo "$P" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" CLAUDE_PROJECT_DIR="$WS/repo1" MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= bash "$ROOT/hooks/gates/worktree-guard-dispatch.sh" 2>/dev/null)
dispatch_out=$(echo "$P" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" CLAUDE_PROJECT_DIR="$WS/repo1" MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= bash "$DISPATCH_SH" 2>/dev/null)
ok=1
python3 -c '
import json, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
sys.exit(0 if a == b else 1)
' "$direct_out" "$dispatch_out" && ok=0
check "worktree-guard redirect: direct and dispatched JSON byte-match (incl. systemMessage)" "$ok"

echo "=== merge precedence (synthetic fixture scripts, not real gates) ==="
FIXTURE_DIR="$TMP/fixtures"
mkdir -p "$FIXTURE_DIR"

cat > "$FIXTURE_DIR/allow_ui.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": {"file_path": "/from/allow_ui"}}}
JSON
exit 0
EOF

cat > "$FIXTURE_DIR/asker.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "fixture ask"}}
JSON
exit 0
EOF

cat > "$FIXTURE_DIR/denier.sh" <<'EOF'
#!/usr/bin/env bash
echo "fixture deny" >&2
exit 2
EOF

cat > "$FIXTURE_DIR/nonblocking_error.sh" <<'EOF'
#!/usr/bin/env bash
echo "transient failure" >&2
exit 1
EOF

cat > "$FIXTURE_DIR/updater_a.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": {"file_path": "/from/a"}}}'
exit 0
EOF

cat > "$FIXTURE_DIR/updater_b.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": {"file_path": "/from/b"}}}'
exit 0
EOF

run_synthetic() { # run_synthetic <table.json>
  echo "$(bash_payload 'irrelevant')" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" python3 "$DISPATCH_PY" "$1" "$FIXTURE_DIR/.."
}

# ask beats allow+updatedInput -- blocking decision suppresses the redirect.
cat > "$TMP/table-ask-vs-allow.json" <<EOF
[
  {"id": "t:asker", "matcher": "Bash", "script": "fixtures/asker.sh"},
  {"id": "t:allow_ui", "matcher": "Bash", "script": "fixtures/allow_ui.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-ask-vs-allow.json" 2>/dev/null); rc=$?
ok=1
if [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ! echo "$out" | /usr/bin/grep -q "updatedInput"; then
  ok=0
fi
check "ask beats allow+updatedInput; updatedInput suppressed by the blocking decision" "$ok"

# deny beats ask.
cat > "$TMP/table-deny-vs-ask.json" <<EOF
[
  {"id": "t:denier", "matcher": "Bash", "script": "fixtures/denier.sh"},
  {"id": "t:asker", "matcher": "Bash", "script": "fixtures/asker.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-deny-vs-ask.json" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "deny beats ask (exit 2)" "$ok"

# a nonzero-non-2 exit is a non-blocking error -- proceeds as allow, not deny.
cat > "$TMP/table-nonblocking.json" <<EOF
[
  {"id": "t:nonblocking_error", "matcher": "Bash", "script": "fixtures/nonblocking_error.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-nonblocking.json" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "exit 1 (non-2 nonzero) is a non-blocking error, not a deny: exit 0, no decision JSON" "$ok"

# two hooks both set updatedInput -- deterministic table-order-wins (last), with a warning.
cat > "$TMP/table-multi-update.json" <<EOF
[
  {"id": "t:updater_a", "matcher": "Bash", "script": "fixtures/updater_a.sh"},
  {"id": "t:updater_b", "matcher": "Bash", "script": "fixtures/updater_b.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-multi-update.json" 2>"$TMP/multi-update-stderr"); rc=$?
stderr_out=$(cat "$TMP/multi-update-stderr" 2>/dev/null)
ok=1
if [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"/from/b"' && ! echo "$out" | /usr/bin/grep -q '"/from/a"'; then
  ok=0
fi
check "multiple updatedInput: last in table order wins deterministically" "$ok"
ok=1; echo "$stderr_out" | /usr/bin/grep -qi "more than one" && ok=0
check "multiple updatedInput: warning logged to stderr" "$ok"

# The SAME multi-updatedInput conflict, but a third gate also asks -- the ask
# wins and suppresses updatedInput entirely. The warning about "applying the
# last in table order" must NOT fire here: neither updatedInput was actually
# applied, so warning about which one "won" would be misleading (#91
# adversarial audit, 2026-08-25 -- the warning used to print unconditionally,
# before the blocking-decision check that discards updatedInput).
cat > "$TMP/table-multi-update-but-asked.json" <<EOF
[
  {"id": "t:updater_a", "matcher": "Bash", "script": "fixtures/updater_a.sh"},
  {"id": "t:updater_b", "matcher": "Bash", "script": "fixtures/updater_b.sh"},
  {"id": "t:asker", "matcher": "Bash", "script": "fixtures/asker.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-multi-update-but-asked.json" 2>"$TMP/multi-update-asked-stderr"); rc=$?
stderr_out2=$(cat "$TMP/multi-update-asked-stderr" 2>/dev/null)
ok=1
if [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ! echo "$out" | /usr/bin/grep -q "updatedInput"; then
  ok=0
fi
check "multi-updatedInput + a co-firing ask: ask wins, updatedInput suppressed (as before)" "$ok"
ok=0; echo "$stderr_out2" | /usr/bin/grep -qi "more than one" && ok=1
check "no misleading 'applying the last in table order' warning when updatedInput was never actually applied" "$ok"

echo "=== failure isolation (#91 adversarial audit, 2026-08-25) ==="
# Before this fix: an uncaught exception anywhere in table loading/matching
# exited 1 -- Claude Code treats any non-2 exit as non-blocking, so a single
# malformed table row silently disabled ALL 9 deny gates with nothing but a
# raw Python traceback. Two failure classes now get two different responses.

# The WHOLE table fails to parse -> deny this call (fail CLOSED). We're the
# sole PreToolUse gate; silently proceeding with zero gate coverage is worse
# than blocking one call with a clear reason.
echo 'not valid json at all' > "$TMP/table-corrupt.json"
out=$(run_synthetic "$TMP/table-corrupt.json" 2>"$TMP/corrupt-stderr"); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "totally unparseable table.json -> exit 2 (fail closed, not silently open)" "$ok"
ok=1; /usr/bin/grep -qi "FATAL" "$TMP/corrupt-stderr" && ok=0
check "unparseable table.json -> a clear FATAL stderr message, not a bare traceback" "$ok"

out=$(echo "$(bash_payload 'irrelevant')" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$TMP" python3 "$DISPATCH_PY" "$TMP/no-such-table.json" "$FIXTURE_DIR/.." 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "table.json path doesn't exist at all -> exit 2 (fail closed)" "$ok"

# ONE malformed entry (missing "script") must not take down evaluation of the
# OTHER entries in the same table -- the old single list-comprehension threw
# on the first bad entry before any gate ever ran.
cat > "$TMP/table-one-bad-entry.json" <<EOF
[
  {"id": "t:bad-entry", "matcher": "Bash"},
  {"id": "t:denier", "matcher": "Bash", "script": "fixtures/denier.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-one-bad-entry.json" 2>"$TMP/bad-entry-stderr"); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "one entry missing 'script' -> the OTHER entry (a real denier) still runs and denies" "$ok"
ok=1; /usr/bin/grep -q "t:bad-entry" "$TMP/bad-entry-stderr" && /usr/bin/grep -qi "malformed" "$TMP/bad-entry-stderr" && ok=0
check "malformed entry is named and logged, not silently dropped" "$ok"

# A bad matcher regex in one entry must not take down the others either.
cat > "$TMP/table-bad-regex.json" <<EOF
[
  {"id": "t:bad-regex", "matcher": "Bash(", "script": "fixtures/asker.sh"},
  {"id": "t:denier", "matcher": "Bash", "script": "fixtures/denier.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-bad-regex.json" 2>"$TMP/bad-regex-stderr"); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "one entry has an invalid matcher regex -> the OTHER entry still runs and denies" "$ok"
ok=1; /usr/bin/grep -q "t:bad-regex" "$TMP/bad-regex-stderr" && /usr/bin/grep -qi "invalid matcher" "$TMP/bad-regex-stderr" && ok=0
check "invalid matcher regex is named and logged, not silently dropped" "$ok"

echo "=== gate-verdict journal (item 2: closes 'how often did gate X fire') ==="
# Non-allow verdict -> a row is written, with the right shape.
JOURNAL="$TMP/.local/share/kbg/metrics/gate-decisions.jsonl"
out=$(run_synthetic "$TMP/table-deny-vs-ask.json" 2>/dev/null); rc=$?
ok=1
if [ -f "$JOURNAL" ] && /usr/bin/grep -q '"decision": "deny"' "$JOURNAL" && /usr/bin/grep -q '"id": "t:denier"' "$JOURNAL"; then
  ok=0
fi
check "a deny verdict is journaled to gate-decisions.jsonl" "$ok"

# Volume control: an allow-only dispatch must NOT add a row (journal only
# non-allow decisions -- matches the actual need and avoids the unbounded
# per-tool-call write-rate the adversarial review flagged).
: > "$JOURNAL"  # reset from the deny row just written above
cat > "$TMP/table-allow-only.json" <<EOF
[
  {"id": "t:allow_ui", "matcher": "Bash", "script": "fixtures/allow_ui.sh"}
]
EOF
out=$(run_synthetic "$TMP/table-allow-only.json" 2>/dev/null)
ok=1
[ ! -s "$JOURNAL" ] && ok=0
check "an allow-only dispatch does not add a journal row" "$ok"

# A non-blocking error (exit 1, non-2 nonzero) is one of the 5 per-entry
# exit points and was never journaled (deep-audit 2026-08-28) -- the
# scope this journal was built for is "ask/deny/defer/error", not just
# "ask/deny/defer".
: > "$JOURNAL"  # reset from the allow-only run above
out=$(run_synthetic "$TMP/table-nonblocking.json" 2>/dev/null)
ok=1
if [ -f "$JOURNAL" ] && /usr/bin/grep -q '"decision": "error"' "$JOURNAL" && /usr/bin/grep -q '"id": "t:nonblocking_error"' "$JOURNAL"; then
  ok=0
fi
check "a non-blocking-error verdict is journaled to gate-decisions.jsonl" "$ok"

echo "=== gate-verdict journal fail-safe (the Critical finding the review caught) ==="
# An unwritable journal path must NEVER change the dispatch's own merged
# verdict -- the fail-open risk: an unguarded journal write throwing inside
# dispatch-pretooluse.py exits non-zero, and this file's own header
# documents what a non-2 exit means: non-blocking error, proceeds as if no
# gate fired at all. Point HOME at a path whose parent is not writable, so
# `os.makedirs(log_dir, exist_ok=True)` inside _journal() fails.
RO_HOME="$TMP/ro-home"
mkdir -p "$RO_HOME"
chmod 555 "$RO_HOME"
denier_rc=$(echo "$(bash_payload 'irrelevant')" | env CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$RO_HOME/no-write-here" python3 "$DISPATCH_PY" "$TMP/table-deny-vs-ask.json" "$FIXTURE_DIR/.." >/dev/null 2>/dev/null; echo $?)
chmod 755 "$RO_HOME"  # restore before the trap tries to trash it
ok=1; [ "$denier_rc" -eq 2 ] && ok=0
check "deny verdict unchanged (still exit 2) when the journal path is unwritable" "$ok"

echo
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
