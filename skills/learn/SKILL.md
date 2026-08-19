---
name: learn
description: "Scan a session transcript for cross-turn patterns ambient auto-memory misses. Use when wrapping up a session; batch-gate via AskUserQuestion. Don't use for single known memories."
bucket: meta
---

# Skill: learn

Turn a working session into durable memory — specifically the part Claude Code's own **native
auto-memory** structurally can't reach. Read the session transcript, surface the **non-obvious,
reusable** things worth keeping — corrections the operator made, conventions they stated,
workflows that repeated, decisions and their *why* — then let the operator pick which to save
before anything is written.

This is the human-gated, propose-only counterpart of `kbg:recursive-improve`: that skill closes
the loop on the *harness's health*; this one closes it on *what the operator taught you this
session*. The store already exists (Claude Code's file-based memory system, `memory/<slug>.md` +
`MEMORY.md`); this skill is one of two things that write to it.

## Autonomy posture (load-bearing)

- **Not the primary writer — Claude Code's native auto-memory is.** Since ~CLI v2.1.59, Claude
  Code ships an ambient, always-on memory feature (`autoMemoryEnabled`, `/memory`): the model
  saves memory files directly, no per-write confirmation, whenever an in-the-moment trigger fires
  (a correction just happened, a preference was stated). That's the same store, same format, same
  `MEMORY.md` index this skill writes to — verified against `code.claude.com/docs/en/memory` and,
  empirically, this project's own transcripts (132 memory files across 53 sessions in this repo's
  own store vs. `/kbg:learn` itself invoked in 3 sessions here, as of 2026-07-20 — the native path
  still accounts for the large majority of writes, and a quality spot-check of several
  ambiently-written files found them well-structured, non-duplicative, correctly filtered).
  Native ambient capture is real, it works, and kbg cannot gate, disable-per-write, or reroute it —
  it's a Claude Code platform feature, not a kbg surface.
- **What this skill actually adds: the retrospective, whole-transcript sweep.** Native ambient
  triggers fire in the moment, on a single turn — they cannot see **cross-turn** patterns: "we ran
  this workflow three times this session," "this decision got re-litigated twice," a correction
  whose generalizable rule only becomes clear once you've seen the whole arc. That requires reading
  the *entire* transcript in one pass, which only happens when this skill is explicitly invoked.
  That is the one capability native auto-memory structurally cannot replicate — everything else it
  already covers ambiently.
- **Operator-invoked only.** This skill runs when the operator asks to capture learnings — there
  is no passive SessionEnd capture hook wired (a prior `learn-capture` SessionEnd design was retired
  alongside ADR 0006 and is not re-armed; its backing `scripts/read-candidates.sh` is absent). A
  separate `hooks/advisory/learn-nudge.sh` (SessionEnd, added 2026-07-06) only *reminds* the operator
  this skill exists when the session had enough activity to plausibly be worth a look — it reads
  nothing about content, extracts no candidates, and writes nothing. It's a nudge toward invoking
  this skill for the retrospective sweep, not a claim that memory capture requires it.
- **This skill's own writes are gated; the store's writes at large are not.** Every candidate this
  skill proposes passes an `AskUserQuestion` gate before it's written — reject = nothing written.
  That gate covers the *batch this skill mined*; it was never able to, and does not claim to, gate
  the native ambient path's own writes.
- **No flag, by design.** The skill is `disable-model-invocation`-free so the model can reach it
  when the operator expresses the intent ("remember how we did this") — the in-flow gate, not a
  user-only lockout, is the safety. (Contrast recursive-improve, which IS flagged because it is a
  *mutation loop* that must not self-start.)

## Procedure

1. **Locate the transcript.** Run `bash "${CLAUDE_SKILL_DIR}/scripts/find-transcript.sh"` for the
   current project's latest `.jsonl` — prints `<path> <bytes>`. If it fails, ask the operator for
   the transcript path directly — no hook injects one into session context (a prior design assumed
   one would; none is wired).

