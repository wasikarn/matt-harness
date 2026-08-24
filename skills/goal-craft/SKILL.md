---
name: goal-craft
description: "Compact a /goal completion condition: done-when check, one-way-door screen, turn bound. Use when drafting a /goal condition. Don't use for single-turn tasks (do it directly)."
bucket: meta
metadata:
  origin: kbg-native
  adapted-from: "goal-spec (retired a518ad1, orphaned from c35afcc)"
argument-hint: "The freeform task description to turn into a /goal condition"
model: inherit
effort: high
---

# Goal Craft

Compact a freeform task description into a single, paste-ready completion-condition string for Claude Code's native `/goal` command. `/goal`'s evaluator is a separate small model that reads only the transcript and calls no tools — a vague condition gets rubber-stamped, an unbounded one loops forever, an irreversible action baked in executes without review. This skill produces the string only; it never invokes `/goal`, shells out, or spawns a process — the user pastes the output themselves, every time.

**Scope note for scheduled/unattended use:** the output here is only the "what does success look like" half of an unattended prompt. If this condition is going into a scheduled task (Routine, desktop scheduled task, GitHub Action, or `/loop`), the prompt still needs its own separate instruction for what to do with the results once the loop stops — post a summary, leave a comment, open a PR — since nothing runs to read a stop condition back to anyone. This skill doesn't produce that clause; say so if the user's task reads as scheduled/unattended and they haven't stated one.

## Procedure

1. **Intake**
   - Read the freeform task description passed as the skill argument, plus whatever repo/task context is already in the conversation.
   - Name the implied deliverable in one sentence, and note anything that reads as irreversible or too vague to check mechanically.
   - Failure mode to avoid: inventing a deliverable the input doesn't support — if the description is too thin to name one, that's the signal to move to step 2's clarify, not to guess silently.
   - Done when: you can state the deliverable in one sentence, or you know exactly what's missing to state it.

2. **Clarify only if consequential**
   - Analyze → recommend → ask, don't over-question. Ask one question via `AskUserQuestion`, with your recommended default pre-filled, only if the ambiguity is genuinely expensive to guess wrong. Each option states what it changes about the resulting condition (which clause, which scope, which Never-touch boundary) — not a bare label; the user is picking a consequence, not a category.
   - Otherwise state your working interpretation inline and proceed.
   - Failure mode to avoid: interrogating the user with a checklist before producing anything — the over-questioning trap `clarify` mode exists to prevent.
   - Done when: either one targeted question is asked, or a stated default is chosen and intake proceeds.

3. **Compact into Goal / Done-when / Never-touch**
   - Compact goal-spec's discipline (Goal, Done-when, Never-touch) into inline clauses — no file is written. Every Done-when clause needs: (a) a measurable end state, (b) a stated check phrased so Claude will actually run it and paste real output — the evaluator reads only the transcript, so a check that was never run produces nothing for it to read, (c) explicit Never-touch constraints naming a real path or directory `git status` can be run against — never a prose description of the change. If the task doesn't name an exact implementation path, name the narrowest concrete scope you can infer (the file/endpoint already mentioned in the task, or the directory it clearly lives in) rather than a description that can't be mechanically checked.
   - Use the table below to convert soft criteria into checkable ones.
   - Failure mode to avoid: writing a clause that asserts a feeling instead of naming a check — Rule 14's "score, not feel" failure, and the exact rubber-stamp risk the evaluator can't catch on its own.
   - Failure mode to avoid: adapting the table's repro-based pattern ("re-run and confirmed") when the task names a bug but supplies no repro steps — that produces a clause that reads as checkable but is actually unfalsifiable by the tool-less evaluator, since nothing forces the loop to have measured anything before claiming "confirmed." When no repro exists, name a regression test instead (fails before the fix, passes after) or fall back to a general test-suite check.
   - Done when: every clause in the draft names a command or artifact Claude will produce real output for — never a feeling.

4. **One-way-door screen**
   - Scan the compacted condition for irreversible-action language. This is a semantic screen, not literal string matching. Watch for: push, deploy, release, merge, delete/rm/drop/truncate/cancel, force-push/overwrite, send/email/notify/publish/post, pay/charge/refund/transfer, rollback/migrate (any schema or data migration, not just ones naming "prod" — a migration against a real database is a one-way door regardless of environment name), close/tag/revoke/rotate credentials — and semantic equivalents in any language, including Thai (ปล่อย/deploy, ส่ง/send, ลบ/delete).
   - Strip and flag by default — every one-way-door fragment gets its own excluded note; never bake it into the loop, never silently drop it either.
   - Scope limit, state it plainly: this screen only sees verbs named in the condition text — it stops the loop from *declaring* an irreversible goal, not from *reaching* one instrumentally (e.g. a `git reset --hard` on the way to "make CI green," verb never in the condition). Claude Code's own per-tool-call permission prompt covers that case in the default permission mode; auto mode turns that prompt off, and auto mode is exactly what `/goal` is meant to be paired with for unattended runs. Don't pair a goal whose instrumental path could plausibly reach a destructive action with auto mode.
   - Failure mode to avoid: stripping a verb that's the task's own subject matter, not an action the loop would take — "fix the delete-account bug" names a bug, it does not ask the loop to delete anything. Only strip when the sentence's grammatical action is the irreversible verb.
   - Edge case: if stripping would empty the condition (the whole task was the one-way-door action, e.g. "deploy to prod"), do not print a bare `/goal` — use the "Nothing left to loop on" shape in the Output Format section below. If step 6's gate would also apply to this same input (no clause was nameable even before this screen ran), this edge case still takes precedence — the one-way-door reason is more informative to the user than a generic "nothing checkable" note.
   - Done when: every stripped fragment has a matching excluded note, and the remaining condition still has a real loop to run — or you've told the user there isn't one, in the format below.

