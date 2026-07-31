#!/usr/bin/env bash
# Advisory: remind the operator that kbg:learn exists when a session had
# enough activity to plausibly contain a durable learning worth capturing.
# SessionEnd hook. Never blocks (SessionEnd has no decision control at all),
# never writes memory, never judges WHAT the learnings are — that's
# kbg:learn's job, gated by its own AskUserQuestion. This hook only decides
# whether to say "consider running it."
#
# SessionEnd stdout is discarded by Claude Code; stderr IS shown to the user
# (hooks reference: "Any stderr output is shown to the user. Use this for
# informational messages.") — so the nudge goes to stderr, not stdout.
#
# Heuristic: count of `"type":"user"` entries in the transcript JSONL (this
# includes tool-result turns, not just literal prompts — a coarse activity
# proxy, not content judgment). A trivial single-question session stays
# silent; anything with real back-and-forth or tool use fires. Deliberately
# not keyword-matching for "corrections" — real learnings often arrive with
# no correction phrasing (stated conventions, decisions, preferences), so a
# broad volume proxy is more reliable than a fragile phrase match.
#
# This is NOT the retired learn-capture/learn-drain-nudge design (removed
# v0.6.0, memory: passive-capture had a queue + confidence scoring + a
# separate SessionStart drain hook). No queue, no state file, no python —
# it fires once per session end and says nothing about content.
# Verified against the test in hooks/tests/test-learn-nudge.sh.
#
# `reason` gate: skip `resume` (docs: "Session switched via interactive
# /resume" — the session ended because the user left it for a possibly-
# different session via /resume, not because this session is pausing to be
# continued later; "before you close out" would be a false framing either
# way) and `clear` (docs: user ran `/clear` — frequent mid-work housekeeping, and
# since tool-result turns inflate the turn count, MIN_TURNS filters almost
# nothing here; nudging on every `/clear` is nag-fatigue noise, not signal).
set -uo pipefail

MIN_TURNS="${KBG_LEARN_NUDGE_MIN_TURNS:-3}"

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

REASON=$(printf '%s' "$INPUT" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
case "$REASON" in
  resume|clear) exit 0 ;;
esac

TRANSCRIPT=$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# grep -c already prints "0" (not nothing) on zero matches, with exit 1 —
# a trailing `|| echo 0` here would double-print and break the comparison.
TURNS=$(/usr/bin/grep -c '"type":"user"' "$TRANSCRIPT" 2>/dev/null)
[ "${TURNS:-0}" -ge "$MIN_TURNS" ] || exit 0

echo "[kbg:learn-nudge] Session had activity worth a look — if anything here is worth remembering next time, run kbg:learn before you close out." >&2
exit 0
