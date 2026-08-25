# review-fixtures — incident record behind the rules

Moved verbatim out of the skill's main file (2026-08-23, 200-LOC cap refactor; that file was
COMMAND.md until review-fixtures converted to a skill, 2026-08-24). Each section is the
evidence behind a rule that stays stated at its point of use in SKILL.md.

## Why the Step 3.5 reconciliation check exists

Fresh reviewers on an already-reconciled workspace burn two dispatches re-deriving a recorded
verdict, with no way to tell after the fact whether the second pass found anything new.
Confirmed once (`mh:plan-reviewer`, 2026-07-27) — a second pass re-derived a conclusion
`feedback.json` already had, caught only because `git diff` came back empty.

## Why eval prompts must be quoted verbatim (Step 6)

A reviewer can't tell your compressed restatement from the real thing, and will read any
qualifying phrase your paraphrase dropped as evidence the with-run output invented something —
a "fabrication" finding that looks double-confirmed when two reviewers converge on it, but is
really one shared blind spot (your paraphrase) counted twice. Confirmed the hard way on
`score-decision` (v0.68.93): both reviewers independently flagged the same 3 "invented"
details, and none held up once checked against the actual dispatch text — every one traced to
a fact genuinely given, just dropped from the compressed prompt.

## Why dispatch-prompts.md must be persisted (Step 6)

`<iteration-path>/dispatch-prompts.md` is the only record of what an agent actually received —
`feedback.json`'s reconciled paragraph is a summary written after the fact, and a
fixture-data-inlined prompt (raw doc-reasoning scenarios, not with_skill/baseline critique) can
run to thousands of words with no other copy. Gitignored and local-only like the rest of
`<name>-workspace/` — won't survive a machine loss, but does survive context compaction, which
has actually bitten twice (code-implementer 2026-07-25, `ship-merge` 2026-07-28 — both
recoverable only by grepping the raw transcript, not guaranteed to still exist).

## The stale-cache re-test trap (Step 8)

When re-running fixtures after a fix, a name-based reference (`Skill(<name>)`,
`subagent_type: <name>`, or the slash command) silently serves the stale cached copy until a
version bump + plugin reinstall happens — same gotcha as CLAUDE.md's "Plugin lifecycle &
install" section (confirmed tech-humanize v0.68.59). `Read` the repo file path directly
instead.
