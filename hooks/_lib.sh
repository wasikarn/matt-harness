#!/bin/bash
# _lib.sh — shared protocol for Claude Code hooks (PreToolUse / UserPromptSubmit / etc).
# Slurps stdin, honors CLAUDE_HOOK_PROFILE=off + CLAUDE_DISABLED_HOOKS, and exposes
# the three emission helpers (decision, audit, strip_quoted) every hook reimplements.
#
# Usage:
#   HOOK_ID=my-hook
#   source "$(dirname "$0")/_lib.sh"
#   hook_init "$HOOK_ID" || exit 0          # sets INPUT/TOOL/SID/TOOL_INPUT
#   hook_decision <allow|deny|ask> "reason" # emits JSON, exits 0
#   hook_audit_log <basename> <col>...      # appends TSV to ~/.claude/<basename>.log
#   hook_strip_quoted [str]                 # echo str with '…' "…" #… neutralized
#
# Knob: HOOK_HONOR_PROFILE_OFF=0 (set BEFORE sourcing) to bypass the PROFILE=off
# short-circuit — use for audit hooks that must log even when PROFILE=off.
#
# Behavioral contract preserved verbatim from the previous inline versions:
#   - decision-emit hooks exit 0 (exit 2 would discard JSON per Claude Code spec)
#   - permissionDecision values: "deny" | "allow" | "ask"
#   - audit log prefix: ts \t session-id, then caller's columns in order
#   - DISABLED match: substring on ",$DISABLED," to avoid partial-id false matches

# hook_init sets TOOL / TOOL_INPUT / PROMPT as globals for CALLERS (the sourcing
# hooks); shellcheck runs without -x so it can't see the cross-file use and flags
# them SC2034. Same cross-file rationale as the per-hook disables (e.g.
# bypass-audit-log.sh), applied file-wide here since this is the shared library.
# shellcheck disable=SC2034
hook_init() {
  local hook_id="$1"
  INPUT=$(cat)
  PROFILE="${CLAUDE_HOOK_PROFILE:-standard}"
  DISABLED="${CLAUDE_DISABLED_HOOKS:-}"

  if [ "${HOOK_HONOR_PROFILE_OFF:-1}" = "1" ] && [ "$PROFILE" = "off" ]; then
    return 1
  fi
  case ",$DISABLED," in
    *",$hook_id,"*) return 1 ;;
  esac

  if command -v jq >/dev/null 2>&1; then
    # ONE jq call extracts the SECURITY-CRITICAL fields (tool_name + tool_input)
    # AND validates the payload is an object (else→error). Folding validation +
    # extraction into a single fork shrinks the transient-jq-failure window that
    # previously left a gate with empty $TOOL = silent fail-open under CPU
    # contention (the validate call and the field calls were separate forks; a
    # transient failure on a field call gave empty TOOL with INPUT_PARSE_ERROR=0).
    # Both fields are newline-free (tool_name is an identifier; tool_input via
    # `tojson` is single-line), so the 2-line output reads cleanly.
    local _crit
    if _crit=$(printf '%s' "$INPUT" | jq -r 'if type=="object" then (.tool_name // ""), (.tool_input // {} | tojson) else error("not-object") end' 2>/dev/null); then
      INPUT_PARSE_ERROR=0
      # Two reads, one per line: a single `read TOOL TOOL_INPUT` stops at the
      # first newline (the line terminator), leaving TOOL_INPUT empty. The first
      # line is tool_name, the second is the single-line tool_input JSON.
      { IFS= read -r TOOL; IFS= read -r TOOL_INPUT; } <<<"$_crit"
      [ -z "$TOOL_INPUT" ] && TOOL_INPUT="{}"
      # session_id + prompt are NON-security (logging only): a transient failure
      # here degrades the log row, not a gate decision — soft defaults are fine.
      SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "no-sid"' 2>/dev/null); [ -z "$SID" ] && SID="no-sid"
      PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
    else
      INPUT_PARSE_ERROR=1
      TOOL=""
      SID="no-sid"
      TOOL_INPUT="{}"
      PROMPT=""
    fi
  else
    INPUT_PARSE_ERROR=0
    TOOL=""
    SID="no-sid"
    TOOL_INPUT="{}"
    PROMPT=""
  fi
  return 0
}

