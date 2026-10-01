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

# --- (2b) GH #157 sibling: an escaped quote outside a span must not mask
# the real "git stash" after it (was a bypass, false ALLOW) --- #
run_gate 'echo \" ; git stash' "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied: echo \\\" ; git stash (escaped quote before a real stash)" "$ok"
run_gate "echo \\' ; git stash" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied: echo \\' ; git stash (escaped single quote before a real stash)" "$ok"
run_gate 'echo "a ; b" ; git stash' "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied: real double-quoted span then a real stash" "$ok"
run_gate "echo '\\' ; git stash" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied: backslash inside single quotes is literal, span closes, real stash follows" "$ok"
run_gate 'echo "\" ; git stash"' "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "subagent allowed: stash inside a real double-quoted span (escaped quote inside the span)" "$ok"

# --- (2c) GH #161: ANSI-C $'\'' is one complete string; the old masker
# opened a fake single-quote span at the escaped apostrophe and masked the
# real "git stash" away (false ALLOW) --- #
run_gate "echo \$'\\'' ; git stash" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied: echo \$'\\'' ; git stash (ANSI-C span before a real stash)" "$ok"
run_gate "echo \$'a ; git stash'" "agent1"; rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "subagent allowed: stash inside an ANSI-C \$'...' span" "$ok"
# Backslash-newline stays a boundary (validator round 2): masking the pair
# hid `\<nl>git stash`, a real stash, from _ANCHOR_RE -- a bypass. So
# `echo \<nl>git stash` (really `echo git stash`) is a deliberate
# conservative false deny, and the three real-stash shapes must deny.
run_gate $'echo \\\ngit stash' "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied (conservative false deny, by design): echo \\<nl>git stash" "$ok"
for cmd in $'\\\ngit stash' $'echo; \\\ngit stash' $'env \\\ngit stash'; do
  run_gate "$cmd" "agent1"; rc=$?
  ok=1; [ "$rc" -eq 2 ] && ok=0
  check "subagent denied: real stash after a backslash-newline: $(printf '%q' "$cmd")" "$ok"
done
# Round 2: an escaped "\$" or a "$$" PID before a plain single-quoted string
# must not open an ANSI-C span whose "\'" swallows the real stash.
run_gate "\\\$'a\\'; git stash; echo 'x'" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied: \\\$'a\\'; git stash; echo 'x' (escaped \$, plain single quotes)" "$ok"
run_gate "\$\$'a\\'; git stash; echo 'x'" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "subagent denied: \$\$'a\\'; git stash; echo 'x' (PID, plain single quotes)" "$ok"

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

# --- (10c) deep-audit fix-round 3, 2026-09-20: _mask_quotes had no "#"
# comment awareness -- an ordinary comment apostrophe ("# don't remove")
# BEFORE a real git command opened an unterminated fake single-quote span
# (no closing "'" anywhere after it), masking every real char after it,
# including the literal "git" anchor -- live-confirmed full bypass of this
# entire gate for any dangerous subcommand, not just one flag. --- #
apostrophe_cmd="$(printf "echo hi # don't remove\ngit reset --hard")"
run_gate "$apostrophe_cmd" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "comment-apostrophe bypass fixed: git reset --hard after a # don't comment now denied" "$ok"

# Comment AFTER the real git call must still deny too (control: the fix must
# not swallow the anchor when the apostrophe comes later on the same line).
run_gate "git reset --hard # don't undo this" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "comment-apostrophe control: apostrophe after the anchor still denies" "$ok"

# 2026-09-21 deep-audit: ")" was missing from the masker's word-boundary set,
# so "(true)#don't" did not open a comment and its apostrophe swallowed the
# real "git stash" on the next line into a fake quote span -- silent ALLOW.
paren_comment_cmd="$(printf "(true)#don't\ngit stash")"
run_gate "$paren_comment_cmd" "agent1"; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "comment right after ')' then git stash on the next line: denied (was silently ALLOWed)" "$ok"

