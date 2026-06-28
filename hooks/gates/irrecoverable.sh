#!/usr/bin/env bash
# Gate: block irrecoverable Bash patterns before they execute.
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
set -uo pipefail

cmd=$(python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" 2>/dev/null || echo "")

deny() {
  echo "[kbg:gate] BLOCKED: $1" >&2
  exit 2
}

# rm -rf in any flag order (rm -rf, rm -fr, rm -r -f, rm -Rf …)
echo "$cmd" | /usr/bin/grep -qE 'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f|rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r|rm[[:space:]]+-r[[:space:]]+-f|rm[[:space:]]+-f[[:space:]]+-r' \
  && deny "rm -rf detected — use 'trash' instead"

# git push --force / -f
echo "$cmd" | /usr/bin/grep -qE 'git[[:space:]]+push[[:space:]].*(-f[[:space:]]|--force[[:space:]]|-f$|--force$)' \
  && deny "git push --force overwrites remote history — needs explicit user approval"

# --no-verify bypasses pre-commit / pre-push hooks
echo "$cmd" | /usr/bin/grep -qF -- '--no-verify' \
  && deny "--no-verify bypasses safety hooks"

# git reset --hard discards uncommitted work
echo "$cmd" | /usr/bin/grep -qE 'git[[:space:]]+reset[[:space:]]+--hard' \
  && deny "git reset --hard discards uncommitted work — confirm with user first"

# git clean -f / -fd / -fdx deletes untracked files
echo "$cmd" | /usr/bin/grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f' \
  && deny "git clean -f deletes untracked files — confirm with user first"

exit 0
