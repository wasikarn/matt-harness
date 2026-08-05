#!/usr/bin/env bash
# Advisory: when the user's prompt looks like non-trivial engineering work,
# nudge plan-first — enter plan mode (Shift+Tab / EnterPlanMode) or kbg:task-prep
# before editing, with the heavyweight spec flow (mattpocock-skills:grilling →
# mattpocock-skills:to-spec → mattpocock-skills:to-tickets → /ship) as the
# branch for a feature to spec out. UserPromptSubmit
# hook. Output → plain stdout — docs: "added as context Claude can see and
# act on" (not the JSON hookSpecificOutput.additionalContext path, which is
# what's specifically documented as wrapped in a "system reminder"; this
# script uses plain stdout instead, a separately-documented mechanism with
# the same practical effect); never blocks, always exits 0. Errors are
# silently swallowed.
#
# Heuristic: a flow verb implies non-trivial work regardless of length.
#   - Empty prompt → silent.
#   - No flow verb → silent.
#   - Flow verb matched → emit nudge.
# Verified against the test in hooks/tests/test-flow-nudge.sh.
set -uo pipefail

# Matching runs against the extracted `.prompt` field only, via jq (already a
# repo dependency — see hooks/stop/cost-tracker.sh), NOT the raw JSON. Used to
# be raw-stdin grep (skip a python3 spawn) with an accepted tradeoff: a cwd or
# transcript_path containing a verb over-triggers a spurious nudge — low
# stakes when the verb set was implement/refactor/redesign/migrate. That
# stopped being low-stakes once split/move/replace/extract/consolidate were
# added (2026-08-05 audit, see below): those are common substrings of real
# repo/service directory names (a clone at .../pdf-extract-service or
# .../order-move-service fired the nudge on a bare "fix typo in README" via
# transcript_path/cwd alone — confirmed empirically, not hypothetical). jq's
# cold start (~single-digit ms, C binary) is cheap enough that scoping to the
# actual prompt text is worth it over the python3-avoidance saving.
# Whole-word boundaries; case-insensitive; extended regex (BSD grep -E, no
# -P lookahead — BSD grep). IMPL includes bare `build` (the v0.35.9 narrowing
# to `build (a|an|the|out)` cost recall: 8/8 natural phrasings — build this /
# build our billing service / build new features / build it / build more —
# were silent, defeating the plan-first nudge on exactly the work the owner
# reported). Precision is reclaimed by the CI-failure carve-out below instead
# of a determiner-restricted alternation.
# Structural-verb set (split/swap out/restructure/move/replace/consolidate/
# extract/overhaul/rework/rethink) added after a held-out 49-prompt audit
# (2026-08-05, docs/research/plan-mode-nudge-audit-2026-08-05.md) measured the
# "clear architecture work" category at 1/8 recall — natural architecture
# phrasings ("split the monolith", "swap out the ORM", "move the whole app
# off REST") used none of the previously-covered verbs. `architect` widened to
# `(re)?architect(ure)?` for the same reason ("architecture"/"rearchitecture"
# as nouns didn't match the bare-verb form). Same recall/precision trade-off
# already accepted for `build`/`add`/`create` above: `move`/`replace`/`extract`/
# `split`/`consolidate` also fire on trivial single-file uses (measured, not
# hypothetical — see the audit doc's G1-G5 cases) — accepted for the same
# reason: the nudge is advisory and low-cost, the model judges. `redo` was
# tried and dropped: only one held-out case needed it, and it collides with
# too much everyday non-code usage ("redo the commit message") to be worth it.
# Gerund forms (-ing) added 2026-08-05 after empirical testing found the
# whole verb set — old and newly-widened alike — silent on natural
# in-progress phrasing ("we're splitting the monolith", "I'm moving the
# billing logic out"): 5/5 tested gerund prompts missed before this pass, 0/5
# after. `swap ?out`/`set ?up` get their gerund form spelled out separately
# (phrasal verbs inflect on the first word: "swapping out", "setting up", not
# a suffix on the tail word). Past tense (-ed) is a related, still-open gap
# ("we migrated the database" misses) — deliberately NOT covered this pass:
# plan-mode's nudge is about work still ahead of you, and a completed-action
# report is retrospective by definition; the forward-looking remainder of
# such a prompt usually carries its own present/future verb anyway. Revisit
# if a real missed past-tense-only prompt is observed, not from more testing
# against self-authored fixtures.
IMPL='implement(ing)?|build(ing)?|creat(e|ing)|add(ing)?|(set ?up|setting ?up)|wir(e|ing)|integrat(e|ing)|optimiz(e|ing)|refactor(ing)?|rewrit(e|ing)|redesign(ing)?|migrat(e|ing)|(re)?architect(ing|ure)?|split(ting)?|(swap(ping)? ?out)|restructur(e|ing)|mov(e|ing)|replac(e|ing)|consolidat(e|ing)|extract(ing)?|overhaul(ing)?|rework(ing)?|rethink(ing)?|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|to-spec|to-tickets|ship(ping)?'
# IMPL without `build`/`building` — used by the carve-out to tell a
# build-failure report (only `build` matched) from a real impl prompt
# (another verb matched too).
IMPL_NO_BUILD='implement(ing)?|creat(e|ing)|add(ing)?|(set ?up|setting ?up)|wir(e|ing)|integrat(e|ing)|optimiz(e|ing)|refactor(ing)?|rewrit(e|ing)|redesign(ing)?|migrat(e|ing)|(re)?architect(ing|ure)?|split(ting)?|(swap(ping)? ?out)|restructur(e|ing)|mov(e|ing)|replac(e|ing)|consolidat(e|ing)|extract(ing)?|overhaul(ing)?|rework(ing)?|rethink(ing)?|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|to-spec|to-tickets|ship(ping)?'
# IMPL without `create`/`creating` — used by the PR-intent carve-out below to
# tell a pure "create a PR" ask (route to kbg:pr) from an impl-heavy prompt
# that also happens to mention a PR ("build X then open a PR" → still wants
# the plan-first nudge). `create` is dropped because it's the one IMPL verb
# that overlaps PR_INTENT.
IMPL_NO_PR_CREATE='implement(ing)?|build(ing)?|add(ing)?|(set ?up|setting ?up)|wir(e|ing)|integrat(e|ing)|optimiz(e|ing)|refactor(ing)?|rewrit(e|ing)|redesign(ing)?|migrat(e|ing)|(re)?architect(ing|ure)?|split(ting)?|(swap(ping)? ?out)|restructur(e|ing)|mov(e|ing)|replac(e|ing)|consolidat(e|ing)|extract(ing)?|overhaul(ing)?|rework(ing)?|rethink(ing)?|new (endpoint|command|skill|surface|hook|agent)|grill[- ]|to-prd|to-issues|to-spec|to-tickets|ship(ping)?'
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

