---
name: learn
description: "Mine the current session for durable, reusable learnings — operator corrections, repeated workflows, stated preferences/conventions, decisions with rationale — and, ONLY after an AskUserQuestion approval gate, save the chosen ones as memory files. Use when the user explicitly asks to capture what was learned: 'learn from this session', 'remember how we did this', 'capture these learnings', 'save what you learned', or Thai 'จำไว้', 'เรียนจาก session นี้', 'บันทึกสิ่งที่เรียนรู้'. Don't use for: writing a single memory you already know (just write it directly), harness self-improvement (use kbg:recursive-improve), memory bookkeeping/lint (use kbg:memory-lint / kbg:memory-trim), or unprompted auto-capture (this is operator-initiated only — there is NO SessionEnd auto-mining)."
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

- **Operator-initiated only.** There is **no** SessionEnd auto-mining hook — the skill runs when
  the operator asks. The autonomy invariant (ADR 0002/0003) is preserved by this + the gate below.
- **Writes are gated.** Candidates are NEVER written silently. Every save passes an
  `AskUserQuestion` gate; the operator approves each one. Reject = nothing written.
- **No flag, by design.** The skill is `disable-model-invocation`-free so the model can reach it
  when the operator expresses the intent ("remember how we did this") — the in-flow gate, not a
  user-only lockout, is the safety. (Mirrors the create-jira-* skills; contrast recursive-improve,
  which IS flagged because it is a *mutation loop* that must not self-start.)

## Procedure

1. **Locate the transcript.** Run `bash "${CLAUDE_SKILL_DIR}/scripts/find-transcript.sh"` for the
   current project's latest `.jsonl`. If it fails, fall back to the transcript path the SessionStart
   hook injected (the `**Transcript:**` line in the session summary).

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
   - it only mattered to this conversation (ephemeral), or it's a secret/credential.

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
- Cleaning or trimming existing memory → `kbg:memory-lint` / `kbg:memory-trim`.
- Unprompted, mid-task → don't; this is a deliberate end-of-work reflection, operator-initiated.

## See also

- `kbg:recursive-improve` — the harness-health sibling (mutation loop, flagged, human-gated).
- `kbg:memory-lint` / `kbg:memory-trim` — memory bookkeeping the write step relies on.
- The memory rules in the session system prompt — the authoritative format + what-to-save contract.
