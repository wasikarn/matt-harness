#!/bin/bash
# Block mutation Bash commands issued by validator-class agents.
# Closes the "validator has Bash that can mutate" gap (audit F1,
# 2026-06-12). 7 validator agents hold `Bash` for read-only inspection
# (git diff/log, ls, cat, npm test, pytest, etc.) — the existing
# `orchestrate` skill gates Bash-holding dispatch behind AskUserQuestion
# for the dispatch step, but a direct Task spawn with Bash granted was
# unconstrained.
#
# Behavioral hook (allow-list of safe prefixes + deny-list of mutation
# patterns) — NOT `disallowedTools: [Bash]` — preserves the read-only
# inspection the validators need. Identifies the calling agent via
# stdin JSON `agent_type` field (vendor: present in PreToolUse input
# when fired inside a subagent — see
# https://code.claude.com/docs/en/hooks#common-input-fields).
#
# Scope of mutation patterns is the SPEC F1 deny-list, NOT a generic
# shell write gate (that's `block-bash-doctrine-write`). The validator
# class is read-only-by-doctrine, so the deny list is the long tail of
# operations they should never do (git push, rm, sed -i, curl POST, etc).
#
# Fail-open for non-validator agents and main-thread (no `agent_type`)
# calls — the user has already approved the action in those paths.
# Fail-open for jq-missing input parse — same fail-soft pattern as the
# other PreToolUse gates in this dir.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=validator-bash-guard

set -uo pipefail

HOOK_ID="validator-bash-guard"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

# jq is mandatory for the command parse below; if missing, fail loud.
if ! command -v jq >/dev/null 2>&1; then
  echo "[$HOOK_ID] ERROR: jq not found — cannot parse hook input" >&2
  exit 1
fi

# agent_type is the agent's `name:` frontmatter value. Present only when
# the hook fires inside a subagent call or a `--agent` session. For the
# main thread (user-driven), it is absent — fail open (return 0).
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
[ -z "$AGENT_TYPE" ] && exit 0

# Validator class — names match the `name:` frontmatter in each agent
# file under agents/. Add a name here only after verifying the agent is
# validator-class (read-only-by-doctrine) and is the source of an actual
# mutation risk.
VALIDATORS='^(code-reviewer|code-explorer|code-architect|comment-analyzer|pr-test-analyzer|silent-failure-hunter|security-reviewer)$'
if ! [[ "$AGENT_TYPE" =~ $VALIDATORS ]]; then
  exit 0
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

# Strip quoted strings and comments so we match shell intent, not the
# literal contents of strings (mirrors block-bash-doctrine-write pattern).
STRIPPED=$(hook_strip_quoted "$COMMAND")

# Fast path: allow-list of read-only command prefixes. Order matters
# loosely — these are anchored on the first token, so a subshell
# wrapper like `(git push ...)` still matches `^git`. Use 'command grep'
# to resist alias shadowing (matches the other PreToolUse bash guards).
ALLOW_PREFIXES='^(git[[:space:]]+(diff|log|show|status|shortlog|rev-parse|describe|tag|name-rev|ls-files|ls-remote|remote\s+-v)[[:space:]]|ls[[:space:]]|cat[[:space:]]|head[[:space:]]|tail[[:space:]]|wc[[:space:]]|grep[[:space:]]|rg[[:space:]]|find[[:space:]]|jq[[:space:]]|node[[:space:]]+-p[[:space:]]|python3[[:space:]]+-c[[:space:]]|npm[[:space:]]+test[[:space:]]|pytest[[:space:]]|cargo[[:space:]]+test[[:space:]]|go[[:space:]]+test[[:space:]]|go[[:space:]]+build[[:space:]]+|npx[[:space:]]+(jest|vitest|mocha|playwright)[[:space:]])'
if echo "$STRIPPED" | command grep -qE "$ALLOW_PREFIXES"; then
  exit 0
fi

# Deny list — 11 mutation patterns from SPEC F1. Each anchored on a
# word/operator boundary to reduce false positives (e.g. `grep` must
# not match `rm`'s token-boundary pattern).
DENY_PATTERNS='(^|[[:space:];&|()`])(rm[[:space:]]|sed[[:space:]]+-i|git[[:space:]]+(push|reset[[:space:]]+--hard|clean[[:space:]]+-fd)|>[[:space:]]*[^[:space:]|;&)]|mv[[:space:]]+.*[[:space:]]+/|chmod[[:space:]]|chown[[:space:]]|curl[[:space:]]+.*-X[[:space:]]+(POST|PUT|DELETE|PATCH)|npm[[:space:]]+(publish|uninstall)|pip[[:space:]]+uninstall)'

# Fork-bomb pattern is a special case (no whitespace tokenizer works cleanly
# for `:(){ :|:& };:`). The canonical signature is `:(){ :|:& };:` — function
# defined with no body, calls itself + pipes to itself in background, terminated
# with `;:`. Some variants use `;}`. Match the structural shape (function
# definition + self-recursion + background pipe) rather than the exact terminator.
if echo "$STRIPPED" | command grep -qE ':[[:space:]]*\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:[[:space:]]*&[[:space:]]*\}[[:space:]]*;'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted fork-bomb pattern: $COMMAND. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
fi

if echo "$STRIPPED" | command grep -qE "$DENY_PATTERNS"; then
  matched=$(echo "$STRIPPED" | command grep -oE "$DENY_PATTERNS" | head -1)
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted mutation ($matched): $COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
fi

exit 0
