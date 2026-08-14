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
FAKE_CI_CHECKS_JSON='[{"name":"build","conclusion":"SUCCESS"}]' FAKE_CI_RC=0 run_gate 42
check "clean: true + CI green -> allow" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"name":"build","conclusion":"FAILURE"}]' FAKE_CI_RC=0 run_gate 42
check "clean: true + CI red -> block" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)"

FAKE_CI_CHECKS_JSON='[{"name":"build","conclusion":null}]' FAKE_CI_RC=0 run_gate 42
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
FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[{"author":{"login":"alice"},"state":"APPROVED"}]')" \
  run_gate 42
ok=1; [ "$rc" -eq 0 ] && [ ! -s "$WORK/out" ] && ok=0
check "CI green + CODEOWNERS PASS (owner matched AND approved via real reviews array) -> allow" "$ok"

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

FAKE_CI_CHECKS_JSON='' FAKE_CI_RC=0 \
FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
  run_gate 42
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "CODEOWNER approval missing" "$WORK/err" && ok=0
check "REGRESSION PIN: CI N/A (no CI configured) + CODEOWNERS STOP -> still block" "$ok"

FAKE_CI_CHECKS_JSON='' FAKE_CI_RC=0 \
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
out=$(printf '%s' "$(merge_payload 42)" \
  | PATH="$WORK/fakebin:$PATH" REVIEW_PR_STATE_DIR="$WORK/state" \
    FAKE_CI_CHECKS_JSON='[]' FAKE_CI_RC=0 \
    FAKE_CODEOWNERS_FOUND=1 FAKE_CODEOWNERS_CONTENT='src/a.py @alice' \
    FAKE_PR_VIEW_JSON="$(pr_view_json '[{"path":"src/a.py"}]' '[]')" \
    bash "$GATE" 2>"$WORK/err")
rc=$?
ok=1; [ "$rc" -eq 2 ] && /usr/bin/grep -q "CODEOWNER approval missing" "$WORK/err" && ok=0
check "CLAUDE_PLUGIN_ROOT unset -> CODEOWNERS import still resolves via \$0, check still runs" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