# hook_guard_unreadable — call right after hook_init in a SECURITY gate. If the
# input was PRESENT but could not be parsed (transient jq failure under load, or
# a malformed envelope), FAIL CLOSED: emit `ask` so the human decides, instead of
# the default fall-through that silently ALLOWS the action. Advisory/log hooks
# skip this (they have nothing to gate). Pairs with the single-fork hook_init
# above: a transient jq failure now reliably sets INPUT_PARSE_ERROR=1, which this
# guard converts to a safe `ask`.
hook_guard_unreadable() {
  if [ "${INPUT_PARSE_ERROR:-0}" -ne 0 ] && [ -n "${INPUT:-}" ]; then
    hook_decision ask "[${HOOK_ID:-hook}] could not parse hook input — failing safe (ask). Retry, or set CLAUDE_DISABLED_HOOKS=${HOOK_ID:-this-hook} if this is a false positive."
  fi
}

# hook_require_jq — call AFTER hook_init when the hook's body needs jq and
# the original behavior was to fail-loud (exit 1) if jq is missing. Most
# PreToolUse gates use this; a few soft-fail (fabrication-verdict-log,
# post-edit-audit, auto-mode-denial-log) and skip the check.
hook_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "[${HOOK_ID:-hook}] ERROR: jq not found — cannot parse hook input" >&2
    exit 1
  fi
}

# hook_require_prompt — call AFTER hook_init when the hook's body needs a
# parsed .prompt field. Fail-loud (exit 1) if stdin was non-empty but the
# payload didn't parse as JSON OR jq was missing. Matches the original
# inline `PROMPT=$(jq -r '.prompt // empty') || { echo ...; exit 1; }`
# behavior of iron-rule-reminder.sh / orchestrator-nudge.sh / skill-nudge.sh.
hook_require_prompt() {
  hook_require_jq
  if [ "${INPUT_PARSE_ERROR:-0}" -ne 0 ] && [ -n "$INPUT" ]; then
    echo "[${HOOK_ID:-hook}] ERROR: failed to parse prompt" >&2
    exit 1
  fi
}

# Emit permissionDecision JSON, then exit 0. Robust against a flaky/broken jq:
# jq is primary, python3 is the fallback, a hand-escaped printf is the last
# resort. This is load-bearing for security — if jq transiently fails (fork/fd
# pressure under load) while emitting a deny/ask, a jq-only path would emit
# NOTHING and the action silently fails OPEN. The fallbacks guarantee the
# decision is always emitted.
hook_decision() {
  local d="$1" r="$2"
  if command -v jq >/dev/null 2>&1 && \
     jq -nc --arg d "$d" --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}' 2>/dev/null; then
    exit 0
  fi
  if command -v python3 >/dev/null 2>&1 && \
     HD_D="$d" HD_R="$r" python3 -c 'import json,os,sys; sys.stdout.write(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":os.environ["HD_D"],"permissionDecisionReason":os.environ["HD_R"]}}, separators=(",",":"))+"\n")' 2>/dev/null; then
    exit 0
  fi
  # Last resort: hand-escape the reason (flatten newlines/tabs, escape \ and ").
  local safe
  safe=$(printf '%s' "$r" | tr '\n\t' '  ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$d" "$safe"
  exit 0
}

