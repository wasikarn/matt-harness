#!/usr/bin/env bash
# test-merge-pr.sh — GH #450: scripts/merge-pr.sh merges only a PR whose head
# contains the origin/develop tip, pinned with --match-head-commit. Stubs gh,
# git and uptime on PATH; never touches GitHub. Each failing case also checks
# that `gh pr merge` was never reached (or, for a head mismatch, that it was
# reached with the checked sha and its refusal propagated).
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../scripts/merge-pr.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }
safe_trash() { [ -n "${1:-}" ] && trash "$1" 2>/dev/null; return 0; }

echo "=== merge-pr.sh requires an up-to-date head (GH #450) ==="

STUB=$(mktemp -d)
if [ -z "$STUB" ]; then echo "mktemp -d failed" >&2; exit 1; fi
LOG="$STUB/calls.log"

# gh: `pr view --json headRefOid` prints STUB_HEAD; `pr merge` refuses unless
# --match-head-commit equals STUB_REMOTE_HEAD (GitHub's real behaviour);
# `pr view --json mergeCommit` prints the merge sha.
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$STUB_LOG"
case "$*" in
  *"pr merge"*)
    want=""; prev=""
    for a in "$@"; do [ "$prev" = "--match-head-commit" ] && want="$a"; prev="$a"; done
    [ "$want" = "$STUB_REMOTE_HEAD" ] || { echo "head branch was modified" >&2; exit 1; }
    exit 0 ;;
  *baseRefName*) echo "$STUB_HEAD ${STUB_BASE:-develop}" ;;
  *headRefOid*) echo "$STUB_HEAD" ;;
  *mergeCommit*) echo "mergesha000" ;;
  *) exit 2 ;;
esac
EOF
# git: fetch succeeds; merge-base --is-ancestor exits STUB_ANCESTOR.
cat >"$STUB/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$STUB_LOG"
case "$1" in
  fetch) exit 0 ;;
  merge-base) exit "$STUB_ANCESTOR" ;;
  *) exit 2 ;;
esac
EOF
cat >"$STUB/uptime" <<'EOF'
#!/usr/bin/env bash
echo "10:00  up 1 day, 2 users, load averages: $STUB_LOAD 2.00 2.00"
EOF
chmod +x "$STUB/gh" "$STUB/git" "$STUB/uptime"

# run <ancestor-rc> <remote-head> <load>; sets out, rc
run() {
  : >"$LOG"
  out=$(PATH="$STUB:$PATH" STUB_LOG="$LOG" STUB_HEAD=headsha111 \
    STUB_ANCESTOR="$1" STUB_REMOTE_HEAD="$2" STUB_LOAD="$3" \
    MERGE_PR_LOAD_WAIT_SECS=0 bash "$SCRIPT" 451 2>&1)
  rc=$?
}
merged() { /usr/bin/grep -q '^gh pr merge' "$LOG"; }

# 1. up to date: merges with the checked head pinned, prints the merge sha.
run 0 headsha111 1.50
if [ "$rc" -eq 0 ]; then ok "up-to-date PR exits 0"; else bad "up-to-date PR rc=$rc: $out"; fi
if /usr/bin/grep -q '^gh pr merge 451 --merge --match-head-commit headsha111$' "$LOG"; then
  ok "merge is pinned to the checked head sha"
else bad "merge call not pinned: $(cat "$LOG")"; fi
if [ "$(printf '%s\n' "$out" | tail -n 1)" = "mergesha000" ]; then
  ok "last line is the merge commit sha"
else bad "last line is not the merge sha: <$out>"; fi
if /usr/bin/grep -q '^git merge-base --is-ancestor origin/develop headsha111$' "$LOG"; then
  ok "ancestry checked against origin/develop"
else bad "no ancestry check: $(cat "$LOG")"; fi

# 2. behind: fails before merging, tells the agent to rebase.
run 1 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "behind PR exits non-zero (rc=$rc)"; else bad "behind PR exited 0"; fi
if merged; then bad "behind PR still reached gh pr merge"; else ok "behind PR never calls gh pr merge"; fi
if printf '%s' "$out" | /usr/bin/grep -qi 'rebase on origin/develop'; then ok "behind message says rebase"; else bad "no rebase hint: $out"; fi

# 3. head mismatch: a push landed after the check; GitHub refuses, script fails.
run 0 othersha999 1.50
if [ "$rc" -ne 0 ]; then ok "head mismatch exits non-zero (rc=$rc)"; else bad "head mismatch exited 0"; fi
if merged; then ok "head mismatch reached gh pr merge with the checked sha"; else bad "head mismatch never tried the merge"; fi
if printf '%s' "$out" | /usr/bin/grep -q 'mergesha000'; then bad "head mismatch printed a merge sha"; else ok "head mismatch prints no merge sha"; fi

# 4. load stays high: fails with the figure, no merge.
run 0 headsha111 7.25
if [ "$rc" -ne 0 ]; then ok "high load exits non-zero (rc=$rc)"; else bad "high load exited 0"; fi
if merged; then bad "high load still reached gh pr merge"; else ok "high load never calls gh pr merge"; fi
if printf '%s' "$out" | /usr/bin/grep -q '7.25'; then ok "high load message carries the figure"; else bad "no load figure: $out"; fi

# 4b. PR targets another branch: the develop ancestry check proves nothing, so refuse.
out=$(PATH="$STUB:$PATH" STUB_LOG="$LOG" STUB_HEAD=headsha111 STUB_BASE=main \
  STUB_ANCESTOR=0 STUB_REMOTE_HEAD=headsha111 STUB_LOAD=1.50 bash "$SCRIPT" 451 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then ok "non-develop base exits non-zero (rc=$rc)"; else bad "non-develop base exited 0"; fi
if merged; then bad "non-develop base still reached gh pr merge"; else ok "non-develop base never calls gh pr merge"; fi

# 5. no PR argument: usage error.
out=$(PATH="$STUB:$PATH" STUB_LOG="$LOG" bash "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then ok "missing PR argument exits non-zero"; else bad "missing PR argument exited 0"; fi

safe_trash "$STUB"
echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
