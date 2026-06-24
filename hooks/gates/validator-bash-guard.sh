#!/bin/bash
# Block mutation Bash commands issued by validator-class agents.
# Closes the "validator has Bash that can mutate" gap (audit F1,
# 2026-06-12). 14 validator agents hold `Bash` for read-only inspection
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
# Fail-safe (ask) for jq-missing input parse — the gate cannot validate
# the command, so it asks rather than silently allowing.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=validator-bash-guard

set -uo pipefail

HOOK_ID="validator-bash-guard"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


if ! command -v jq >/dev/null 2>&1; then
  hook_decision ask "[$HOOK_ID] jq unavailable — failing safe (ask)."
  exit 0
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
VALIDATORS='^(code-reviewer|code-explorer|code-architect|comment-analyzer|pr-test-analyzer|silent-failure-hunter|security-reviewer|type-design-analyzer|ux-reviewer|researcher|inferential-structural-judge|incident-commander|finops-engineer|product-analyst)$'
if ! [[ "$AGENT_TYPE" =~ $VALIDATORS ]]; then
  exit 0
fi

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
  hook_decision ask "[$HOOK_ID] could not parse tool_input.command — failing safe (ask)."
  exit 0
}
[ -z "$COMMAND" ] && exit 0

# Normalize backslash-escaped command words (\rm, \bash, etc.) so that existing
# allow/deny patterns see the real token. The leading backslash only suppresses
# alias expansion; the underlying mutation/interpreter command is unchanged.
RAW_COMMAND=$COMMAND
COMMAND=$(printf '%s\n' "$COMMAND" | sed -E "s/(^|[[:space:];|&()<>'\"])\\\\([[:alnum:]_-])/\1\2/g")

# Narrow read-only exception: `python3 -m pytest` is a common test invocation
# that the generic `python3 -m` deny (arbitrary module execution) would
# otherwise block. We allow it ONLY when the entire command is a single
# pytest invocation with simple arguments — no shell operators, command
# substitution, quotes, redirects, or embedded newlines. Plain `pytest ...`
# is already handled by ALLOW_PREFIXES; this carve-out covers the
# `python[0-9]* -m` form (python, python3, python3.11, ...).
if [[ "$COMMAND" != *$'\n'* ]] &&
   printf '%s\n' "$COMMAND" | command grep -qE '(^|[[:space:];|(&`\\])((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?python[0-9]*(\.[0-9]*)*[[:space:]]+-m[[:space:]]+pytest([[:space:]]|$)' &&
   ! printf '%s\n' "$COMMAND" | command grep -qE '[;|&`$()\<>"'"'"'"]'; then
  exit 0
fi

# Python with any flag other than -m pytest is an arbitrary-code path
# (-c, -i, -u script.py, --command, etc.). Read-only validators only need
# `python[0-9]* -m pytest`; everything else is denied.
if printf '%s\n' "$COMMAND" | command grep -qE '(^|[[:space:];|(&`\\])((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?python[0-9]*(\.[0-9]*)*[[:space:]]+-' &&
   ! printf '%s\n' "$COMMAND" | command grep -qE '(^|[[:space:];|(&`\\])((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?python[0-9]*(\.[0-9]*)*[[:space:]]+-m[[:space:]]+pytest([[:space:]]|$)'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted python flag other than -m pytest: $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0
fi

