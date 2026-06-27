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
# shellcheck disable=SC2034  # HOOK_PROFILES is consumed by _lib.sh hook_init (sourced above)
HOOK_PROFILES="minimal standard strict"  # floor gate: survives a `minimal` session (CLAUDE.md §Hook architecture (current profile ladder design))
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(hook_strip_quoted "$COMMAND")

SEP='(^|[[:space:];&|()`])'

# Git global options sit BETWEEN `git` and the subcommand (`git -c k=v push`,
# `git --no-pager reset`, `git -C dir branch -D`). Without allowing them, the
# `git<space>subcommand` adjacency is broken and every gate is bypassed
# (`git -c x=y push --force origin main` slipped through pre-fix). GOPT matches
# zero-or-more global-option tokens (value-takers consume their arg; flags don't).
GOPT='((-c|-C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)[=[:space:]]+[^[:space:]]+[[:space:]]+|(-P|-p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--exec-path|--html-path|--man-path|--info-path)[[:space:]]+)*'

# Use command grep to bypass potential ugrep/claude wrapper that breaks backtracking
_GREP="command grep"

# Space-delimited force flag pattern — prevents matching -f inside branch names like fix/ or followup-spec.
# Right-anchored with ([[:space:]]|$) so trailing-position flags (e.g. `git push origin main --force`) match.
# GAP 2 (ECC parity): --force-with-lease is the SAFE force — the lease redeems
# it. Removed from FORCE_FLAG_PAT so `git push --force-with-lease` matches NO
# force pattern below and falls through to ALLOW (ECC allows it everywhere).
# Bare --force/-f and +refspec still deny/ask as before.
FORCE_FLAG_PAT='([[:space:]]--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$))'

# Order-agnostic branch matching: real-world git invocations put the
# flag either before or after the branch name (`git push --force origin
# main` vs `git push origin main --force`). Each pattern allows both
# orders via a 2-branch alternation.

# Force push to main/master: always BLOCK
FORCE_MAIN_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*(${FORCE_FLAG_PAT}.*main|main.*${FORCE_FLAG_PAT})"
FORCE_MASTER_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*(${FORCE_FLAG_PAT}.*master|master.*${FORCE_FLAG_PAT})"
REF_MAIN_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*([+].*main|main.*[+])"
REF_MASTER_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*([+].*master|master.*[+])"

# Force push to develop: WARN
FORCE_DEVELOP_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*(${FORCE_FLAG_PAT}.*develop|develop.*${FORCE_FLAG_PAT})"
REF_DEVELOP_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*([+].*develop|develop.*[+])"

# Force push to allowed prefixes (fix/bugfix/feature/feat): ALLOW
FORCE_FIX_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*(${FORCE_FLAG_PAT}.*([^[:alnum:]_]|^)(fix|bugfix|feature|feat)|([^[:alnum:]_]|^)(fix|bugfix|feature|feat).*${FORCE_FLAG_PAT})"
REF_FIX_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*([+].*([^[:alnum:]_]|^)(fix|bugfix|feature|feat)|([^[:alnum:]_]|^)(fix|bugfix|feature|feat).*[+])"

# General force push: BLOCK (any --force/-f or + refspec after git push).
# --force-with-lease is intentionally absent (GAP 2) — it falls through to ALLOW.
FORCE_ANY_PATTERN="${SEP}git[[:space:]]+${GOPT}push.*(${FORCE_FLAG_PAT}|[+])"

# Other dangerous patterns (GAP 3 widened the set — ECC parity). Each uses GOPT
# so `git -c k=v commit --amend` is caught: GOPT sits BETWEEN `git` and the
# subcommand and consumes the global-option tokens, preserving `git<space>sub`
# adjacency for the regex (see GOPT comment above).
DANGEROUS_PATTERNS=(
  "${SEP}git[[:space:]]+${GOPT}reset[[:space:]]+--hard"
  "${SEP}git[[:space:]]+${GOPT}clean[[:space:]]+-[a-zA-Z]*f"
  "${SEP}git[[:space:]]+${GOPT}branch[[:space:]]+-D"
  "${SEP}git[[:space:]]+${GOPT}checkout[[:space:]]+\\."
  "${SEP}git[[:space:]]+${GOPT}restore[[:space:]]+\\."
  "${SEP}git[[:space:]]+${GOPT}commit[[:space:]].*--amend([[:space:]]|$)"
  "${SEP}git[[:space:]]+${GOPT}rm.*[[:space:]]-[^[:space:]]*r[^[:space:]]*([[:space:]]|$)"
  "${SEP}git[[:space:]]+${GOPT}switch.*[[:space:]](-f|-C|--force|--discard-changes)([[:space:]]|$)"
  "${SEP}git[[:space:]]+${GOPT}checkout.*[[:space:]](-f|--force)([[:space:]]|$)"
)

