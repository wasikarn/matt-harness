#!/usr/bin/env bash
# Advisory: when the user's prompt looks like non-trivial engineering work,
# nudge plan-first — enter plan mode (Shift+Tab / EnterPlanMode) or kbg:task-prep
# before editing, with the heavyweight spec flow (mattpocock-skills:grilling →
# mattpocock-skills:to-spec → mattpocock-skills:to-tickets → /ship) as the
# branch for a feature to spec out. UserPromptSubmit
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
# extract .prompt first. English flow verbs are alphabetic, and Thai verbs
# match via bare alternation on raw UTF-8 bytes (CC emits `prompt` as real
# UTF-8, not \u-escaped) — so JSON escaping never mangles either, and this
# hook is advisory-only (never blocks, always exit 0).
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
IMPL='implement|build|create|add|set ?up|wire|integrate|optimize|refactor|rewrite|redesign|migrate|architect|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|to-spec|to-tickets|ship'
# IMPL without `build` — used by the carve-out to tell a build-failure report
# (only `build` matched) from a real impl prompt (another verb matched too).
IMPL_NO_BUILD='implement|create|add|set ?up|wire|integrate|optimize|refactor|rewrite|redesign|migrate|architect|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|to-spec|to-tickets|ship'
# IMPL without `create` — used by the PR-intent carve-out below to tell a pure
# "create a PR" ask (route to kbg:pr) from an impl-heavy prompt that also happens
# to mention a PR ("build X then open a PR" → still wants the plan-first nudge).
# `create` is dropped because it's the one IMPL verb that overlaps PR_INTENT.
IMPL_NO_PR_CREATE='implement|build|add|set ?up|wire|integrate|optimize|refactor|rewrite|redesign|migrate|architect|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|to-spec|to-tickets|ship'
# Thai impl-verb detection. Bare substring alternation, NO \b and NO -i: Thai
# has no ASCII word-boundary characters (\b never matches Thai script) and is
# caseless. Proven pattern copied from jira-route-nudge.sh:51. `ทำ` (do/make)
# is deliberately excluded — it's a bare substring of extremely common words
# (ทำไม=why, ทำงาน=work, ทำอะไร=do what) and would false-positive on ordinary
# Thai questions. `พัฒนา` (develop) has no English IMPL peer — included as the
# single most natural Thai verb for "build/develop a system". `เขียน` (write)
# is deliberately excluded too, mirroring English `write`'s deliberate absence
# from IMPL — prose-vs-code ambiguous (e.g. "ช่วยเขียนอีเมลให้หน่อย" = "help me
# write an email", not implementation work); found false-firing 2026-07-16.
THAI_IMPL='สร้าง|พัฒนา|เพิ่ม|แก้ไข|ปรับปรุง|ติดตั้ง|ผสาน|ออกแบบ|ย้าย'
# THAI_IMPL without สร้าง — the Thai PR-intent carve-out's peer of
# IMPL_NO_PR_CREATE above: สร้าง overlaps the Thai PR-creation verb, so a pure
# "สร้าง PR ให้หน่อย" ask must not also count as an impl verb blocking the
# carve-out (same reasoning as `create` being dropped from IMPL_NO_PR_CREATE).
THAI_IMPL_NO_PR_CREATE='พัฒนา|เพิ่ม|แก้ไข|ปรับปรุง|ติดตั้ง|ผสาน|ออกแบบ|ย้าย'
THAI_PR_VERB='สร้าง|เปิด'

emit_pr_nudge() {
  cat <<'EOF'

[kbg:flow-nudge] PR creation → use kbg:pr
  It builds a consistent, templated body and previews it for your confirmation
  before creating the PR — instead of a free-hand `gh pr create` with an ad-hoc body.
The nudge is advisory; the model judges.
EOF
  exit 0
}

