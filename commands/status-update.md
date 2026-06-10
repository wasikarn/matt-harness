---
description: "Rewrite engineer-to-engineer content for engineering-org leadership (VPs, directors, PMs, release managers, execs in an engineering-savvy company) and shape it for the channel it's going to — JIRA comment, Slack post, async standup line, email, or meeting talking-points. Trigger when the user asks to write/rewrite for management / exec / VP / director / PM / release manager, asks for an 'executive summary / leadership update / status update', says 'make this less technical / less jargony', or asks for a slack / email / standup / meeting version of work originally written engineer-to-engineer."
argument-hint: "[channel] [source-material]"
disable-model-invocation: true
---

# Status Update

Rewrite engineering content for leadership consumption, shaped for the channel it's going to. The audience reads product/framework names and cross-references JIRA keys and PRs. They do not read code.

## Core Principles

- **Channel decides the shape.** Same content, different shell. JIRA gets full structure; Slack gets bullets; standup gets one-liners; email gets flowing paragraphs; talking-points gets spoken bullets.
- **Keep the bridge identifiers.** Product names, framework names, team-owned component names, JIRA keys, PR numbers, customer/workload identifiers — these are the cross-reference bridge between engineering and leadership tracking. Never strip them.
- **Strip the implementation details.** Function names, file paths, struct fields, commit SHAs, code expressions, env var names, line numbers, internal data-structure jargon — none of this is actionable to the audience.
- **Translate mechanism to cause-and-effect.** Not "the kernel reads from `scratchBuf == NULL`" but "the GPUs end up reading from an uninitialized buffer and wait forever for a signal that never arrives."
- **Active voice, concrete subjects.** "We found the bug. Alex wrote the fix. PR is up for review." beats passive constructions.
- **Never invent facts.** If the engineering source says "root cause unknown," the rewrite says "root cause unknown." Do not promote speculation to finding for narrative tidiness.

---

## Phase 1: Identify Source + Channel

**Goal**: Know what we're rewriting and where it's going.

**Actions**:
1. Parse `$ARGUMENTS`:
   - **Source**: Is the engineering content in `$ARGUMENTS` directly? Or is it the current conversation? Or a JIRA key?
   - **Channel**: JIRA comment, Slack post, async standup, email, meeting talking-points? **Analyze**: `$ARGUMENTS` shape — long-form narrative = JIRA; bullet summary = standup; terse = talking-points. **Recommend** the channel that matches the content length and audience. Ask only when evidence is ambiguous: *"JIRA, Slack, standup, email, or talking-points?"* — then stop.
2. If source is a **JIRA key** (e.g., `JIRA-12345`): fetch via `gh` or JIRA API to get current status + latest substantive comment. Use the latest comment as source material.
3. If source is **the current conversation**: reuse what was just produced (e.g., user said "now in slack" after a `/fix-bug` summary).
4. If source is **pasted text**: use directly.

**Anti-pattern**: assuming the channel. A JIRA-shaped block dumped into Slack looks like "I escaped from JIRA."

---

## Phase 2: Extract Building Blocks

**Goal**: Pull the load-bearing facts from the engineering source.

**Actions**:
1. Read the source material holistically.
2. Extract these building blocks (use as many as fit the story):
   - **Status / TL;DR.** One bolded line. Reader can stop here and have the right answer. *"Fixed pending merge."* / *"Root cause unknown — investigating."* / *"Blocked on vendor."*
   - **Impact.** Who's affected, how badly, what they see. Customer / workload / product terms.
   - **What broke.** Short paragraph. Plain-English mechanism, one level of why, no code identifiers.
   - **Why now / how it slipped through.** Optional. Include when leadership will ask anyway.
   - **Owner.** Person + team + their PR/branch/JIRA artifact. One link.
   - **Next steps.** Concrete, near-term, ordered. *"Code review → merge → backport to 7.2."*
   - **Workaround / mitigation.** If customers are hitting it now, what can they do today?
   - **Risk.** Optional. Real risks only — *"fix touches hot path; perf regression possible until benchmarked."*
3. Order blocks by what matters most for *this* item, not by template order.

---

## Phase 3: Translate

**Goal**: Convert engineering identifiers to leadership-appropriate language.

**Rules**:
- **Keep**: Product names, framework names, component names, JIRA keys, PR numbers, customer/workload identifiers.
- **Strip**: Function names, file paths, struct fields, commit SHAs, code expressions, env var names, line numbers, internal jargon.
- **Translate**: Mechanism into 1-2 sentences of plain-English cause-and-effect.
  - Bad: "the kernel reads from `scratchBuf == NULL`"
  - Good: "the GPUs end up reading from an uninitialized buffer and wait forever for a signal that never arrives."
- **Don't over-strip.** Engineering-org leadership reads concept-level vocabulary fluently — *race condition, synchronization, uninitialized buffer, fast-path, workaround*. The line is between "concept exists and matters here" (keep) and "here's the function/struct/file/SHA" (strip).
- **Bias active voice.** *"We found the bug. Alex wrote the fix."* not *"The root cause has been identified and a fix has been authored."*
- **Avoid**:
  - Hedging: *"we believe," "appears to," "may have"* — state it or don't.
  - Obvious re-statements: *"This bug is in Tada, which is used for GPU communication, which is important for distributed training..."*
  - Telling leadership how to do their job: *"you should prioritize," "this needs to land before X"* — give facts; they decide.
  - Process minutiae: bisect runs, debug iterations, GDB sessions — unless the *process itself* is the story.

---

## Phase 4: Shape for Channel

**Goal**: Format the translated blocks for the destination channel.

### JIRA Comment / Written Status Report
Full structured block. Bolded section labels. Easy to scan from the ticket page.

Use the building blocks from Phase 2, ordered by relevance.

