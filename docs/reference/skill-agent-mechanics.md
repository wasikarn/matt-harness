# Skill/agent/command mechanics & routing

Reference material for skill/agent frontmatter fields, `disable-model-invocation` carriers, and a
few routing distinctions that come up when authoring or dispatching — not ambient, load on
demand. Moved out of `CLAUDE.md` 2026-08-29 (a `/mh:deep-audit`-triggered analysis found this
section pure lookup material, no "must recall before acting" urgency, same shape as the
`docs/skill-authoring-conventions.md` and `docs/agents/*.md` sections that already use a
pointer-plus-summary pattern in `CLAUDE.md`). See
`docs/research/maximizing-value-claude-code-sessions-audit-2026-08-29.md`'s fifth pass for the
full reasoning, including why 2 other candidate sections were **not** moved (a documented history
of skill-parked doctrine silently lost to resyncs/dedup sweeps in this repo).

- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions
  ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1);
  `mattpocock-skills:grilling` is the on-demand escalation for genuinely hard or
  contested-diagnosis choices. The former `decide` skill was de-scoped 2026-07-02 (0
  real-world invocations vs 55 `advisor()` calls across 182 sessions) and deleted
  2026-08-24, #79. The 39 named mental models are cataloged in
  `docs/reference/reasoning-models.md`, which points to the upstream cc-thinking-skills repo
  for full write-ups. The 42-file vendored local copy under
  `docs/reference/thinking-skills/` was removed 2026-08-24 (ticket 94, operator-only
  reference surface); the harness-audit check that guarded against re-vendoring it into
  `skills/` (formerly check 41) was deleted 2026-08-25 in ticket 87's ghost-check cleanup,
  since there's no local tree left to promote from.
- **`disable-model-invocation: true`:** carried by 10 skills (`recursive-improve`,
  `score-decision`, `ship-merge`, `ideate-search`, `tiered-pipeline`, `wiki-ingest`,
  `address-review`, `post-mortem`, `ship-release`, `compliance-audit`); no commands carry it
  any more (the command surface type is retired, its carriers converted to skills or deleted
  across #79-#112; `/mattpocock-skills:implement` covers what `ship/COMMAND.md` did).
  `compliance-audit` was deleted 2026-08-24 (#80) and restored 2026-08-25 as a skill
  alongside `agents/plan-reviewer.md` — both were judged wrongly removed on the mistaken
  premise that two other installed skills covered the same job (see the "Plan → implement" /
  "Implementation → verify" rows of `docs/reference/decision-doctrine-map.md` for which ones
  and why they don't). Re-check carriers via the frontmatter-scoped sweep (a bare
  `grep -rl` misreports: surfaces that only *mention* another one's flag in prose also
  match): `for f in skills/*/*/SKILL.md; do [ -f "$f" ] && head -20 "$f" | grep -qF
  'disable-model-invocation: true' && echo "$f"; done`. 3 of the 10 carriers are
  **CRIT**-guarded against a rewrite silently dropping the flag:
  `recursive-improve/SKILL.md` (check 36), `score-decision/SKILL.md` (check 45),
  `ship-merge/SKILL.md` (check 40); the other 7 have no equivalent guard yet. Check 30 only
  WARNs that a `-reason` field exists — it's the presence-of-reason check, not the
  flag-survives-a-rewrite check; the three CRIT checks are what close that gap.
- **Description shape for these 10 carriers.** All 10 descriptions were rewritten 2026-08-30 to a
  one-line summary — the "Use when X. Don't use for Y (Z instead)" trigger clauses moved into a
  `**When to use / not:**` body line each (`recursive-improve` already had one; the other 9 got new
  ones). This follows matt's own `writing-for-agents/SKILL-MECHANICS.md` rule that a
  `disable-model-invocation: true` skill's description becomes human-facing, trigger lists
  stripped — and the underlying fact makes it more than a style call: `code.claude.com/docs/en/skills.md`
  states plainly that the flag "removes the skill from Claude's context entirely" — a gated
  skill's description is not in the model's context at all. The old trigger-list descriptions were
  therefore inert; the model was never reading the "Don't use for X" cross-references they carried.
  This is also why mh built `hooks/advisory/compliance-audit-nudge.sh` and its sibling nudges — a
  hook is the only layer that can surface a gated skill to the model, since the description can't.
  Don't "fix" these 10 descriptions back to a trigger-list shape; that reverts a correctness fix,
  not a style preference.

<!-- The both-surface-types line caught 2026-07-22, not folded back here until 2026-08-04. -->
- **`orchestrate` vs deciding:** orchestrate decides whether and how to spend effort on an
  ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood
  as a bounded decision. A bounded question you're already committed to answering is
  reasoned through directly under METHODOLOGY Rule 1 (triad + `advisor()`,
  `mattpocock-skills:grilling` for hard/contested calls). A pile of competing asks routes
  through `orchestrate` first.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** a skill's tool-control fields are
  `allowed-tools` (pre-approves without asking, turn-scoped — clears on the next message) and
  `disallowed-tools` (a turn-scoped denylist — corrected 2026-08-29; this line previously
  claimed skills have no hard-restriction field, which is wrong). `tools:` is the separate
  `agents/*.md` subagent field (hard-restricts to a fixed set for that subagent's whole run,
  not just one turn). Confirmed against `code.claude.com/docs/en/skills`.
  `metadata` is itself a documented, spec-recognized field (a free-form YAML map) — corrected
  2026-08-29 from a prior mislabeling as kbg-native. What's actually unrecognized by the
  platform: the flat dotted-key form `metadata.origin:` (correct usage is a nested map,
  `metadata:` then an indented `origin:` — `skills/review/pr/SKILL.md` was the one skill using
  the wrong flat form, fixed the same day) and `disable-model-invocation-reason`. Unrecognized
  frontmatter keys inside Claude Code are silently tolerated (no confirmed warning, no error);
  a *separate* six-field portability allowlist (`name`, `description`, `license`,
  `compatibility`, `metadata`, `allowed-tools`) applies only when packaging a skill for the
  Skills API or a claude.ai upload — anything outside that set is a hard error there, though
  harmless inside Claude Code itself. None of this fleet's skills currently target that
  packaging path.
- **Auto-compaction skill re-attach budget (code.claude.com/docs/en/skills, verified
  2026-08-29):** when a conversation is summarized, Claude Code re-attaches the most recent
  invocation of each skill used so far, keeping the first 5,000 tokens of each, filled
  newest-invoked-first against a **combined 25,000-token budget** across all re-attached
  skills — an older-invoked skill can be dropped entirely once the budget fills. Relevant to
  this fleet's long multi-skill sessions (`orchestrate`, `deep-audit`, `recursive-improve`);
  not previously documented anywhere in this repo.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop
  (v2.1.139+, judged each turn by a separate small model). kbg never wraps or auto-invokes
  `/goal` — the user always types it themselves, no exceptions (prose-only; holds because no
  fleet surface is written to call it). `skills/goal-craft` only composes a paste-ready
  condition string (one-way-door screen + turn bound); model-invocable since 2026-07-08, but
  the string is inert until the user pastes it after `/goal`. Auto-dispatch
  (`claude -p "/goal ..."`) stays a deliberate non-goal — it reopens the retired "no model
  self-start" invariant.