# P0: security fix — Deny list checked TWICE: first against the FULL
# unstripped command (catches mutations hidden inside quotes, e.g.
# bash -c 'git push origin main'), then against the stripped command.
# The full-command check must come BEFORE hook_strip_quoted.
# SEP class now includes the quote chars '"` so a mutation verb GLUED to an
# opening quote (`bash -c 'git push'`, `eval "rm -rf x"`) is at a boundary and
# matches — pre-fix it slipped through because `'`/`"` weren't separators (the
# hook's own header claimed this case was closed; it wasn't). Interpreters that
# run arbitrary code in another language (eval, python -c/-m, bash/sh -c,
# node -e, perl -e, ruby -e) are denied outright — they defeat shell-pattern
# matching entirely and a read-only validator never needs them (it has Read/Grep).
# read -d '' consumes the whole heredoc (multi-line-safe); newlines are
# stripped because POSIX ERE treats a literal newline as matching a newline
# in the input, not as regex syntax.
read -r -d '' DENY_PATTERNS <<'REGEX'
(^|[[:space:];&|()`'"\\])(rm[[:space:]]|sed[[:space:]]+(-i|--in-place)|eval[[:space:]]|python[0-9]*(\.[0-9]*)*[[:space:]]+-c|python[0-9]*(\.[0-9]*)*[[:space:]]+-m|python[0-9]*(\.[0-9]*)*[[:space:]]+-([[:space:]]|$)|bash[[:space:]]+-(c|s)|sh[[:space:]]+-(c|s)|zsh[[:space:]]+-(c|s)|dash[[:space:]]+-(c|s)|ksh[[:space:]]+-(c|s)|node[[:space:]]+-[ep]|perl[[:space:]]+-[Ee]|ruby[[:space:]]+-e|git[[:space:]]+(push|commit|merge|rebase[[:space:]]+-i|reset[[:space:]]+--hard|clean[[:space:]]+-fd)|>[[:space:]]*[^[:space:]|;&)]|tee[[:space:]]|mv[[:space:]]|cp[[:space:]]|chmod[[:space:]]|chown[[:space:]]|touch[[:space:]]|mkdir[[:space:]]|mkfifo[[:space:]]|ln[[:space:]]|install[[:space:]]|curl[[:space:]]+.*-X[[:space:]]+(POST|PUT|DELETE|PATCH)|curl[[:space:]]+.*-(o|O|output|remote-name)|wget[[:space:]]+(-O|--output-document)(=|[[:space:]])|(curl|wget)[[:space:]]+.*[|][[:space:]]*((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?(bash|sh|zsh|dash|ksh|python[0-9]*(\.[0-9]*)*|node|ruby|perl)([[:space:]]|$)|(^|[[:space:];&|()`'"\\])(source|[.])[[:space:]]+(["'][^"';|]*["']|[^[:space:];&|()`"]+)([[:space:]]|$)|(^|[[:space:];&|()`'"\\])(source|[.])[[:space:]]+[$<\`]|(((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?(bash|sh|zsh|dash|ksh))[[:space:]]+(-(c|s)|--init-file|--rcfile)|(((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?node)[[:space:]]+-[ep]|(((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?ruby)[[:space:]]+-e|(((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(sudo[[:space:]]+)?perl)[[:space:]]+-[Ee]|(((/usr(/local)?/|/)?bin/)?(env[[:space:]]+)?(python[0-9]*(\.[0-9]*)*|bash|sh|zsh|dash|ksh|node|ruby|perl))[[:space:]]+[^-[:space:];&|()<>`"][^[:space:];&|()<>`"]*([[:space:]]|$)|npm[[:space:]]+(publish|uninstall)|pip[[:space:]]+uninstall|docker[[:space:]]+(push|build))
REGEX
DENY_PATTERNS=${DENY_PATTERNS//$'\n'/}

# 1. Full-command deny check — catches quoted mutations that
# hook_strip_quoted would strip away.
if printf '%s\n' "$COMMAND" | command grep -qE "$DENY_PATTERNS"; then
  matched=$(printf '%s\n' "$COMMAND" | command grep -oE "$DENY_PATTERNS" | head -1)
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted mutation ($matched): $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# Strip quoted strings and comments so we match shell intent, not the
# literal contents of strings (mirrors block-bash-doctrine-write pattern).
STRIPPED=$(hook_strip_quoted "$COMMAND")

# ANSI-C quotes ($'...') encode arbitrary bytes (including newlines) and are
# not stripped by hook_strip_quoted. Read-only validators never need them.
if printf '%s' "$COMMAND" | command grep -qE "\$'"; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted ANSI-C quote (can encode hidden commands): $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# Fast path: allow-list of read-only command prefixes. Order matters
# loosely — these are anchored on the first token, so a subshell
# wrapper like `(git push ...)` still matches `^git`. Use 'command grep'
# to resist alias shadowing (matches the other PreToolUse bash guards).
# P0: security fix — removed python3 -c, node -p, go build from the
# allow-list because quote-stripping made them bypass vectors (any
# payload inside quotes was invisible after hook_strip_quoted).
ALLOW_PREFIXES='^(git[[:space:]]+(diff|log|show|status|shortlog|rev-parse|describe|tag|name-rev|ls-files|ls-remote|remote[[:space:]]+-v)[[:space:]]|ls[[:space:]]|cat[[:space:]]|head[[:space:]]|tail[[:space:]]|wc[[:space:]]|grep[[:space:]]|rg[[:space:]]|find[[:space:]]|jq[[:space:]]|npm[[:space:]]+test[[:space:]]|pytest[[:space:]]|cargo[[:space:]]+test[[:space:]]|go[[:space:]]+test[[:space:]]|npx[[:space:]]+(jest|vitest|mocha|playwright)[[:space:]]|python[0-9]*(\.[0-9]*)*[[:space:]]+-m[[:space:]]+pytest[[:space:]])'
if [[ "$RAW_COMMAND" != *$'\n'* ]] &&
   printf '%s\n' "$STRIPPED" | command grep -qE "$ALLOW_PREFIXES" &&
   ! printf '%s\n' "$STRIPPED" | command grep -qE '[;|&`$()<>"'"'"'"]'; then
  exit 0
fi

# P0: if a source/. or script interpreter invocation had its entire argument
# inside quotes (possibly hiding command/process substitution), the argument
# disappears during hook_strip_quoted. Deny the stripped husk so validators
# cannot use source "$(...)" or bash "$(...)" to execute arbitrary code.
if printf '%s\n' "$STRIPPED" | command grep -qE '(^|[[:space:];&|/()`'"'"'"])(source|[.]|python[0-9]*(\.[0-9]*)*|bash|sh|node|ruby|perl)[[:space:]]+$'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted interpreter/source with quoted/arbitrary argument: $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# Block interpreters reading arbitrary code via heredoc (<<) or process
# substitution (<()). A read-only validator has no legitimate reason to run
# bash <(curl ...), python3 <<EOF, python3 <(foo), etc.
if printf '%s\n' "$STRIPPED" | tr '\n' ' ' | command grep -qE '(^|[[:space:];&|/()`'"'"'"])(bash|sh|zsh|dash|ksh|python[0-9]*(\.[0-9]*)*|node|ruby|perl)[[:space:]]*(<|<<)'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted interpreter with heredoc/process-substitution input: $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# General pipe-to-interpreter: any shell pipeline ending in an interpreter
# (bash/python/node/ruby/perl) is arbitrary-code execution. The curl/wget
# variant is already in DENY_PATTERNS; this catches cat <<EOF | bash,
# echo 'rm -rf /' | bash, etc. Prefix wrappers (nice, timeout, command,
# env/sudo with flags, doas, run0) are also denied.
if printf '%s\n' "$STRIPPED" | tr '\n' ' ' | command grep -qE '[|][[:space:]]+((/usr(/local)?/|/)?bin/)?(nice[[:space:]]+(-n[[:space:]]+[0-9]+[[:space:]]+)?|timeout[[:space:]]+(-?[0-9]+[smhd]?[[:space:]]+)?|command[[:space:]]+|doas[[:space:]]+(-[a-zA-Z]+[[:space:]]+[[:alnum:]_-]+[[:space:]]+)?|run0[[:space:]]+(-[a-zA-Z]+[[:space:]]+[[:alnum:]_-]+[[:space:]]+)?)?(env[[:space:]]+([[:alnum:]_-]+(=[^[:space:]]*)?[[:space:]]+|(-[a-zA-Z]|--[a-z-]+)([[:space:]]+[^[:space:]]+)?[[:space:]]+)*)?(sudo[[:space:]]+(-[uSiE]+([[:space:]]+[[:alnum:]_-]+)?[[:space:]]+)?)?(bash|sh|zsh|dash|ksh|python[0-9]*(\.[0-9]*)*|node|ruby|perl)([[:space:]]|$)'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted pipe-to-interpreter (arbitrary code execution): $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# xargs executes an arbitrary command with attacker-controlled input. The
# pipe-to-interpreter check above catches `... | bash`; this catches `... | xargs rm`
# and `xargs bash -c ...` before the backstop.
if printf '%s\n' "$STRIPPED" | tr '\n' ' ' | command grep -qE '(^|[[:space:];|&()<>'"'"'"])xargs([[:space:]]|$)'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted xargs wrapper (arbitrary command execution): $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# Backstop: any interpreter invocation (with or without arguments) is
# arbitrary-code execution for a read-only validator. The python -m pytest
# carve-out and the allow-list fast path above already handle the only
# legitimate interpreter forms; anything else reaching here is unrecognized
# and is denied. Catches bash -x script.sh, node app.js, ruby -Ilib x.rb,
# bash --norc --init-file, etc.
INTERPRETER_BACKSTOP='^((/usr(/local)?/|/)?bin/)?(exec[[:space:]]+|command[[:space:]]+|nice[[:space:]]+(-n[[:space:]]+[0-9]+[[:space:]]+)?|timeout[[:space:]]+(-?[0-9]+[smhd]?[[:space:]]+)?|doas[[:space:]]+(-[a-zA-Z]+[[:space:]]+[[:alnum:]_-]+[[:space:]]+)?|run0[[:space:]]+(-[a-zA-Z]+[[:space:]]+[[:alnum:]_-]+[[:space:]]+)?)?(env[[:space:]]+([[:alnum:]_-]+(=[^[:space:]]*)?[[:space:]]+|(-[a-zA-Z]|--[a-z-]+)([[:space:]]+[^[:space:]]+)?[[:space:]]+)*)?(sudo[[:space:]]+(-[uSiE]+([[:space:]]+[[:alnum:]_-]+)?[[:space:]]+)?)?(bash|sh|zsh|dash|ksh|python[0-9]*(\.[0-9]*)*|node|ruby|perl)([[:space:]]|$)'
if printf '%s\n' "$STRIPPED" | command grep -qE "$INTERPRETER_BACKSTOP"; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted interpreter invocation: $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# Variable / command-substitution indirection bypasses literal interpreter-name
# matching. We deny two shapes:
#   1. Pre-strip: a double-quoted first word containing $ or backtick (e.g.
#      "$x" -c "id", "`which bash`" -c "id"). hook_strip_quoted removes these,
#      so the unquoted check below would miss them.
#   2. Post-strip: an unquoted $ or backtick at the start of a command word
#      (e.g. x=bash; $x -c "id", `which bash` -c "id"), including after
#      compound-command openers.
if printf '%s' "$COMMAND" | command grep -qE '(^|[;|&(){}<>]|\n)[[:space:]]*"[^"]*[$`][^"]*"'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted quoted variable/backtick command-word indirection: $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi
if printf '%s\n' "$STRIPPED" | command grep -qE '(^|[];|\|&(){}<>[[:space:]])[[:space:]]*[$`]'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted variable or backtick indirection: $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# Fork-bomb pattern is a special case (no whitespace tokenizer works cleanly
# for `:(){ :|:& };:`). The canonical signature is `:(){ :|:& };:` — function
# defined with no body, calls itself + pipes to itself in background, terminated
# with `;:`. Some variants use `;}`. Match the structural shape (function
# definition + self-recursion + background pipe) rather than the exact terminator.
if printf '%s\n' "$STRIPPED" | command grep -qE ':[[:space:]]*\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:[[:space:]]*&[[:space:]]*\}[[:space:]]*;'; then
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted fork-bomb pattern: $RAW_COMMAND. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

# 2. Stripped-command deny check — preserves existing unquoted-mutation
# detection and catches anything the full-command check missed.
if printf '%s\n' "$STRIPPED" | command grep -qE "$DENY_PATTERNS"; then
  matched=$(printf '%s\n' "$STRIPPED" | command grep -oE "$DENY_PATTERNS" | head -1)
  hook_decision deny "VALIDATOR-BASH: $AGENT_TYPE attempted mutation ($matched): $RAW_COMMAND. Validators are read-only-by-doctrine — use Edit/Write tools for mutations, or dispatch a writer-class agent. Bypass: CLAUDE_DISABLED_HOOKS=validator-bash-guard"
  exit 0  # P0: security fix — explicit exit after deny
fi

exit 0
