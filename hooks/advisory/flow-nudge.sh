#!/usr/bin/env bash
# Advisory: nudge kbg:grilling → kbg:to-prd → kbg:to-issues → /ship when the
# user's prompt looks like non-trivial engineering work. UserPromptSubmit
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
# Whole-word boundaries; case-insensitive; extended regex (BSD grep -E).
if ! /usr/bin/grep -qiE '\b(implement|build a feature|refactor|redesign|migrate|architect|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|ship)\b'; then
  exit 0
fi

cat <<'EOF'

[kbg:flow-nudge] Non-trivial work detected — consider matt's flow:
  kbg:grilling → kbg:to-prd → kbg:to-issues → /ship
Skip the nudge if the work shape is already known (typo-fix / doc-tweak /
direct skill invocation). The nudge is advisory; the model judges.
EOF

exit 0