# Append ts \t session \t <caller cols...> as TSV to ~/.claude/<basename>.log.
hook_audit_log() {
  local log="$HOME/.claude/${1}.log"; shift
  # P0: fail loud on unwritable audit dir — silent drop loses audit rows
  mkdir -p "$(dirname "$log")" || {
      echo "[${HOOK_ID:-hook}] ERROR: cannot create audit log directory" >&2
      return 2
  }
  # P1: fail loud on append failure — silent drop loses audit rows
  {
    printf '%s\t%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SID:-no-sid}"
    local col
    for col in "$@"; do printf '\t%s' "$col"; done
    printf '\n'
  } >> "$log" || {
    echo "[${HOOK_ID:-hook}] ERROR: failed to append to audit log $log" >&2
    return 2
  }
}

# _now_ms — millisecond epoch timestamp. BSD `date` (macOS) has no %N, so
# `date +%3N` yields a literal "3N" — mint via python3 instead. Used to compose
# the journal `id`. See claude/hooks/JOURNAL-SCHEMA.md.
_now_ms() {
  python3 -c 'import time; print(int(time.time() * 1000))'
}

# journal_append <hook_id> <event_name> <fields_json>
# Append one nested-envelope event to the governance evidence journal
# (~/.claude/governance-events.jsonl). Contract: claude/hooks/JOURNAL-SCHEMA.md.
# Bash producers call this; python producers build the same dict via json.dumps.
#   - exit 2 (fail-loud) if jq is missing — never a silent drop
#   - deny-list redaction over fields keys + string values BEFORE write
#   - id = <ms>-<hook>-<rand> stays unique across parallel appends (no flock needed)
# Override the target with CLAUDE_JOURNAL_PATH (test-only).
journal_append() {
  local hook_id="$1" event="$2" fields_json="$3"
  command -v jq >/dev/null 2>&1 || {
    echo "[${hook_id}] ERROR: jq not found — cannot append governance event" >&2
    exit 2
  }
  local journal="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
  # P0: fail loud on unwritable journal dir — silent drop loses governance events
  mkdir -p "$(dirname "$journal")" || {
      echo "[${hook_id}] ERROR: cannot create journal directory" >&2
      return 2
  }

  local ms iso rand
  ms=$(_now_ms)
  # ISO8601-with-ms (ts) + random suffix (id uniqueness), one python call.
  read -r iso rand < <(python3 -c 'import uuid,datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]+"Z", uuid.uuid4().hex[:8])')
  # Fail loud if the mint came back empty (python3 missing/broken) instead of
  # writing a malformed envelope with an empty ts or a "<ms>-<hook>-" id.
  if [ -z "$ms" ] || [ -z "$iso" ] || [ -z "$rand" ]; then
    echo "[${hook_id}] ERROR: failed to mint id/ts (python3?) — not writing a malformed event" >&2
    exit 2
  fi

  # Deny-list backstop (thin — source minimization is the PRIMARY defense; see
  # JOURNAL-SCHEMA.md). walk() recurses objects AND arrays AND scalars: a value
  # is redacted when its KEY matches a secret-ish name, or when a string (at any
  # depth, including array elements) matches a secret name OR a known secret
  # SHAPE (AWS/GitHub/Slack tokens, PEM private keys, user:pass@ URLs). Over-
  # redaction is acceptable for a backstop.
  local key_dl='password|api_key|secret|token|credential'
  local val_dl='password|api_key|secret|token|credential|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN[A-Z ]*PRIVATE KEY|[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@'
  local redacted
  redacted=$(printf '%s' "$fields_json" | jq -c --arg kdl "$key_dl" --arg vdl "$val_dl" '
    walk(
      if type == "object" then
        with_entries(if (.key | test($kdl; "i")) then .value = "[redacted]" else . end)
      elif type == "string" then
        (if test($vdl; "i") then "[redacted]" else . end)
      else . end)' 2>/dev/null) || redacted=""
  # Never silent-drop (JOURNAL-SCHEMA.md): if redaction produced nothing, jq
  # failed, or the caller passed invalid JSON, the final --argjson would discard
  # the event with no trace. Surface it and exit 2 instead of writing nothing.
  if [ -z "$redacted" ] || ! printf '%s' "$redacted" | jq -e . >/dev/null 2>&1; then
    echo "[${hook_id}] ERROR: fields_json is not valid JSON (or redaction failed) — refusing to drop the event silently" >&2
    exit 2
  fi

  # P1: fail loud on journal append failure — silent drop loses governance events
  if ! jq -nc \
    --arg id "${ms}-${hook_id}-${rand}" \
    --arg ts "$iso" \
    --arg session "${SID:-no-sid}" \
    --arg hook "$hook_id" \
    --arg event "$event" \
    --argjson fields "$redacted" \
    '{id: $id, ts: $ts, session: $session, hook: $hook, event: $event, source: "journal_append", fields: $fields}' \
    >> "$journal"; then
    echo "[${hook_id}] ERROR: failed to append to journal $journal" >&2
    exit 2
  fi
  # Phase II (C1 Evidence Journal): echo the minted id on stdout so callers
  # that link events (e.g. the review-pr journaler in `claude/scripts/`) can
  # capture the finding id and reference it as a later verdict's `subject_id`.
  # Existing callers that ignore stdout are unaffected; `$(journal_append ...)`
  # captures cleanly on one line.
  printf '%s\n' "${ms}-${hook_id}-${rand}"
}

# _sensor_heartbeat — write one "sensor_evaluated" event per hook per session.
# Called from comp-ff hooks (PreToolUse gates) so harness-coverage can see them
# as active on clean sessions (no deny/ask fired). Dedup via a temp file keyed
# on hook_id + session_id; non-blocking (subshell + || true).
_sensor_heartbeat() {
  local hook_id="${HOOK_ID:-hook}"
  local sid="${SID:-nosid}"
  local safe_id; safe_id=$(printf '%s' "${hook_id}_${sid}" | tr -c 'a-zA-Z0-9_' '_')
  local flag="/tmp/kbg_hb_${safe_id}"
  [ -f "$flag" ] && return 0
  touch "$flag" 2>/dev/null || true
  ( journal_append "$hook_id" "sensor_evaluated" '{"trigger":"heartbeat"}' \
      >/dev/null 2>&1 ) || true
}

# Python shim over _lib.py:journal_append. Form A (python3 -c) — no
# `if __name__ == "__main__"` block in _lib.py per Delta 2 (single emission
# point; CLI dispatch lives in the caller). Routes config-change-log.sh
# (the one remaining bash caller of journal_append) through the Python
# module so the journal path has exactly ONE redaction/id-mint impl.
# Lockstep invariant: this shim stamps the same envelope literal that
# _lib.sh:journal_append does (source: "journal_append" pinned in
# JOURNAL-SCHEMA.md; COMPACT_JSON shape `separators=(",", ":")`).
# Args: <hook_id> <event> <fields_json>  — identical to journal_append.
# The python module prints the minted id on stdout (Phase II linkage);
# the bash shim must propagate that same id so `$(...)` captures cleanly.
# sys.path.insert(0, libdir) is required because _lib.py is repo-local
# (claude/hooks/), not pip-installed. CLAUDE_SESSION_ID propagation matches
# _lib.py's `os.environ.get("CLAUDE_SESSION_ID", "no-sid")` precedence.
_journal_append_py() {
  local hook_id="$1" event="$2" fields_json="$3"
  # Guard: python3 must exist (F5 contract = rc=2 + ERROR prefix). Without
  # this, a host without python3 in PATH returns 127 with "python3: command
  # not found" — not 2, no [hook_id] ERROR prefix — and monitoring alerts
  # that grep for "ERROR" miss the case. Sister to the jq guard in
  # journal_append above.
  command -v python3 >/dev/null 2>&1 || {
    echo "[${hook_id}] ERROR: python3 not found in PATH; cannot journal event '${event}'" >&2
    return 2
  }
  local libdir="${_LIBPY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  # Forward CLAUDE_JOURNAL_PATH explicitly: the bash `journal_append` reads it
  # via local expansion, but python's `os.environ.get(...)` only sees EXPORTED
  # vars. A non-exported subshell assignment (e.g. `CLAUDE_JOURNAL_PATH=$J
  # _journal_append_py …`) would silently fall through to the production journal
  # — the only direct producer-side foot-gun the python path inherits.
  # Capture python's stderr explicitly (Important #1 from PR #1 review):
  # the caller can now suppress or reformat the shim's stderr without
  # touching their own stream. Stdout passes through unchanged (FF
  # contract: the minted id is on stdout).
  #
  # FD 7 (not FD 3 — FDs 3-6 are caller-reserved by convention; a caller
  # that pre-opens FD 3 for audit logging would have it silently closed
  # by `exec 3>&-` on return) holds the function's call-site stdout.
  # The subshell inherits it and python's stdout goes there. `$(...)`
  # captures only the subshell's stdout (which now holds python's
  # stderr), leaving python's actual stdout untouched on FD 7.
  #
  # F5 enforcement (Critical #2 from PR #2 review): if python exits
  # non-zero and the captured stderr doesn't already carry the
  # `[<hook_id>]` prefix, re-emit with the prefix. The python journaler
  # is supposed to print `[hook_id] ERROR: ...` before `sys.exit(2)`,
  # but a non-2 failure path (NameError, ImportError, OOM at rc=137,
  # SIGSEGV at rc=139) bypasses the prefix and leaves the caller with
  # a raw traceback. The shim is the contract enforcer, not a passthrough.
  local _py_stderr="" _py_rc=0
  exec 7>&1
  # Capture python's stderr only; python's stdout passes through to
  # FD 7 (the caller's stdout) unchanged. The shim cannot directly
  # inspect the id on stdout, but the python journaler's contract is
  # "always print rid on success" and the regression-guard is the LL
  # test in test-critical-hooks.sh (faked _lib.py that omits
  # `print(rid)` → asserts the caller observably notices via the
  # bash `journal_append` test, F2, which already pins stdout non-empty
  # for the bash path; the LL test is the shim-path equivalent).
  _py_stderr=$(CLAUDE_SESSION_ID="${CLAUDE_SESSION_ID:-${SID:-no-sid}}" \
    CLAUDE_JOURNAL_PATH="${CLAUDE_JOURNAL_PATH:-}" \
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _lib; _lib.journal_append(*sys.argv[2:])' \
    "$libdir" "$hook_id" "$event" "$fields_json" 2>&1 1>&7)
  _py_rc=$?
  exec 7>&-
  # F5 enforcement (Critical #2 from PR #2 review): if python exits
  # non-zero and the captured stderr doesn't already carry the
  # `[<hook_id>]` prefix, re-emit with the prefix. The python journaler
  # is supposed to print `[hook_id] ERROR: ...` before `sys.exit(2)`,
  # but a non-2 failure path (NameError, ImportError, OOM at rc=137,
  # SIGSEGV at rc=139) bypasses the prefix and leaves the caller with
  # a raw traceback. The shim is the contract enforcer, not a passthrough.
  if [ "$_py_rc" -ne 0 ] && ! [[ "$_py_stderr" == "[${hook_id}]"* ]]; then
    _py_stderr="[${hook_id}] ERROR: python journaler exited rc=${_py_rc} without F5 prefix — ${_py_stderr}"
  fi
  if [ -n "$_py_stderr" ]; then
    printf '%s\n' "$_py_stderr" >&2
  fi
  return $_py_rc
}

# Echo arg (or stdin) with '…' "…" #… neutralized so a regex matches shell
# intent rather than literal string contents.
hook_strip_quoted() {
  local input="${1:-$(cat)}"
  # Three sed passes: drop '…' then "…" then #… tails. (Easier to read with
  # one regex each than a single combined alternation.)
  sed -E -e "s/'[^']*'//g" -e 's/"[^"]*"//g' -e 's/#.*$//g' <<<"$input"
}
