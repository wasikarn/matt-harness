#!/usr/bin/env bash
# SessionStart: surface memory-lint findings (dangling links, orphans, index
# drift, near-budget) at session start.
#
# Restores the surfacing loop dropped in the 2026-06-27 "reset: rebuild from
# scratch" (c452102), which deleted the prior
# hooks/maintenance/memory-lint-check.sh without updating
# skills/memory-lint/SKILL.md — that doc claimed this hook was still running
# for ~6 weeks while it wasn't. See
# docs/research/agent-memory-engineering-2026-08-07.md (proposal A1): 87
# findings had accumulated silently on the live store before this was
# noticed. memory-lint.py itself was never broken — only the loop that makes
# anyone actually run it was gone.
#
# Advisory only. SessionStart stdout becomes injected session context, never
# a permissionDecision (cf. hooks/session/doctrine-bootstrap.sh); silent when
# clean, matching every other nudge in this fleet.
#
# Directory resolution: memory-lint.py's own memory_dir() resolves
# os.getcwd().replace("/", "-") — NOT git toplevel (a prior version of this
# hook used git-toplevel encoding; the current memory-lint.py's own comments
# flag that as a bug — it points at the wrong memory dir whenever CC launches
# from a subdirectory). This script never re-implements that encoding for the
# real lookup — it invokes memory-lint.py with no positional path argument
# and lets it resolve its own directory from the inherited cwd, so there is
# exactly one place that logic lives. The pwd-based substitution below is
# ONLY a cheap pre-check (a bash builtin fork, orders of magnitude cheaper
# than a python3 interpreter spawn) to skip spawning python3 in the common
# case (a project with no memory store at all); it
# does not need to be authoritative — but it must still resolve the same
# physical path os.getcwd() would, so `pwd -P` (not $PWD) is required: on
# macOS, /tmp and /var are symlinks into /private/…, so a project reached
# through one of those would silently never match without -P (confirmed via
# a manual fixture run against /tmp during this hook's own testing).
set -uo pipefail

LINT="${CLAUDE_PLUGIN_ROOT:-}/skills/memory-lint/scripts/memory-lint.py"
[ -f "$LINT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

PHYSPWD="$(pwd -P)"
ENC="${PHYSPWD//\//-}"
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR" ] || exit 0

# Skip the python3 scan if nothing in the store changed since the last run.
# -maxdepth 1 is deliberate, not a gap: memory-lint.py's collect_state() reads
# only top-level *.md via non-recursive os.listdir() (see its own "lives flat"
# comment) — _archive/ and _candidates/ never feed the detector, so a change
# inside either can never affect what a rescan would report. Widening this to
# recurse would only add pointless rescans.
CACHE="$HOME/.claude/state/memory-lint-cache-$ENC"
mkdir -p "$HOME/.claude/state" 2>/dev/null
if [ -f "$CACHE" ] && [ -z "$(find "$MEMDIR" -maxdepth 1 -type f -newer "$CACHE" 2>/dev/null | head -1)" ]; then
  exit 0
fi

# memory-lint.py exits len(findings) on success (see its own sys.exit calls) —
# a non-zero exit is the NORMAL path whenever findings exist, so exit code
# alone can't tell "1 real finding" (exit 1) apart from a genuine crash
# (also typically exit 1). Only an actual traceback on stderr means it
# crashed; that's the one case where OUT can't be trusted and the cache must
# not be touched, since a stale touch here would suppress every subsequent
# run's rescan (and any real findings) until $MEMDIR's mtime changes again.
ERRLOG=$(mktemp "${TMPDIR:-/tmp}/kbg-memlint-err.XXXXXX" 2>/dev/null) || ERRLOG=""
if [ -n "$ERRLOG" ]; then
  OUT=$(python3 "$LINT" 2>"$ERRLOG")
  if command grep -q '^Traceback' "$ERRLOG" 2>/dev/null; then
    OUT=""
  else
    touch "$CACHE" 2>/dev/null
  fi
  rm -f "$ERRLOG" 2>/dev/null
else
  OUT=$(python3 "$LINT" 2>/dev/null) || true
  touch "$CACHE" 2>/dev/null
fi

# memory-lint prints "… | findings: N" — emit only when N ≥ 1 (silent when
# clean). Deliberately NOT gating on the 2026-08-17 "advisory: N stale, M
# template-gap" line either signal: template compliance sits at 71/149 on the
# live store and won't reach 0 soon, and staleness has the identical
# permanence problem — MEMORY.md's own "Settled audits — don't redo without
# new evidence" entries are dormant *by design* and will cross the 90d
# threshold with nobody editing them (the earliest, refactor-survey-2026-06-18,
# in September 2026). Gating on either would make this hook fire forever,
# defeating the silent-when-clean design — matches memory-lint.py's own
# framing of both signals as "visibility… not enforcement", i.e. deliberately
# non-gating. Both still ride along in the body when findings trigger a fire.
printf '%s' "$OUT" | command grep -qE 'findings: [1-9]' || exit 0

# Strip both the Staleness and Template compliance sections before printing —
# each can dump one line per file (up to 71 for template-gap; staleness has
# the identical shape once any file crosses the 90d threshold, confirmed live
# 2026-08-17: a fixture with 1 dangling-link finding + 1 stale file leaked
# "STALE: <file> — 100d since last edit" straight into the nudge, the same
# bury-the-actual-finding bug this section was written to fix in the first
# place, one section over). `kbg:memory-lint` still surfaces both on demand.
# The trailing "advisory: N stale, M template-gap" line (kept below) already
# carries both counts, so nothing is lost by collapsing the two sections.
FILTERED=$(printf '%s\n' "$OUT" | command sed -e '/^--- Staleness/,/^advisory:/{' -e '/^advisory:/!d' -e '}')

printf '%s\n' \
  "[memory-lint] The memory store has findings (dangling links / orphans / index drift / near-budget):" \
  "$FILTERED" \
  "Run \`kbg:memory-lint\` for detail, or fix inline. Advisory only — not a gate."

# UNINDEXED findings conflate two states: an authoring oversight vs. the fold
# rule's own correct end-state (pointer removed, file kept — see
# skills/memory-lint/SKILL.md "UNINDEXED fold-vs-forgotten triage"). Only pay
# for the extra git-history scan (one `git log -S` per UNINDEXED file) when
# the findings above actually include one, and only speak up when there's a
# genuinely new candidate — folded-confirmed / ambiguous-pre-baseline files
# need no action and would just be noise every time the store changes.
if printf '%s' "$OUT" | command grep -q 'UNINDEXED:'; then
  CLASSIFY=$(python3 "$LINT" --classify-unindexed 2>/dev/null) || true
  NEVER_COUNT=$(printf '%s' "$CLASSIFY" | command grep -oE '^never-indexed \([0-9]+\)' | command grep -oE '[0-9]+')
  if [ -n "$NEVER_COUNT" ] && [ "$NEVER_COUNT" -gt 0 ]; then
    printf '%s\n' \
      "[memory-lint] UNINDEXED triage: $NEVER_COUNT of the UNINDEXED file(s) above look like real candidates (never-indexed, not a prior fold). Run \`memory-lint.py --classify-unindexed\` for the full breakdown before adding anything."
  fi
fi

exit 0
