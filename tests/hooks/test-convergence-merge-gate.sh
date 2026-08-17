#!/usr/bin/env bash
# Behavioral tests for hooks/gates/convergence-merge-gate.sh -- this gate's
# FIRST persisted test coverage of any kind (confirmed zero references in
# test-gates.sh before this file was added, 2026-08-15).
#
# Built alongside a kbg:plan-reviewer-revised extension that gives this gate
# CODEOWNERS awareness (mirrors ship-merge.md step 7, which already had it).
# The plan-reviewer pass found 2 Critical bugs in the first draft:
#   - Critical #1: a DEFERRED CODEOWNERS verdict hard-blocked with no way
#     out, since ship-merge.md's own Phase 2 human confirmation for the
#     exact same case runs the exact same `gh pr merge` this gate
#     intercepts -- fixed by mapping DEFERRED to permissionDecision:"ask"
#     instead of a hard block.
#   - Critical #2: the pre-existing CI-check logic had TWO separate
#     sys.exit(0) allow points (the documented bottom one, and an earlier
#     one inside the "CI unreadable, empty stdout + rc==0" branch for a
#     repo with no CI configured) -- a naive fix moving only the bottom
#     exit would silently skip CODEOWNERS entirely on the no-CI-configured
#     path. Fixed by wrapping the CI logic in ci_check_passed(), which can
#     only return True or exit(2) itself, so there is exactly one place
#     code can fall through to an allow, and CODEOWNERS sits on that path.
#
# Part C below (CI-N/A x CODEOWNERS) exists specifically to pin Critical #2:
# these two cases were manually verified to FAIL against the pre-revision
# gate (git HEAD at the time this file was written) before being trusted
# green here -- same discipline as tests/commands/test-risk-check.sh's
# case 7 and test-ship-merge-codeowners.sh.
#
# Run standalone: bash tests/hooks/test-convergence-merge-gate.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/convergence-merge-gate.sh"

pass=0
fail=0

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/state" "$WORK/fakebin"

# A fake `gh` dispatching on subcommand, driven entirely by env vars so each
# test case just sets what it needs before calling run_gate. Mirrors the
# PATH-shim pattern already used in test-ship-merge-codeowners.sh's Part 3.
cat > "$WORK/fakebin/gh" <<'GHEOF'
#!/bin/bash
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
  printf '%s' "${FAKE_CI_CHECKS_JSON:-}"
  exit "${FAKE_CI_RC:-0}"
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  # Two distinct callers now hit `gh pr view`: the CI check (--json
  # statusCheckRollup, added when gh pr checks stopped working on gh
  # 2.95.0) and the pre-existing CODEOWNERS check (--json
  # headRefOid,files,reviews). Route on which --json fields were asked
  # for, same distinction the real gh CLI response shape carries.
  is_rollup=0
  for a in "$@"; do
    case "$a" in *statusCheckRollup*) is_rollup=1 ;; esac
  done
  if [ "$is_rollup" = "1" ]; then
    printf '{"statusCheckRollup":%s}' "${FAKE_CI_CHECKS_JSON:-[]}"
    exit "${FAKE_CI_RC:-0}"
  fi
  printf '%s' "${FAKE_PR_VIEW_JSON:-}"
  exit "${FAKE_PR_VIEW_RC:-0}"
fi
if [ "$1" = "api" ]; then
  if [ "${FAKE_CODEOWNERS_FOUND:-0}" = "1" ]; then
    printf '%s' "${FAKE_CODEOWNERS_CONTENT:-}"
    exit 0
  fi
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
echo "fake gh: unhandled invocation: $*" >&2
exit 1
GHEOF
chmod +x "$WORK/fakebin/gh"

merge_payload() { # merge_payload <pr_num>
  printf '{"tool_input":{"command":"gh pr merge %s"}}' "$1"
}

raw_payload() { # raw_payload <raw_shell_command_json_escaped>
  printf '{"tool_input":{"command":"%s"}}' "$1"
}

# run_gate <pr_num> [with_gh:0|1]
# Writes stdout to $WORK/out, stderr to $WORK/err, sets $rc.
run_gate() {
  local pr="$1" with_gh="${2:-1}"
  local p
  if [ "$with_gh" = "1" ]; then
    p="$WORK/fakebin:$PATH"
  else
    p="/usr/bin:/bin"  # deliberately no gh -- proves the fast path never spawns it
  fi
  printf '%s' "$(merge_payload "$pr")" \
    | PATH="$p" REVIEW_PR_STATE_DIR="$WORK/state" CLAUDE_PLUGIN_ROOT="$ROOT" \
      bash "$GATE" >"$WORK/out" 2>"$WORK/err"
  rc=$?
}

