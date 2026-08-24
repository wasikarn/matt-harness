#!/usr/bin/env bash
# Behavioral tests for git-hooks/pre-commit's new-file LOC gate (Layer 4):
# brand-new agents/*.md, commands/*.md, commands/*/COMMAND.md, or
# skills/*/SKILL.md over 200 lines get hard-blocked; editing an existing file
# past the cap stays WARN-only (grandfather — case 3 below also pins the
# accepted `git commit --amend` gap, since the hook can't distinguish "HEAD is
# the commit I'm about to replace" from any other HEAD: both read as an edit,
# not a new file). Mirrors tests/git-hooks/test-pre-commit-version-gate.sh's
# fixture style, with one deliberate difference: reset_fixture here does NOT
# preserve any untracked subtree via --exclude, since the only file that must
# survive a reset (the stub audit.sh) is tracked and therefore already safe
# from `git clean` — an unscoped exclude would let one case's leftover
# untracked file silently contaminate the next case's identical path.
# Run standalone: bash tests/git-hooks/test-pre-commit-loc-gate.sh
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/git-hooks/pre-commit"
CHECK56="$ROOT/skills/harness-audit/scripts/checks/56-loc-cap-auto-loaded-surfaces.sh"

pass=0
fail=0
check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/precommit-loc-gate.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

FIX="$TMP/fixture"
mkdir -p "$FIX"
git init -q -b develop "$FIX"
git -C "$FIX" config user.email t@t
git -C "$FIX" config user.name t

write_manifests() { # write_manifests <version>
  mkdir -p "$FIX/.claude-plugin"
  printf '{"name":"fix","version":"%s"}\n' "$1" > "$FIX/.claude-plugin/plugin.json"
  printf '{"plugins":[{"name":"fix","version":"%s"}]}\n' "$1" > "$FIX/.claude-plugin/marketplace.json"
}

mkfile() { # mkfile <relpath> <lines>
  mkdir -p "$FIX/$(dirname "$1")"
  seq 1 "$2" > "$FIX/$1"
}

write_manifests v0.0.1
mkdir -p "$FIX/skills/harness-audit/scripts" "$FIX/agents" "$FIX/commands" "$FIX/skills" "$FIX/docs"
printf '#!/usr/bin/env bash\necho "Critical: 0"\n' > "$FIX/skills/harness-audit/scripts/audit.sh"
git -C "$FIX" add .claude-plugin skills
git -C "$FIX" commit -qm baseline

run_hook() { # run_hook [extra env K=V ...]
  (cd "$FIX" && env KBG_SKIP_VERSION_GATE= "$@" bash "$HOOK")
}

reset_fixture() {
  git -C "$FIX" reset -q --hard HEAD
  git -C "$FIX" clean -qfd # no --exclude: only the tracked stub needs to survive, and reset --hard already covers that
  mkdir -p "$FIX/agents" "$FIX/commands" "$FIX/skills" "$FIX/docs" # clean -d drops empty untracked dirs
}

next_version=1
bump_and_add() { # bump_and_add <path...>
  next_version=$((next_version + 1))
  write_manifests "v0.0.$next_version"
  git -C "$FIX" add .claude-plugin "$@"
}

# 1. New file at 201 lines in a capped pattern → blocked
mkfile agents/x.md 201
bump_and_add agents/x.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "new file 'agents/x.md' is 201 lines (cap 200)" <<<"$out"
check "new agents/x.md at 201 lines → blocked" $?
reset_fixture

# 2. New file at exactly 200 lines → allowed, and the layer provably ran
mkfile agents/y.md 200
bump_and_add agents/y.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -q "new-file LOC gate" <<<"$out" && ! grep -q "cap 200" <<<"$out"
check "new agents/y.md at exactly 200 lines → allowed (layer provably ran)" $?
reset_fixture

# 3. Existing file edited past cap (195 → 205 lines) → NOT blocked (grandfather;
# this is also the accepted `git commit --amend` gap, since the hook sees an
# edit to a HEAD-tracked path either way — see file header comment)
mkfile agents/existing.md 195
bump_and_add agents/existing.md
git -C "$FIX" commit -qm "add existing.md at 195 lines"
mkfile agents/existing.md 205
bump_and_add agents/existing.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! grep -q "new file 'agents/existing.md'" <<<"$out"
check "existing agents/existing.md edited 195→205 → allowed (grandfather)" $?
reset_fixture