2. **Mine candidates — bias toward what a single-turn trigger can't see.** If the reported size is
   under ~2MB, read the whole transcript. Above that, don't — this repo's own transcripts range up
   to 83MB, and reading that whole into one mining pass is the same "cut what your model has to
   read" problem a 2026-08-17 audit found in this fleet's fan-out/synthesis steps. Instead, bound
   the read with a deterministic pre-filter: `grep -n '"type":"user"' <path> | grep -iE '\b(no,|instead|don.t|actually,|wait,|revert|undo)\b'`
   for correction-shaped turns, plus `tail -c 500000 <path>` for the most recent stretch (native
   ambient capture already thins the middle of a long session; the tail and the corrections are
   where cross-turn value concentrates). Read only the matched line ranges plus their surrounding
   context, not the full file. (ponytail: a hard byte cap + grep pre-filter, not smarter chunking —
   upgrade only if a real run shows this misses too much. A 2026-08-17 deep-audit already caught
   one real miss and closed it here: the original pattern anchored the trigger words to right after
   a literal `"`, which only matches text starting a JSON string — real corrections are usually
   mid-message, so on a live 4MB transcript it returned 16 matches and 0 were genuine user
   corrections, all false positives from prose/tool-descriptions elsewhere in the file. Restricting
   to `"type":"user"` lines and dropping the `"`-anchor fixed recall on the same transcript;
   precision is still loose — a pasted document inside a user turn can still match — accepted
   because a pre-filter's job is to bound the read, not achieve perfect precision, and losing a
   real correction to a too-narrow filter is worse than reading a few extra irrelevant lines.)
   Either way, extract things that are
   **durable + non-obvious + reusable next session**, weighting repetition and cross-turn arcs over
   one-shot moments (native ambient capture already catches the obvious in-the-moment correction —
   this pass's marginal value is what only shows up across the full session):
   - **Repeated workflows** — a multi-step sequence the operator ran more than once this session.
   - **Decisions re-litigated or reversed** — a choice revisited later in the same session, and why.
   - **Corrections whose rule only generalizes in hindsight** — "no, do X instead" where the
     generalizable version only becomes clear after seeing where else it applied (or should have).
   - **Stated preferences / conventions** — "always…", "never…", "in this repo we…" — include these
     even as single-turn moments; drop only if step 3's dedupe check shows native ambient already
     captured them — an inconclusive check is not grounds to drop (see step 3).

3. **Filter hard (this is most of the value).** Drop a candidate if:
   - it's already in `MEMORY.md` or an existing `memory/` file — dedupe against the store at
     `~/.claude/projects/<project-dir>/memory/` (the same project directory step 1's
     `find-transcript.sh` resolves to — cwd with every `/` replaced by `-`): read `MEMORY.md` first,
     then any files it links to that look topically relevant. Match on
     *substance*, not exact wording — a candidate that restates an existing memory's meaning in
     different words is still a duplicate. This also catches what native ambient capture already
     wrote earlier in the same session. If the store can't be located or read, don't drop on that
     basis — say so explicitly and let step 4's gate decide, rather than silently assuming either
     "already captured" or "clearly new";
   - the repo already records it (code structure, git history, CLAUDE.md, an ADR) or a *deterministic,
     fail-closed* tool/platform default already enforces it (a guardrail hook that blocks the action, a
     linter rule, a CI check) — not an advisory prose instruction (a system-prompt bullet, a "please
     don't" line) that a model could still comply past. Even then, only drop the candidate if the
     default covers its full substance: the specific *why* and any narrower guidance (an approved
     alternative, an incident it's guarding against) the candidate adds on top of the default's blanket
     rule, and the default is scoped to the *project the transcript is about*, not just whatever
     tooling happens to be running this mining session. A default that's broader-but-shallower than the
     candidate doesn't make the candidate redundant — per the memory rules, save what was *non-obvious*,
     not what something else already guarantees;
   - it only mattered to this conversation (ephemeral), or it's a secret/credential;
   - it was a trivial one-off (a typo, a simple syntax slip) with no generalizable rule behind it —
     a "no, do X instead" correction is only high-signal when X *generalizes* past this one spot.

4. **Gate.** Present the surviving candidates with `AskUserQuestion` (multiSelect), ordered
   strongest-first — each option: a one-line summary + proposed `type` (user / feedback / project /
   reference) + what saving it changes next session (the consequence, not just the topic). Mark
   `(Recommended)` only when the clearly-save-worthy set is a minority of the menu; when most
   candidates survived step 3's filter (the usual case — that's what the filter is for), mark none.
   A candidate you'd tag `(Skip — …)` usually belonged in step 3's drop pile, not the menu — don't
   present options your own filter already refuted. The operator picks which to save. If none
   survive step 3, say so and stop — do not manufacture learnings.

5. **Write the approved ones** as `memory/<slug>.md` in the standard format (frontmatter with
   `name` / `description` / `metadata.type`; body; for feedback/project add **Why:** + **How to
   apply:**; link related memories with `[[name]]`). Add a one-line pointer to `MEMORY.md`. Convert
   relative dates to absolute. Follow the memory rules in the system prompt verbatim.

6. **Lint.** Run `kbg:memory-lint` to catch dangling `[[links]]`, orphans, and index drift.

## When NOT to use

- You already know the single fact to record → just write the memory file directly (or let native
  auto-memory catch it — it will, for an in-the-moment trigger).
- Harness health / self-improvement → `kbg:recursive-improve`.
- Cleaning or trimming existing memory → `kbg:memory-lint` (use `--trim` to archive bloat).
- Unprompted, mid-task → don't; this is a deliberate end-of-work reflection, operator-initiated.

## See also

- `kbg:recursive-improve` — the `kbg:harness-audit` sibling for harness health (mutation loop, flagged, human-gated), vs. this skill's operator-taught learnings.
- `kbg:memory-lint` — memory bookkeeping (with `--trim` mode) the write step relies on.
- The memory rules in the session system prompt — the authoritative format + what-to-save contract, and the source of the native auto-memory behavior this skill complements.

## Done when

The chosen learnings are saved as memory files with the operator's gate approval — verify each file is linked from MEMORY.md before stopping.