# run_gate_raw <json_escaped_command> [with_gh:0|1]
# Same as run_gate but takes a raw (already-escaped) command string instead
# of building "gh pr merge <N>" -- needed for the indirection test cases
# (issue #49), where the actual command text isn't the literal merge form.
run_gate_raw() {
  local cmd="$1" with_gh="${2:-1}"
  local p
  if [ "$with_gh" = "1" ]; then
    p="$WORK/fakebin:$PATH"
  else
    p="/usr/bin:/bin"
  fi
  printf '%s' "$(raw_payload "$cmd")" \
    | PATH="$p" REVIEW_PR_STATE_DIR="$WORK/state" CLAUDE_PLUGIN_ROOT="$ROOT" \
      bash "$GATE" >"$WORK/out" 2>"$WORK/err"
  rc=$?
}

pr_view_json() { # pr_view_json <files_json_array> <reviews_json_array>
  printf '{"headRefOid":"deadbeef","files":%s,"reviews":%s}' "$1" "$2"
}

state_clean_true() { printf '{"clean": true}' > "$WORK/state/review-pr-42.json"; }
state_clean_false() { printf '{"clean": false, "round": 3, "convergence_state": "critical_open"}' > "$WORK/state/review-pr-42.json"; }
state_clean_malformed() { printf '{"clean": "true"}' > "$WORK/state/review-pr-42.json"; }
rm_state() { rm -f "$WORK/state/review-pr-42.json"; }

echo "=== convergence-merge-gate: Part A -- pre-existing behavior baseline ==="

rm_state
printf '{"tool_input":{"command":"echo hello, not a merge"}}' \
  | PATH="/usr/bin:/bin" REVIEW_PR_STATE_DIR="$WORK/state" CLAUDE_PLUGIN_ROOT="$ROOT" \
    bash "$GATE" >"$WORK/out" 2>"$WORK/err"; rc=$?
check "non-merge command -> exit 0, no output, no gh needed (fast path)" \
  "$([ "$rc" -eq 0 ] && [ ! -s "$WORK/out" ] && echo 0 || echo 1)"

rm_state
run_gate 42 0
check "no state file -> allow, no gh needed" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

state_clean_malformed
run_gate 42 0
check "clean field wrong type -> block" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

state_clean_false
run_gate 42 0
check "clean: false -> block" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

state_clean_true
export KBG_SKIP_CODEOWNERS_GATE=1  # isolate the pre-existing CI layer only
FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 run_gate 42
check "clean: true + CI green -> allow" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"FAILURE"}]' FAKE_CI_RC=0 run_gate 42
check "clean: true + CI red -> block" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":null}]' FAKE_CI_RC=0 run_gate 42
check "clean: true + CI pending -> block" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='' FAKE_CI_RC=1 run_gate 42
check "clean: true + CI unreadable (gh errors) -> block" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
unset KBG_SKIP_CODEOWNERS_GATE

echo ""
echo "=== Part B -- CODEOWNERS x CI-green matrix ==="

state_clean_true
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='docs/* @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
check "CI green + CODEOWNERS PASS (no owned files touched) -> allow" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# The symmetric case the above never covers: an owner IS matched and DID
# approve, so the "reviews" half of the same gh pr view fetch has to reach
# evaluate() as a real list of {"author":{"login":...},"state":...} dicts,
# not just the "no owned files" trivial PASS. Every other case in this file
# passes reviews='[]' -- this is the only one where a real approval must be
# read back correctly. A shape mismatch here fails toward a false STOP on a
# legitimately-approved PR, the worst outcome this gate can produce.
# The approval's commit.oid must match headRefOid ("deadbeef" here, set by
# pr_view_json) -- issue #50's fix pins approval-counting to the PR's
# current head SHA, not just author+state.
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":"deadbeef"}}]')" \
  run_gate 42
ok=1; [ "$rc" -eq 0 ] && [ ! -s "$WORK/out" ] && ok=0
check "CI green + CODEOWNERS PASS (owner matched AND approved via real reviews array) -> allow" "$ok"

