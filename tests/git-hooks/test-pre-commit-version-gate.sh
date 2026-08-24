#!/usr/bin/env bash
# Behavioral tests for git-hooks/pre-commit's version-bump layer — specifically
# that scripts/ and contexts/ are shipped surfaces (added 2026-08-21 after three
# scripts/-only commits silently never reached the installed plugin cache).
# Runs the real hook against a throwaway repo; a stub skills/harness-audit/
# scripts/audit.sh inside the fixture keeps the audit layer away from the real
# $HOME fallback. Run standalone: bash tests/git-hooks/test-pre-commit-version-gate.sh
set -uo pipefail

# Inherited git env would make fixture git calls resolve against the real repo
# (run-gauntlet unsets these for its children; standalone runs need it here too).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/git-hooks/pre-commit"

pass=0
fail=0
check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/precommit-gate.XXXXXX")
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

# Baseline: manifests at v0.0.1 + a stub audit so the layer-2 $HOME fallback
# (a real, slow audit against the fixture) never fires. scripts/base.sh exists
# committed so the rename-out case below has something to move.
write_manifests v0.0.1
mkdir -p "$FIX/skills/harness-audit/scripts" "$FIX/scripts" "$FIX/contexts" "$FIX/docs"
printf '#!/usr/bin/env bash\ntouch "$(dirname "$0")/audit-ran"\necho "Critical: 0"\n' > "$FIX/skills/harness-audit/scripts/audit.sh"
printf 'echo base\n' > "$FIX/scripts/base.sh"
git -C "$FIX" add .claude-plugin skills scripts/base.sh
git -C "$FIX" commit -qm baseline

run_hook() { # run_hook [extra env K=V ...] — cwd fixture, ambient skip-valve neutralized
  (cd "$FIX" && env MH_SKIP_VERSION_GATE= "$@" bash "$HOOK")
}

reset_fixture() {
  git -C "$FIX" reset -q --hard HEAD
  git -C "$FIX" clean -qfd --exclude=skills
  mkdir -p "$FIX/scripts" "$FIX/contexts" "$FIX/docs" # clean -d drops empty untracked dirs
}

# 1. scripts/-only staged, no bump → blocked with the shipped-surface message
echo 'echo hi' > "$FIX/scripts/tool.sh"
git -C "$FIX" add scripts/tool.sh
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "shipped-surface files staged" <<<"$out"
check "scripts/-only, no bump → blocked" $?
reset_fixture

# 2. scripts/ staged + both manifests bumped → passes, and provably not
# because the layer never ran (assert absence of the block message too)
echo 'echo hi' > "$FIX/scripts/tool.sh"
write_manifests v0.0.2
git -C "$FIX" add scripts/tool.sh .claude-plugin
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! grep -q "shipped-surface files staged" <<<"$out" && grep -q "version-bump" <<<"$out"
check "scripts/ + both manifests bumped → allowed (layer provably ran)" $?
reset_fixture

# 3. contexts/-only staged, no bump → blocked
echo '# frame' > "$FIX/contexts/dev.md"
git -C "$FIX" add contexts/dev.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "shipped-surface files staged" <<<"$out"
check "contexts/-only, no bump → blocked" $?
reset_fixture

# 4. contexts/ + both manifests bumped → passes
echo '# frame' > "$FIX/contexts/dev.md"
write_manifests v0.0.2
git -C "$FIX" add contexts/dev.md .claude-plugin
run_hook >/dev/null 2>&1
check "contexts/ + both manifests bumped → allowed" $?
reset_fixture

# 5. plugin.json bumped but marketplace.json left behind → mismatch blocks
echo 'echo hi' > "$FIX/scripts/tool.sh"
printf '{"name":"fix","version":"v0.0.2"}\n' > "$FIX/.claude-plugin/plugin.json"
git -C "$FIX" add scripts/tool.sh .claude-plugin/plugin.json
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "manifest version mismatch" <<<"$out"
check "manifest version mismatch → blocked" $?
reset_fixture

