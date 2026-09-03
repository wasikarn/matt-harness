# Autonomy posture (load-bearing)

Moved verbatim from `SKILL.md` (progressive disclosure). Read before the first `AskUserQuestion`
gate of a session, or whenever a candidate looks like something native auto-memory should have
caught — the bullets below say what this skill adds over the ambient path and why it carries no
`disable-model-invocation` flag.

- **Not the primary writer — Claude Code's native auto-memory is.** Since ~CLI v2.1.59, Claude
  Code ships an ambient, always-on memory feature (`autoMemoryEnabled`, `/memory`): the model
  saves memory files directly, no per-write confirmation, whenever an in-the-moment trigger fires
  (a correction just happened, a preference was stated). That's the same store, same format, same
  `MEMORY.md` index this skill writes to (`code.claude.com/docs/en/memory`); in this repo's own
  store the native path accounts for the large majority of writes.
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