# issue #50 regression pin: an approval left on an EARLIER revision (commit
# oid != current headRefOid) must not count -- the owned files may have
# changed again since that approval was submitted.
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":"stale-sha-from-an-earlier-push"}}]')" \
  run_gate 42
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "CODEOWNER approval missing" "$WORK/err" && ok=0
check "REGRESSION PIN (#50): approval pinned to a stale SHA -> block, not counted as approved" "$ok"

FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "CODEOWNER approval missing" "$WORK/err" && ok=0
check "CI green + CODEOWNERS STOP (missing user approval) -> block" "$ok"

FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @org/team' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
ok=1; [ "$rc" -eq 0 ] && /usr/bin/grep -q '"permissionDecision": "ask"' "$WORK/out" && ok=0
check "CI green + CODEOWNERS DEFERRED (@org/team) -> ask (JSON shape)" "$ok"

FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=0 \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
check "CI green + no CODEOWNERS file anywhere (N/A) -> allow" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

echo ""
echo "=== Part C -- CI-N/A x CODEOWNERS (Critical #2 / High #1 regression pins) ==="
echo "    (manually verified to FAIL against the pre-revision gate -- see header)"

FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "CODEOWNER approval missing" "$WORK/err" && ok=0
check "REGRESSION PIN: CI N/A (no CI configured) + CODEOWNERS STOP -> still block" "$ok"

FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @org/team' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
ok=1; [ "$rc" -eq 0 ] && /usr/bin/grep -q '"permissionDecision": "ask"' "$WORK/out" && ok=0
check "REGRESSION PIN: CI N/A (no CI configured) + CODEOWNERS DEFERRED -> still ask" "$ok"

echo ""
echo "=== Part D -- gh pr view --json files extraction ==="

# A realistic multi-file gh pr view response: each file object carries extra
# fields (additions/deletions/etc) beyond "path" -- proves the extraction
# line (`f.get("path","") for f in pv.get("files", []) if isinstance(f, dict)`)
# doesn't choke on the real response shape, not just a hand-trimmed fixture.
REALISTIC_FILES='[{"path":"docs/readme.md","additions":1,"deletions":0},{"path":"src/owned.py","additions":5,"deletions":2}]'
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/owned.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json "$REALISTIC_FILES" '[]')" \
  run_gate 42
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "CODEOWNER approval missing" "$WORK/err" && ok=0
check "realistic multi-field --json files response correctly extracts owned path -> block" "$ok"

echo ""
echo "=== Part E -- KBG_SKIP_CODEOWNERS_GATE=1 kill switch (narrow scope) ==="

export KBG_SKIP_CODEOWNERS_GATE=1
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
check "kill switch ON + CI green + would-be CODEOWNERS STOP -> allow (CODEOWNERS skipped)" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

state_clean_false
run_gate 42 0
check "kill switch ON does NOT bypass the pre-existing clean check (still blocks)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
unset KBG_SKIP_CODEOWNERS_GATE

echo ""
echo "=== Part F -- CODEOWNERS import resolves without CLAUDE_PLUGIN_ROOT ==="
# Pins the fix: lib_dir used to be built from CLAUDE_PLUGIN_ROOT alone, so an
# empty/unset var (any install where the hook is invoked without it set)
# silently hard-blocked every clean, CI-green merge on an import failure.
# gate_dir now resolves from $0 (how hooks.json actually invokes this file)
# first -- this case runs the SAME gate binary with CLAUDE_PLUGIN_ROOT
# explicitly unset and confirms the CODEOWNERS import still succeeds.
state_clean_true
printf '%s' "$(merge_payload 42)" \
  | PATH="$WORK/fakebin:$PATH" REVIEW_PR_STATE_DIR="$WORK/state" \
    FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
    FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
    FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
    bash "$GATE" >/dev/null 2>"$WORK/err"
rc=$?
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "CODEOWNER approval missing" "$WORK/err" && ok=0
check "CLAUDE_PLUGIN_ROOT unset -> CODEOWNERS import still resolves via \$0, check still runs" "$ok"

echo ""
echo "=== Part G -- regression pin: gh pr view response missing 'files' key -> fail closed ==="
# Pins the fix: changed_files used to be built via pv.get("files", []), so a
# malformed/incomplete gh pr view response (key absent, not just empty) was
# silently read as "zero changed files" -> evaluate() returns PASS regardless
# of what CODEOWNERS actually protects. This is the same class of gap already
# closed for headRefOid; files now gets the identical fail-closed treatment.
state_clean_true
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON='{"headRefOid":"deadbeef","reviews":[]}' \
  run_gate 42
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "PR file list unreadable" "$WORK/err" && ok=0
check "REGRESSION PIN: gh pr view response missing 'files' key -> block, not silent allow" "$ok"

