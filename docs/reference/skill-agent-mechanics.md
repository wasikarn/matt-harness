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
  match): `for f in skills/*/*/SKILL.md; do [ -f "$f" ] && [ "$(fm_get "$f"
  disable-model-invocation)" = true ] && echo "$f"; done`. **All 10 carriers are now
  CRIT-guarded** against a rewrite silently dropping the flag, one check per skill (verified
  2026-08-30): `recursive-improve/SKILL.md` (check 36), `score-decision/SKILL.md` (check 45),
  `ship-merge/SKILL.md` (check 40), `ideate-search/SKILL.md` (check 58),
  `tiered-pipeline/SKILL.md` (check 59), `wiki-ingest/SKILL.md` (check 60),
  `address-review/SKILL.md` (check 61), `post-mortem/SKILL.md` (check 62),
  `ship-release/SKILL.md` (check 63), `compliance-audit/SKILL.md` (check 64). Check 30 only
  WARNs that a `-reason` field exists — it's the presence-of-reason check, not the
  flag-survives-a-rewrite check; the ten CRIT checks are what close that gap. Check 30's own
  gate idiom was also switched from `head -20 | grep -qF` to frontmatter-scoped `fm_get` in
  the same pass, closing a latent (never live on this tree) false-negative: a stripped flag
  whose description prose still happened to contain the literal string would otherwise have
  let check 30 WARN "missing reason" on a skill that no longer carries the flag at all.
  **Superseded 2026-08-30 — history, not current state:** an earlier commit (`ed40f0db`,
  same day) had documented a partial, incidental WARN/INFO backstop for the then-7 unguarded
  carriers (checks 05/47 firing if the flag was stripped without also restoring the
  description) as a stopgap ahead of building real CRIT guards. That gap is now closed by
  checks 58-64 above; the backstop is no longer load-bearing for these 10 surfaces, but the
  finding stands as a real, verified interim result — checks 05/47 still provide the same
  incidental signal for any *future* `disable-model-invocation` carrier that hasn't yet
  gotten its own dedicated CRIT check. **Two follow-ups from the same-day deep-audit on this
  commit:** checks 36 and 45 were missing the `else` branch (fires CRIT if the SKILL.md itself
  is missing/renamed) that checks 40/58-64 all carry — fixed, verified live by renaming both
  files in a scratch copy and confirming CRIT fires. And check 65 (new) closes the structural
  gap the hardcoded-per-skill pattern otherwise reopens on its own: an 11th
  `disable-model-invocation: true` carrier added after this doc was written gets no dedicated
  guard until a human notices — check 65 WARNs whenever a carrier's path has no matching `_f=`
  line anywhere under `checks/`, so that gap surfaces instead of silently recurring. WARN, not
  CRIT: it flags a coverage gap in the audit system, not proof the flag is currently absent.
- **Description shape for these 10 carriers.** All 10 descriptions were rewritten 2026-08-30 to a
  one-line summary — the "Use when X. Don't use for Y (Z instead)" trigger clauses moved into a
  `**When to use / not:**` body line each (`recursive-improve` already had one; the other 9 got new
  ones). This follows matt's own `writing-for-agents/SKILL-MECHANICS.md` rule that a
  `disable-model-invocation: true` skill's description becomes human-facing, trigger lists
  stripped — and the underlying fact makes it more than a style call: `code.claude.com/docs/en/skills.md`
  states plainly that the flag "removes the skill from Claude's context entirely" — a gated
  skill's description is not in the model's context at all. The old trigger-list descriptions were
  therefore inert; the model was never reading the "Don't use for X" cross-references they carried.
  This is also why mh built `hooks/advisory/compliance-audit-nudge.sh` — a hook is the only layer
  that can surface a gated skill to the model, since the description can't. **Correction
  2026-08-31:** this doc previously said "and its sibling nudges" — false. Verified: exactly one
  such hook exists, hardcoded to `/mh:compliance-audit` only. The other 9 carriers (`ship-merge`,
  `recursive-improve`, `ideate-search`, `score-decision`, `tiered-pipeline`, `wiki-ingest`,
  `address-review`, `post-mortem`, `ship-release`) have zero nudge coverage — per the mechanism
  above, the model has no path to ever proactively suggest them. Real gap, not (yet) fixed; note
  it here so a future pass doesn't assume coverage exists because this doc once implied it did.
  Don't "fix" these 10 descriptions back to a trigger-list shape; that reverts a correctness fix,
  not a style preference.
