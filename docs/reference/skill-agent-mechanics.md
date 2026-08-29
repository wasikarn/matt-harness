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

<!-- The both-surface-types line caught 2026-07-22, not folded back here until 2026-08-04. -->
- **`orchestrate` vs deciding:** orchestrate decides whether and how to spend effort on an
  ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood
  as a bounded decision. A bounded question you're already committed to answering is
  reasoned through directly under METHODOLOGY Rule 1 (triad + `advisor()`,
  `mattpocock-skills:grilling` for hard/contested calls). A pile of competing asks routes
  through `orchestrate` first.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool
  control is `allowed-tools` (pre-approves without asking; skills have no hard-restriction
  field), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed
  set). Confirmed against the official `skills.md` reference and the CLI binary's compiled
  schema keys. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are
  non-standard-but-harmless kbg conventions: unrecognized frontmatter keys warn, never
  error, and carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop
  (v2.1.139+, judged each turn by a separate small model). kbg never wraps or auto-invokes
  `/goal` — the user always types it themselves, no exceptions (prose-only; holds because no
  fleet surface is written to call it). `skills/goal-craft` only composes a paste-ready
  condition string (one-way-door screen + turn bound); model-invocable since 2026-07-08, but
  the string is inert until the user pastes it after `/goal`. Auto-dispatch
  (`claude -p "/goal ..."`) stays a deliberate non-goal — it reopens the retired "no model
  self-start" invariant.