# The fix must not overreach: a PR that genuinely has zero changed files
# (files: [], key present) still has to reach the existing no-owned-files PASS.
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[]' '[]')" \
  run_gate 42
check "files: [] (genuinely zero changed files, key present) -> still allow" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

echo ""
echo "=== Part H -- shell-indirection bypasses (issue #49) ==="
# Confirmed 2026-08-15: both these commands returned rc=0 (silent allow)
# against a clean:false state on the pre-fix gate -- a real bypass, not a
# hypothetical. Manually re-verified against the pre-fix code before trusting
# these green, same discipline as Part C.

state_clean_false
run_gate_raw 'bash -c \"gh pr merge 42\"' 0
check "REGRESSION PIN: bash -c wrapper on non-clean review -> block (was silent allow)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'GH=gh; $GH pr merge 42' 0
check "REGRESSION PIN: VAR=value; \$VAR indirection on non-clean review -> block (was silent allow)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'M=merge; gh pr $M 42' 0
check "sibling case: non-contiguous gh...merge via mid-command var -> block (was silent allow)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

# Confirmed 2026-08-15 by a code-review agent AFTER 2112bcd (the first #49
# fix) had already shipped: three more bypasses, all rc=0 against that
# commit. Manually re-verified against 2112bcd before trusting these green.
run_gate_raw 'git pull;gh pr merge 42' 0
check "REGRESSION PIN: bare semicolon, zero indirection syntax -> block (Finding A, shlex never split on ;)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'bash -ec \"gh pr merge 42\"' 0
check "REGRESSION PIN: bundled short flags -ec -> block (Finding B, -c regex required its own token)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'GH=gh; GHX=merge; $GH pr $GHX 42' 0
check "REGRESSION PIN: variable-name substring collision, GH is a prefix of GHX -> block (Finding C)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'GH=gh;$GH pr merge 42' 0
check "no-space variant of VAR indirection (GH=gh;\$GH, no space after ;) -> block" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

# The fix must not overreach: resolution on a CLEAN, CI-green review must
# still allow -- proves indirection got resolved to a real merge and
# evaluated normally, not just blanket-blocked.
state_clean_true
export KBG_SKIP_CODEOWNERS_GATE=1
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 run_gate_raw 'bash -c \"gh pr merge 42\"'
check "clean + CI green through bash -c wrapper -> allow (resolution, not blanket block)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 run_gate_raw 'GH=gh; $GH pr merge 42'
check "clean + CI green through VAR indirection -> allow (resolution, not blanket block)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
unset KBG_SKIP_CODEOWNERS_GATE

# False-positive guards: prose mentioning gh/merge, or an unrelated $VAR
# embedded in a quoted string, must not trip the residual fail-closed check.
rm_state
run_gate_raw 'echo \"$HOME: run gh pr merge later\"' 0
check "unrelated \$HOME next to gh/merge prose -> allow, no false block" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

run_gate_raw 'echo \"talking about gh pr merge\" && bash -c \"ls -la\"' 0
check "bash -c wrapper with unrelated payload beside gh/merge prose -> allow" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# Named ceiling: command substitution is never resolved. Whether that's a
# block now depends on whether there's a state file to protect (MEDIUM fix,
# 2026-08-15): no state -> nothing for this gate to check -> allow, matching
# the documented "no state file -> allow" philosophy this gate already
# applies to a CONFIRMED merge below. A state file present -> still fail
# closed, unchanged.
run_gate_raw 'XPR=$(echo gh); $XPR pr merge 42' 0
check "unresolvable command substitution, NO state file -> allow (MEDIUM fix: nothing to protect)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# A residual-ambiguous command never has a confirmed pr_num, so it can't
# check ONE specific keyed file -- it scans both review-pr-*.json and
# review-last.json and blocks if any is non-clean. Pin with the unkeyed
# layout here (own-branch reviews).
printf '{"clean": false, "round": 3, "convergence_state": "critical_open"}' > "$WORK/state/review-last.json"
run_gate_raw 'XPR=$(echo gh); $XPR pr merge 42' 0
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "statically resolve" "$WORK/err" && ok=0
check "unresolvable command substitution, non-clean state present -> fail closed (named ceiling, not silently allowed)" "$ok"
rm -f "$WORK/state/review-last.json"
rm_state

