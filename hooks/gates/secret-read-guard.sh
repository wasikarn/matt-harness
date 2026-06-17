#!/bin/bash
# Block READING secret files via the Read tool or Bash reader-commands.
# Complements secret-scan.sh (which blocks WRITING secret values).
#
# Why this exists: on 2026-05-25 we proved permissions.deny Read(**/*.pem),
# Read(**/*.key), Read(**/credentials.json) does NOT enforce — a broad "Read"
# allow rule overrides the specific Read(...) denies (anthropics/claude-code
# #51211, open; #37210 deny tool-inconsistency). Native deny is unreliable for
# the Read tool, so a deterministic hook is the real control — METHODOLOGY
# Rule 5 (let code answer deterministic questions), Rule 12 (fail loud).
#
# Detection:
#   Read tool  → file_path matched against is_secret_path.
#   Bash tool  → command is split into segments on shell operators
#                (| || && ; & and $()/backtick boundaries); a segment is only
#                inspected when it is LED by a file-argument reader command
#                (cat/head/tail/less/strings/xxd/cp/dd/gpg/...). Each arg of
#                such a segment is checked. This per-segment + segment-leader
#                design fixes the 2026-05-25 false-positive where any reader
#                token anywhere in a compound command (e.g. `git commit -m
#                "...env..." | grep mode`) caused the whole line's tokens to be
#                scanned.
#
# NOT airtight (acceptable per Rule 2 — common exfil readers covered, note gaps):
#   - pattern-first readers (grep/sed/awk/rg/ag) are intentionally NOT covered:
#     their first arg is a pattern not a file, so including them re-introduced
#     false positives (`grep '.env' file`). `grep KEY .env` therefore slips.
#   - env-prefixed or wrapped invocations (`sudo cat .env`, `env cat .env`),
#     python/perl one-liners, and nested command substitution can slip.
#   Template env files (.env.example/.sample/.template/.dist) are allowed.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=secret-read-guard
#
# Behavior (canonical per Claude Code hooks spec):
#   secret path detected → exit 0 with hookSpecificOutput permissionDecision=deny
#   no match             → exit 0 silently (pass-through)
#   non-target tool      → exit 0
#   jq missing / parse error → exit 1 (fail loud, Rule 12 — a guard that can't
#     read its input must not silently pass)

set -uo pipefail

HOOK_ID="secret-read-guard"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


hook_require_jq

# Return 0 (true) if the argument looks like a secret file path.
# Template / example env files are explicitly allowed (read often, no secrets).
is_secret_path() {
  local p="$1"
  case "$p" in
    *.env.example|*.env.sample|*.env.template|*.env.dist|*.env.defaults) return 1 ;;
    *.example|*.sample|*.template|*.dist) return 1 ;;
  esac
  case "$p" in
    *.env|*.env.*) return 0 ;;
    *.pem|*.key|*.p12|*.pfx|*.pkcs12|*.keystore|*.jks|*.ppk) return 0 ;;
    credentials.json|*/credentials.json) return 0 ;;
    */.ssh/*|*/.aws/*|*/.gnupg/*) return 0 ;;
    */id_rsa|*/id_dsa|*/id_ecdsa|*/id_ed25519) return 0 ;;
  esac
  return 1
}

REASON_TAIL="Native permissions.deny does not reliably block reads (anthropics/claude-code#51211). Use an env var / secret manager, or read a redacted copy. Bypass: CLAUDE_DISABLED_HOOKS=secret-read-guard"

# Normalize a token for path matching: drop leading redirection chars and
# trailing shell punctuation (so `.env.example).` is tested as `.env.example`).
clean_token() {
  printf '%s' "$1" | sed -E 's/^[<>]+//; s/[).,;:]+$//'
}

case "$TOOL" in
  Read)
    FP=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // empty') || {
      echo "[$HOOK_ID] ERROR: failed to parse Read file_path" >&2
      exit 1
    }
    [ -z "$FP" ] && exit 0
    if is_secret_path "$FP"; then
      hook_decision deny "Blocked Read of secret-looking file: ${FP}. ${REASON_TAIL}"
    fi
    ;;
  Bash)
    COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
      echo "[$HOOK_ID] ERROR: failed to parse Bash command" >&2
      exit 1
    }
    [ -z "$COMMAND" ] && exit 0

    # Strip comments, then DELETE quote characters AND backslashes so
    # escaped quotes (\" or \') can't hide a secret path.
    STRIPPED=$(printf '%s\n' "$COMMAND" | sed -E 's/#.*$//g' | tr -d '"'\''\\')

    # Break into command segments on shell operators + command-substitution
    # boundaries, so each segment is a single simple command we can judge by
    # its leading command word.
    SEGMENTS=$(printf '%s\n' "$STRIPPED" | sed -E 's/\|\|/\n/g; s/&&/\n/g; s/[|;&]/\n/g; s/\$\(/\n/g; s/[`)]/\n/g')

    while IFS= read -r seg; do
      [ -z "$seg" ] && continue
      set -f
      # shellcheck disable=SC2086
      set -- $seg
      set +f
      # Skip leading VAR=value environment-assignment prefixes.
      while [ $# -gt 0 ]; do
        case "$1" in
          [A-Za-z_]*=*) shift ;;
          *) break ;;
        esac
      done
      [ $# -eq 0 ] && continue
      cmd="${1##*/}"; shift   # basename, so /bin/cat -> cat
      # Only inspect segments led by a file-argument reader command.
      case "$cmd" in
        cat|tac|nl|less|more|head|tail|strings|xxd|od|hexdump|base64|bat|view|cp|scp|rsync|dd|gpg) ;;
        *) continue ;;
      esac
      for a in "$@"; do
        clean=$(clean_token "$a")
        if is_secret_path "$clean"; then
          hook_decision deny "Blocked Bash read of secret-looking path: ${clean}. ${REASON_TAIL}"
        fi
      done
    done <<< "$SEGMENTS"
    ;;
  *)
    exit 0
    ;;
esac

exit 0