5. **Append the bound clause**
   - Always end with an explicit stop condition. Default: `or stop after 15 turns`; adjust down (~10) for a one-file fix or up (~20-25) for a multi-file feature. State the number, don't ask — the user edits it in the paste if it's wrong.
   - Optionally fold in one stuck-detection OR-clause (adapted from goal-spec's "Stop if"), only when a baseline was already established earlier in the same transcript the evaluator can compare against (e.g. a test run from step 3) — an unestablished baseline is unfalsifiable by the evaluator's own no-tools constraint.
   - Failure mode to avoid: leaving the condition unbounded — an unbounded condition plus auto mode is a loop with no backstop but the evaluator's judgment.
   - Done when: the compacted string ends in a bound the loop cannot run past.

6. **Assemble and gate the output**
   - Concatenate done-when clauses + never-touch constraints + bound clause into one compacted `/goal <condition>` string, ≤4000 chars (`/goal`'s own limit) — trim prose before trimming the check or the bound.
   - Gate: if step 3 could not produce even one clause with a real, nameable check, do not emit a rubber-stampable condition — use the "Nothing left to loop on" shape in the Output Format section below, naming what's missing (or ask the step-2 clarifying question instead, if that's still live).
   - Failure mode to avoid: passing a vague condition through anyway — that's the fake-done shortcut the evaluator will rubber-stamp (arXiv 2606.09863, "confident closing language" as a false proxy for verified completion).
   - Render the Output Format below, fenced exactly as shown there — the fencing is part of the format, not decoration, since a paste-ready string that isn't cleanly delimited defeats the point.
   - Done when: the printed `/goal` line is self-contained — pasteable with no more context — every excluded fragment has its own flagged note, and both are wrapped in fenced code blocks.

## Writing verifiable Done-when clauses

Each clause must be mechanically checkable by something Claude will actually run and paste output from — not by feel.

| Weak (fake-done risk) | Strong (drop-in for a `/goal` condition) |
|---|---|
| "the code is good" / "it works well" | "`npm test` exits 0 in `src/auth`" |
| "the bug is fixed" (repro given) | "the repro steps in the report no longer trigger the error, re-run and confirmed" |
| "the bug is fixed" (no repro given) | "a new regression test reproduces the bug (fails before the fix) then passes after it" |
| "docs are updated" | "`docs/api.md` contains a `## Endpoints` section" |
| "nothing else broke" | "`git status` is clean outside `src/auth`" (pairs with Never-touch) |
| "tests pass" | "`cargo test 2>&1 \| grep 'test result: ok'`" |

## Output Format

Print exactly two parts, no preamble:

1. **The compacted condition** — one fenced line, ready to paste after `/goal`:

```
/goal <done-when clauses>, <never-touch clause> or stop after <N> turns[, or <stop-if clause>]
```

2. **Excluded notes** — only if the one-way-door screen stripped anything, one line per fragment. If nothing was stripped, omit this block entirely.

```
⚠ excluded: "<fragment>" — one-way door, approve manually after the goal completes
```

### "Nothing left to loop on" shape

Used when step 4's edge case or step 6's gate fires (see those steps for which applies). No `/goal` line at all — state plainly, then list excluded notes if any:

```
This task is [entirely a manual action / too vague to name a mechanical check] — there's nothing left to loop on.
```

```
⚠ excluded: "<fragment>" — one-way door, do this step manually
```

### Worked example

Input: `kbg:goal-craft "fix auth bug แล้ว deploy ให้ด้วย"`

Output:
```
/goal npm test ใน src/auth ผ่านหมด และ git status สะอาด ยกเว้นไฟล์ใน src/auth or stop after 15 turns
```
```
⚠ ตัดออก: "deploy" — เป็น one-way door ต้องอนุมัติเองหลัง goal เสร็จ
```

## Don't duplicate canon

- METHODOLOGY Rule 14 ("score, not feel") and the fake-done-guard doctrine (harness-audit check 34, arXiv 2606.09863) own the falsifiability principle; this skill is the `/goal`-shaped composition tool for it.
- `goal-spec` (retired `a518ad1`, orphaned from `c35afcc`) owned the same Goal/Done-when/Never-touch discipline for a persistent, multi-session `PROMPT.md` read by a human before a loop starts. This skill covers the narrower case `/goal` needs: a single inline string, no file, no pre-loop human review of the condition itself (goal-spec's PROMPT.md was read by a human before the loop started; `/goal` isn't) — which is exactly why the one-way-door screen exists here and never existed in `goal-spec`. The persistent-file, multi-session case stays covered by `ship`/`recursive-improve`/`eval-harness`, not re-created here.