# --- (11) malformed/non-JSON stdin: fail-safe allow --- #
out=$(echo "not json" | bash "$GATE" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "malformed stdin: fail-safe allow, exit 0, no stdout" "$ok"

# --- (12) spelling variants (GH #213): the same denied verbs behind a wrapper the anchor did not
# know, a shell keyword, a bash -c / eval body, or a git global flag with a separate value --- #
sgg_rc() { payload "$1" fork | bash "$GATE" >/dev/null 2>&1; echo $?; }
for _c in \
  'exec git stash' \
  'timeout 5 git stash' \
  'gtimeout 5 git stash' \
  'setsid git stash' \
  'stdbuf -oL git stash' \
  'ionice -c3 git stash' \
  'env timeout=30 git stash' \
  'for i in 1; do git stash; done' \
  'while true; do git reset HEAD~1; done' \
  'until false; do git clean -n; done' \
  'if true; then git stash; fi' \
  'if false; then :; else git stash; fi' \
  '! git stash' \
  'coproc git stash' \
  'bash -c "git stash"' \
  "sh -c 'git stash'" \
  'zsh -lc "git reset HEAD~1"' \
  'sudo bash -c "git stash"' \
  'eval "git stash"' \
  'git --namespace x stash' \
  'git --attr-source HEAD stash' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
  check "spelling variant denied for a subagent: $_c" "$ok"
done
for _c in \
  'echo do git stash' \
  'git commit -m "then git stash"' \
  'git commit -m "run bash -c '"'"'git stash'"'"'"' \
  'bash -c "git status"' \
  'bash -c "git stash list"' \
  'timeout 5 git status' \
  'env timeout=30 git status' \
  'for i in 1; do git stash list; done' \
  'eval "git status"' \
  'git --namespace x status' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "0" ] && ok=0
  check "spelling-variant control allowed for a subagent: $_c" "$ok"
done

# --- (13) deep-audit 4 (2026-09-29): unquoted eval / builtin, and the rtk wrapper that
# irrecoverable.py's shared list gained (GH #216) while this file kept its own copy --- #
for _c in \
  'eval git stash' \
  'eval git reset --hard' \
  'eval git clean -fd' \
  'eval eval git stash' \
  'eval command git stash' \
  'builtin command git stash' \
  'builtin eval git stash' \
  'builtin exec git stash' \
  'eval exec git stash' \
  'eval -- git stash' \
  'rtk run git stash' \
  'rtk run --skip-env git stash' \
  'rtk proxy -- git stash' \
  'eval "eval git stash"' \
  "sh -c 'eval git stash'" \
  'rtk git stash' \
  'rtk proxy git stash' \
  'rtk proxy git reset --hard' \
  'rtk -v proxy git stash' \
  'rtk err git stash' \
  'rtk test git stash' \
  'rtk summary git stash' \
  "rtk run -c 'git stash'" \
  'rtk run --command "git reset --hard"' \
  'rtk run "git stash"' \
  'rtk err "git clean -fd"' \
  'rtk test "git stash"' \
  'rtk summary "git reset --hard"' \
  'rtk -v run "git stash"' \
  'rtk run --skip-env -c "git stash"' \
  "rtk run --command='git stash'" \
  'rtk run -- "git stash"' \
  'rtk run --ultra-compact "git reset HEAD~1"' \
  'rtk err --skip-env "git clean -fd"' \
  'rtk test --ultra-compact "git stash"' \
  'env eval=1 git stash' \
  'env builtin=1 git stash' \
  'env rtk=1 git stash' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
  check "eval/builtin/rtk spelling denied for a subagent: $_c" "$ok"
done
for _c in \
  'eval git status' \
  'eval git stash list' \
  'eval echo "git stash"' \
  'builtin echo hi' \
  'rtk git status' \
  'rtk proxy git stash list' \
  "rtk run -c 'git status'" \
  "rtk run --command='git status'" \
  'rtk grep "git stash" docs' \
  'eval=1 git status' \
  'builtin=1 git status' \
  'rtk=1 git status' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "0" ] && ok=0
  check "eval/builtin/rtk control allowed for a subagent: $_c" "$ok"
done

# Drift guard: every wrapper word in irrecoverable.py's PREFIX_WRAPPERS must also be a wrapper
# here (the two lists are typed by hand, GH #213). irrecoverable.py runs on import, so the two
# tuples are read from its source. A parse failure yields no words and fails the count check.
_wrappers=$(python3 - "$ROOT/hooks/gates/irrecoverable.py" <<'PY'
import ast, sys
env = {}
for n in ast.parse(open(sys.argv[1]).read()).body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") in ("FLAG_VALUE_WRAPPERS", "PREFIX_WRAPPERS"):
        exec(compile(ast.Module([n], []), "irrecoverable.py", "exec"), env)
print(*env.get("PREFIX_WRAPPERS", ()))
PY
)
_n=0; for _w in $_wrappers; do _n=$((_n + 1)); done
ok=1; [ "$_n" -ge 8 ] && ok=0
check "drift guard read $_n wrapper words from irrecoverable.py PREFIX_WRAPPERS (expect at least 8)" "$ok"
for _w in $_wrappers; do
  rc=$(sgg_rc "$_w git stash"); ok=1; [ "$rc" = "2" ] && ok=0
  check "irrecoverable wrapper word is a wrapper in the guard too: $_w git stash" "$ok"
  # command and exec are also in the guard's bounded chain, which hides their removal from the wrapper
  # list when the flag is absent; a flag before the command word only the wrapper walk can skip.
  rc=$(sgg_rc "$_w -x git stash"); ok=1; [ "$rc" = "2" ] && ok=0
  check "irrecoverable wrapper word is a wrapper in the guard too, flag before the command: $_w -x git stash" "$ok"
