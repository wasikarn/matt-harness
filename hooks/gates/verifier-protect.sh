#!/usr/bin/env bash
# Gate: prompt the human to approve any Write/Edit/MultiEdit — OR a Bash-mediated
# write (redirect, tee, sed -i, perl -i, cp, mv, rm, trash) — to the verifier
# surfaces: hooks/gates/**, hooks/advisory/**, hooks/hooks.json, the
# PreToolUse dispatcher's own routing (hooks/pretooluse-table.json,
# hooks/dispatch-pretooluse.py/.sh), AND the non-model audit verifier
# (skills/meta/harness-audit/scripts/audit.sh + checks/**) — so the model cannot
# neuter the deny-gates, silently turn an advisory sensor into something
# that emits permissionDecision, repoint or delete a gate's table entry, OR
# weaken the audit checks that judge it without an in-session human
# approval (the tamper-resistance principle: the agent cannot edit the code
# that judges it). hooks/advisory/** added 2026-08-06: previously
# unprotected, meaning a sensor could be edited into a real gate with zero
# prompt (found by a blind-spot sweep). hooks/pretooluse-table.json +
# dispatch-pretooluse.* added 2026-08-25: T12 moved gate routing OUT of the
# already-protected hooks/hooks.json into these three new files, which
# inherited none of that protection (found by an independent adversarial
# audit of #91, same day). A gate/check the model can silently disable is
# not a computational deny — and a half-protected perimeter is worse than
# none, so ALL FOUR deterministic verifier classes (gates, advisory
# sensors, the dispatcher's own routing, and audit) are guarded.
#
# Bash mode (tool_name == Bash): the Write/Edit matchers above do not see Bash,
# so `echo x > hooks/gates/irrecoverable.sh`, `sed -i …`, `tee`, `cp`/`mv` could
# edit a verifier surface with zero prompt (found 2026-07-03). This gate scans
# the Bash command for redirect targets and write-command file args that resolve
# into the protected set. Bounded idiom set — a habit-guard, not an adversarial
# sandbox; revisit if the threat model demands full Bash analysis.
#
# Emits a PreToolUse `permissionDecision: ask` JSON (exit 0) so Claude Code
# surfaces a live Approve/Deny prompt to the operator — no env-var bypass, no
# restart. The maker still cannot self-approve; the human decides each edit.
#
# Reads the PreToolUse JSON payload from stdin. Exit 0 + ask JSON on hit
# (JSON honored); exit 0 + no output on miss (clean allow); exit 0 + ask JSON
# on internal error too (fail-safe: an unparseable payload must never resolve
# to a silent allow on a tamper-resistance gate). One deliberate carve-out
# (#93): a machine with no python3 at all allows with a stderr note instead —
# announced fail-open, not silent (doctrine-bootstrap.sh also names it at
# SessionStart), because the classifier below cannot run at all there.
#
# Path matching is case-INsensitive: macOS/APFS is case-insensitive but
# case-preserving, and os.path.realpath() does not correct a path's casing to
# match the on-disk directory-entry casing — so a case-sensitive substring
# check can be bypassed by writing to a differently-cased path (e.g.
# "hooks/Gates/x.sh") that the filesystem still resolves into the real
# protected directory. Lowercasing both sides only widens the match (more
# prompts, never fewer) so it is safe on case-sensitive filesystems too.
#
# Folded path-hardcode deny (2026-07-03): the former gate:write:path-hardcode
# hook (a separate parallel PreToolUse hook) is folded into this gate's Write
# branch. It blocks a hardcoded /Users/<name> path written into a .sh/.py/.js
# file (case-insensitive endswith; scans content/new_string and MultiEdit
# edits[]) by exiting 2 BEFORE the verifier ask — a block wins over an ask,
# matching the prior parallel behavior where path-hardcode denied while this
# gate asked. Folding removes one python3 spawn per Write/Edit (a CPU win,
# not a felt-latency win: this gate's own python cold-start remains the
# Write-matcher floor). path-hardcode.sh and its hooks.json entry are deleted.
set -uo pipefail

