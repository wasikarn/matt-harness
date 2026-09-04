#!/usr/bin/env bash
# Behavioral tests for hooks/advisory/agent-write-scope.sh (issue #137, rev 4
# log-mode sensor). This gate NEVER exits non-zero on either leg, so every
# assertion here reads the JOURNAL FILE CONTENT (recorder: the per-agent
# ~/.local/share/kbg/mh-agent-writes/<id>.jsonl; enforcer: the shared
# ~/.local/share/kbg/metrics/agent-write-scope.jsonl), not the exit code.
# Every run sets HOME to a throwaway fixture so those paths never touch the
# operator's real ~/.local. Enforcer cases run inside throwaway git
# fixtures (mktemp -d, git init) so they never touch the real matt-harness
# working tree.
# Run standalone: bash tests/hooks/test-agent-write-scope.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/advisory/agent-write-scope.sh"

pass=0
fail=0

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== agent-write-scope sensor ==="

FIXDIR="$(mktemp -d)"
CLEANUP_DIRS=("$FIXDIR")
trap 'for d in "${CLEANUP_DIRS[@]}"; do trash "$d" 2>/dev/null || true; done' EXIT

WRITE_DIR="$FIXDIR/.local/share/kbg/mh-agent-writes"
JOURNAL="$FIXDIR/.local/share/kbg/metrics/agent-write-scope.jsonl"
ERR="$FIXDIR/stderr"

new_gitfix() { # new_gitfix -> prints the new repo dir path
  local d
  d="$(mktemp -d)"
  CLEANUP_DIRS+=("$d")
  (cd "$d" && git init -q && git config user.email t@t.com && git config user.name t) >/dev/null
  echo "$d"
}

run_gate() { # run_gate <dir> <payload> -> sets rc; gate stderr lands in $ERR
  # No OUT/ERRTXT capture here (unlike the sibling test-main-exec-guard.sh
  # run()): this sensor never denies and never has a decision channel to
  # verify -- every assertion in this file reads the JOURNAL FILE CONTENT
  # (see header), not stdout/stderr. $ERR is kept on disk for post-mortem
  # if a check fails.
  (cd "$1" && HOME="$FIXDIR" bash "$GATE") <<<"$2" >/dev/null 2>"$ERR"; rc=$?
}

write_payload() { # write_payload <tool_name> <agent_id> <path>
  jq -nc --arg t "$1" --arg a "$2" --arg p "$3" \
    '{tool_name:$t, agent_id:$a, agent_type:"general-purpose",
      tool_input:(if $t=="NotebookEdit" then {notebook_path:$p} else {file_path:$p} end)}'
}

bash_payload() { # bash_payload <agent_id-or-empty> <command>
  if [ -n "$1" ]; then
    jq -nc --arg a "$1" --arg c "$2" \
      '{tool_name:"Bash", agent_id:$a, agent_type:"general-purpose", tool_input:{command:$c}}'
  else
    jq -nc --arg c "$2" '{tool_name:"Bash", tool_input:{command:$c}}'
  fi
}

jlines() { [ -f "$JOURNAL" ] && wc -l <"$JOURNAL" | tr -d ' ' || echo 0; }

# ==================================================================== recorder leg
RECFIX="$(new_gitfix)"

echo "--- recorder leg ---"

for t in Write Edit MultiEdit; do
  agent="rec-$t"
  run_gate "$RECFIX" "$(write_payload "$t" "$agent" "$RECFIX/sub/file-$t.txt")"
  ok=1
  [ "$rc" -eq 0 ] &&
    jq -e --arg tn "$t" --arg p "sub/file-$t.txt" \
      'select(.tool_name==$tn and .path==$p)' <"$WRITE_DIR/$agent.jsonl" >/dev/null 2>&1 &&
    ok=0
  check "recorder appends on $t (repo-root-relative path)" "$ok"
done

run_gate "$RECFIX" "$(write_payload NotebookEdit "rec-nb" "$RECFIX/nb/analysis.ipynb")"
ok=1
[ "$rc" -eq 0 ] &&
  jq -e 'select(.tool_name=="NotebookEdit" and .path=="nb/analysis.ipynb")' <"$WRITE_DIR/rec-nb.jsonl" >/dev/null 2>&1 &&
  ok=0
check "recorder appends on NotebookEdit (notebook_path field)" "$ok"

