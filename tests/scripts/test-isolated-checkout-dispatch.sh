#!/usr/bin/env bash
# test-isolated-checkout-dispatch.sh — exercises the git mechanics documented in
# docs/reference/spawn-brief.md's "Isolated checkout dispatch (opt-in pilot, 2026-09-28)" section
# (steps 1, 3, 4) against a disposable git sandbox built fresh under mktemp -d, never the real
# repo. The pilot was hand-verified once via an ad hoc scratch-repo probe (now gone); this makes
# that verification repeatable. Section 0 pins that the doc still names the commands the later
# sections replay, so the replay cannot keep passing against text the doc no longer says.
set -uo pipefail
# A git hook (pre-push from a linked worktree) exports GIT_DIR; the sandbox `git init`/`git config` below
# would then target the real repo and leave `Test <test@example.com>` in its shared config.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
SELF="$HERE/$(basename "$0")"
# SPAWN_BRIEF points section 0's doc checks at another copy of the doc (used to prove a broken doc
# fails); the git replays in sections 1-6 never read the doc.
DOC="${SPAWN_BRIEF:-$ROOT/docs/reference/spawn-brief.md}"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== isolated checkout dispatch git-mechanics self-test ==="

sandbox="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
cleanup() { [ -n "${sandbox:-}" ] && rm -rf "$sandbox"; }
trap cleanup EXIT

# === 0. Doc coupling ===
# Every command and rule the sections below replay must still appear in the pilot section of the
# doc. The section is squashed to one line so a rewrap of the prose cannot split a pinned string.
# Negative control: the same check has to fail on a copy with one command altered, or it proves
# nothing.
pilot_section() {
  awk '/^## Isolated checkout dispatch/{f=1; next} /^## /{f=0} f' "$1" | tr '\n' ' ' | tr -s ' '
}
doc_has() { [[ "$(pilot_section "$1")" == *"$2"* ]]; }
DOC_NAME="$(basename "$DOC")"
DOC_CMDS=(
  'git worktree add <path> -b subagent/<slug> HEAD'
  'git -C <path> status --porcelain'
  'then reads `git -C <path> diff <base-sha>..HEAD`'
  'git merge --no-ff <that-sha> -m "Merge subagent/<slug> @ <that-sha>"'
  'git rev-parse -q --verify MERGE_HEAD'
  'git merge --abort'
  'git worktree remove <path>'
  're-checks `git -C <path> rev-parse HEAD` still equals the SHA step 3 validated'
  'never the bare branch name'
)
for c in "${DOC_CMDS[@]}"; do
  doc_has "$DOC" "$c" \
    && ok "$DOC_NAME pilot section still documents: $c" \
    || bad "$DOC_NAME pilot section no longer documents: $c"
done
sed 's/--no-ff/--ff/' "$DOC" > "$sandbox/mutated-brief.md"
doc_has "$sandbox/mutated-brief.md" "${DOC_CMDS[3]}" \
  && bad "negative control: the doc check still passed with --no-ff altered in the doc" \
  || ok "negative control: the doc check fails when the documented merge command is altered"

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
# Step 4's recheck: a commit added to the branch after validation must move HEAD off the SHA that
# was validated, so the dispatcher can see it and re-validate instead of merging it unreviewed.
validated_sha="$(git -C "$wt1" rev-parse HEAD)"
echo post-validation >> "$wt1/file.txt"
git -C "$wt1" commit -q -am "commit added after validation"
[ -n "$validated_sha" ] && [ "$(git -C "$wt1" rev-parse HEAD)" != "$validated_sha" ] \
  && ok "a commit added after validation moves HEAD off the validated SHA" \
  || bad "HEAD did not move after a post-validation commit (still $validated_sha)"

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
git -C "$repo" worktree add -q "$wt5" -b subagent/clean "$base_sha"
echo clean-content > "$wt5/newfile.txt"
git -C "$wt5" add newfile.txt
git -C "$wt5" commit -q -m "clean branch change"
clean_sha="$(git -C "$wt5" rev-parse HEAD)"
# A commit added after "validation": merging the validated SHA (step 4) must leave it out.
echo late > "$wt5/late.txt"
git -C "$wt5" add late.txt
git -C "$wt5" commit -q -m "late commit after validation"
# The -m text is the message template inside the pinned merge command (section 0) with slug=clean
# and the validated SHA filled in; the assertion below reads the real branch name back from git.
msg_tpl="${DOC_CMDS[3]#*-m \"}"
msg_tpl="${msg_tpl%\"}"
merge_msg="${msg_tpl//<slug>/clean}"
merge_msg="${merge_msg//<that-sha>/$clean_sha}"
git -C "$repo" merge --no-ff "$clean_sha" -m "$merge_msg" >/dev/null 2>&1
merge5_status=$?
[ "$merge5_status" -eq 0 ] \
  && ok "a clean, non-conflicting merge succeeds" \
  || bad "clean merge unexpectedly failed"
[ -e "$repo/newfile.txt" ] && [ ! -e "$repo/late.txt" ] \
  && ok "merging the validated SHA leaves out a commit added after validation" \
  || bad "the post-validation commit rode along (or the validated change is missing)"
subject="$(git -C "$repo" log -1 --format=%s)"
clean_branch="$(git -C "$wt5" rev-parse --abbrev-ref HEAD)"
[[ "$subject" == *"$clean_branch"* ]] \
  && ok "merge commit subject names the merged branch ($clean_branch), not just a bare SHA" \
  || bad "merge commit subject is missing the merged branch name $clean_branch (got: $subject)"

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

# === 7. A failed mktemp aborts before the sandbox is used ===
# With mktemp failing, `sandbox` would be empty and repo="$sandbox/repo" would be /repo. Extract the
# assignment line (running this whole script again would recurse) and eval it with mktemp shimmed
# to fail: it must exit non-zero and never fall through.
SANDBOX_LINE="$(/usr/bin/grep -m1 '^sandbox="\$(mktemp -d)"' "$SELF")"
mkdir -p "$sandbox/shim"
printf '#!/bin/sh\nexit 1\n' > "$sandbox/shim/mktemp"
chmod +x "$sandbox/shim/mktemp"
guard_out="$(PATH="$sandbox/shim:$PATH" bash -c "set -uo pipefail; $SANDBOX_LINE; echo fell-through" 2>&1)"
guard_rc=$?
# rc != 0 alone proves nothing (the failed command substitution already returns 1), so the guard's
# own message must appear too.
if [ -n "$SANDBOX_LINE" ] && [ "$guard_rc" -ne 0 ] && [[ "$guard_out" != *fell-through* ]] \
   && [[ "$guard_out" == *"mktemp -d failed"* ]]; then
  ok "a failed mktemp -d aborts before the sandbox is used (rc=$guard_rc)"
else
  bad "a failed mktemp -d did not abort (rc=$guard_rc): $(printf '%s' "$guard_out" | tr '\n' '|')"
fi

echo
echo "=== Summary: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