Example:
> **Status: Fixed pending merge.** Bug found, fix validated, PR up for review.
>
> **Impact:** LLM-7B fine-tuning on 8 GPUs would hang every eval step.
>
> **What broke:** Tada skipped an internal sync step under a config that dumbModel triggers. GPUs read uninitialized memory and got stuck.
>
> **Owner:** Alex (Tada team). PR org/platform#5751.
>
> **Next steps:** code review → merge.

### Slack — Channel Post or DM
Single message, no walls of text.

- One **bolded TL;DR** as the first line.
- 2–4 short bullets: impact, owner+link, next step.
- One link, embedded inline (`JIRA-12345` / `PR #5751`).
- No greeting, no signoff.
- **Thread reply** → lose the TL;DR, just lead with the answer.

Length: ~80 words top-level; ~40 words thread reply.

Example:
> **Tada hang affecting dumbModel LLM-7B fine-tuning is fixed pending merge.** (JIRA-12345)
>
> - Skipped sync in comms fast-path → GPUs read uninitialized memory → hang.
> - Owner: Alex, PR #5751 in review.
> - Workaround until merge: disable IPC registration.

### Async Standup Note
The audience scans 10 of these in 30 seconds. Front-load the verb.

- 1–3 lines, max.
- Pattern: *"<state> <thing>. <owner if not me>. <next>."*
- No bullets, no bolded labels.

Examples:
- *"Fixed Tada hang on dumbModel LLM-7B (JIRA-12345). Alex's PR #5751 in review. Backport to v7.2 next."*
- *"Still chasing the LLM-7B eval-step hang. Reproducer is reliable now; bisecting. No ETA yet."*

### Email — Internal Exec / Cross-Team
Subject line is half the value.

- **Subject:** TL;DR as noun phrase. *"Tada hang in dumbModel: fix in review (JIRA-12345)."*
- **Greeting:** match recipient register (*Hi Sam,* / *Hi all,*)
- **Body:** JIRA-comment shape as flowing paragraphs, 2-3 paragraphs.
- **Sign off** with the next decision point that needs the recipient's attention, if any.

### Meeting Talking-Points
You're going to *say* this, not show it.

- Bullet list, max one short clause per bullet.
- Order = speaking order.
- Include numbers/keys you want to reference out loud.
- Skip prose. *"dumbModel LLM-7B fine-tuning was hanging."* / *"Root cause: skipped sync in Tada fast-path."* / *"Alex's fix in review, PR #5751."*

---

## Phase 5: Verify

**Goal**: Quality-check before presenting.

**Actions**:
1. Check: no code identifiers leaked into the output (function names, file paths, SHAs)?
2. Check: no invented facts? Every claim traceable to the engineering source?
3. Check: channel-appropriate length? (Slack under ~80 words, standup 1-3 lines, etc.)
4. Check: active voice dominates?
5. Check: TL;DR is the first thing the reader sees?
6. Present the shaped update to the user in a single chat block formatted as the channel would render it.

---

## Phase 6: Handoff

**Goal**: Deliver the draft; user posts it.

**Actions**:
1. Present the final shaped update.
2. **Analyze**: content sensitivity (public vs internal), channel norms (exec update vs sprint update vs incident report), JIRA integration availability, user's historical preference from memory. **Recommend** the channel that matches the audience and sensitivity.
3. **AskUserQuestion** single-select: "Phase 6: channel = [JIRA / Slack / standup / email / talking-points], sensitivity = [public / internal / exec], length = [words / lines]. My recommendation: [channel]. Confirm destination?"
   - `Print-only (Recommended for sensitive or exec-level content)` — hand draft to user; they copy and post manually
   - `JIRA back-post (Recommended for routine sprint or incident updates)` — show exact payload, then post after user confirms
   - *Never post to Slack, email, or any non-JIRA channel from this skill.*
4. **One iteration is normal, three is a smell.** **Analyze**: revision delta — what changed between v1, v2, v3? Tone? Scope? Audience? Detail level? **Recommend** the framing dimension that drifted (e.g., "too technical for exec audience" or "missing impact metric"). Ask that specific dimension rather than a generic "what's wrong?" — don't keep tweaking blindly.

---

## Rules

- **Never invent facts** to make the rewrite cleaner.
- **Never strip a JIRA key, PR number, or customer/workload name** during de-jargoning. They're the cross-reference bridge.
- **Never invent owners.** **Analyze**: does the source material (JIRA, PR, commit message) name a DRI? **Recommend** infer only when the source explicitly names a single owner; otherwise ask the user rather than guessing from `git blame` or assuming the author is the owner.
- **Get sign-off before posting to JIRA.** Print-only output needs no approval.
- **Never post to Slack, email, or any non-JIRA channel from this skill.**
- **Stay out of advocacy.** This produces a status update, not a recommendation. If the user wants a recommendation memo, confirm before reframing.

---

## Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Think before coding) → Phase 1 identifies channel before shaping. Rule 7 (Surface conflicts, don't average) → if source says "unknown," output says "unknown" — no averaging toward confidence. Rule 12 (Fail loud) → Phase 1 asks channel if unclear, doesn't guess.
- **Post-/fix-bug workflow**: `/fix-bug` Phase 7 summary (what broke, root cause, fix shape, regression test, files touched) is perfect source material for a `/status-update`. The two commands compose naturally.
- **Post-review-pr workflow**: `review-pr` Phase 6 findings can be source material for a status update about review progress.
- **Hooks active**: doctrine-edit-gate protects CLAUDE.md/METHODOLOGY.md if this command is used in a session that also edits doctrine.
- **Channel detection**: If `$ARGUMENTS` contains "slack" / "standup" / "email" / "jira" / "meeting" — treat as explicit channel specification. Otherwise ask.