done

# --- (14) eval / builtin / rtk must not hide the statements after them (deep-audit 4, whole-picture
# pass). Putting them in the wrapper list made the greedy argument walk run across `;` / `&&` /
# newlines to the last `git`, so these went from denied to allowed. They now take a bounded prefix
# that never walks arguments. (The same leak after time, timeout, env and the other old wrappers
# is closed by the overlapping scan in section 15, GH #245.) --- #
for _c in \
  'eval "$(ssh-agent -s)" && git stash && git status' \
  'eval true; git stash; git status' \
  'rtk ls && git stash && git status' \
  'builtin cd /tmp && git clean -n && git status' \
  'rtk run -n||timeout 5 bash -c "git stash"; git status' \
  'rtk -v||git stash' \
  'rtk run -x&&git stash' \
  'rtk proxy -v;git stash' \
  'eval true; bash -c "git stash"; bash -c "git status"' \
  'builtin cd x && sh -c "git stash" && sh -c "git status"' \
  'rtk ls && eval "git stash" && eval "git status"' \
  $'eval "$(direnv export bash)"\ngit stash\ngit status' \
  $'rtk git status\ngit stash\ngit log -1' \
  'nohup >/dev/null 2>&1 git stash' \
  'env FOO=1 2>&1 git stash' \
  'env FOO=1 &>/dev/null git stash' \
  'env A=$(printf x) git stash' \
  'env A=\;x git stash' \
  'sudo -u $(id -un) git stash' \
  'env A=$(a b) FOO=1 git stash' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
  check "later statement still checked behind a wrapper: $_c" "$ok"
done
for _c in \
  'eval "$(ssh-agent -s)"; echo git stash done' \
  'time ls; git status; git log' \
  'eval true && git status && git log' \
  'env FOO=1 make; git stash list; git status' \
  'nohup >/dev/null 2>&1 git status' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "0" ] && ok=0
  check "walk-boundary control allowed for a subagent: $_c" "$ok"
done

# --- (15) GH #245: after an old wrapper (time, timeout, env, sudo, ...) the greedy argument walk
# crosses `;` / `&&` / `||` / `|` / newline to the LAST `git` (or shell word), and finditer resumed
# after that match, so an earlier statement was never checked. Anchors are now found by an
# overlapping scan, so every separator inside a walked span gets its own attempt. --- #
for _c in \
  'time ls; git stash; git status' \
  'timeout 5 ls && git reset --hard && git status' \
  'env FOO=1 make || git clean -fd; git status' \
  'sudo ls | git stash; git log -1' \
  'nice make; git -C /r stash; git status' \
  $'time ls\ngit stash\ngit status' \
  'time ls; bash -c "git stash"; bash -c "git status"' \
  'env A=1 ls && sh -c "git reset --hard" && sh -c "git log"' \
  'time ls; eval "git stash"; eval "git status"' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
  check "earlier statement behind an old wrapper still checked: $_c" "$ok"
done
for _c in \
  'time ls; git status; git log' \
  'timeout 5 make && git diff && git status' \
  'time ls; bash -c "git status"; bash -c "git log"' \
  'env FOO=1 make; git stash list; git status' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "0" ] && ok=0
  check "old-wrapper multi-statement control allowed: $_c" "$ok"
done

