#!/usr/bin/env bash
# test-isolated-checkout-dispatch.sh — exercises the git mechanics documented in
# docs/reference/spawn-brief.md's "Isolated checkout dispatch (opt-in pilot, 2026-09-28)" section
# (steps 1, 3, 4) against a disposable git sandbox built fresh under mktemp -d, never the real
# repo. The pilot was hand-verified once via an ad hoc scratch-repo probe (now gone); this makes
# that verification repeatable.
set -uo pipefail
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== isolated checkout dispatch git-mechanics self-test ==="

sandbox="$(mktemp -d)"
cleanup() { rm -rf "$sandbox"; }
trap cleanup EXIT

repo="$sandbox/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
echo base > "$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "base"
base_sha="$(git -C "$repo" rev-parse HEAD)"

# === 1. Base-SHA / commit-not-stash (step 1) ===
# git worktree add ... <base-sha> branches from a commit; committing inside the worktree must
# never touch the dispatcher's own (parent) working tree.
wt1="$sandbox/wt1"
git -C "$repo" worktree add -q "$wt1" -b test-branch "$base_sha"
echo branch-change >> "$wt1/file.txt"
git -C "$wt1" add file.txt
git -C "$wt1" commit -q -m "branch change"
branch_sha="$(git -C "$wt1" rev-parse HEAD)"

[ "$(git -C "$repo" rev-parse HEAD)" = "$base_sha" ] \
  && ok "parent repo's HEAD is unaffected by a commit made inside the worktree" \
  || bad "parent repo's HEAD moved (got $(git -C "$repo" rev-parse HEAD), want $base_sha)"
[ "$(cat "$repo/file.txt")" = "base" ] \
  && ok "parent repo's working-tree file content is unaffected by the worktree commit" \
  || bad "parent repo's file.txt changed (got: $(cat "$repo/file.txt"))"
[ -z "$(git -C "$repo" status --porcelain)" ] \
  && ok "parent repo's working tree stays clean after the worktree commit" \
  || bad "parent repo's working tree is dirty after the worktree commit"

# === 2. Clean-tree precondition (step 3) ===
# An untracked file left in the worktree must make `status --porcelain` non-empty — the doc's
# signal that routes to a validator-reject, not a pass.
touch "$wt1/untracked.txt"
[ -n "$(git -C "$wt1" status --porcelain)" ] \
  && ok "an untracked file in the worktree makes status --porcelain non-empty" \
  || bad "status --porcelain stayed empty despite an untracked file"

# === 3. SHA-pin / diff (step 3) ===
diff_out="$(git -C "$wt1" diff "$base_sha"..HEAD)"
[[ "$diff_out" == *"branch-change"* ]] \
  && ok "diff base-sha..HEAD shows the branch's committed change" \
  || bad "diff base-sha..HEAD is missing the branch's change (got: $diff_out)"
sha_call1="$(git -C "$wt1" rev-parse HEAD)"
sha_call2="$(git -C "$wt1" rev-parse HEAD)"
[ -n "$sha_call1" ] && [ "$sha_call1" = "$sha_call2" ] \
  && ok "rev-parse HEAD returns a stable SHA across two calls" \
  || bad "rev-parse HEAD was unstable ($sha_call1 vs $sha_call2)"

# === 4. Merge-conflict vs. dirty-tree-preflight-refusal (step 4) ===
# Case (a): the DISPATCHER's own tree has a conflicting uncommitted edit — a preflight refusal,
# not a real merge attempt, so MERGE_HEAD is never set and there's nothing to abort.
echo dirty-uncommitted >> "$repo/file.txt"
merge_out_a="$(git -C "$repo" merge --no-ff "$branch_sha" 2>&1)"
merge_status_a=$?
git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1
verify_status_a=$?
[ "$merge_status_a" -ne 0 ] \
  && ok "merge fails when the dispatcher's own tree has an uncommitted conflicting edit" \
  || bad "merge unexpectedly succeeded with a dirty dispatcher tree ($merge_out_a)"
[ "$verify_status_a" -ne 0 ] \
  && ok "MERGE_HEAD is not set on a dirty-tree preflight refusal (nothing to abort)" \
  || bad "MERGE_HEAD was set on a dirty-tree preflight refusal"

# Case (b): commit that same edit as a real diverging commit, so the SAME branch now produces a
# real content conflict. MERGE_HEAD is set this time, and `merge --abort` restores the tree.
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "dispatcher diverging commit"
pre_merge_sha="$(git -C "$repo" rev-parse HEAD)"
pre_merge_file="$(cat "$repo/file.txt")"
merge_out_b="$(git -C "$repo" merge --no-ff "$branch_sha" 2>&1)"
merge_status_b=$?
git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1
verify_status_b=$?
[ "$merge_status_b" -ne 0 ] \
  && ok "merge fails on a real conflicting commit" \
  || bad "merge unexpectedly succeeded on a real conflict ($merge_out_b)"
[ "$verify_status_b" -eq 0 ] \
  && ok "MERGE_HEAD IS set on a real conflict (there's something to abort)" \
  || bad "MERGE_HEAD was not set on a real conflict"
git -C "$repo" merge --abort
abort_status=$?
[ "$abort_status" -eq 0 ] \
  && ok "git merge --abort succeeds on the real conflict" \
  || bad "git merge --abort failed (exit $abort_status)"
[ "$(git -C "$repo" rev-parse HEAD)" = "$pre_merge_sha" ] && [ "$(cat "$repo/file.txt")" = "$pre_merge_file" ] \
  && ok "merge --abort returns the tree to its pre-merge state" \
  || bad "tree was not fully restored after merge --abort"

# === 5. Clean merge names the branch (step 4) ===
# A non-conflicting case, on a fresh branch that touches a different file so it can merge cleanly
# regardless of section 4's leftover repo state.
wt5="$sandbox/wt5"
git -C "$repo" worktree add -q "$wt5" -b clean-branch "$base_sha"
echo clean-content > "$wt5/newfile.txt"
git -C "$wt5" add newfile.txt
git -C "$wt5" commit -q -m "clean branch change"
clean_sha="$(git -C "$wt5" rev-parse HEAD)"
git -C "$repo" merge --no-ff "$clean_sha" -m "Merge test-branch @ $clean_sha" >/dev/null 2>&1
merge5_status=$?
[ "$merge5_status" -eq 0 ] \
  && ok "a clean, non-conflicting merge succeeds" \
  || bad "clean merge unexpectedly failed"
subject="$(git -C "$repo" log -1 --format=%s)"
[[ "$subject" == *"test-branch"* ]] \
  && ok "merge commit subject names the branch, not just a bare SHA" \
  || bad "merge commit subject is missing the branch name (got: $subject)"

# === 6. Untracked file blocks worktree remove (step 4) ===
# wt1 still holds the untracked.txt left by section 2.
git -C "$repo" worktree remove "$wt1" >/dev/null 2>&1
remove_status_dirty=$?
[ "$remove_status_dirty" -ne 0 ] \
  && ok "worktree remove fails while an untracked file remains" \
  || bad "worktree remove unexpectedly succeeded with an untracked file present"
rm -f "$wt1/untracked.txt"
git -C "$repo" worktree remove "$wt1"
remove_status_clean=$?
[ "$remove_status_clean" -eq 0 ] \
  && ok "worktree remove succeeds once the untracked file is gone" \
  || bad "worktree remove still failed after removing the untracked file"

echo
echo "=== Summary: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
