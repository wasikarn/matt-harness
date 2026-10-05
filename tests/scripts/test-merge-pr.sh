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

# gh: `pr view --json headRefOid,baseRefName` prints "STUB_HEAD STUB_BASE" (nothing when
# STUB_EMPTY is set); `pr view --json baseRefName` prints STUB_BASE2, else STUB_BASE, else
# develop (the re-read just before the merge); `pr merge` refuses unless
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
  *headRefOid,baseRefName*) [ -n "${STUB_EMPTY:-}" ] || echo "$STUB_HEAD ${STUB_BASE:-develop}" ;;
  *baseRefName*) echo "${STUB_BASE2:-${STUB_BASE:-develop}}" ;;
  *mergeCommit*) echo "mergesha000" ;;
  *) exit 2 ;;
esac
EOF
# git: fetch succeeds; merge-base --is-ancestor exits STUB_ANCESTOR on its first call and
# STUB_ANCESTOR2 (default STUB_ANCESTOR) on later ones (develop moved during the load wait);
# `show <ref>:.claude-plugin/plugin.json` prints a manifest whose version is STUB_HEAD_VER
# for the PR head and STUB_DEV_VER for origin/develop.
cat >"$STUB/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$STUB_LOG"
case "$1" in
  fetch) exit 0 ;;
  merge-base)
    n=$(/usr/bin/grep -c '^git merge-base' "$STUB_LOG")
    if [ "$n" -gt 1 ]; then exit "${STUB_ANCESTOR2:-$STUB_ANCESTOR}"; fi
    exit "$STUB_ANCESTOR" ;;
  show)
    [ -z "${STUB_SHOW_FAIL:-}" ] || { echo "fatal: path does not exist" >&2; exit 128; }
    case "$2" in
      origin/develop:*) v="$STUB_DEV_VER" ;;
      *:.claude-plugin/marketplace.json) v="${STUB_HEAD_MKT_VER-$STUB_HEAD_VER}" ;;
      *) v="$STUB_HEAD_VER" ;;
    esac
    printf '{\n  "version": "%s"\n}\n' "$v" ;;
  *) exit 2 ;;
esac
EOF
cat >"$STUB/uptime" <<'EOF'
#!/usr/bin/env bash
echo "10:00  up 1 day, 2 users, load averages: $STUB_LOAD 2.00 2.00"
EOF
chmod +x "$STUB/gh" "$STUB/git" "$STUB/uptime"