# --- (16) GH #246: every anchor scan is quadratic on padded input, and a hook past its 8 s timeout
# allows. Padding in front of a real `git stash` (5000 x `env ; `, 30 KB) walked around the deny.
# A shared work budget now denies a command too dense to scan, fast, and never scans it. --- #
_pad() { python3 -c 'import sys; sys.stdout.write(sys.argv[1] * int(sys.argv[2]))' "$1" "$2"; }
_t0=$(date +%s)
_c="git $(_pad '-c a ' 20000); git stash"  # the flag walk re-sliced the tail per flag (4.6 s at 1.25 MB; a Linux argv arg caps this row at 128 KB)
rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
check "long git flag run still reaches the deny (${#_c} bytes)" "$ok"
_PAD_ENV=$(_pad 'env ; ' 5000; printf x); _PAD_ENV=${_PAD_ENV%x}  # keep the trailing blank $(...) would strip
_PAD_NL=$(_pad $'\n' 6000; printf x); _PAD_NL=${_PAD_NL%x}  # $(...) strips trailing newlines
for _c in \
  "${_PAD_ENV}time ls; git stash; git status" \
  "${_PAD_ENV}git status" \
  "${_PAD_NL}git status" \
  "bash -c \"${_PAD_ENV}git status\"" \
  "eval '${_PAD_NL}git status'" ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
  check "padded command denied, not timed out into allow (${#_c} bytes): ${_c:0:30}" "$ok"
done
_out=$(payload "${_PAD_ENV}git status" fork | bash "$GATE" 2>&1 >/dev/null)
case "$_out" in *"too long or too dense"*) ok=0 ;; *) ok=1 ;; esac
check "over-budget deny names the reason and the way out" "$ok"
_el=$(( $(date +%s) - _t0 ))
ok=1; [ "$_el" -lt 8 ] && ok=0
check "all padded shapes decided well inside the 8 s hook timeout (${_el}s for the section)" "$ok"
for _c in \
  "echo $(_pad x 20000)" \
  "$(_pad $'echo hello world\n' 400)git status" \
  "$(_pad 'ls -la; ' 200)git log -1" ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "0" ] && ok=0
  check "long but ordinary command still allowed (${#_c} bytes): ${_c:0:30}" "$ok"
done

# GH #248: a wrapped FIRST statement (the greedy walk lands on the last git) and a brace group.
for _c in \
  'time git stash; git status' \
  'env A=1 git reset --hard; git status' \
  'timeout 5 git clean -fd && git status' \
  'xargs git stash; git status' \
  '{ git stash; }' \
  'true; { git reset --hard; }' \
  '{ git clean -fd; } 2>&1' \
  'bash -c "{ git stash; }"' \
  'bash -c "time git stash; git status"' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
  check "GH #248 denied: $_c" "$ok"
done
for _c in \
  'time git status; git log -1' \
  '{ git status; }' \
  'echo {a,b} git stash' \
  'git commit -m "{ git stash; }"' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "0" ] && ok=0
  check "GH #248 control still allowed: $_c" "$ok"
done

# --- (17) Deep-audit 5: the chain prefix (eval/builtin/command/exec/rtk) after a wrapper walk re-reads
# the rest of a chain run from every walk position, so a long run costs run x run per command start,
# which the separator x length charge never saw: `true; ` + `command ` x 8000 before a real
# `git stash` ran 9 s with one `;`, and a timed-out hook allows. Each row must be DECIDED inside 8 s:
# sgg_rc waits forever, so a late deny would read as a pass. --- #
sgg_rc8() {
  payload "$1" fork | python3 -c '
import os, signal, subprocess, sys
p = subprocess.Popen(["bash", sys.argv[1]], stdin=sys.stdin, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
try:
    print(p.wait(timeout=8))
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    print(124)
' "$GATE"
}
for _c in \
  "true; $(_pad 'command ' 8000)git stash; git status" \
  "time git stash; time $(_pad 'rtk -a ' 8000)ls" \
  "time git stash; git status; $(_pad 'time ; ' 50)$(_pad 'command ' 1000)ls" \
  "bash -c 'true; $(_pad 'command ' 8000)git stash; git status'" \
  "sudo $(_pad 'git -C ' 10000)x; time git stash; git status" ; do
  rc=$(sgg_rc8 "$_c"); ok=1; [ "$rc" = "2" ] && ok=0
  check "padded command denied inside 8 s, not timed out into allow (rc $rc, ${#_c} bytes): ${_c:0:30}" "$ok"
done
# The last row guards a dropped fix: a lazy target that looked ahead for the denied subcommand
# re-read a `git -C` run from every `git` (11 s at 70 KB). `sudo -u git git stash; git status` is
# still allowed, a known residual.
for _c in \
  'command -v git && git status' \
  'eval "$(ssh-agent -s)"; git status' \
  'rtk proxy git status' \
  'sudo -u git git status; git log -1' \
  'sudo -u git git stash list; git status' ; do
  rc=$(sgg_rc "$_c"); ok=1; [ "$rc" = "0" ] && ok=0
  check "chain and wrapper-argument control still allowed: $_c" "$ok"
done

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