emit_address_review_nudge() {
  cat <<'EOF'

[kbg:flow-nudge] Replying to PR review feedback → tell the user to type `/address-review`
  It triages every open thread, fixes in clusters, and replies per-thread with a commit
  sha citation — instead of an ad-hoc `gh pr comment`/`gh api` reply with no fixed shape.
  `/address-review` is user-invocation-only (disable-model-invocation: true) — the model
  cannot run it; say the literal string so the user can type it themselves.
The nudge is advisory; the model judges.
EOF
  exit 0
}

# Read stdin ONCE into a variable, then extract just the prompt text via jq.
# The greps below all read from $INPUT/$INPUT_TH; if they shared the live
# pipe, the first grep would consume it and the rest would see EOF and never
# match — silently defeating the carve-out (found v0.36.0 when adding the
# 2nd/3rd grep: the build-failure check ran on empty stdin). here-strings feed
# each grep from the captured text without re-spawning a pipe. On malformed or
# empty stdin, jq fails and INPUT stays empty — every check below then misses
# and the hook falls through to the silent exit, matching this file's
# documented "errors silently swallowed" contract.
INPUT=$(printf '%s' "$(cat)" | jq -r '.prompt // empty' 2>/dev/null)
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

# Reply-to-PR-review intent -> address-review, not creation. Placed before the
# IMPL gate for the same reason as PR_INTENT: reply/respond/answer aren't IMPL
# verbs, so without this carve-out the whole hook stays silent on exactly the
# prompt that reported this gap (ad-hoc `gh pr comment`/`gh api` replies with no
# fixed shape, because the model never learns `/address-review` exists — it's a
# command, not a listed skill, and disable-model-invocation blocks the model
# from just running it). Partial verb stems (repl/respond/answer/address), no
# \b, mirrors this file's existing PR_INTENT convention (creat/open/rais/mak).
# Context set is `review|reviewer` only — NOT comment/feedback (excluded up
# front: everyday words like "respond to the comment about the budget") and
# NOT `thread` either (added, then cut on fresh-context review: "reply to the
# thread on Slack" / "answer this thread with a summary" fire on Slack/forum/
# worker threads that have nothing to do with a PR — the same over-generic-
# noun mistake the comment/feedback exclusion already existed to avoid). An
# impl-heavy prompt still falls through to the plan-first nudge instead
# (mirrors PR_INTENT's own IMPL_NO_PR_CREATE guard) — otherwise "implement the
# fix, refactor the module, and reply to the review thread" would lose the
# plan-first nudge to this narrower one. `repl(y|ies|ying)`, not bare `repl` —
# a bare stem also matches "replicate"/"replica"/"replace" ("replicate the
# reviewer environment" wrongly fired on the bare stem, caught on review).
# Window is {0,18}, not {0,15}: measured gap on two real missed phrasings
# ("answer all of miguel's review comments", "address the feedback the
# reviewer left") is 18-19 chars — 15 silently missed both. Widened only to
# 18, not further: an 8-prompt precision check (2026-07-25) showed window=20
# already false-positives on "address this in the design review meeting" (a
# non-PR design review), so 18 is the largest width that closes the measured
# gap without that regression. Reversed noun-then-verb order ("the reviewer's
# comments... reply") is a known, deliberately unfixed ceiling — matching it
# needs `(review|reviewer).{0,N}(respond|answer|address)`, and those three
# common verbs in the reversed direction risk far more false positives (e.g.
# "the review said we should address the schema") than the forward direction
# ever did; the nudge is advisory, the model is expected to catch this case
# on its own reading even when the regex doesn't.
PR_REPLY_INTENT='(repl(y|ies|ying)|respond|answer|address).{0,18}(review|reviewer)'
# "implement/apply the requested changes" describes Phase 4+5 work address-
# review's own Phase 3 already plans for — exempt it from the IMPL carve-out
# below so a bounded, reviewer-scoped ask doesn't lose the nudge to the
# generic plan-first one. Deliberately narrow (a fixed collocation, not a
# broader "reviewer + changes" pattern) so it doesn't also exempt a prompt
# that bundles the review-scoped fix with real freestanding work, e.g. "fix
# the bugs the reviewer flagged and also refactor the auth module" — that
# still needs plan-first for the unscoped "refactor" half, so it correctly
# stays out of this exemption (no "requested changes" phrase either).
IMPL_BOUNDED_TO_REVIEW='(requested|suggested) changes'
if /usr/bin/grep -qiE "$PR_REPLY_INTENT" <<< "$INPUT" \
   && ( ! /usr/bin/grep -qiE "\b($IMPL)\b" <<< "$INPUT" \
        || /usr/bin/grep -qiE "$IMPL_BOUNDED_TO_REVIEW" <<< "$INPUT" ); then
  emit_address_review_nudge
