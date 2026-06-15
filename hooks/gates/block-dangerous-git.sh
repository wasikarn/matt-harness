#!/bin/bash
# Block dangerous git commands — strips quoted strings and comments
# before pattern-matching to avoid false positives.
#
# Bypass (ported from ECC hook-flags pattern):
#   export CLAUDE_HOOK_PROFILE=off              # disable all hooks honoring this var
#   export CLAUDE_DISABLED_HOOKS=block-dangerous-git[,other-id...]
# Default profile is `standard` (this hook active).

set -uo pipefail

HOOK_ID="block-dangerous-git"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

# jq is mandatory for the command parse below; if missing, fail loud.
if ! command -v jq >/dev/null 2>&1; then
  echo "[$HOOK_ID] ERROR: jq not found — cannot parse hook input" >&2
  exit 1
fi

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(hook_strip_quoted "$COMMAND")

SEP='(^|[[:space:];&|()`])'

# Use command grep to bypass potential ugrep/claude wrapper that breaks backtracking
_GREP="command grep"

# Space-delimited force flag pattern — prevents matching -f inside branch names like fix/ or followup-spec.
# Right-anchored with ([[:space:]]|$) so trailing-position flags (e.g. `git push origin main --force`) match.
FORCE_FLAG_PAT='([[:space:]]--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$)|[[:space:]]--force-with-lease([[:space:]]|$))'

# Order-agnostic branch matching: real-world git invocations put the
# flag either before or after the branch name (`git push --force origin
# main` vs `git push origin main --force`). Each pattern allows both
# orders via a 2-branch alternation.

# Force push to main/master: always BLOCK
FORCE_MAIN_PATTERN="${SEP}git[[:space:]]+push.*(${FORCE_FLAG_PAT}.*main|main.*${FORCE_FLAG_PAT})"
FORCE_MASTER_PATTERN="${SEP}git[[:space:]]+push.*(${FORCE_FLAG_PAT}.*master|master.*${FORCE_FLAG_PAT})"
FORCE_LEASE_MAIN_PATTERN="${SEP}git[[:space:]]+push.*(--force-with-lease.*main|main.*--force-with-lease)"
FORCE_LEASE_MASTER_PATTERN="${SEP}git[[:space:]]+push.*(--force-with-lease.*master|master.*--force-with-lease)"
REF_MAIN_PATTERN="${SEP}git[[:space:]]+push.*([+].*main|main.*[+])"
REF_MASTER_PATTERN="${SEP}git[[:space:]]+push.*([+].*master|master.*[+])"

# Force push to develop: WARN
FORCE_DEVELOP_PATTERN="${SEP}git[[:space:]]+push.*(${FORCE_FLAG_PAT}.*develop|develop.*${FORCE_FLAG_PAT})"
REF_DEVELOP_PATTERN="${SEP}git[[:space:]]+push.*([+].*develop|develop.*[+])"

# Force push to allowed prefixes (fix/bugfix/feature/feat): ALLOW
FORCE_FIX_PATTERN="${SEP}git[[:space:]]+push.*(${FORCE_FLAG_PAT}.*([^[:alnum:]_]|^)(fix|bugfix|feature|feat)|([^[:alnum:]_]|^)(fix|bugfix|feature|feat).*${FORCE_FLAG_PAT})"
REF_FIX_PATTERN="${SEP}git[[:space:]]+push.*([+].*([^[:alnum:]_]|^)(fix|bugfix|feature|feat)|([^[:alnum:]_]|^)(fix|bugfix|feature|feat).*[+])"

# General force push: BLOCK (any --force/-f/--force-with-lease or + refspec after git push)
FORCE_ANY_PATTERN="${SEP}git[[:space:]]+push.*(${FORCE_FLAG_PAT}|[+])"

# Other dangerous patterns
DANGEROUS_PATTERNS=(
  "${SEP}git[[:space:]]+reset[[:space:]]+--hard"
  "${SEP}git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f"
  "${SEP}git[[:space:]]+branch[[:space:]]+-D"
  "${SEP}git[[:space:]]+checkout[[:space:]]+\\."
  "${SEP}git[[:space:]]+restore[[:space:]]+\\."
)

# Check force push to main/master first (BLOCK via canonical permissionDecision=deny)
for pattern in "$FORCE_MAIN_PATTERN" "$FORCE_MASTER_PATTERN" "$FORCE_LEASE_MAIN_PATTERN" "$FORCE_LEASE_MASTER_PATTERN" "$REF_MAIN_PATTERN" "$REF_MASTER_PATTERN"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+push[^#]*" | head -1 | xargs)
    hook_decision deny "force push to main/master: '$matched'. User policy prevents this command."
  fi
done

# Check force push to develop (escalate to user via permissionDecision=ask)
for pattern in "$FORCE_DEVELOP_PATTERN" "$REF_DEVELOP_PATTERN"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+push[^#]*" | head -1 | xargs)
    hook_decision ask "force push to develop: '$matched'. Confirm before proceeding."
  fi
done

# Check force push to allowed prefixes (ALLOW) — skip blocking
for pattern in "$FORCE_FIX_PATTERN" "$REF_FIX_PATTERN"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    exit 0
  fi
done

# Check general force push (BLOCK)
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$FORCE_ANY_PATTERN"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+push[^#]*" | head -1 | xargs)
  hook_decision deny "force push: '$matched'. User policy prevents this command."
fi

# Check other dangerous patterns
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "$pattern" | head -1 | xargs)
    hook_decision deny "dangerous git command: '$matched'. User policy prevents this command."
  fi
done

# Git remote mutation (add/set-url) — silent exfil risk; escalate to user.
# Closes round-4 audit finding: silent remote swap → next `git push`
# exfiltrates repo. Legitimate uses exist (upstream tracking, repo migration),
# so ASK rather than BLOCK.
REMOTE_MUTATION_PATTERN="${SEP}git[[:space:]]+remote[[:space:]]+(add|set-url)"
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$REMOTE_MUTATION_PATTERN"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+remote[[:space:]]+(add|set-url)[^#]*" | head -1 | xargs)
  hook_decision ask "git remote mutation: '$matched'. Adding/changing a remote redirects future pushes — confirm origin URL is intended."
fi

exit 0