- **`user-invocable: false` — the documented pair to `disable-model-invocation`.** Official
  semantics: only Claude can invoke the skill; Claude Code hides it from the `/` menu and won't
  run it on `/name`, but its description stays in Claude's context and preload is unaffected
  (`code.claude.com/docs/en/skills`, "Control who invokes a skill" + frontmatter reference,
  verified 2026-08-31). The settings-only equivalent is `skillOverrides: {"<name>":
  "user-invocable-only"}`, for gating a skill you don't want to edit (e.g. one checked into a
  shared repo you don't own). Applied 2026-08-31 to this fleet's 8 pure agent-preload catalogs
  (`performance-optimizer-algorithms`, `plan-reviewer-format`, `requirement-analyst-format`,
  `spec-miner-anti-patterns`, `summarizer-format`, `blind-spot-hunter-shapes`,
  `review-lens-nextjs-routing`, `security-reviewer-patterns`) — each one's own description already
  read "Auto-loads when `<agent>` runs," the docs' exact stated use case for the field.
  **Tamper-guard parity:** unlike `disable-model-invocation`'s 10 carriers (checks 30/36/40/45/58-65
  above), these 8 had zero protection against a future edit silently dropping the flag until check
  66 (`66-user-invocable-carrier-tamper-guard.sh`, added 2026-08-31, WARN tier — lower stakes than
  the CRIT carriers since dropping this flag just un-hides a catalog skill, it doesn't remove a
  safety block) closed the gap: one check covering all 8 known carriers plus a self-extending
  second pass that flags any *new* `user-invocable: false` skill not yet in its known-carrier list.
  **Historical note:** an earlier cleanup (`CHANGELOG.md:11447`) stripped `user-invocable: false`
  from two now-deleted skills as an "unofficial frontmatter field... not in the vendor schema" —
  it's actually official; that entry misclassified it alongside 4 other genuinely-official fields
  (`context: fork`, `agent:`, `license:`, `compatibility:`). Don't repeat that mistake if any of
  those five show up again.
- **`disable-model-invocation: true` has two side effects beyond blocking the Skill-tool call**,
  neither previously documented here: it also prevents the skill from being preloaded into
  subagents via their `skills:` frontmatter, and (as of Claude Code v2.1.196) prevents it from
  running when a scheduled task fires with the skill as its prompt. No agent in this fleet
  currently lists a gated skill under `skills:` (verified 2026-08-31), so this is a
  forward-looking constraint, not a live bug — check before ever adding one.
- **`skills/review/pr` is a deliberate non-carrier of `disable-model-invocation`**, despite doing
  a real `git push` + creating a GitHub PR. Its own body calls itself "an unflagged external-write
  surface" and relies on the Phase-4 preview-confirm gate instead. Reasoned tradeoff, confirmed
  2026-08-31: gating would strip its description from Claude's context entirely (per the flag's
  actual mechanism, above), killing the "open a PR / เปิด PR" conversational trigger — for an
  action that's reversible (an open PR can be closed) and already confirm-gated. Don't add the
  flag here without re-litigating that tradeoff first.
- **`skills/workflow/incident` and `skills/review/deep-audit`** follow the same unflagged-but-gated
  pattern as `pr`, for the same reason (both are meant to trigger on natural-language phrasing —
  "alerts fire", "audit what we just built" — so removing their description from context would
  break that). `incident` already had its own AskUserQuestion confirm before irreversible
  mitigation (step 3, self-consistency skip only for an already-confirmed-expanding blast radius);
  `deep-audit` didn't — verified 2026-08-31 it applied fixes directly with zero confirm step
  anywhere in 121 lines — so it got one added (step 5, mirrors `incident`'s skip-only-on-explicit-
  same-turn-authorization shape) rather than gaining `disable-model-invocation`, consistent with
  the `pr` precedent above.
- **Agents have no frontmatter-level counterpart to `disable-model-invocation`/`user-invocable`.**
  `agents/*.md`'s `tools:` field hard-restricts what a dispatched agent may call during its run —
  it says nothing about whether the agent may be auto-dispatched in the first place. Nothing in
  the Skills docs' invocation-control sections covers this, and no equivalent field exists on the
  agents surface. Platform limitation, not a repo gap — recorded so it isn't re-discovered.

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
  the wrong flat form, fixed the same day), `disable-model-invocation-reason`, and
  `model_limitation` (used once, `tech-humanize/SKILL.md`). Unrecognized
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
