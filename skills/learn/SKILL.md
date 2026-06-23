---
name: learn
description: "Mine the current session for durable, reusable learnings — operator corrections, repeated workflows, stated preferences/conventions, decisions with rationale — and, ONLY after an AskUserQuestion approval gate, save the chosen ones as memory files. Use when the user explicitly asks to capture what was learned: 'learn from this session', 'remember how we did this', 'capture these learnings', 'save what you learned', or Thai 'จำไว้', 'เรียนจาก session นี้', 'บันทึกสิ่งที่เรียนรู้'. Don't use for: writing a single memory you already know (just write it directly), harness self-improvement (use kbg:recursive-improve), memory bookkeeping/lint (use kbg:memory-lint / kbg:memory-trim), or unprompted auto-*apply*. A default-ON SessionEnd hook (learn-capture; opt out with KBG_LEARN_CAPTURE=0) passively STAGES candidates to an out-of-repo queue, but nothing is written without your approval here."
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

- **Capture is passive (default-ON); APPLY is operator-gated.** A SessionEnd hook
  (`learn-capture`, default-ON — opt out with `KBG_LEARN_CAPTURE=0`) passively *stages* candidates to an
  out-of-repo queue (journal-only, never the repo, never a `permissionDecision`). But this skill
  is still the **only** path that WRITES memory, and only after the `AskUserQuestion` gate. The
  autonomy invariant is preserved by capture-never-applies + the gate below — see
  [`docs/adr/0002-addendum-passive-capture.md`](../../docs/adr/0002-addendum-passive-capture.md)
  (the conscious relaxation of the prior "no SessionEnd hook" stance) + the
  [candidate schema](CANDIDATE-SCHEMA.md).
- **Writes are gated.** Candidates are NEVER written silently. Every save passes an
  `AskUserQuestion` gate; the operator approves each one. Reject = nothing written.
- **No flag, by design.** The skill is `disable-model-invocation`-free so the model can reach it
  when the operator expresses the intent ("remember how we did this") — the in-flow gate, not a
  user-only lockout, is the safety. (Mirrors the create-jira-* skills; contrast recursive-improve,
  which IS flagged because it is a *mutation loop* that must not self-start.)

## Procedure

0. **Drain the candidate queue first (if passive capture is enabled).** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-candidates.sh" --transcript "$(bash "${CLAUDE_SKILL_DIR}/scripts/find-transcript.sh")"`
   to list staged candidates — one JSON object per line, already merged across sessions and ranked
   by the **ordering-only** confidence ([`CANDIDATE-SCHEMA.md`](CANDIDATE-SCHEMA.md); the rank only
   sorts the list — never treat it as a gate). Empty/exit-0 = nothing staged; proceed to Step 1.
   - **When the queue holds rows from THIS session, Step 0 REPLACES Step 2's re-mine for those** —
     do not double-surface. If you also mine in Step 2, hash-dedupe by `trigger`/`evidence` before
     the gate so each learning appears once.
   - Carry the queue candidates into the Step-3 filter and the Step-4 gate alongside any freshly
     mined ones. After the gate, dispose each handled candidate by its `key` field:
     `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-candidates.sh" --transcript "<path>" --archive "<key>" promoted|rejected`
     so it leaves the open list (rejected rows are kept, re-openable, never `rm`).

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