# --- Fast path (Bash matcher only): skip the python3 cold-start on Bash
# commands that cannot write to a verifier surface. Write|Edit|NotebookEdit
# calls always reach python (the gate's primary purpose). For a Bash call, a
# write to a verifier surface needs EITHER the verifier path spelled out in the
# command (redirects, tee/cp/mv/sed/perl/rsync/dd/rm/trash targets are argv) OR
# a diff/archive carrier (git apply/am, patch, tar -x) whose real target lives
# inside a diff file or resolves to cwd -- invisible to a command-string
# substring match, so those carriers fall through to python unconditionally
# (plan-review 2026-08-14: git apply/am + patch + tar-cwd would otherwise fail
# open -- `git apply /tmp/x.diff` with `+++ b/hooks/gates/...` rewrites a gate
# with no prompt) OR an unquoted $VAR/~ target that python expands
# (os.path.expandvars/expanduser, line ~427) into a verifier path invisible to
# the raw command string (found by tests/hooks/test-verifier-protect.sh's
# existing $TARGETDIR/~ battery cases -- both fell open on the first version of
# this fast-path). False positives (digit/start/dispatch) just spawn python.
# Out of threat model (this gate is not an adversarial sandbox, line ~210): a
# pre-existing symlink whose realpath resolves into a verifier surface, and
# \u JSON escapes (the CC serializer emits ASCII alphanumerics literally).
# sync-seam: the stdin-capture + whitespace-normalize prefix (this line +
# the next) is hand-duplicated in irrecoverable.sh's own fast-path -- not
# extracted to a shared sourced helper because these gates govern their own
# edits (a shared-helper bug would break both simultaneously; editing this
# exact fast-path cost 2 self-inflicted lockouts before it landed clean,
# 2026-08-14). If either file's normalize step changes, check the other.
_input="$(cat)"
_ws="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ')"
_run=1
# GH #125: the sed step above matches only the LAST backslash immediately
# before a JSON-encoded "\n", so a real 1-backslash bash line-continuation
# (which fully vanishes in real bash, gluing e.g. "hoo" + continuation +
# "ks/gates/x.sh" into "hooks/gates/x.sh") survives normalization as a
# residual space instead ("hoo ks/gates/x.sh") -- breaking the contiguous
# substring match below and letting a real verifier-surface write fall
# through as a fast-path allow. Rather than reimplement bash own
# parity-sensitive continuation rule (odd backslash-run = continuation, even
# = a real escaped backslash + ordinary newline) in sed/bash -- this exact
# fast-path region has already cost 2 self-inflicted lockouts, and python own
# _newlines_to_seps below already gets this parity rule right -- any raw
# backslash anywhere in the input disables the whole fast-allow
# classification below and defers to python unconditionally. Same "false
# positives just spawn python" direction as every other coarse check here.
_has_bs=0
case "$_input" in *\\*) _has_bs=1 ;; esac
# GH #128/#130: a backtick or $(...) command substitution (also ${x} with x
# unset, $'...' ANSI-C quoting, and $@/$* with zero positional parameters --
# each found and fixed one spelling at a time, 2026-09-03) vanishes in real
# bash but survives here as literal characters, splicing either check below
# apart -- a protected path (`echo x > hoo`true`ks/gates/probe.sh`, GH #128)
# or a write-command NAME (`c$(true)p evil.sh hooks/gates/x.sh`, GH #130) --
# so the contiguous substring match neither case-statement below performs can
# catch it. Enumerating specific spellings kept finding gaps (4 rounds), so
# this is the general form instead: ANY bare `$` or backtick anywhere in the
# raw input refuses the whole fast-path classification below (one guard on
# the outer `if`, since both case-statements live inside it) -- a strict
# superset of every enumerated marker, since each one itself contains a `$`
# or a backtick. Same conservative-deferral direction as the _has_bs guard
# above and the sibling fix in irrecoverable.sh: detect the PRESENCE of the
# marker on the RAW input rather than resolving the substitution here.
_has_subst=0
case "$_input" in *'`'*|*'$'*) _has_subst=1 ;; esac
# Match the quoted tool_name value precisely (the "Bash" is the JSON value, not
# a substring of a longer word) so a Write to a file_path that happens to
# contain "Bash" is not mis-routed through the Bash fast-path (which could exit
# 0 and skip the gate's primary Write-path protection). [[ =~ ]] is used
# because a `case` pattern cannot contain literal double-quotes cleanly (the
# syntax-error lockout on the first attempt). The regex tolerates the optional
# space after the colon in both JSON serializations.
if [ "$_has_bs" -eq 0 ] && [ "$_has_subst" -eq 0 ] && [[ $_ws =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"Bash\" ]]; then
  # GH #127: lowercase before matching. macOS/APFS is case-insensitive but
  # case-preserving (header comment above), so a case-sensitive substring
  # check can be bypassed by a differently-cased path spelling
  # (hooks/GATES/x.sh) that the filesystem still resolves into the same real
  # protected directory. Lowercasing only widens the match (more python
  # spawns, never fewer allows), matching the python-side is_gate_path()
  # behavior this file's header already promises.
  _norm="$(printf '%s' "$_ws" | tr -d "\"'\\" | tr '[:upper:]' '[:lower:]')"
  case "$_norm" in
    *git*|*patch*|*tar*) : ;;  # diff/archive carrier -> target may be in a file/cwd -> python
    *tee*|*sed*|*perl*|*cp*|*mv*|*install*|*rsync*|*dd*|*rm*|*trash*|*">"*)
      case "$_norm" in
        *hooks/gates*|*hooks/advisory*|*hooks/hooks.json*|*hooks/pretooluse-table.json*|*hooks/dispatch-pretooluse*|*skills/harness-audit*|*skills/*/harness-audit*|*'~'*) : ;;  # write + verifier path (or an expandable ~ target) -> python (a $ target is already caught by the outer _has_subst guard above)
        *) _run=0 ;;  # write to a non-verifier, non-expandable surface -> allow fast
      esac
      ;;
    *) _run=0 ;;  # no write/redirect token -> allow fast
  esac
fi
[ "$_run" -eq 0 ] && exit 0

# Portability guard (#93): announced fail-open — without python3 this gate
# cannot classify the call at all; doctrine-bootstrap.sh names the missing
# dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — verifier-protect gate cannot run; allowing (install python3 to restore verifier-surface protection)" >&2
  exit 0
fi

_py="$(dirname "$0")/verifier-protect.py"
# Corrupted/partial plugin install (follow-up to #146): without this check,
# python3 itself exits 2 on the missing file with a raw "can't open file
# ..." message -- a bare nonzero exit, not this gate's documented
# all-outcomes-are-exit-0 "ask on internal error too" contract (header
# comment above). Emit the same ask-JSON shape emit_ask() produces so the
# operator gets a clean, actionable prompt instead of a stray traceback.
if [ ! -r "$_py" ]; then
  printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "verifier-protect: sibling script verifier-protect.py is missing or unreadable -- failing safe, approve manually or investigate the plugin install."}}'
  exit 0
fi

printf '%s' "$_input" | python3 "$_py" "$(dirname "$0")/lib"