fi

# Thai reply-to-PR-review intent. Deliberately just address-review's own
# frontmatter Thai trigger phrase ("แก้ตามรีวิว"), not a broader ตอบ...รีวิว
# co-occurrence check — คำว่า รีวิว is an everyday Thai loanword for product/
# restaurant reviews ("ตอบคำถามลูกค้าในรีวิวสินค้าให้หน่อย" = "please answer
# customer questions in the product review" fires on the broader pattern and
# has nothing to do with a PR), far more generic than English "review" in this
# harness's mostly-engineering context. Same impl-verb guard as the English
# block above.
if /usr/bin/grep -qE "แก้ตามรีวิว" <<< "$INPUT_TH" \
   && ! /usr/bin/grep -qE "$THAI_IMPL" <<< "$INPUT_TH"; then
  emit_address_review_nudge
fi

# Complex-bug-fix carve-in: `fix`/`debug`/`diagnose` are deliberately absent
# from IMPL (a trivial "fix typo" must stay silent — decision-doctrine-map.md's
# "Bug report -> fix" row explicitly defers a bug-report-specific nudge). But
# Rule 1's plan-mode criteria (multi-file / unfamiliar subsystem / architectural)
# apply to a hard bug fix exactly as much as a feature — a race condition or
# memory leak spanning "every service" is exactly the shape plan-first exists
# for, and the held-out audit (see IMPL comment above) measured 0/8 recall on
# this category. Not extended to Thai — no held-out evidence for Thai
# bug-language phrasing yet.
#
# Two tiers, added 2026-08-06 after the audit's residual-miss review found one
# tested case ("fix the race condition ... causing intermittent prod outages")
# had strong bug-language but no explicit breadth word:
#   - STRONG: race condition / deadlock / memory leak. These fire alone, no
#     breadth co-occurrence required — a race condition or deadlock is, by its
#     own definition, an interaction between multiple components; diagnosing
#     one correctly is rarely a single-file task even when the eventual patch
#     is small. Treating them as self-evidently non-trivial is a claim about
#     what those terms mean, not a rule shaped to match one audit sentence.
#   - WEAK: bug / leak(s) / intermittent / flaky / silently drops-fails /
#     regression / corrupt(s/ed/ing). These stay behind the original
#     co-occurrence gate (WEAK signal AND a breadth word, neither alone) —
#     "there's a regression in the login flow" or "debug this one function"
#     must still stay silent, and a bare "corrupted" without breadth language
#     is exactly that kind of ordinary, possibly-trivial report.
BUG_SIGNAL_STRONG='(race condition|deadlock|memory leak)'
BUG_SIGNAL_WEAK='(\bbug\b|\bleaks?\b|intermittent|flak(y|iness)|silently (drops?|fails?)|\bregression\b|corrupt(s|ed|ing)?)'
SCOPE_SIGNAL='\b(across|throughout|every|all|whole|entire|multiple|several|many)\b'
BUG_COMPLEX=0
if /usr/bin/grep -qiE "$BUG_SIGNAL_STRONG" <<< "$INPUT"; then
  BUG_COMPLEX=1
