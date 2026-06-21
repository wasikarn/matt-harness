#!/usr/bin/env bash
# test-ch-task-board-lib.sh — audit #46 task-board-lib.sh sync-seam. The skills that
# ship a byte-identical copy of scripts/task-board-lib.sh must stay identical; #46
# WARNs on drift. Runs the REAL audit.sh against temp skills/ fixtures (no logic copy
# → the test can't drift from the check it guards).
# shellcheck disable=SC1090,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"

REPO="$(cd "$HOOKS/.." && pwd)"
AUDIT="$REPO/skills/harness-audit/scripts/audit.sh"

SAME=$'#!/usr/bin/env bash\n# task board\necho board\n'
DIFF=$'#!/usr/bin/env bash\n# DIVERGED\necho different\n'
mk() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }

# clean fixture: two identical copies → no drift warning
CT="$FIXTURE/a46clean"; mkdir -p "$CT/agents"
printf -- '---\nname: x\n---\nx\n' > "$CT/agents/x.md"
mk "$CT/skills/aaa/scripts/task-board-lib.sh" "$SAME"
mk "$CT/skills/bbb/scripts/task-board-lib.sh" "$SAME"
OUT_CLEAN=$(bash "$AUDIT" "$CT" 2>&1)

# drift fixture: a third copy that differs (sorts last → ref stays aaa) → warning
DT="$FIXTURE/a46drift"; mkdir -p "$DT/agents"
printf -- '---\nname: x\n---\nx\n' > "$DT/agents/x.md"
mk "$DT/skills/aaa/scripts/task-board-lib.sh" "$SAME"
mk "$DT/skills/bbb/scripts/task-board-lib.sh" "$SAME"
mk "$DT/skills/zdrift/scripts/task-board-lib.sh" "$DIFF"
OUT_DRIFT=$(bash "$AUDIT" "$DT" 2>&1)

# acheck <want: yes|no> <out-var> <substr> <label>
acheck() {
  local want="$1" out="$2" sub="$3" label="$4" hit
  if printf '%s\n' "$out" | /usr/bin/grep -qF "$sub"; then hit=yes; else hit=no; fi
  if [ "$hit" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#46" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "audit#46" "$label" "$want" "$hit"; fi
}

acheck no  "$OUT_CLEAN" "task-board-lib.sh drift" "silent on identical copies"
acheck yes "$OUT_DRIFT" "task-board-lib.sh drift" "fires on diverged copy"
acheck yes "$OUT_DRIFT" "zdrift"                   "names the diverged copy"

# numbering stability — load-bearing ID must not drift
if /usr/bin/grep -qE '^# 46\. ' "$AUDIT"; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#46" "#46 present"
else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#46" "#46 MISSING (ID drifted)"; fi

report
