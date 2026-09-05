#!/usr/bin/env bash
# Behavioral tests for config-write-guard.sh (#98, deferred backlog from spec #75).
# Run standalone: bash tests/hooks/test-config-write-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$ROOT/hooks/gates/config-write-guard.sh"

pass=0
fail=0

payload_write() { # payload_write <file_path>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":""}}))' "$1"
}

payload_write_content() { # payload_write_content <file_path> <content>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$1" "$2"
}

payload_edit() { # payload_edit <file_path> <old_string> <new_string> [replace_all:true|false]
  python3 -c '
import json, sys
replace_all = len(sys.argv) > 4 and sys.argv[4] == "true"
print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3],"replace_all":replace_all}}))
' "$1" "$2" "$3" "${4:-false}"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== config-write-guard gate ==="

FIXTURE=$(mktemp -d)
trap 'trash "$FIXTURE" 2>/dev/null || true' EXIT
mkdir -p "$FIXTURE/.claude"

out=$(payload_write "$FIXTURE/.claude/settings.local.json" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "CREATE .claude/settings.local.json (doesn't exist yet) -> ask" "$ok"

out=$(payload_write "$FIXTURE/.claude/settings.json" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "CREATE .claude/settings.json (doesn't exist yet) -> ask" "$ok"

# Ordinary edit that never touches hooks/enabledPlugins stays frictionless.
# Both sides must be JSON objects (not "" -> {}), otherwise the unparseable
# original would hit the ask branch for the wrong reason and this assertion
# would pass without ever exercising the new comparison logic.
echo '{"foo":"bar"}' > "$FIXTURE/.claude/settings.local.json"
out=$(payload_write_content "$FIXTURE/.claude/settings.local.json" '{"foo":"bar","baz":true}' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "MODIFY existing .claude/settings.local.json, no hooks/enabledPlugins touched -> exit 0, no output" "$ok"

# Deliberate behavior change from the create-only version of this gate: a
# dangling symlink has no real content behind it, so the old "already
# occupied path = already reviewed" rationale never actually applied here --
# hooks/enabledPlugins genuinely can't be verified unchanged, so this now
# asks instead of waving through.
ln -s "$FIXTURE/.claude/does-not-exist-target" "$FIXTURE/.claude/settings.json"
out=$(payload_write "$FIXTURE/.claude/settings.json" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "dangling symlink already at settings.json path -> unreadable, cannot verify -> ask" "$ok"
rm -f "$FIXTURE/.claude/settings.json"

# Regression: a stray non-UTF-8 byte anywhere in the on-disk file used to
# raise UnicodeDecodeError, which is NOT an OSError subclass -- it fell
# through the local except into the outer bare except and silently allowed,
# even when the edit unambiguously rewrites hooks. Found by compliance-audit
# adversarial verification 2026-08-30.
printf '{"hooks":{"PreToolUse":[]},\xff\xfe"other":1}' > "$FIXTURE/.claude/settings.json"
out=$(payload_write_content "$FIXTURE/.claude/settings.json" '{"hooks":{"PreToolUse":[{"id":"evil"}]}}' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "on-disk file has invalid UTF-8 byte, edit changes hooks -> unreadable, cannot verify -> ask" "$ok"
rm -f "$FIXTURE/.claude/settings.json"

out=$(payload_write "$FIXTURE/.claude/config.json" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "unrelated .claude/config.json (wrong basename) -> exit 0, no output" "$ok"

out=$(payload_write "$FIXTURE/settings.json" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "settings.json NOT under a .claude dir -> exit 0, no output" "$ok"

# --- content-aware edit checks: hooks/enabledPlugins vs everything else ---

echo '{"hooks":{"PreToolUse":[]}}' > "$FIXTURE/.claude/settings.json"
out=$(payload_write_content "$FIXTURE/.claude/settings.json" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"evil"}]}]}}' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write edit changes hooks key -> ask" "$ok"

echo '{"enabledPlugins":{"mh@wasikarn":true}}' > "$FIXTURE/.claude/settings.json"
out=$(payload_write_content "$FIXTURE/.claude/settings.json" '{"enabledPlugins":{"mh@wasikarn":false}}' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write edit changes enabledPlugins key -> ask" "$ok"

# The matt-skill attack shape: inserting a new array entry next to an
# existing one. old_string/new_string deliberately never contain the literal
# substring "hooks" -- proving the check reconstructs and parses the full
# file rather than substring-matching the edited fragment for that word.
echo '{"hooks":{"PreToolUse":[{"id":"a","matcher":"Bash"}]},"other":1}' > "$FIXTURE/.claude/settings.json"
out=$(payload_edit "$FIXTURE/.claude/settings.json" '{"id":"a","matcher":"Bash"}]}' '{"id":"a","matcher":"Bash"},{"id":"evil","matcher":"Write"}]}' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Edit inserts a new hooks.PreToolUse array entry (fragment has no literal 'hooks') -> ask" "$ok"

echo '{"hooks":{"PreToolUse":[]},"theme":"dark"}' > "$FIXTURE/.claude/settings.json"
out=$(payload_edit "$FIXTURE/.claude/settings.json" '"theme":"dark"' '"theme":"light"' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Edit touches an unrelated key, hooks present elsewhere unchanged -> no friction" "$ok"

# replace_all correctness: the first occurrence of "tag" sits outside hooks
# (in "note"); the second sits inside hooks.PreToolUse. With replace_all
# true, both change, so hooks changes -> must ask. A hardcoded count=1 would
# only touch the first (outside hooks) occurrence and wrongly allow -- this
# is the one case that fails if the replace_all branch is dropped.
echo '{"note":"tag","hooks":{"PreToolUse":[{"id":"tag"}]}}' > "$FIXTURE/.claude/settings.json"
out=$(payload_edit "$FIXTURE/.claude/settings.json" 'tag' 'evil' 'true' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Edit with replace_all=true changes hooks via the 2nd occurrence -> ask" "$ok"

# Regression: macOS/APFS is case-insensitive but case-preserving, so
# .claude/SETTINGS.JSON resolves to the same on-disk file as
# .claude/settings.json -- a case-sensitive basename/parent compare let a
# one-character-case edit skip this gate entirely. Found by deep-audit
# adversarial verification 2026-08-30.
echo '{"hooks":{"PreToolUse":[]}}' > "$FIXTURE/.claude/settings.json"
out=$(payload_write_content "$FIXTURE/.claude/SETTINGS.JSON" '{"hooks":{"PreToolUse":[{"id":"evil"}]}}' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "uppercase .claude/SETTINGS.JSON resolves to the real file on a case-insensitive FS -> ask" "$ok"
rm -f "$FIXTURE/.claude/settings.json"

# Regression: SECURITY_KEYS originally covered only hooks/enabledPlugins.
# Claude Code's settings `env` block is injected into hook subprocess
# environments too (docs/reference/env-vars.md), and this repo's own gates
# already honor escape-hatch env vars (MH_ALLOW_MAIN_EDIT,
# MH_ALLOW_DIRECT_ATLASSIAN_MCP) -- a frictionless env-key edit could flip
# one of those without ever touching hooks/enabledPlugins. Found by
# deep-audit adversarial verification 2026-08-30.
echo '{"env":{"FOO":"bar"}}' > "$FIXTURE/.claude/settings.json"
out=$(payload_write_content "$FIXTURE/.claude/settings.json" '{"env":{"FOO":"bar","MH_ALLOW_MAIN_EDIT":"1"}}' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write edit changes env key -> ask" "$ok"
rm -f "$FIXTURE/.claude/settings.json"

echo ""
echo "=== missing lib/_hook_output.py (corrupted/partial plugin install, deep-audit follow-up to #146) ==="
# This gate's embedded python does `from _hook_output import emit_ask`,
# resolved from this gate's sibling lib/ dir. A missing lib module raises
# ModuleNotFoundError -> exit 1, a nonzero non-2 exit that
# Claude Code's hook contract treats as non-blocking --
# the gated settings write proceeds regardless, i.e. this gate fails OPEN.
# Simulate by copying ONLY the .sh + an empty lib/ into an isolated scratch
# dir (never touch the real repo files).
MISSLIB_CWG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kbg-misslib-cwg.XXXXXX")
cp "$GUARD" "$MISSLIB_CWG_DIR/config-write-guard.sh"
mkdir -p "$MISSLIB_CWG_DIR/lib"
_errf=$(mktemp "${TMPDIR:-/tmp}/kbg-misslib-cwg-err.XXXXXX")
# Payload precomputed into a variable, THEN piped via printf (not a live
# python3 producer process) -- the gate exits before reading all of stdin
# (it has no early "$(cat)" stdin-drain like verifier-protect.sh/
# merge-door.sh do), so chaining a live python3 producer directly into it
# triggers a spurious BrokenPipeError/exit-120 on the PRODUCER side that
# `pipefail` then surfaces as this pipeline's own exit code -- a test-harness
# artifact, not a real gate bug (confirmed: $_out already holds the correct
# ask JSON either way).
_payload_cwg=$(payload_write "$FIXTURE/.claude/settings.json")
_out=$(printf '%s' "$_payload_cwg" | bash "$MISSLIB_CWG_DIR/config-write-guard.sh" 2>"$_errf")
_rc=$?
_ok=1
# Real JSON parse, not a substring grep -- a grep on the literal ask text
# would also pass on a typo'd key Claude Code's own parser would silently
# ignore, falling through to allow on this gate.
if [ "$_rc" -eq 0 ] \
   && echo "$_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)["hookSpecificOutput"]
sys.exit(0 if d["hookEventName"] == "PreToolUse" and d["permissionDecision"] == "ask" and d["permissionDecisionReason"] else 1)' 2>/dev/null \
   && ! /usr/bin/grep -qi "ModuleNotFoundError\|Traceback" "$_errf"; then
  _ok=0
fi
check "missing lib/_hook_output.py -> ask JSON (exit 0), no raw traceback" "$_ok"
rm -f "$_errf"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
