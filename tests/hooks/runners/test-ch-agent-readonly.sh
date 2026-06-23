#!/usr/bin/env bash
# test-ch-agent-readonly.sh — audit #45 reviewer read-only invariant (maker≠checker).
# An agent whose NAME marks it a reviewer/analyzer must not grant Write/Edit. Runs the
# REAL audit.sh against a temp agents/ fixture (no logic copy → no sync-seam drift).
# shellcheck disable=SC1090,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"

REPO="$(cd "$HOOKS/.." && pwd)"
AUDIT="$REPO/skills/harness-audit/scripts/audit.sh"

AT="$FIXTURE/a45"; mkdir -p "$AT/agents"
printf -- '---\nname: clean-reviewer\ntools: Read, Grep, Glob, Bash\n---\nx\n' > "$AT/agents/clean-reviewer.md"
printf -- '---\nname: bad-reviewer\ntools: Read, Grep, Write, Edit\n---\nx\n'  > "$AT/agents/bad-reviewer.md"
printf -- '---\nname: writer-engineer\ntools: Read, Write, Edit\n---\nx\n'     > "$AT/agents/writer-engineer.md"

OUT=$(bash "$AUDIT" "$AT" 2>&1)
ANCHOR=$(printf '%s\n' "$OUT" | /usr/bin/grep -i 'read-only invariant' || true)

# acheck <want: yes|no> <substr-in-anchor-lines> <label>
acheck() {
  local want="$1" sub="$2" label="$3" hit
  if printf '%s\n' "$ANCHOR" | /usr/bin/grep -qF "$sub"; then hit=yes; else hit=no; fi
  if [ "$hit" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#45" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "audit#45" "$label" "$want" "$hit"; fi
}

acheck yes "bad-reviewer"    "fires on reviewer granting Write/Edit"
acheck no  "clean-reviewer"  "silent on read-only reviewer"
acheck no  "writer-engineer" "exempts non-reviewer writer"

# numbering stability — load-bearing ID must not drift
if /usr/bin/grep -qE '^# 45\. ' "$AUDIT" "$(dirname "$AUDIT")"/checks/*.sh 2>/dev/null; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#45" "#45 present"
else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#45" "#45 MISSING (ID drifted)"; fi

report
