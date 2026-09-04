#!/usr/bin/env bash
# Gate: ask before a raw `gh pr merge` runs outside the `ship-merge` skill flow.
# `convergence-merge-gate.sh` used to cover this and was retired 2026-08-24
# with the review pipeline (#82) — ship-merge/SKILL.md's own text admits its
# in-flow gates are "now the only merge-door protection", but those only fire
# when the model goes through the Skill call; a raw Bash `gh pr merge` had
# zero hook coverage until this file. Reads the PreToolUse JSON payload from
# stdin; emits `permissionDecision: ask` (exit 0) on a match, never a hard
# deny — a human can still approve a legitimate emergency merge in the
# moment, same tier `verifier-protect.sh` uses for tamper-sensitive edits.
#
# Known, deliberate non-goal: the REST equivalent (`gh api ... /pulls/N/merge`)
# is NOT covered. Catching every way to reach that endpoint is an arms race
# this gate does not try to win — `gh pr merge` is the documented, ordinary
# path `ship-merge` itself uses and the one operators actually type. Unlike
# irrecoverable.sh, PREFIX_WRAPPERS below has no xargs/docker-exec unwrap, so
# a wrapped form like `echo x | xargs -I{} gh pr merge {}` also isn't caught
# (deep-audit 2026-08-28) — same reasoning: not the ordinary typed path.
set -uo pipefail

# Fast path: skip the python3 cold-start unless both "gh" and "merge" survive
# a light normalize — same optimization idiom as irrecoverable.sh's own
# fast-path (a false positive here just spawns python; safe direction).
_input="$(cat)"
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ' | tr -d "\"'\\")"
# A backslash-newline continuation splitting "gh" or "merge" itself (e.g.
# "g\<newline>h pr merge 123") turns the \n escape into a space above, so
# neither candidate substring survives and the case below would exit 0
# without ever reaching the python scanner that reassembles it correctly
# -- confirmed live 2026-09-03, GH #126 (same "GH #122 adjacent finding"
# shape already fixed this way in irrecoverable.sh). A second, fully
# whitespace-collapsed variant catches that shape too; a false positive
# here just costs a python spawn, same safe direction as above.
_norm_nows="$(printf '%s' "$_norm" | tr -d '[:space:]')"
# A backtick, $(...) command substitution, or ${x}/$'...'/$@ splice vanishes
# (or resolves to unrelated text) in real bash but survives here as literal
# characters -- "g$(true)h pr merge 123" never contains a contiguous "gh"
# substring under either normalization pass above, so the case below would
# otherwise exit 0 and fully bypass this gate on a real `gh pr merge`-shaped
# command spliced this way (confirmed live 2026-09-03: rc=0, python3 never
# spawned). A raw backslash gets the same treatment for the same reason
# verifier-protect.sh's sibling _has_bs guard (GH #125/#134-adjacent) does:
# multiple backslashes ahead of a JSON-encoded newline can leave a residual
# character the substring match above doesn't expect. Same conservative-
# deferral direction as the sibling fixes in irrecoverable.sh/verifier-
# protect.sh: detect the PRESENCE of a marker on the RAW input and refuse the
# fast-allow regardless of what the substring match finds, rather than
# resolving/stripping the marker here -- python3's own tokenizer is a
# separate, deeper question and does not itself resolve command-substitution
# splicing (out of scope here, same as GH #129 for the sibling gates).
# Tradeoff: this moves merge-door.sh from "fast-exit unless gh+merge
# substrings survive" to "python3 spawns on any $/backtick/backslash
# command" -- a meaningfully larger share of real commands than the narrow
# gh+merge substring test above, since $ and backslash both appear in
# ordinary non-merge commands too. Accepted: a false positive here only
# costs a python3 cold start, never a wrong verdict.
_defer=0
case "$_input" in *\\*|*'`'*|*'$'*) _defer=1 ;; esac
case "$_norm$_norm_nows" in
  *gh*merge*) : ;;                    # candidate -> python
  *) [ "$_defer" -eq 1 ] || exit 0 ;; # no candidate token, but a splice marker is present -> defer to python
esac

# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — merge-door gate cannot run; allowing (install python3 to restore the gh pr merge ask)" >&2
  exit 0
fi

printf '%s' "$_input" | python3 "$(dirname "$0")/merge-door.py" "$(dirname "$0")/lib"
