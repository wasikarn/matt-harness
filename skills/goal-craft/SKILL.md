---
name: goal-craft
description: "Compact a /goal completion condition: done-when check, one-way-door screen, turn bound. Use when drafting a /goal condition. Don't use for single-turn tasks (do it directly)."
metadata:
  origin: kbg-native
  adapted-from: "goal-spec (retired a518ad1, orphaned from c35afcc)"
argument-hint: "The freeform task description to turn into a /goal condition"
---

# Goal Craft

Compact a freeform task description into a single, paste-ready completion-condition string for Claude Code's native `/goal` command. `/goal`'s evaluator is a separate small model that reads only the transcript and calls no tools — a vague condition gets rubber-stamped, an unbounded one loops forever, an irreversible action baked in executes without review. This skill produces the string only; it never invokes `/goal`, shells out, or spawns a process — the user pastes the output themselves, every time.

## Procedure

1. **Intake**
   - Read the freeform task description passed as the skill argument, plus whatever repo/task context is already in the conversation.
   - Name the implied deliverable in one sentence, and note anything that reads as irreversible or too vague to check mechanically.
   - Failure mode to avoid: inventing a deliverable the input doesn't support — if the description is too thin to name one, that's the signal to move to step 2's clarify, not to guess silently.
   - Done when: you can state the deliverable in one sentence, or you know exactly what's missing to state it.

2. **Clarify only if consequential**
   - Analyze → recommend → ask, don't over-question (same discipline as `kbg:decide`'s `clarify` mode). Ask one question via `AskUserQuestion`, with your recommended default pre-filled, only if the ambiguity is genuinely expensive to guess wrong.
   - Otherwise state your working interpretation inline and proceed.
   - Failure mode to avoid: interrogating the user with a checklist before producing anything — the over-questioning trap `clarify` mode exists to prevent.
   - Done when: either one targeted question is asked, or a stated default is chosen and intake proceeds.

3. **Compact into Goal / Done-when / Never-touch**
   - Compact goal-spec's discipline (Goal, Done-when, Never-touch) into inline clauses — no file is written. Every Done-when clause needs: (a) a measurable end state, (b) a stated check phrased so Claude will actually run it and paste real output — the evaluator reads only the transcript, so a check that was never run produces nothing for it to read, (c) explicit Never-touch constraints naming files/dirs/surfaces that must not change.
   - Use the table below to convert soft criteria into checkable ones.
   - Failure mode to avoid: writing a clause that asserts a feeling instead of naming a check — Rule 14's "score, not feel" failure, and the exact rubber-stamp risk the evaluator can't catch on its own.
   - Done when: every clause in the draft names a command or artifact Claude will produce real output for — never a feeling.

4. **One-way-door screen**
   - Scan the compacted condition for irreversible-action language. This is a semantic screen, not literal string matching. Watch for: push, deploy, release, merge, delete/rm/drop/truncate/cancel, force-push/overwrite, send/email/notify/publish/post, pay/charge/refund/transfer, rollback/migrate (any schema or data migration, not just ones naming "prod" — a migration against a real database is a one-way door regardless of environment name), close/tag/revoke/rotate credentials — and semantic equivalents in any language, including Thai (ปล่อย/deploy, ส่ง/send, ลบ/delete).
   - Strip and flag by default — every one-way-door fragment gets its own excluded note; never bake it into the loop, never silently drop it either.
   - Failure mode to avoid: stripping a verb that's the task's own subject matter, not an action the loop would take — "fix the delete-account bug" names a bug, it does not ask the loop to delete anything. Only strip when the sentence's grammatical action is the irreversible verb.
   - Edge case: if stripping would empty the condition (the whole task was the one-way-door action, e.g. "deploy to prod"), do not print a bare `/goal` — tell the user this task is entirely a manual action and there is nothing left to loop on.
   - Done when: every stripped fragment has a matching excluded note, and the remaining condition still has a real loop to run — or you've told the user there isn't one.

5. **Append the bound clause**
   - Always end with an explicit stop condition. Default: `or stop after 15 turns`; adjust down (~10) for a one-file fix or up (~20-25) for a multi-file feature. State the number, don't ask — the user edits it in the paste if it's wrong.
   - Optionally fold in one stuck-detection OR-clause (adapted from goal-spec's "Stop if"), only when a baseline was already established earlier in the same transcript the evaluator can compare against (e.g. a test run from step 3) — an unestablished baseline is unfalsifiable by the evaluator's own no-tools constraint.
   - Failure mode to avoid: leaving the condition unbounded — an unbounded condition plus auto mode is a loop with no backstop but the evaluator's judgment.
   - Done when: the compacted string ends in a bound the loop cannot run past.

6. **Assemble and gate the output**
   - Concatenate done-when clauses + never-touch constraints + bound clause into one compacted `/goal <condition>` string, ≤4000 chars (`/goal`'s own limit) — trim prose before trimming the check or the bound.
   - Gate: if step 3 could not produce even one clause with a real, nameable check, do not emit a rubber-stampable condition — stop, and either ask the step-2 clarifying question or hand back a short rework note naming what's missing.
   - Failure mode to avoid: passing a vague condition through anyway — that's the fake-done shortcut the evaluator will rubber-stamp (arXiv 2606.10209 §3 "confident garbage").
   - Render the Output Format below.
   - Done when: the printed `/goal` line is self-contained — pasteable with no more context — and every excluded fragment has its own flagged note.

## Writing verifiable Done-when clauses

Each clause must be mechanically checkable by something Claude will actually run and paste output from — not by feel.

| Weak (fake-done risk) | Strong (drop-in for a `/goal` condition) |
|---|---|
| "the code is good" / "it works well" | "`npm test` exits 0 in `src/auth`" |
| "the bug is fixed" | "the repro steps in the report no longer trigger the error, re-run and confirmed" |
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

- METHODOLOGY Rule 14 ("score, not feel") and the fake-done-guard doctrine (harness-audit check 34, arXiv 2606.10209 §3) own the falsifiability principle; this skill is the `/goal`-shaped composition tool for it.
- `goal-spec` (retired `a518ad1`, orphaned from `c35afcc`) owned the same Goal/Done-when/Never-touch discipline for a persistent, multi-session `PROMPT.md` read by a human before a loop starts. This skill covers the narrower case `/goal` needs: a single inline string, no file, no built-in human review gate on the target command — which is exactly why the one-way-door screen exists here and never existed in `goal-spec`. The persistent-file, multi-session case stays covered by `ship`/`recursive-improve`/`eval-harness`, not re-created here.