# run <ancestor-rc> <remote-head> <load>; sets out, rc. Extra stub env (STUB_BASE,
# STUB_BASE2, STUB_EMPTY) comes from the caller's environment.
run() {
  : >"$LOG"
  out=$(PATH="$STUB:$PATH" STUB_LOG="$LOG" STUB_HEAD=headsha111 \
    STUB_ANCESTOR="$1" STUB_REMOTE_HEAD="$2" STUB_LOAD="$3" \
    STUB_HEAD_VER="${STUB_HEAD_VER-1.1.2}" STUB_DEV_VER="${STUB_DEV_VER-1.1.1}" \
    MERGE_PR_LOAD_WAIT_SECS=0 MERGE_PR_LOAD_MAX=4 bash "$SCRIPT" 451 2>&1)
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
STUB_BASE=main run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "non-develop base exits non-zero (rc=$rc)"; else bad "non-develop base exited 0"; fi
if merged; then bad "non-develop base still reached gh pr merge"; else ok "non-develop base never calls gh pr merge"; fi
if printf '%s' "$out" | /usr/bin/grep -q "not develop"; then ok "non-develop message names the base"; else bad "no base message: $out"; fi

# 4c. base retargeted while waiting for load: the re-read before the merge refuses.
STUB_BASE2=main run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "retargeted base exits non-zero (rc=$rc)"; else bad "retargeted base exited 0"; fi
if merged; then bad "retargeted base still reached gh pr merge"; else ok "retargeted base never calls gh pr merge"; fi

# 4d. gh prints nothing: refuse before any merge.
STUB_EMPTY=1 run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "empty gh output exits non-zero (rc=$rc)"; else bad "empty gh output exited 0"; fi
if merged; then bad "empty gh output still reached gh pr merge"; else ok "empty gh output never calls gh pr merge"; fi

# 4e. develop moved during the load wait: the first ancestry check passed, the second fails.
STUB_ANCESTOR2=1 run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "develop moved after the first check exits non-zero (rc=$rc)"; else bad "moved develop exited 0"; fi
if merged; then bad "moved develop still reached gh pr merge"; else ok "moved develop never calls gh pr merge"; fi
if [ "$(/usr/bin/grep -c '^git merge-base' "$LOG")" -eq 2 ]; then ok "ancestry re-checked after the wait"; else bad "ancestry not re-checked: $(cat "$LOG")"; fi

# 4f. same manifest version as origin/develop: refuse before merging (identical bumps rebase away).
STUB_HEAD_VER=1.1.5 STUB_DEV_VER=1.1.5 run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "same version exits non-zero (rc=$rc)"; else bad "same version exited 0"; fi
if merged; then bad "same version still reached gh pr merge"; else ok "same version never calls gh pr merge"; fi
if printf '%s' "$out" | /usr/bin/grep -q '1.1.5'; then ok "same-version message carries the version"; else bad "no version in message: $out"; fi

# 4g. opt-out for a PR that needs no bump.
MERGE_PR_ALLOW_SAME_VERSION=1 STUB_HEAD_VER=1.1.5 STUB_DEV_VER=1.1.5 run 0 headsha111 1.50
if [ "$rc" -eq 0 ]; then ok "same version with the opt-out merges"; else bad "opt-out rc=$rc: $out"; fi

# 4h. unreadable manifest version: refuse.
STUB_HEAD_VER='' run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "unreadable version exits non-zero (rc=$rc)"; else bad "unreadable version exited 0"; fi
if merged; then bad "unreadable version still reached gh pr merge"; else ok "unreadable version never calls gh pr merge"; fi
if printf '%s' "$out" | /usr/bin/grep -q 'could not read'; then ok "unreadable version says so"; else bad "no unreadable-version message: $out"; fi

# 4i. a same-version head fails fast, before the load wait (load 7.25 would otherwise wait).
STUB_HEAD_VER=1.1.5 STUB_DEV_VER=1.1.5 run 0 headsha111 7.25
if printf '%s' "$out" | /usr/bin/grep -q '1.1.5' && ! printf '%s' "$out" | /usr/bin/grep -q 'load'; then
  ok "same version is refused before the load wait"
else bad "same version not refused up front: $out"; fi

# 4j. the two manifests at the head disagree: refuse (checking plugin.json alone would miss it).
STUB_HEAD_MKT_VER=1.1.9 run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "manifest mismatch exits non-zero (rc=$rc)"; else bad "manifest mismatch exited 0"; fi
if merged; then bad "manifest mismatch still reached gh pr merge"; else ok "manifest mismatch never calls gh pr merge"; fi
if printf '%s' "$out" | /usr/bin/grep -q 'marketplace'; then ok "mismatch message names marketplace.json"; else bad "no marketplace message: $out"; fi

# 4k. a manifest missing at the head (git show fails): the script says which one and refuses.
STUB_SHOW_FAIL=1 run 0 headsha111 1.50
if [ "$rc" -ne 0 ]; then ok "unreadable manifest file exits non-zero (rc=$rc)"; else bad "unreadable manifest file exited 0"; fi
if merged; then bad "unreadable manifest file still reached gh pr merge"; else ok "unreadable manifest file never calls gh pr merge"; fi
if printf '%s' "$out" | /usr/bin/grep -q 'cannot read'; then ok "unreadable manifest file says so"; else bad "no cannot-read message: $out"; fi

# 5. no PR argument: usage error.
out=$(PATH="$STUB:$PATH" STUB_LOG="$LOG" bash "$SCRIPT" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then ok "missing PR argument exits non-zero"; else bad "missing PR argument exited 0"; fi

safe_trash "$STUB"
echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