# 6. MH_SKIP_VERSION_GATE set → same no-bump staging passes (amend valve)
echo 'echo hi' > "$FIX/scripts/tool.sh"
git -C "$FIX" add scripts/tool.sh
run_hook MH_SKIP_VERSION_GATE=1 >/dev/null 2>&1
check "MH_SKIP_VERSION_GATE=1 → skip valve honored" $?
reset_fixture

# 7. Control: non-shipped docs file staged, no bump → passes (layer not demanded)
echo 'note' > "$FIX/docs/note.md"
git -C "$FIX" add docs/note.md
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! grep -q "version-bump" <<<"$out"
check "non-shipped docs/ file, no bump → allowed (layer provably not launched)" $?
reset_fixture

# 8. Manifest-only staged at the SAME version → allowed, and the layer DID run
# (guards the deliberate B-vs-C asymmetry: .claude-plugin/* triggers the
# version layer's mismatch check without demanding a bump — a future edit
# adding .claude-plugin/* to the bump-demand list breaks every release-prep
# manifest-only commit; this case is the tripwire)
printf '{"name":"fix","version":"v0.0.1","x":1}\n' > "$FIX/.claude-plugin/plugin.json"
git -C "$FIX" add .claude-plugin/plugin.json
out=$(run_hook 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! grep -q "shipped-surface files staged" <<<"$out" && grep -q "version-bump" <<<"$out"
check "manifest-only, same version → allowed (mismatch layer provably ran)" $?
reset_fixture

# 9. Rename OUT of a shipped dir, no bump → blocked (adversarial find 2026-08-21:
# with rename detection on, `git diff --cached --name-only` emits only the
# destination path and both lists miss it — --no-renames closes this)
mkdir -p "$FIX/tools"
git -C "$FIX" mv scripts/base.sh tools/base.sh
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "shipped-surface files staged" <<<"$out"
check "git mv scripts/→tools/, no bump → blocked (rename-out closed)" $?
reset_fixture

# 10. Non-ASCII filename under scripts/, no bump → blocked (adversarial find:
# default core.quotepath wraps the path in a quoted literal that defeats the
# case patterns — -c core.quotepath=false closes this)
printf 'echo th\n' > "$FIX/scripts/ไฟล์.sh"
git -C "$FIX" add "scripts/ไฟล์.sh"
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "shipped-surface files staged" <<<"$out"
check "non-ASCII scripts/ filename, no bump → blocked (quotepath closed)" $?
reset_fixture

# 11. Rename OUT of a shipped dir must still launch the AUDIT layer, not just
# the version layer (blind-spot find 2026-08-22: ecosystem_staged was derived
# from the ACMR-filtered STAGED list, which drops the rename's D side — the
# CRITICAL harness-audit silently skipped on exactly the commit shape that
# removes a guarded file). The stub audit drops a witness file when invoked.
rm -f "$FIX/skills/harness-audit/scripts/audit-ran"
mkdir -p "$FIX/tools"
git -C "$FIX" mv scripts/base.sh tools/base.sh
run_hook >/dev/null 2>&1
if [ -f "$FIX/skills/harness-audit/scripts/audit-ran" ]; then witness=0; else witness=1; fi
check "git mv scripts/→tools/ still launches the audit layer (witness file)" "$witness"
reset_fixture

# 12. Same version but DIFFERENT descriptions across the two manifests →
# blocked (sync-seam: the description string lives in both files with no
# shared source; drifted for real 2026-08-22 — marketplace.json rewritten,
# plugin.json left carrying a stale count).
printf '{"name":"fix","version":"v0.0.1","description":"new text"}\n' > "$FIX/.claude-plugin/plugin.json"
printf '{"plugins":[{"name":"fix","version":"v0.0.1","description":"old text"}]}\n' > "$FIX/.claude-plugin/marketplace.json"
git -C "$FIX" add .claude-plugin
out=$(run_hook 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "description mismatch" <<<"$out"
check "manifest description mismatch → blocked (sync-seam)" $?
reset_fixture

echo
echo "pre-commit-version-gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