# Check force push to main/master first (BLOCK via canonical permissionDecision=deny)
for pattern in "$FORCE_MAIN_PATTERN" "$FORCE_MASTER_PATTERN" "$REF_MAIN_PATTERN" "$REF_MASTER_PATTERN"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+${GOPT}push[^#]*" | head -1 | xargs)
    hook_decision deny "force push to main/master: '$matched'. User policy prevents this command."
  fi
done

# Check force push to develop (escalate to user via permissionDecision=ask)
for pattern in "$FORCE_DEVELOP_PATTERN" "$REF_DEVELOP_PATTERN"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+${GOPT}push[^#]*" | head -1 | xargs)
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
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+${GOPT}push[^#]*" | head -1 | xargs)
  hook_decision deny "force push: '$matched'. User policy prevents this command."
fi

# Check other dangerous patterns
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$pattern"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "$pattern" | head -1 | xargs)
    hook_decision deny "dangerous git command: '$matched'. User policy prevents this command."
  fi
done

# GAP 4 (ECC block-no-verify.js parity): deny --no-verify / -n hook-bypass on
# commit|push|merge|cherry-pick|rebase|am. hook_strip_quoted (called at the top)
# already removed quoted strings, so `git commit -m "--no-verify"` became
# `git commit -m` -> --no-verify is gone -> no false positive from quoted forms.
# BUT bare `git commit -m --no-verify` (unquoted) leaves --no-verify as the -m
# VALUE -> a naive grep would false-positive. Token-scan STRIPPED and skip any
# token that immediately follows a value-taking option (mirrors ECC
# block-no-verify.js COMMIT_OPTIONS_WITH_VALUE). -n is the hook-bypass short
# flag ONLY for commit (push -n=dry-run, rebase -n=--no-stat, am -n=--no-resolv-
# message, cherry-pick -n=--no-commit) so deny -n on commit alone.
NOVERIFY_SUBS='commit|push|merge|cherry-pick|rebase|am'
if printf '%s\n' "$STRIPPED" | $_GREP -qE "${SEP}git[[:space:]]+${GOPT}(${NOVERIFY_SUBS})[[:space:]]"; then
  # Value-taking options whose NEXT token is a value (not a real --no-verify).
  # -e is EXCLUDED: for `git commit`, -e is the boolean --edit flag (NOT value-
  # taking), so including it let `git commit -e --no-verify` skip --no-verify as
  # -e's "value" — a real hook-bypass false-negative. -T/--output are dead for
  # these subcommands (git rejects them) so they are harmless but kept minimal.
  NOVERIFY_VAL_OPTS=' -m --message -C -F --file -t -T --author --date -o --output --pathspec-from-file '
  _prev_val=0
  _is_commit=0
  printf '%s\n' "$STRIPPED" | $_GREP -qE "${SEP}git[[:space:]]+${GOPT}commit[[:space:]]" && _is_commit=1
  for _tok in $STRIPPED; do
    if [ "$_prev_val" = "1" ]; then
      # ponytail: this token is the VALUE of the previous value-taking option
      # (e.g. the message after -m) — skip it, it is not a real --no-verify flag.
      _prev_val=0
      continue
    fi
    case "$_tok" in
      --no-verify)
        hook_decision deny "git --no-verify hook-bypass: '$(printf '%s' "$STRIPPED" | xargs)'. --no-verify skips pre-commit AND commit-msg hooks — never bypass the gauntlet."
        ;;
      -n)
        if [ "$_is_commit" = "1" ]; then
          hook_decision deny "git commit -n hook-bypass: '$(printf '%s' "$STRIPPED" | xargs)'. -n skips pre-commit AND commit-msg hooks on commit."
        fi
        ;;
    esac
    # Detect a value-taking option -> next token is its value and must be skipped.
    # Attached `--opt=value` forms keep the value in-token, so no separate value
    # token follows and prev_val stays 0 (the value can't be a bare --no-verify).
    case " $NOVERIFY_VAL_OPTS " in
      *" $_tok "*) _prev_val=1 ;;
    esac
  done
fi

# Git remote mutation (add/set-url) — silent exfil risk; escalate to user.
# Closes round-4 audit finding: silent remote swap → next `git push`
# exfiltrates repo. Legitimate uses exist (upstream tracking, repo migration),
# so ASK rather than BLOCK.
REMOTE_MUTATION_PATTERN="${SEP}git[[:space:]]+${GOPT}remote[[:space:]]+(add|set-url)"
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$REMOTE_MUTATION_PATTERN"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]]+${GOPT}remote[[:space:]]+(add|set-url)[^#]*" | head -1 | xargs)
  hook_decision ask "git remote mutation: '$matched'. Adding/changing a remote redirects future pushes — confirm origin URL is intended."
fi

# core.hooksPath redirect — ported from the retired push-gate.sh (2026-06-25, ECC-
# alignment). A `core.hooksPath` redirect (persistent `git config` or ephemeral `git -c
# core.hooksPath=`) neuters the git-hook gauntlet — the safety surface that gates
# commits/pushes. push-gate.sh denied this under the autonomy flag; with push-gate gone
# this scoped deny stays here so the gauntlet can't be silently redirected by ANY
# session (ECC's block-no-verify.js parity: deny hooksPath/core.hooks redirects).
# Matches `core.hooksPath` / `core.hooks` anywhere after `git` so GOPT can't consume the
# `-c core.hooksPath=` form before `config`/the subcommand.
HOOKSPATH_PAT="${SEP}git[[:space:]][^#]*(hooksPath|core\.hooks)"
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$HOOKSPATH_PAT"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "git[[:space:]][^#]*(hooksPath|core\.hooks)[^#]*" | head -1 | xargs)
  hook_decision deny "git hooksPath/core.hooks redirect: '$matched'. Redirecting the hooks path neuters the gauntlet — never a legitimate part of a commit/push. Restore the default hooks path if you need to."
fi

exit 0