elif /usr/bin/grep -qiE "$BUG_SIGNAL_WEAK" <<< "$INPUT" && /usr/bin/grep -qiE "$SCOPE_SIGNAL" <<< "$INPUT"; then
  BUG_COMPLEX=1
fi

if ! /usr/bin/grep -qiE "\b($IMPL)\b" <<< "$INPUT" && ! /usr/bin/grep -qE "$THAI_IMPL" <<< "$INPUT_TH" \
   && [[ "$BUG_COMPLEX" -eq 0 ]]; then
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

[kbg:flow-nudge] Non-trivial work detected — interrogate the requirement, then plan before you edit.
  Multi-file / unfamiliar / architectural / hard-to-reverse?
    → enter plan mode (Shift+Tab, or EnterPlanMode) or kbg:task-prep first (now also surfaces requirement gaps — Rule 3).
  A new feature to spec out? → mattpocock-skills:grilling → mattpocock-skills:to-spec → mattpocock-skills:to-tickets → /ship
  Bounded, independently-verifiable slices? → consider delegating via the Agent tool (see kbg:orchestrate).
Skip if the work shape is already known (typo / doc-tweak / known small fix).
The nudge is advisory; the model judges.
EOF

# Ticket + implementation-intent combo -> requirement-grounding reminder.
# TICKET_KEY is a deliberate, labeled duplicate of jira-route-nudge.sh's TP-*
# detection (kept in sync by hand -- see that file if this needs updating).
# The pattern is frozen (TP-* is a fixed, client-specific convention per
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