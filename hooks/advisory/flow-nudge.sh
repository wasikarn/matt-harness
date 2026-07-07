#!/usr/bin/env bash
# Advisory: when the user's prompt looks like non-trivial engineering work,
# nudge plan-first — enter plan mode (Shift+Tab / EnterPlanMode) or kbg:task-prep
# before editing, with the heavyweight PRD flow (kbg:grilling → kbg:to-prd →
# kbg:to-issues → /ship) as the branch for a feature to spec out. UserPromptSubmit
# hook. Output → stdout (CC surfaces as a system-reminder); never blocks,
# always exits 0. Errors are silently swallowed.
#
# Heuristic: a flow verb implies non-trivial work regardless of length.
#   - Empty prompt → silent.
#   - No flow verb → silent.
#   - Flow verb matched → emit nudge.
# Verified against the test in hooks/tests/test-flow-nudge.sh.
set -uo pipefail

# ponytail: grep the raw JSON stdin directly instead of spawning python3 to
# extract .prompt first. The flow verbs are alphabetic, so JSON escaping never
# mangles them, and this hook is advisory-only (never blocks, always exit 0).
# Tradeoff (accepted): raw grep scans every JSON field, so a cwd or
# transcript_path containing a verb (e.g. a clone named refactor-cleaner)
# over-triggers a spurious nudge line — low stakes. Restrict to the prompt
# value with a bash regex if the over-nudge proves annoying. Saves the
# python3 cold-start (~21ms) on every user prompt.
# Whole-word boundaries; case-insensitive; extended regex (BSD grep -E, no
# -P lookahead — BSD grep). IMPL includes bare `build` (the v0.35.9 narrowing
# to `build (a|an|the|out)` cost recall: 8/8 natural phrasings — build this /
# build our billing service / build new features / build it / build more —
# were silent, defeating the plan-first nudge on exactly the work the owner
# reported). Precision is reclaimed by the CI-failure carve-out below instead
# of a determiner-restricted alternation.
IMPL='implement|build|create|add|set ?up|wire|integrate|optimize|refactor|rewrite|redesign|migrate|architect|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|ship'
# IMPL without `build` — used by the carve-out to tell a build-failure report
# (only `build` matched) from a real impl prompt (another verb matched too).
IMPL_NO_BUILD='implement|create|add|set ?up|wire|integrate|optimize|refactor|rewrite|redesign|migrate|architect|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|ship'

# Read stdin ONCE into a variable. The greps below all read stdin; if they
# shared the live pipe, the first grep would consume it and the rest would
# see EOF and never match — silently defeating the carve-out (found v0.36.0
# when adding the 2nd/3rd grep: the build-failure check ran on empty stdin).
# Still raw-grep (no python3 cold-start); here-strings feed each grep from
# the captured text without re-spawning a pipe.
INPUT=$(cat)

if ! /usr/bin/grep -qiE "\b($IMPL)\b" <<< "$INPUT"; then
  exit 0
fi
# CI-failure carve-out: "build failed, help me debug the CI" is a DEBUG task,
# not implementation. If the ONLY impl verb that matched is a build-failure
# phrase (no other IMPL verb present), stay silent. Two-pass keeps both
# recall (bare `build` fires on real impl) and precision (CI reports silent):
#   build failed, help me debug the CI  → build-failure phrase + no other verb → silent
#   build new features                 → no build-failure phrase → fire
#   build failed, but also add a limiter → `add` matches IMPL_NO_BUILD → fire
if /usr/bin/grep -qiE '\bbuild (failed|broken|error|fails|failing|crashes?|errors|is broken)\b' <<< "$INPUT" \
   && ! /usr/bin/grep -qiE "\b($IMPL_NO_BUILD)\b" <<< "$INPUT"; then
  exit 0
fi

cat <<'EOF'

[kbg:flow-nudge] Non-trivial work detected — plan before you edit.
  Multi-file / unfamiliar / architectural / hard-to-reverse?
    → enter plan mode (Shift+Tab, or EnterPlanMode) or kbg:task-prep first.
  A new feature to spec out? → kbg:grilling → kbg:to-prd → kbg:to-issues → /ship
Skip if the work shape is already known (typo / doc-tweak / known small fix).
The nudge is advisory; the model judges.
EOF

exit 0