echo ""
echo "=== Part I -- round 2 findings (issue #49, post-2112bcd adversarial review) ==="
# A code-review agent actually EXECUTED the round-1 fix (2112bcd, already
# pushed) against fresh adversarial payloads and found two more confirmed
# rc=0 bypasses, both re-verified against that commit before trusting these
# green -- same discipline as Parts C and H above.

# Finding 1: `cmd.replace("\n", " ")` alone turned real bash backslash-
# newline continuation ("\"+NL) into "\ " (backslash-space), which
# shlex(posix=True) reads as an ESCAPED space folded into the next token
# ("merge" -> " merge"), breaking the has_merge adjacency check. Needs a
# state file present (keyed-only, the realistic layout) to prove it's a
# real bypass and not just "no state to protect anyway".
state_clean_false
run_gate_raw 'gh pr \\\nmerge 42' 0
check "REGRESSION PIN: backslash-newline continuation before merge -> block (Finding 1, round 2)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'gh \\\npr merge 42' 0
check "REGRESSION PIN: backslash-newline continuation before pr -> block (Finding 1, round 2)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

# Finding 2: the residual/ambiguous fail-closed check looked ONLY at the
# unkeyed review-last.json. write-review-state.sh writes ONLY the keyed
# review-pr-<N>.json for a PR-by-number review (skills/review-pr/scripts/
# write-review-state.sh:99-102) -- the realistic shape a non-clean review
# actually leaves on disk. state_clean_false() here writes ONLY the keyed
# file, same as that real flow -- this is the gap, not a contrived setup.
run_gate_raw 'eval \"gh pr merge 42\"' 0
check "REGRESSION PIN: eval wrapper, KEYED-ONLY state (real review-pr layout) -> block (Finding 2, round 2)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw '`echo gh pr merge 42`' 0
check "REGRESSION PIN: backtick command substitution, keyed-only state -> block (Finding 2, round 2)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'GH=gh; eval $GH pr merge 42' 0
check "REGRESSION PIN: eval + VAR indirection combined, keyed-only state -> block (Finding 2, round 2)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'bash -c \"bash -c \\\"gh pr merge 42\\\"\"' 0
check "nested bash -c bash -c, keyed-only state -> block (residual -c regex catches it independent of double-unwrap)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'gh pr merge 42 $(true)' 0
check "confirmed-looking merge with trailing \$(...), keyed-only state -> block (opaque indirection forces ambiguous path)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
rm_state

# The fix must not overreach: an ambiguous command with only an UNRELATED
# clean:true state file on disk (for a different PR) must still allow --
# proves the check reads the `clean` field, not just file existence (the
# MEDIUM finding the round-1 fix introduced).
printf '{"clean": true}' > "$WORK/state/review-pr-99.json"
run_gate_raw 'eval \"gh pr merge 42\"' 0
check "ambiguous command, only an unrelated PR's clean:true state exists -> allow (reads clean, not just existence)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
rm -f "$WORK/state/review-pr-99.json"

echo ""
echo "=== Part J -- round 3 finding: confirmed merge with no resolvable PR number ==="
# A third review round (this time scoped to just the round-2 fixes) found the
# CONFIRMED-merge path (has_merge=True, zero shell tricks) had the identical
# gap Finding 2 had already closed on the ambiguous path: `gh pr merge` with
# no PR number in the command text -- bare, --squash-only, a branch name, or
# a URL -- never sets pr_num, so the keyed lookup is skipped, no unkeyed
# review-last.json exists either (write-review-state.sh writes only the
# keyed file for a PR-by-number review), and the old code took that as
# "unreviewed merge, not this gate's concern" and allowed. `gh pr merge`
# resolves ALL of those forms from the current branch -- this is the single
# most common way to type the command, not an edge case. All 4 confirmed
# rc=0 against the round-2 code before this fix.
state_clean_false
run_gate_raw 'gh pr merge' 0
check "REGRESSION PIN: bare gh pr merge, keyed-only state -> block (Finding, round 3)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'gh pr merge --squash' 0
check "REGRESSION PIN: gh pr merge --squash (no number), keyed-only state -> block (Finding, round 3)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'gh pr merge feature-x' 0
check "REGRESSION PIN: gh pr merge <branch-name>, keyed-only state -> block (Finding, round 3)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

