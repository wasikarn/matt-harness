#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in payload strings is intentional
# Flow-nudge unit tests: simulates UserPromptSubmit JSON payloads and
# asserts stdout output (nudge fired) vs silence (nudge skipped). The
# hook never blocks, so all tests expect exit 0.
# Run standalone: bash tests/hooks/test-flow-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/flow-nudge.sh"

pass=0
fail=0

# Build a UserPromptSubmit payload. The real CC payload carries `prompt` at the
# TOP LEVEL (not under tool_input) — found 2026-07-03: the old fixture put it
# under tool_input, matching the hook's same wrong read, so the suite validated
# the bug and stayed green while the sensor never fired in production.
user_prompt_payload() {
  python3 -c '
import sys, json
prompt = sys.argv[1]
print(json.dumps({"tool_name": "UserPromptSubmit", "prompt": prompt}, ensure_ascii=False))
' "$1"
}

# Expect the hook to FIRE (stdout non-empty, exit 0).
test_nudge() {
  local desc="$1" prompt="$2"
  local out
  out=$(echo "$(user_prompt_payload "$prompt")" | bash "$HOOK" 2>/dev/null)
  local rc=$?
  if [[ "$rc" == "0" && -n "$out" ]]; then
    echo "  ✅ NUDGE: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the hook to be SILENT (stdout empty, exit 0).
test_silent() {
  local desc="$1" prompt="$2"
  local out
  out=$(echo "$(user_prompt_payload "$prompt")" | bash "$HOOK" 2>/dev/null)
  local rc=$?
  if [[ "$rc" == "0" && -z "$out" ]]; then
    echo "  ✅ SILENT: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ SILENT EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== flow-nudge hook (UserPromptSubmit) ==="
echo ""
echo "--- trivial prompts (must stay silent) ---"
test_silent "single-word prompt"          "typo"
test_silent "short typo-fix prompt"       "fix typo in CLAUDE.md line 5"
test_silent "short doc tweak"             "update README header"
test_silent "single-line question"        "what does this skill do?"
test_silent "empty prompt"                ""
# v0.36.0: bare 'build' fires (the v0.35.9 narrowing to `build (a|an|the|out)`
# cost recall — 8/8 natural impl phrasings were silent). Precision is reclaimed
# by a 2-pass CI-failure carve-out: if the ONLY impl match is a build-failure
# phrase (build failed/broken/error/fails/…) and no other impl verb is present,
# stay silent — it's a debug task, not implementation.
test_silent "build-failure is debug, not impl (carve-out)" "build failed, help me debug the CI"
test_silent "build broken in CI (carve-out)" "the build is broken after the merge"
test_nudge  "build failed BUT also add a limiter (other verb → fire)" \
  "build failed, but also add a rate limiter to the public API"

echo ""
echo "--- non-trivial prompts (must fire nudge) ---"
test_nudge  "explicit 'build a new feature' verb" \
  "build a new skill called playwright-coach for visual regression"
test_nudge  "long + multi-sentence feature request" \
  "I want to build a feature. It involves a database migration. Then a REST endpoint. Then CLI wiring. Can you plan it for me so we can ship it next sprint?"
test_nudge  "refactor verb" \
  "refactor the audit script to use the new plugin architecture and shared library"
test_nudge  "migrate verb" \
  "migrate the existing table-based inventory to a content-addressable store with backward compatibility"
test_nudge  "new endpoint verb" \
  "design a new endpoint to expose the audit results over HTTP with proper auth and rate limiting"
test_nudge  "implicit flow verbs (grill, to-prd)" \
  "let's grill this design and turn it into a PRD then split into issues for the team to pick up"
# Natural implementation phrasings on a real project (not kbg meta-work) — these
# were all silent before v0.35.8 (verb set was tuned to harness self-work), which
# defeated the plan-first nudge on exactly the work the owner reported. Guard the
# widened verb set so a future narrowing re-introduces the miss loudly.
test_nudge  "add verb (feature on a real project)" \
  "add a rate limiter to the public API"
test_nudge  "create verb (new endpoint, natural phrasing)" \
  "create an endpoint for user search with pagination"
test_nudge  "set up verb (auth wiring)" \
  "set up auth with JWT and refresh tokens"
test_nudge  "optimize verb (perf work)" \
  "optimize the slow dashboard queries"
# v0.36.0: bare 'build' phrasings that the v0.35.9 narrowing (build a/an/the/out)
# silently missed — these are the natural real-project impl phrasings the owner
# reported were going unplanned. Guard bare 'build' recall.
test_nudge  "build new features (bare build, plural)" \
  "build new features for the admin dashboard"
test_nudge  "build this feature (bare build, determiner-less)" \
  "build this feature for the billing flow"
test_nudge  "build our billing service (bare build, our)" \
  "build our billing service with metered usage"
test_nudge  "build it (bare build, pronoun)" \
  "build it and wire it to the existing API"
test_nudge  "build out the dashboard (build out was in v0.35.9 too)" \
  "build out the dashboard with the new charts"
test_nudge  "implement the auth flow" \
  "implement the auth flow with JWT and refresh tokens"
test_nudge  "wire up the webhook" \
  "wire up the webhook to the billing service"
test_nudge  "integrate the payments service" \
  "integrate the payments service with the order pipeline"
test_nudge  "rewrite the audit pipeline" \
  "rewrite the audit pipeline to use the shared library"
test_nudge  "new command for X" \
  "new command for exporting audit results to CSV"
# to-prd/to-issues removed from IMPL 2026-09-01 (dead pre-rename matt names;
# to-spec/to-tickets removed the same day as a mid-flow conflict carve-out) —
# these now assert the dead tokens stay dead, so a regex revert re-fails here.
test_silent "to-prd (dead token — must stay silent)" \
  "to-prd this idea about a usage metering feature"
test_silent "to-issues (dead token — must stay silent)" \
  "to-issues this PRD into grabbable tickets"
test_silent "to-spec mid-flow (carve-out — must stay silent)" \
  "to-spec the payments feature we just grilled"
test_nudge  "ship this" \
  "ship this rate-limiter change"
test_silent "long doc reorg w/ no flow verb (must stay silent — length alone must not fire)" \
  "document the README to introduce the plugin, then cover a quickstart for install plus first surface plus first hook. Then a troubleshooting section. Then a deep-dive on the composer-not-creator doctrine and how matt-pocock's flow fits our native doctrine. After that, expand the existing examples. After that, a migration guide. After that, link out to the relevant skills and commands. After that, a CHANGELOG entry."

echo ""
echo "--- Thai prompts (must fire nudge) ---"
test_nudge  "Thai: create a function (สร้าง)"             "ช่วยสร้างฟังก์ชันสำหรับค้นหาผู้ใช้"
test_nudge  "Thai: develop auth system (พัฒนา)"           "พัฒนาระบบยืนยันตัวตนด้วยโทเคน"
test_nudge  "Thai: add a rate limiter (เพิ่ม)"             "เพิ่มตัวจำกัดอัตราให้กับบริการสาธารณะ"
test_nudge  "Thai: refactor the audit script (ปรับปรุง)"  "ปรับปรุงโครงสร้างของสคริปต์ตรวจสอบ"
test_nudge  "Thai: design a new endpoint (ออกแบบ)"        "ออกแบบปลายทางใหม่สำหรับแดชบอร์ด"
test_nudge  "Thai: fix the login bug (แก้ไข)"              "แก้ไขข้อผิดพลาดในระบบล็อกอิน"
test_nudge  "Thai: install a new dependency (ติดตั้ง)"     "ติดตั้งไลบรารีใหม่สำหรับการเชื่อมต่อฐานข้อมูล"
test_nudge  "Thai: merge the branches (ผสาน)"              "ผสานโค้ดจากสองบรานช์เข้าด้วยกัน"
test_nudge  "Thai: move the service (ย้าย)"                "ย้ายบริการไปยังโครงสร้างพื้นฐานใหม่"
# Guards the ทำ exclusion: silent on current hook, must stay silent post-fix too
# (ทำ is a substring of ทำอะไร — if ทำ were in THAI_IMPL this would wrongly fire).
test_silent "Thai: 'what does this file do' (guards ทำ exclusion)" "ไฟล์นี้ทำอะไร"
# Guards the เพิ่มเติม/เพิ่ม collision (found 2026-07-16): เพิ่มเติม is a bare
# superstring of the THAI_IMPL verb เพิ่ม and must not fire on its own.
test_silent "Thai: 'explain more?' (guards เพิ่มเติม/เพิ่ม collision)" "อธิบายเพิ่มเติมได้ไหม"
# Guards the เขียน exclusion (found 2026-07-16, mirrors English `write`'s
# deliberate absence from IMPL — prose-vs-code ambiguous).
test_silent "Thai: 'help me write an email' (guards เขียน exclusion)" "ช่วยเขียนอีเมลให้หน่อย"

echo ""
echo "--- PR-creation intent (routes to mh:pr, not plan-first) ---"
# open/raise aren't in IMPL, so these would be silenced by the generic gate
# without the PR branch that runs before it.
test_nudge  "create a PR (pure ask)"        "create a PR for these changes"
test_nudge  "open a pull request"           "open a pull request"
test_nudge  "raise a PR against a base"     "raise a PR against develop"
test_nudge  "make me a PR"                   "make me a PR from these commits"
test_silent "review a PR is not creation"   "review this PR"
# Thai PR-creation intent (found false-firing to the generic nudge 2026-07-16,
# fixed via THAI_PR_VERB — see flow-nudge.sh). Mirrors the English PR_INTENT
# carve-out above: a pure "สร้าง PR" ask routes to mh:pr, not plan-first.
test_nudge  "Thai: create a PR (สร้าง PR)" "สร้าง PR ให้หน่อย"
# 'PRD' must never read as 'PR' (word boundary) — to-prd fires the generic nudge,
# never the PR nudge.
prd_out=$(echo "$(user_prompt_payload "to-prd this idea about usage metering")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$prd_out" | /usr/bin/grep -qi "mh:pr\b"; then
  echo "  ❌ CONTENT: 'PRD' wrongly routed to mh:pr nudge: <$(printf '%s' "$prd_out" | head -c 120)>" >&2
  fail=$((fail + 1))
else
  echo "  ✅ CONTENT: 'PRD' does not route to the PR nudge"
  pass=$((pass + 1))
fi
# Pure PR ask names mh:pr.
pr_out=$(echo "$(user_prompt_payload "open a PR for the current branch")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$pr_out" | /usr/bin/grep -qi "mh:pr"; then
  echo "  ✅ CONTENT: pure PR ask names 'mh:pr'"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED 'mh:pr': <$(printf '%s' "$pr_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi
# Thai pure PR ask also names mh:pr (content, not just fire/silent).
thai_pr_out=$(echo "$(user_prompt_payload "สร้าง PR ให้หน่อย")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$thai_pr_out" | /usr/bin/grep -qi "mh:pr"; then
  echo "  ✅ CONTENT: Thai PR ask names 'mh:pr'"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED 'mh:pr' (Thai): <$(printf '%s' "$thai_pr_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi
# Impl-heavy prompt that also mentions a PR still gets the plan-first nudge.
impl_pr_out=$(echo "$(user_prompt_payload "implement the auth flow then open a PR")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$impl_pr_out" | /usr/bin/grep -qi "plan mode"; then
  echo "  ✅ CONTENT: impl-heavy PR ask falls through to plan-first"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED 'plan mode' (impl-heavy): <$(printf '%s' "$impl_pr_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- reply-to-PR-review intent (routes to /mh:address-review) ---"
test_nudge  "reply to review comments"      "reply to the review comments on this PR"
test_nudge  "respond to reviewer feedback"  "respond to the reviewer feedback"
test_nudge  "address the review feedback"   "address the review feedback on PR 42"
test_nudge  "answer the review comments"    "answer the review comments please"
test_silent "review a PR is not a reply (no reply/respond/answer/address verb)" "review this PR"
test_silent "address with no PR/review context" "address the bug in the login flow"
# Regression guards: 'comment'/'feedback' are everyday words dropped from the
# trigger context on purpose — these must NOT fire the GitHub-PR nudge.
test_silent "respond to a comment (no review/reviewer context)" "respond to the comment about the budget"
test_silent "address feedback from a retro (not a PR)" "address the feedback from the retro"
test_silent "reply to a comment on a design doc (not a PR)" "reply to her comment on the design doc"
# Regression guards: 'thread' was also tried and cut on fresh-context review —
# too generic (Slack/forum/worker threads), same mistake as comment/feedback.
test_silent "reply to a Slack thread (not a PR)" "reply to the thread on Slack about lunch plans"
test_silent "answer a forum thread (not a PR)" "answer this thread with a summary"
# Regression guard: bare 'repl' stem also matched replicate/replica/replace —
# must require an actual reply/replies/replying form.
test_silent "replicate the reviewer environment (not a reply)" "we should replicate the reviewer environment on staging"
# Distance-window regression guards (eval-set review, 2026-07-25): window
# widened 15->18 chars after two independent staff-engineer reviewers + a live
# run confirmed these natural phrasings were silently missed at 15.
test_nudge  "address the feedback the reviewer left (18-char gap, was missed at 15)" "address the feedback the reviewer left before we merge"
test_nudge  "answer all of X's review comments (18-char gap, was missed at 15)" "I need to answer all of miguel's review comments before we merge"
# Precision guards for the same widen: an 8-prompt check at window=20 already
# false-positived on "design review meeting"; these must all stay silent at
# 18, which is why 18 was chosen over 20.
test_silent "respond to legal before a review (not a PR reply)" "please respond to legal before the review"
test_silent "design review meeting (not a PR review)" "address this in the design review meeting"
test_silent "annual performance review (not a PR review)" "respond to HR before your annual performance review"
test_silent "code review with the team lead, generic (not an address-review ask)" "answer these questions before your code review with the team lead"
test_silent "review of an RFC (not a PR)" "address the concerns raised during the review of the RFC"
test_silent "compliance review (not a PR)" "respond to the auditor before the compliance review next week"
# Known, deliberately unfixed ceiling: reversed noun-then-verb order isn't
# matched. Fixing it needs (review|reviewer).{0,N}(respond|answer|address),
# and those three common verbs in reverse risk far more false positives (e.g.
# "the review said we should address the schema") than the gap is worth —
# the nudge is advisory, the model is expected to catch this on its own
# reading. Asserted explicitly so a future regex change that starts matching
# this is a conscious choice, not a silent drift.
test_silent "reversed order: noun before verb (documented ceiling, not a bug)" "let's go through the reviewer's comments one by one and reply"
# Impl-heavy prompt still falls through to plan-first, mirrors PR_INTENT's
# own IMPL_NO_PR_CREATE guard — the narrower address-review nudge must not
# steal a prompt that also has real implementation work in it.
impl_reply_out=$(echo "$(user_prompt_payload "implement the fix, refactor the auth module, and reply to the review thread")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$impl_reply_out" | /usr/bin/grep -qi "plan mode" \
   && ! printf '%s' "$impl_reply_out" | /usr/bin/grep -qi "address-review"; then
  echo "  ✅ CONTENT: impl-heavy reply-to-review ask falls through to plan-first, not address-review"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED plan-first only: <$(printf '%s' "$impl_reply_out" | head -c 160)>" >&2
  fail=$((fail + 1))
fi
# Bounded-to-review implement phrasing ("the requested changes") is exempt
# from the impl carve-out above — this is address-review's own Phase 4+5
# job, not freestanding work needing plan-first.
test_nudge  "implement the requested changes + reply (bounded to review, exempt from impl carve-out)" "implement the requested changes and reply to the review thread"
# But the exemption is narrow: a real freestanding bolt-on (no "requested
# changes" phrase) still correctly falls through to plan-first, same as the
# impl_reply_out check above — must not accidentally widen the exemption to
# every reviewer-mentioning impl prompt.
bolt_on_out=$(echo "$(user_prompt_payload "let's fix the bugs the reviewer flagged and also refactor the auth module")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$bolt_on_out" | /usr/bin/grep -qi "plan mode" \
   && ! printf '%s' "$bolt_on_out" | /usr/bin/grep -qi "address-review"; then
  echo "  ✅ CONTENT: bundled reviewer-fix + unscoped refactor still falls through to plan-first"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED plan-first only: <$(printf '%s' "$bolt_on_out" | head -c 160)>" >&2
  fail=$((fail + 1))
fi
test_nudge  "Thai: fix-per-review (แก้ตามรีวิว, address-review's own trigger)" "แก้ตามรีวิวให้หน่อย"
# Regression guard: รีวิว (review) alone is an everyday Thai loanword for
# product/restaurant reviews — must NOT fire on a non-PR product-review ask.
test_silent "Thai: answer customer questions in a product review (not a PR)" "ตอบคำถามลูกค้าในรีวิวสินค้าให้หน่อย"
addr_out=$(echo "$(user_prompt_payload "reply to the review comments on this PR")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$addr_out" | /usr/bin/grep -qi "mh:address-review"; then
  echo "  ✅ CONTENT: reply-to-review ask names '/mh:address-review'"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED '/mh:address-review': <$(printf '%s' "$addr_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- nudge content contract (must name plan mode) ---"
# Lock the plan-first framing: a future edit that drops the plan-mode line from
# the nudge output must fail here (the fire/silent tests only check the trigger,
# which is unchanged, so they wouldn't catch a content regression).
content_out=$(echo "$(user_prompt_payload "refactor the whole audit pipeline across many files")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$content_out" | /usr/bin/grep -qi "plan mode"; then
  echo "  ✅ CONTENT: nudge names 'plan mode'"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED 'plan mode' in nudge: <$(printf '%s' "$content_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- delegation content contract (must name delegation) ---"
delegation_out=$(echo "$(user_prompt_payload "refactor the whole audit pipeline across many files")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$delegation_out" | /usr/bin/grep -qi "delegat"; then
  echo "  ✅ CONTENT: nudge suggests delegation"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED delegation line: <$(printf '%s' "$delegation_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- requirement-interrogation reminder (content contract, v0.66.0 widened scope) ---"
# v0.66.0 (METHODOLOGY Rule 3): the base nudge's OPENING LINE now says
# "Rule 1 sizes the checkpoint" on ANY impl-verb prompt, ticket or not — that's
# the widened signal. The base nudge deliberately does NOT name
# 'requirement-analyst' directly (the plan explicitly rejected a standalone
# 5th route naming it — that would just stack a 4th/5th route onto an already
# crowded nudge; the mh:task-prep route that used to carry the deep pass was
# removed with the surface itself 2026-08-24 (#78) — the base route now points
# at plan mode / mattpocock-skills:grilling instead). The ticket-SPECIFIC
# addendum ("Ticket reference detected", naming requirement-analyst directly)
# stays gated on TICKET_KEY — unchanged, pre-existing behavior.
ticket_impl_out=$(echo "$(user_prompt_payload "implement TP-919")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$ticket_impl_out" | /usr/bin/grep -qi "Rule 1 sizes the checkpoint" \
   && printf '%s' "$ticket_impl_out" | /usr/bin/grep -qi "Ticket reference detected" \
   && printf '%s' "$ticket_impl_out" | /usr/bin/grep -qi "requirement-analyst"; then
  echo "  ✅ CONTENT: ticket + impl verb gets widened opening line AND the ticket-specific addendum"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED all 3 markers: <$(printf '%s' "$ticket_impl_out" | head -c 160)>" >&2
  fail=$((fail + 1))
fi
# Impl verb with NO ticket key: gets the widened opening line, but must NOT
# surface the ticket-specific addendum OR name 'requirement-analyst' directly
# — regression guard against re-adding a standalone 5th route (the exact
# over-implementation an audit caught and reverted here).
impl_no_ticket_out=$(echo "$(user_prompt_payload "implement the auth flow")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$impl_no_ticket_out" | /usr/bin/grep -qi "Rule 1 sizes the checkpoint" \
   && ! printf '%s' "$impl_no_ticket_out" | /usr/bin/grep -qi "Ticket reference detected" \
   && ! printf '%s' "$impl_no_ticket_out" | /usr/bin/grep -qi "requirement-analyst"; then
  echo "  ✅ CONTENT: impl verb with no ticket gets widened opening line only (no standalone route, no ticket addendum)"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT MISMATCH: <$(printf '%s' "$impl_no_ticket_out" | head -c 160)>" >&2
  fail=$((fail + 1))
fi
# Thai ticket + impl verb — verifies TICKET_KEY matches against mixed
# Thai/ASCII input, same as jira-route-nudge.sh's proven pattern.
thai_ticket_impl_out=$(echo "$(user_prompt_payload "พัฒนา TP-919 ให้หน่อย")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$thai_ticket_impl_out" | /usr/bin/grep -qi "Rule 1 sizes the checkpoint" \
   && printf '%s' "$thai_ticket_impl_out" | /usr/bin/grep -qi "Ticket reference detected" \
   && printf '%s' "$thai_ticket_impl_out" | /usr/bin/grep -qi "requirement-analyst"; then
  echo "  ✅ CONTENT: Thai ticket + impl verb gets widened opening line AND the ticket-specific addendum"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED all 3 markers (Thai): <$(printf '%s' "$thai_ticket_impl_out" | head -c 160)>" >&2
  fail=$((fail + 1))
fi
# Ticket key with no impl verb at all — the whole hook must stay silent
# (existing IMPL gate already covers this; guards the addendum from firing
# on a purely informational ticket mention).
test_silent "ticket key, no impl verb (status question)" "what's the status of TP-919?"

echo ""
echo "--- verb-widening + complex-bug-fix carve-in (2026-08-05 audit, docs/research/plan-mode-nudge-audit-2026-08-05.md) ---"
# Held-out audit measured the pre-widening verb list at 12% accuracy on natural
# "clear architecture work" phrasings — none of split/swap out/move/replace/
# consolidate/extract/restructure/overhaul/rework/rethink were covered.
test_nudge  "split (structural verb, not previously covered)" \
  "we need to split the monolith service into two independently deployable services"
test_nudge  "swap out (structural verb, not previously covered)" \
  "swap out the ORM for a different one across the whole codebase"
test_nudge  "consolidate (structural verb, not previously covered)" \
  "consolidate the three duplicated notification pipelines into one shared module"
test_nudge  "overhaul (nominalized, no verb form previously matched)" \
  "the caching layer needs a full overhaul across every service"
test_nudge  "rethink (nominalized, no verb form previously matched)" \
  "our permission model needs a fundamental rethink to support org-level roles"
test_nudge  "architecture as a noun (architect widened to (re)?architect(ure)?)" \
  "what's the right architecture for a plugin system that supports hot reload across five languages"
test_nudge  "rearchitecture (re-prefixed noun form)" \
  "the notification system could use a rearchitecture, it's grown organically for two years"

# Complex-bug-fix carve-in: fix/debug/diagnose stay OUT of the verb list on
# purpose (a trivial "fix typo" must stay silent) -- this only fires on
# bug-language AND a breadth signal BOTH present, never either alone.
test_nudge  "bug-language + breadth signal (carve-in fires)" \
  "debug why the payment webhook silently drops events under high traffic across three services"
test_nudge  "race condition + breadth signal (carve-in fires)" \
  "there's a bug where sessions leak across requests under load, needs a deep dive across the whole request pipeline"
test_silent "bug-language alone, no breadth signal (carve-in must NOT fire on either alone)" \
  "there's a regression in the login flow"
test_silent "breadth signal alone, no bug-language (carve-in must NOT fire on either alone)" \
  "this happens across every environment"
test_silent "trivial debug, no breadth signal, no impl verb (must stay silent)" \
  "debug this one function"

echo ""
echo "--- strong bug-signal tier, no breadth co-occurrence needed (2026-08-06, target-category recall 83.3%->91.7%) ---"
# race condition / deadlock / memory leak fire alone -- these terms describe
# multi-component interaction bugs by definition, unlike a bare "bug"/"leak"/
# "regression" which stays behind the co-occurrence gate below.
test_nudge  "race condition alone, no breadth word (strong signal fires alone)" \
  "fix the race condition in the connection pool that's causing intermittent prod outages"
test_nudge  "deadlock alone, no breadth word (strong signal fires alone)" \
  "there's a deadlock between the scheduler and the job runner"
test_nudge  "memory leak alone, no breadth word (strong signal fires alone)" \
  "diagnose the memory leak in the worker process"
# corrupt(s/ed/ing) added to the weak tier -- still requires breadth co-occurrence,
# same gate as bug/leak/regression above.
test_nudge  "corrupt + breadth signal (weak tier, co-occurrence still required)" \
  "figure out why deploys sometimes corrupt state in the shared config store, across every environment"
test_silent "corrupt alone, no breadth signal (weak tier must NOT fire alone)" \
  "the migration script corrupted one row in the test database"

echo ""
echo "--- gerund forms (2026-08-05 audit: 5/5 tested gerund prompts missed pre-fix) ---"
test_nudge  "splitting (gerund, no bare 'split')" \
  "we're splitting the monolith into two services"
test_nudge  "moving (gerund, no bare 'move')" \
  "I'm thinking about moving the billing logic out into its own service"
test_nudge  "replacing (gerund, no bare 'replace')" \
  "replacing the auth provider with a new SSO vendor across every service"
test_nudge  "extracting (gerund, no bare 'extract')" \
  "we've been extracting the billing logic out of the monolith piece by piece"
test_nudge  "setting up (phrasal gerund, not 'set uping')" \
  "setting up auth with JWT and refresh tokens"

echo ""
echo "--- prompt-only scoping via jq (2026-08-05 audit: cwd/transcript_path leaked into matching before this fix) ---"
# Real UserPromptSubmit payloads carry cwd/transcript_path alongside prompt.
# Confirmed empirically pre-fix: a repo path containing one of the widened
# verbs as a hyphen-delimited token (pdf-extract-service, order-move-service)
# fired the nudge on a bare "fix typo in README" purely from the path -- the
# widened verb list made this a real risk, not the low-stakes tradeoff it was
# when only implement/refactor/redesign were checked. Paths are built under
# $HOME, not hardcoded, per this repo's own path-hardcode gate.
path_leak_out=$(echo "{\"session_id\":\"abc\",\"transcript_path\":\"$HOME/.claude/projects/pdf-extract-service/y.jsonl\",\"cwd\":\"$HOME/Codes/pdf-extract-service\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"fix typo in README\"}" | bash "$HOOK" 2>/dev/null)
if [[ -z "$path_leak_out" ]]; then
  echo "  ✅ SILENT: verb-shaped substring in cwd/transcript_path does not leak into matching (extract-service)"
  pass=$((pass + 1))
else
  echo "  ❌ SILENT EXPECTED: path-leak regression, cwd/transcript_path substring fired the nudge: <$(printf '%s' "$path_leak_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi
path_leak_out2=$(echo "{\"session_id\":\"abc\",\"transcript_path\":\"$HOME/.claude/projects/order-move-service/y.jsonl\",\"cwd\":\"$HOME/Codes/order-move-service\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"fix typo in README\"}" | bash "$HOOK" 2>/dev/null)
if [[ -z "$path_leak_out2" ]]; then
  echo "  ✅ SILENT: verb-shaped substring in cwd/transcript_path does not leak into matching (move-service)"
  pass=$((pass + 1))
else
  echo "  ❌ SILENT EXPECTED: path-leak regression, cwd/transcript_path substring fired the nudge: <$(printf '%s' "$path_leak_out2" | head -c 120)>" >&2
  fail=$((fail + 1))
fi
# A real impl-verb prompt still fires even with a full realistic payload shape
# (cwd/transcript_path present but clean) -- guards against jq extraction
# itself going silent on the whole payload, not just the leaked fields.
real_payload_out=$(echo "{\"session_id\":\"abc\",\"transcript_path\":\"$HOME/.claude/projects/kbg-harness/y.jsonl\",\"cwd\":\"$HOME/Codes/kbg-harness\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"move the whole app from REST to GraphQL\"}" | bash "$HOOK" 2>/dev/null)
if [[ -n "$real_payload_out" ]]; then
  echo "  ✅ NUDGE: real impl verb still fires against a full realistic payload shape"
  pass=$((pass + 1))
else
  echo "  ❌ NUDGE EXPECTED: jq extraction silenced a real impl-verb prompt" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- delegation-ratio trigger, independent of the IMPL gate (GH #120) ---"
# Root cause GH #120 fixed: the delegation-nudge line used to live ONLY inside
# the IMPL-gated heredoc, so it never fired on a read/research-heavy prompt
# with no IMPL verb -- exactly the shape where hoarding happens. This prompt
# has no IMPL verb ("go through"/"tell" aren't in IMPL) and no bug-complex
# signal, so under the OLD code the hook would have gone fully silent. Under
# the new independent trigger (FILES_COUNT: "5 files" > 3, METHODOLOGY Rule
# 13's anchor), it must fire the delegation nudge -- and must NOT also print
# the "Non-trivial work detected" plan-mode heredoc, proving the two triggers
# are now independent, not the same gate.
files_no_impl_out=$(echo "$(user_prompt_payload "can you go through these 5 files and tell me what each one does")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$files_no_impl_out" | /usr/bin/grep -qi "delegat" \
   && printf '%s' "$files_no_impl_out" | /usr/bin/grep -qi "F9" \
   && ! printf '%s' "$files_no_impl_out" | /usr/bin/grep -qi "Non-trivial work detected"; then
  echo "  ✅ CONTENT: read/research prompt with no IMPL verb fires delegation nudge alone (names F9), independent of the plan-mode heredoc"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT MISMATCH (expected delegation+F9, no plan-mode heredoc): <$(printf '%s' "$files_no_impl_out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi
# Files-plural noun + breadth word co-occurrence (no explicit count), still no
# IMPL verb ("look through" isn't IMPL) -- second, independent path to the
# same trigger.
files_breadth_out=$(echo "$(user_prompt_payload "can you look through every module in the payments directory and summarize what you find")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$files_breadth_out" | /usr/bin/grep -qi "delegat" \
   && ! printf '%s' "$files_breadth_out" | /usr/bin/grep -qi "Non-trivial work detected"; then
  echo "  ✅ CONTENT: files-noun + breadth-word co-occurrence (no explicit count) also fires the independent trigger"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT MISMATCH: <$(printf '%s' "$files_breadth_out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi
# Regression guard: a breadth word with NO files-ish noun must still stay
# fully silent -- this is the exact prompt the pre-existing bug-carve-in test
# above already locks as silent; re-asserted here so a future widening of the
# delegation trigger can't quietly break it by treating any breadth word as
# sufficient on its own.
test_silent "breadth word alone, no files-noun (delegation trigger must NOT fire on breadth alone)" \
  "this happens across every environment"
# Ratio computed from real costs.jsonl data (not hardcoded): seed a scratch
# metrics file via MH_COST_METRICS_FILE (flow-nudge.sh's test-only override),
# dedup'd latest-per-(stream,model,agent_type) rows summing to orchestrator
# total tokens 900, subagent total tokens 300 -- 300/1200 = 25%. A prior/
# earlier row per key is included on purpose to prove dedup (take-latest, not
# sum-all) actually runs, not just that a single row is read.
ratio_fixture=$(mktemp)
cat > "$ratio_fixture" <<'JSONL'
{"timestamp":"2026-09-01T00:00:00Z","session_id":"gh120-test","model":"claude-sonnet-5","model_scoped":true,"stream":"orchestrator","agent_type":null,"turns":5,"input_tokens":999,"output_tokens":999,"cache_write_tokens":999,"cache_read_tokens":999}
{"timestamp":"2026-09-01T00:05:00Z","session_id":"gh120-test","model":"claude-sonnet-5","model_scoped":true,"stream":"subagent","agent_type":"general-purpose","turns":2,"input_tokens":50,"output_tokens":150,"cache_write_tokens":50,"cache_read_tokens":50}
{"timestamp":"2026-09-01T00:10:00Z","session_id":"gh120-test","model":"claude-sonnet-5","model_scoped":true,"stream":"orchestrator","agent_type":null,"turns":8,"input_tokens":150,"output_tokens":250,"cache_write_tokens":100,"cache_read_tokens":400}
JSONL
ratio_out=$(echo "{\"session_id\":\"gh120-test\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"review these 4 files for correctness\"}" | MH_COST_METRICS_FILE="$ratio_fixture" bash "$HOOK" 2>/dev/null)
python3 -c "import os; os.unlink('$ratio_fixture')" 2>/dev/null
if printf '%s' "$ratio_out" | /usr/bin/grep -qE "25% of tokens went to subagents \(300 subagent / 900 orchestrator"; then
  echo "  ✅ CONTENT: delegation ratio computed from real costs.jsonl fixture (dedup'd latest-per-key, 300/1200=25%)"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED computed 25% ratio: <$(printf '%s' "$ratio_out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi
# No session_id / no metrics file yet -- graceful "no data" text, not a
# hardcoded number and not a crash.
no_data_out=$(echo "$(user_prompt_payload "go through these 5 files and tell me what they do")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$no_data_out" | /usr/bin/grep -qi "no delegation data yet"; then
  echo "  ✅ CONTENT: no session_id/data yet -> graceful fallback text, not a fabricated ratio"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED 'no delegation data yet' fallback: <$(printf '%s' "$no_data_out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- empty / malformed input (must stay silent + exit 0) ---"
# Empty stdin (no JSON) → silent. Test by piping empty input directly.
empty_out=$(echo "" | bash "$HOOK" 2>/dev/null)
empty_rc=$?
if [[ "$empty_rc" == "0" && -z "$empty_out" ]]; then
  echo "  ✅ SILENT: empty stdin"
  pass=$((pass + 1))
else
  echo "  ❌ SILENT EXPECTED but rc=$empty_rc stdout=<$(printf '%s' "$empty_out" | head -c 80)>: empty stdin" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1