before_count=$(ls -1 "$WRITE_DIR" 2>/dev/null | wc -l | tr -d ' ')
run_gate "$RECFIX" "$(jq -nc --arg p "$RECFIX/x.txt" '{tool_name:"Write", tool_input:{file_path:$p}}')"
after_count=$(ls -1 "$WRITE_DIR" 2>/dev/null | wc -l | tr -d ' ')
ok=1; [ "$rc" -eq 0 ] && [ "$after_count" -eq "$before_count" ] && ok=0
check "recorder no-op for main session (no agent_id): no new write-set file created" "$ok"

run_gate "$RECFIX" "not json"
ok=1; [ "$rc" -eq 0 ] && ok=0
check "malformed stdin: fails open, exit 0" "$ok"

run_gate "$RECFIX" "$(jq -nc '{tool_name:"Write", agent_id:"rec-null-input", tool_input:null}')"
ok=1; [ "$rc" -eq 0 ] && [ ! -f "$WRITE_DIR/rec-null-input.jsonl" ] && ok=0
check "recorder: tool_input null -> no crash, no row" "$ok"

# ==================================================================== enforcer leg
echo "--- enforcer leg ---"

# --- A. baseline: committed path present in write-set vs absent from it ---
GA="$(new_gitfix)"
echo a > "$GA/A.txt"; echo b > "$GA/B.txt"
(cd "$GA" && git add A.txt B.txt) >/dev/null
run_gate "$GA" "$(write_payload Write "wA" "$GA/A.txt")"  # record A.txt only
before=$(jlines)
run_gate "$GA" "$(bash_payload "wA" 'git commit -m "add A and B"')"
after=$(jlines)
ok=1
[ "$rc" -eq 0 ] && [ "$after" -eq $((before + 1)) ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '(.committed_paths | index("A.txt")) != null and (.committed_paths | index("B.txt")) != null and
     (.unrecorded_paths | index("B.txt")) != null and (.unrecorded_paths | index("A.txt")) == null' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: recorded path (A.txt) excluded from unrecorded_paths, unrecorded path (B.txt) included" "$ok"

# --- A2. write_state_file_present/recorded_write_count when the file exists
# (issue #137 spec finding: the journal must distinguish "wrote nothing" from
# "recorder never correlated" -- this case is the "exists, has data, but is
# missing a committed path" side of that distinction) ---
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '.write_state_file_present == true and .recorded_write_count == 1' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: write-state file exists with 1 recorded write -> write_state_file_present true, recorded_write_count 1" "$ok"

# --- B. no state file at all for the committing agent ---
run_gate "$GA" "$(bash_payload "wE-never-recorded" 'git commit -m "solo"')"
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '(.committed_paths | index("A.txt")) != null and (.unrecorded_paths | index("A.txt")) != null and
     (.unrecorded_paths | index("B.txt")) != null' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: agent with no write-set file at all -> every committed path is unrecorded" "$ok"

# --- B2. this is the OTHER side of the #137 spec-finding distinction: no
# write-state file at all (never correlated) vs. A2 above (file exists,
# just missing a path). Both currently show identical unrecorded_paths --
# only these two new fields let a reader tell them apart. ---
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '.write_state_file_present == false and .recorded_write_count == 0' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: no write-state file at all -> write_state_file_present false, recorded_write_count 0 (distinguishes 'agent wrote nothing' from 'recorder never correlated for this agent_id')" "$ok"

# --- C. -am/-ma bundled short-flag distinction (git commit's own value-taking
# flags, not a naive per-character scan) ---
GB="$(new_gitfix)"
echo c1 > "$GB/C.txt"
(cd "$GB" && git add C.txt && git commit -q -m "seed") >/dev/null   # give it a real HEAD
echo c2 >> "$GB/C.txt"                                              # tracked, unstaged modification
echo d1 > "$GB/D.txt"
(cd "$GB" && git add D.txt) >/dev/null                               # staged new file

run_gate "$GB" "$(bash_payload "wB1" 'git commit -am "msg"')"
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '(.committed_paths | index("D.txt")) != null and (.committed_paths | index("C.txt")) != null' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: git commit -am sets -a -> tracked-modified C.txt included alongside staged D.txt" "$ok"

run_gate "$GB" "$(bash_payload "wB2" 'git commit -ma "msg"')"
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '(.committed_paths | index("D.txt")) != null and (.committed_paths | index("C.txt")) == null' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: git commit -ma gives -m the value \"a\" (does NOT set -a) -> C.txt excluded" "$ok"

# --- D. false positive: -a mentioned only in a quoted commit message must
# not be read as the real -a flag ---
run_gate "$GB" "$(bash_payload "wJ" 'git commit -m "explain the -a flag here"')"
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e '(.committed_paths | index("C.txt")) == null' >/dev/null 2>&1 &&
  ok=0
check "enforcer: -a inside a quoted commit message is not treated as the real flag" "$ok"

# --- E. non-ASCII path round-trip via -z (the quoted diff form would have
# quoted this path, breaking the match against the recorder's raw path) ---
GC="$(new_gitfix)"
printf hi > "$GC/café.txt"
(cd "$GC" && git add "café.txt") >/dev/null
run_gate "$GC" "$(write_payload Write "wC" "$GC/café.txt")"
run_gate "$GC" "$(bash_payload "wC" 'git commit -m "unicode"')"
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '(.committed_paths | index("café.txt")) != null and (.unrecorded_paths | index("café.txt")) == null' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: non-ASCII path matches the recorded path via -z (no quoting mismatch)" "$ok"

# --- F. unborn-HEAD rc=128: the -a leg's second git diff fails; must journal
# the enumeration failure (null), not read empty output as "nothing staged" ---
GD="$(new_gitfix)"
echo e > "$GD/E.txt"
(cd "$GD" && git add E.txt) >/dev/null   # staged, but HEAD does not exist yet
run_gate "$GD" "$(bash_payload "wD" 'git commit -am "first commit"')"
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e '.committed_paths == null and .unrecorded_paths == null' >/dev/null 2>&1 &&
  ok=0
check "enforcer: unborn-HEAD rc=128 on the -a diff journals enumeration failure (null), not []" "$ok"

# --- F2. write_state_file_present/recorded_write_count are computed
# UNCONDITIONALLY -- independent of whether git-diff enumeration above
# succeeded. Without this, every enumeration-failure row would silently ship
# with the new fields missing, which is exactly the failure mode #137's
# spec finding exists to prevent. wD never recorded a write here. ---
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e \
    '.write_state_file_present == false and .recorded_write_count == 0' \
    >/dev/null 2>&1 &&
  ok=0
check "enforcer: write_state_file_present/recorded_write_count still populated even when git-diff enumeration fails" "$ok"

# --- G. sanitizer round-trip: an agent_id with characters outside
# [A-Za-z0-9_-] must still correlate correctly between the two legs ---
GE="$(new_gitfix)"
echo f > "$GE/F.txt"
(cd "$GE" && git add F.txt) >/dev/null
WEIRD='agent/1: weird name'
run_gate "$GE" "$(write_payload Write "$WEIRD" "$GE/F.txt")"
run_gate "$GE" "$(bash_payload "$WEIRD" 'git commit -m "weird id"')"
ok=1
[ "$rc" -eq 0 ] &&
  tail -n1 "$JOURNAL" | jq -e '(.unrecorded_paths | index("F.txt")) == null' >/dev/null 2>&1 &&
  ok=0
check "enforcer: agent_id with special characters still round-trips through the sanitizer" "$ok"

# --- H. main session (no agent_id) git commit -> not this sensor's scope,
# no journal row at all ---
before=$(jlines)
run_gate "$GA" "$(bash_payload "" 'git commit -m "main session"')"
after=$(jlines)
ok=1; [ "$rc" -eq 0 ] && [ "$after" -eq "$before" ] && ok=0
check "enforcer: main session (no agent_id) -> no journal row" "$ok"

# --- I. a Bash command that is not a git commit -> no journal row ---
before=$(jlines)
run_gate "$GA" "$(bash_payload "wA" 'git status')"
after=$(jlines)
ok=1; [ "$rc" -eq 0 ] && [ "$after" -eq "$before" ] && ok=0
check "enforcer: non-commit git command -> no journal row" "$ok"

# --- J. never exits non-zero regardless of input ---
for p in 'not json' '[]' '{"tool_input":{"command":"git commit -m x"}}' \
         "$(jq -nc '{tool_name:"Bash", agent_id:"z", tool_input:{command:null}}')"; do
  run_gate "$GA" "$p"
  ok=1; [ "$rc" -eq 0 ] && ok=0
  check "enforcer never exits non-zero: payload '${p:0:40}...'" "$ok"
done

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