run_gate_raw 'gh pr merge https://github.com/o/r/pull/42' 0
check "REGRESSION PIN: gh pr merge <URL>, keyed-only state -> block (Finding, round 3)" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
rm_state

# Must not overreach: truly nothing on disk, or only an unrelated clean
# review, still allows a bare merge -- same "no state file -> allow"
# philosophy, just now correctly scoped to "no AT-RISK state" instead of
# "no file matching this exact selector".
run_gate_raw 'gh pr merge' 0
check "bare gh pr merge, NO state at all -> allow (nothing to protect)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

printf '{"clean": true}' > "$WORK/state/review-pr-99.json"
run_gate_raw 'gh pr merge' 0
check "bare gh pr merge, only an unrelated PR's clean:true state exists -> allow" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
rm -f "$WORK/state/review-pr-99.json"

echo ""
echo "=== Part K -- round 4 finding: known-but-unreviewed PR must not inherit an unrelated PR's non-clean state ==="
# A 4th review round found the round-3 fix (Part J above) over-broadened: it
# gated the _any_at_risk_state() fallback on state_file being None, which
# also fires for a PLAUSIBLE, KNOWN PR NUMBER that simply has no review file
# yet -- not just genuinely ambiguous selectors. That turned a previously
# inert case (old code: state_file is None -> unconditional allow) into a
# false block on a merge the gate can actually name, just because some
# UNRELATED PR's state happens to be non-clean. Confirmed rc=2 against the
# round-3 code before this fix.
state_clean_false  # unrelated PR 42, non-clean
run_gate_raw 'gh pr merge 999' 0
check "REGRESSION PIN (round 4): gh pr merge 999 (known PR, never reviewed), unrelated PR 42 non-clean -> allow (named target, simply unreviewed -- not ambiguous)" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
rm_state

echo ""
echo "=== Part L -- issue #51 fix: value-taking gh pr merge flags no longer swallow pr_num ==="
# FIXED (github.com/wasikarn/kbg-harness/issues/51): a value-taking flag in
# separated-token form (--repo owner/repo, not --repo=owner/repo) used to
# swallow the NEXT token as pr_num instead of skipping past it. The
# extraction loop now consults an explicit allowlist of gh pr merge's
# value-taking flags (verified against cli/cli's pkg/cmd/pr/merge/merge.go
# + cli.github.com/manual/gh_pr_merge, gh 2.95.0) and skips both the flag
# and its value token. These cases were manually confirmed to resolve
# pr_num="owner/repo" (wrong) and rc=2 (block) against the pre-fix gate
# before being trusted here -- same discipline as every prior "REGRESSION
# PIN" case in this file.
state_clean_true  # review-pr-42.json clean:true (the PR actually being merged)
printf '{"clean": false}' > "$WORK/state/review-pr-7.json"  # unrelated PR, non-clean
export KBG_SKIP_CODEOWNERS_GATE=1  # isolate the pr_num-extraction fix from the CODEOWNERS layer
FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge --repo owner/repo 42'
check "FIX: --repo owner/repo 42 correctly resolves pr_num=42 (long form, unrelated PR 7 non-clean is irrelevant) -> allow" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge -R owner/repo 42'
check "FIX: -R owner/repo 42 correctly resolves pr_num=42 (short form) -> allow" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

# kbg:code-reviewer (issue #51 review pass) flagged that only -R had short-form
# coverage -- the other three short flags are added to _MERGE_VALUE_FLAGS by
# this same diff and are exactly where a future wrong-shorthand edit would
# ship silently green. One case per remaining short flag closes the gap.
FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge -A a@b.com 42'
check "FIX: -A a@b.com 42 correctly resolves pr_num=42 (short form of --author-email)" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge -b \"see CHANGELOG\" 42'
check "FIX: -b \"see CHANGELOG\" 42 correctly resolves pr_num=42 (short form of --body)" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge -F /tmp/body.txt 42'
check "FIX: -F /tmp/body.txt 42 correctly resolves pr_num=42 (short form of --body-file)" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge -t \"release notes\" 42'
check "FIX: -t \"release notes\" 42 correctly resolves pr_num=42 (short form of --subject)" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge --subject \"release notes\" --body \"see CHANGELOG\" --repo owner/repo 42'
check "FIX: three chained value-flags (--subject, --body, --repo) before the PR number all skip correctly -> allow" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge --repo=owner/repo 42'
check "no regression: glued --repo=owner/repo (single token, already skipped pre-fix) -> allow" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
unset KBG_SKIP_CODEOWNERS_GATE
rm_state
rm -f "$WORK/state/review-pr-7.json"

