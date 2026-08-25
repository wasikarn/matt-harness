#!/usr/bin/env bash
# precompact-state-flush unit tests (#92/T13): simulates PreCompact JSON
# payloads and asserts a deterministic snapshot (git HEAD, git status
# --porcelain, plugin/marketplace manifest versions) lands in
# ~/.local/share/kbg/metrics/precompact-snapshots.jsonl before compaction —
# the computational backstop for the same class of fact CLAUDE.md's own
# Compact-instructions section already asks the compacting model to
# preserve in prose. Pure flush: never emits permissionDecision, even
# though PreCompact supports one (verified against official docs before
# building this hook — deny would block compaction, which isn't this
# hook's job).
# Run standalone: bash tests/hooks/test-precompact-state-flush.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/precompact-state-flush.sh"

pass=0
fail=0
assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"; pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2; fail=$((fail + 1))
  fi
}

TMP_HOME="$(mktemp -d)"
trap 'trash "$TMP_HOME" 2>/dev/null || true' EXIT
LOG_FILE="$TMP_HOME/.local/share/kbg/metrics/precompact-snapshots.jsonl"

echo "=== precompact-state-flush hook (PreCompact) ==="
echo ""

# Real git repo fixture with a manifest, one commit, and one dirty file.
REPO=$(mktemp -d)
(cd "$REPO" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "initial")
mkdir -p "$REPO/.claude-plugin"
printf '{"version":"v9.9.9"}\n' > "$REPO/.claude-plugin/plugin.json"
printf '{"plugins":[{"version":"v9.9.9"}]}\n' > "$REPO/.claude-plugin/marketplace.json"
echo "dirty" > "$REPO/untracked.txt"

payload=$(python3 -c 'import json,sys; print(json.dumps({"session_id": "sess-1", "cwd": sys.argv[1], "compaction_reason": "auto"}))' "$REPO")
out=$(HOME="$TMP_HOME" bash -c "printf '%s' '$payload' | '$HOOK'")
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "SILENT + exit 0: never emits stdout JSON (pure flush, no permissionDecision)" "$ok"

if [[ -f "$LOG_FILE" ]] && jq -e '.session_id == "sess-1" and .compaction_reason == "auto" and .plugin_version == "v9.9.9" and .marketplace_version == "v9.9.9"' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ LOGGED: row carries session_id/compaction_reason/plugin_version/marketplace_version"
  pass=$((pass + 1))
else
  echo "  ❌ LOG MISMATCH: expected a row with the fixture's manifest versions and compaction_reason" >&2
  fail=$((fail + 1))
fi

if jq -e '.git_head | length == 40' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ GIT HEAD: captures a real 40-char commit SHA"
  pass=$((pass + 1))
else
  echo "  ❌ expected git_head to be a real 40-char SHA" >&2
  fail=$((fail + 1))
fi

if jq -e '.git_status_porcelain | any(. | contains("untracked.txt"))' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ GIT STATUS: dirty untracked file appears in git_status_porcelain"
  pass=$((pass + 1))
else
  echo "  ❌ expected git_status_porcelain to include untracked.txt" >&2
  fail=$((fail + 1))
fi

trash "$REPO" 2>/dev/null || true

# Not a git repo, no manifests: every git/plugin field must fall back to
# null, not crash, not omit the row entirely.
NONREPO=$(mktemp -d)
payload2=$(python3 -c 'import json,sys; print(json.dumps({"session_id": "sess-2", "cwd": sys.argv[1], "compaction_reason": "manual"}))' "$NONREPO")
HOME="$TMP_HOME" bash -c "printf '%s' '$payload2' | '$HOOK'" >/dev/null
rc2=$?
if [[ "$rc2" == "0" ]] && jq -e 'select(.session_id == "sess-2") | .compaction_reason == "manual" and .git_head == null and .plugin_version == null and .git_status_porcelain == []' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ NON-GIT CWD: git_head/plugin_version fall back to null, git_status_porcelain to [], still appends (fail-open)"
  pass=$((pass + 1))
else
  echo "  ❌ expected a null-fallback row for a non-git cwd, rc=$rc2" >&2
  fail=$((fail + 1))
fi
trash "$NONREPO" 2>/dev/null || true

# Missing cwd in the payload entirely -> falls back to $PWD, still appends, never crashes.
payload3='{"session_id":"sess-3","compaction_reason":"auto"}'
HOME="$TMP_HOME" bash -c "printf '%s' '$payload3' | '$HOOK'" >/dev/null
rc3=$?
[[ "$rc3" == "0" ]] && ok=1 || ok=0
assert "missing cwd in payload -> falls back silently, exit 0" "$ok"

# Malformed payload must not crash the hook or corrupt the log.
lines_before=$(wc -l <"$LOG_FILE" | tr -d ' ')
HOME="$TMP_HOME" bash -c "printf 'not json' | '$HOOK'" >/dev/null
rc4=$?
lines_after=$(wc -l <"$LOG_FILE" | tr -d ' ')
[[ "$rc4" == "0" && "$lines_before" == "$lines_after" ]] && ok=1 || ok=0
assert "malformed payload doesn't crash the hook and appends no row" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