# 4. git mv an over-cap file WITHIN scope (already-grandfathered content
# moved to a new in-scope path) → allowed, not treated as brand-new
mkfile commands/big.md 250
git -C "$FIX" add commands/big.md
git -C "$FIX" commit -qm "add commands/big.md at 250 lines (pre-existing over cap)"
mkdir -p "$FIX/commands/big"
git -C "$FIX" mv commands/big.md commands/big/COMMAND.md
bump_and_add
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! grep -q "new file 'commands/big/COMMAND.md'" <<<"$out"
check "git mv commands/big.md→commands/big/COMMAND.md (in-scope→in-scope) → allowed" $?
reset_fixture

# 5. git mv an over-cap file INTO scope FROM OUTSIDE → blocked (the source
# path was never subject to the cap, so this is a genuinely new surface file)
mkfile docs/big.md 300
git -C "$FIX" add docs/big.md
git -C "$FIX" commit -qm "add docs/big.md at 300 lines (out of scope)"
git -C "$FIX" mv docs/big.md agents/big.md
bump_and_add
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "new file 'agents/big.md' is 300 lines" <<<"$out"
check "git mv docs/big.md→agents/big.md (out-of-scope→in-scope) → blocked" $?
reset_fixture

# 6. New reference.md at 500 lines → allowed (on-demand exemption, same as check 56)
mkfile skills/newthing/reference.md 500
bump_and_add skills/newthing/reference.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -q "new-file LOC gate" <<<"$out" && ! grep -q "cap 200" <<<"$out"
check "new skills/newthing/reference.md at 500 lines → allowed (exempt)" $?
reset_fixture

# 7. New nested SKILL.md (one directory level too deep) at 400 lines → allowed.
# Negative control for the glob-vs-regex parity claim: check 56's real
# filesystem glob (skills/[!_]*/SKILL.md) never crosses a `/`; this pins that
# the hook's regex doesn't either.
mkfile skills/foo/deep/SKILL.md 400
bump_and_add skills/foo/deep/SKILL.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -q "new-file LOC gate" <<<"$out" && ! grep -q "cap 200" <<<"$out"
check "new nested skills/foo/deep/SKILL.md at 400 lines → allowed (glob-parity control)" $?
reset_fixture

# 8. New SKILL.md under an underscore-prefixed dir at 400 lines → allowed.
# Pins the [!_] exemption check 56 also carries.
mkfile skills/_lib/SKILL.md 400
bump_and_add skills/_lib/SKILL.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -q "new-file LOC gate" <<<"$out" && ! grep -q "cap 200" <<<"$out"
check "new skills/_lib/SKILL.md at 400 lines → allowed (underscore-dir exemption)" $?
reset_fixture

# 9. KBG_SKIP_LOC_GATE=1 → valve honored even for a 300-line new file
mkfile agents/skipped.md 300
bump_and_add agents/skipped.md
out=$(run_hook KBG_SKIP_LOC_GATE=1 2>&1); rc=$?
[ "$rc" -eq 0 ] && grep -q "new-file LOC gate skipped" <<<"$out"
check "KBG_SKIP_LOC_GATE=1 → skip valve honored" $?
reset_fixture

# 10. Sync guard: the cap value here must match check 56's cap value —
# the pattern SET is asserted structurally above (cases 1/2/6/7/8); this
# pins the numeric constant the two scripts don't share a source for.
hook_cap=$(grep -m1 '^LOC_CAP=' "$HOOK" | cut -d= -f2)
check56_cap=$(grep -m1 '^LOC_CAP=' "$CHECK56" | cut -d= -f2)
[ -n "$hook_cap" ] && [ "$hook_cap" = "$check56_cap" ]
check "git-hooks/pre-commit LOC_CAP ($hook_cap) matches check 56's LOC_CAP ($check56_cap)" $?

echo
echo "pre-commit-loc-gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