# Read stdin ONCE into a variable. The greps below all read stdin; if they
# shared the live pipe, the first grep would consume it and the rest would
# see EOF and never match — silently defeating the carve-out (found v0.36.0
# when adding the 2nd/3rd grep: the build-failure check ran on empty stdin).
# Still raw-grep (no python3 cold-start); here-strings feed each grep from
# the captured text without re-spawning a pipe.
INPUT=$(cat)
# เพิ่มเติม ("additionally" / "more") is a bare superstring of the THAI_IMPL
# verb เพิ่ม ("add") — POSIX ERE has no lookahead to exclude it inline, so it
# is stripped from a separate copy of the input before any THAI_IMPL match.
# "อธิบายเพิ่มเติมได้ไหม" (explain more?) has no impl intent at all; stripping
# the superstring first is a correct exclusion, not a substring pattern that
# would also miss a real "เพิ่ม X" co-occurring with "เพิ่มเติม" in the same
# prompt. Only used for Thai matching — English checks stay on raw $INPUT.
INPUT_TH="${INPUT//เพิ่มเติม/}"

# PR-creation intent → route to kbg:pr and skip the generic plan-first nudge
# (which is the wrong advice for a discrete "create a PR" action). Placed BEFORE
# the IMPL gate because the PR verbs open/raise/make aren't in IMPL — the gate
# would otherwise silence "open a PR". Fires only on a PURE PR ask: if another
# impl verb is present (IMPL_NO_PR_CREATE — "build X then open a PR"), fall
# through so impl-heavy work still gets the plan-first nudge. `\bPRs?\b` needs a
# word boundary, so "PRD" (create a PRD) never matches — it's not a pull request.
# English/romanized verbs. CC emits `prompt` as real UTF-8 (not \u-escaped —
# see the THAI_IMPL comment above), so a Thai PR ask is handled by the
# parallel THAI_PR_VERB check right below, not left to kbg:pr's own
# description-match fallback.
PR_INTENT='(creat|open|rais|mak|submit|put up|cut).{0,12}(pull request|\bPRs?\b)'
if /usr/bin/grep -qiE "$PR_INTENT" <<< "$INPUT" \
   && ! /usr/bin/grep -qiE "\b($IMPL_NO_PR_CREATE)\b" <<< "$INPUT"; then
  emit_pr_nudge
fi

# Thai PR-creation intent — same carve-out as PR_INTENT above, mirrored for
# สร้าง/เปิด PR. Uses INPUT_TH (เพิ่มเติม-stripped) for consistency with the
# main Thai gate below, though สร้าง/เปิด PR never collides with เพิ่มเติม.
if /usr/bin/grep -qE "($THAI_PR_VERB).{0,12}(pull request|\bPRs?\b)" <<< "$INPUT_TH" \
   && ! /usr/bin/grep -qE "$THAI_IMPL_NO_PR_CREATE" <<< "$INPUT_TH"; then
  emit_pr_nudge
fi

if ! /usr/bin/grep -qiE "\b($IMPL)\b" <<< "$INPUT" && ! /usr/bin/grep -qE "$THAI_IMPL" <<< "$INPUT_TH"; then
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
  A new feature to spec out? → mattpocock-skills:grilling → mattpocock-skills:to-spec → mattpocock-skills:to-tickets → /ship
  Bounded, independently-verifiable slices? → consider delegating via the Agent tool (see kbg:orchestrate).
Skip if the work shape is already known (typo / doc-tweak / known small fix).
The nudge is advisory; the model judges.
EOF

# Ticket + implementation-intent combo -> requirement-grounding reminder.
# TICKET_KEY is a deliberate, labeled duplicate of jira-route-nudge.sh's TP-*
# detection (kept in sync by hand -- see that file if this needs updating).
# The pattern is frozen (TP-* is a fixed, tathep-only convention per
# CLAUDE.md), so duplicating THIS is lower-risk than duplicating this file's
# own IMPL/THAI_IMPL verb regexes into jira-route-nudge.sh instead, which
# have churned constantly (v0.35.7 through v0.36.0, several false-positive
# fixes on record). jira-route-nudge.sh already fires independently on the
# same prompt (verified live, 2026-07-18) -- that nudge covers Jira tool-call
# routing, this one covers requirement grounding before implementation:
# distinct concerns, not the same advice twice.
TICKET_KEY='\btp-[0-9]+\b'
if /usr/bin/grep -qiE "$TICKET_KEY" <<< "$INPUT"; then
  cat <<'EOF'
  Ticket reference detected — before implementing, dispatch kbg:requirement-analyst
  on the ticket text first (functional_requirements / business_trace / open_questions),
  then fold its output into the implementer's spawn prompt.
EOF
fi

exit 0