# The negative direction must still work: a correctly-resolved pr_num=42
# whose OWN state is non-clean blocks for the right reason (reading
# clean:false directly), not via the ambiguity backstop.
state_clean_false  # review-pr-42.json clean:false
run_gate_raw 'gh pr merge --repo owner/repo 42' 0
check "FIX, negative direction: --repo owner/repo 42 resolves pr_num=42, PR 42 itself is clean:false -> block" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
rm_state

# A value-taking flag with nothing after it (no PR number at all) must still
# fall through to "unresolved" -- not crash, not wrongly resolve.
state_clean_false  # unrelated PR 42 non-clean (only file on disk)
run_gate_raw 'gh pr merge --repo owner/repo' 0
check "value-taking flag with no trailing PR number -> pr_num stays unresolved, falls through to the at-risk backstop (block)" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
rm_state

# Compliance-audit gap (kbg:compliance-audit V1, 2026-08-15): a correctly-
# resolved pr_num that names a KNOWN, SPECIFIC PR with no review file of its
# own must still hit Part K's "known PR, simply unreviewed" allow logic
# (line ~326-327, unchanged by this fix) -- an unrelated PR's non-clean
# state elsewhere on disk must not punish it. Part L's other FIX cases all
# use review-pr-42.json clean:true for the resolved target; none exercised
# "resolved via a value-taking flag, but the resolved PR has NO state file
# at all". Correctly allows on the current code -- pinning it as a
# regression guard now that the extraction fix makes this combination newly
# reachable through a value-taking flag.
state_clean_false  # unrelated PR 42, non-clean (only file on disk)
run_gate_raw 'gh pr merge --repo owner/repo 999' 0
check "FIX + Part K interaction: --repo owner/repo 999 resolves pr_num=999 (no state file for 999), unrelated PR 42 non-clean -> allow (named target, simply unreviewed -- not ambiguous)" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
rm_state

echo ""
echo "=== Part M -- deep-audit gap: combined short-flag clusters (e.g. -db) ==="
# Found by kbg:deep-audit, 2026-08-15, cross-checked against the advisor
# review and against spf13/pflag's own parseSingleShortArg before being
# trusted here (same discipline as every other pinned case in this file).
# gh, like every pflag/cobra CLI, lets short boolean flags cluster with a
# trailing value-taking short flag: -db means -d (delete-branch, takes no
# value) followed by -b (body, takes the NEXT token as its value) -- NOT
# a single unknown flag named "db". Part L's allowlist only matched exact
# flag strings ("-b" alone), so a cluster like "-db" was not recognized as
# value-taking at all, and the token right after it (the intended PR
# number) got wrongly captured as -b's swallowed value instead of being
# skipped -- reopening exactly the bug class issue #51 named, through a
# flag SHAPE the original fix did not enumerate.
# github.com/wasikarn/kbg-harness/issues/51
export KBG_SKIP_CODEOWNERS_GATE=1

state_clean_false  # PR 42 (the real target) is non-clean; no state file for 123 at all
run_gate_raw 'gh pr merge -db 123 42'
check "SECURITY: -db 123 42 must resolve pr_num=42 (not 123, the value -b swallows from the cluster) -> PR 42 non-clean -> block" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
rm_state

state_clean_true  # PR 42 clean:true
FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge -db 123 42'
check "FIX: -db 123 42 correctly resolves pr_num=42, PR 42 clean:true -> allow" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
rm_state

state_clean_true  # PR 42 clean:true
FAKE_CI_CHECKS_JSON='[{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 \
  run_gate_raw 'gh pr merge -dR owner/repo 42'
check "FIX: -dR owner/repo 42 (cluster ending in a different value-taking short flag) correctly resolves pr_num=42 -> allow" \
  "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"
rm_state

state_clean_false  # PR 42 non-clean
run_gate_raw 'gh pr merge -ds 42'
check "no regression: -ds (an all-boolean cluster, delete-branch + squash, no trailing value flag) still correctly resolves pr_num=42 -> block" \
  "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"
rm_state
unset KBG_SKIP_CODEOWNERS_GATE

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
