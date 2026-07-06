---
name: learn
description: "Catalogue durable session learnings; save as memory after an AskUserQuestion gate. Use when asked to capture learnings. Don't use for single known memories or self-improvement."
---

# Skill: learn

Turn a working session into durable memory. Read the session transcript, surface the
**non-obvious, reusable** things worth keeping — corrections the operator made, conventions
they stated, workflows that repeated, decisions and their *why* — then let the operator pick
which to save before anything is written.

This is the human-gated, propose-only counterpart of `kbg:recursive-improve`: that skill closes
the loop on the *harness's health*; this one closes it on *what the operator taught you this
session*. The store already exists (the file-based memory system); this skill is the part that
notices what belongs in it.

## Autonomy posture (load-bearing)

- **Operator-invoked only.** This skill runs when the operator asks to capture learnings — there
  is no passive SessionEnd capture hook wired (a prior `learn-capture` SessionEnd design was retired
  alongside ADR 0006 and is not re-armed; its backing `scripts/read-candidates.sh` is absent). The
  skill is the **only** path that WRITES memory here, and only after the `AskUserQuestion` gate. A
  separate `hooks/advisory/learn-nudge.sh` (SessionEnd, added 2026-07-06) only *reminds* the operator
  this skill exists when the session had enough activity to plausibly be worth a look — it reads
  nothing about content, extracts no candidates, and writes nothing. It's a nudge toward invoking
  this skill, not a second entry point into it.
- **Writes are gated.** Candidates are NEVER written silently. Every save passes an
  `AskUserQuestion` gate; the operator approves each one. Reject = nothing written.
- **No flag, by design.** The skill is `disable-model-invocation`-free so the model can reach it
  when the operator expresses the intent ("remember how we did this") — the in-flow gate, not a
  user-only lockout, is the safety. (Contrast recursive-improve, which IS flagged because it is a
  *mutation loop* that must not self-start.)

## Procedure

1. **Locate the transcript.** Run `bash "${CLAUDE_SKILL_DIR}/scripts/find-transcript.sh"` for the
   current project's latest `.jsonl`. If it fails, ask the operator for the transcript path directly
   — no hook injects one into session context (a prior design assumed one would; none is wired).

2. **Mine candidates.** Read the transcript and extract things that are **durable + non-obvious +
   reusable next session**. Good sources:
   - **Corrections** — where the operator said "no, do X instead" / "use Y not Z" (the highest-signal
     learnings; capture the rule + the why).
   - **Stated preferences / conventions** — "always…", "never…", "in this repo we…".
   - **Repeated workflows** — a multi-step sequence the operator ran more than once.
   - **Decisions + rationale** — a choice made and the reason that would otherwise be re-litigated.

3. **Filter hard (this is most of the value).** Drop a candidate if:
   - it's already in `MEMORY.md` or an existing `memory/` file (dedupe — read the index first);
   - the repo already records it (code structure, git history, CLAUDE.md, an ADR) — per the memory
     rules, save what was *non-obvious*, not what a file already states;
   - it only mattered to this conversation (ephemeral), or it's a secret/credential;
   - it was a trivial one-off (a typo, a simple syntax slip) with no generalizable rule behind it —
     a "no, do X instead" correction is only high-signal when X *generalizes* past this one spot.

4. **Gate.** Present the surviving candidates with `AskUserQuestion` (multiSelect) — each option a
   one-line summary + proposed `type` (user / feedback / project / reference). The operator picks
   which to save. If none survive step 3, say so and stop — do not manufacture learnings.

5. **Write the approved ones** as `memory/<slug>.md` in the standard format (frontmatter with
   `name` / `description` / `metadata.type`; body; for feedback/project add **Why:** + **How to
   apply:**; link related memories with `[[name]]`). Add a one-line pointer to `MEMORY.md`. Convert
   relative dates to absolute. Follow the memory rules in the system prompt verbatim.

6. **Lint.** Run `kbg:memory-lint` to catch dangling `[[links]]`, orphans, and index drift.

## When NOT to use

- You already know the single fact to record → just write the memory file directly.
- Harness health / self-improvement → `kbg:recursive-improve`.
- Cleaning or trimming existing memory → `kbg:memory-lint` (use `--trim` to archive bloat).
- Unprompted, mid-task → don't; this is a deliberate end-of-work reflection, operator-initiated.

## See also

- `kbg:recursive-improve` — the `kbg:harness-audit` sibling for harness health (mutation loop, flagged, human-gated), vs. this skill's operator-taught learnings.
- `kbg:memory-lint` — memory bookkeeping (with `--trim` mode) the write step relies on.
- The memory rules in the session system prompt — the authoritative format + what-to-save contract.

## Done when

The chosen learnings are saved as memory files with the operator's gate approval — verify each file is linked from MEMORY.md before stopping.
