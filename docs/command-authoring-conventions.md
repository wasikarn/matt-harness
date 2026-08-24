# Command authoring conventions

**Status:** Convention reference. Owned by the harness. Sibling of
[`agent-authoring-conventions.md`](./agent-authoring-conventions.md).

**Origin:** a deep-research critique of `commands/` (2026-07-20) confirmed the fleet's
17 command surfaces converge on sound content/workflow design (flat-file-by-default,
`disable-model-invocation` for irreversible actions, fresh-context verifiers), but found
one real defect no doctrine had ever named: `commands/`'s directory-form loader doesn't
distinguish a command's own entrypoint from its private reference files. The only prior
guidance (`skills/add-surface/SKILL.md`) said "follow the pattern of an existing
component in the same directory" — which is exactly how the defect spread from `ship` to
`ideate`. This doc is what the fleet actually needs to get right, made explicit.

The question this doc answers: **what does a new command in this fleet need to get
right, and why?**

## 1. Flat file by default

A `commands/<name>.md` file is functionally identical to a skill for a single-workflow
surface — Anthropic's own docs confirm a command file and a `skills/<name>/SKILL.md`
"both create `/name` and work the same way" (see
`[[command-vs-skill-equivalence-2026-07-07]]` memory). `allowed-tools` and natural-language
auto-invocation both work on a plain command file. Don't reach for a directory, a bundled
`references/` folder, or a skill conversion "to get NL invocation" or "to get
`allowed-tools`" — a flat file already has both.

**Why:** most commands in this fleet are flat files and need nothing more. A
directory only earns its cost when the content genuinely doesn't fit in one file.

## 2. Directory-form is real, but rare — and has one hard rule

`commands/<name>/COMMAND.md` + a `references/` subfolder is a recognized Claude Code
loader category — `getSkills` reports a distinct `N skill dir commands` bucket separate
from flat plugin skills (confirmed via a live `--debug-file` capture). Several commands
use it today (e.g. `ideate`, `ship-merge`), each because its procedure outgrew a single
file's reasonable token budget (the same size concern documented elsewhere for
`SKILL.md` bodies).

**The rule this doc exists to state:** any `.md` file under `commands/` — at any depth —
that carries its own YAML frontmatter with a `description:` becomes an independently
loadable command, regardless of directory nesting or author intent. This was confirmed
directly: two files that lived in the now-removed `commands/ship/references/`
directory (`classify.md` and `pre-ship-verify.md`; `ship` was retired in the
2026-08-24 matt-harness migration, ticket #86) both had `name:`/`description:`
frontmatter and were loaded as standalone commands (`ship-classify`, `pre-ship-verify`)
even though `ship/COMMAND.md` only ever read them by file path. `commands/ideate/
references/frames.md` carries no frontmatter and correctly does **not** leak.

**A `references/` file must never carry a `--- ... ---` frontmatter block.** Point to
`frames.md` as the correct shape: a plain heading, prose, and tables — nothing else.
`harness-audit` check 46 enforces this mechanically (WARN on any offending file).

**Why:** the loader has no concept of "this file is private support material" — frontmatter
presence is the only signal it uses to decide what's independently invocable. Encapsulation
has to be enforced by the author (no frontmatter), not assumed from directory position.

## 3. `disable-model-invocation` for irreversible or external-effect actions

Set `disable-model-invocation: true` + a non-empty `disable-model-invocation-reason:` on
any command whose effect is hard to reverse or reaches outside the repo — merging a PR,
cutting a release, posting to GitHub/Jira, spawning a costly multi-agent fan-out that
gates a done-declaration. Several commands already do this
(`ship-merge`, `ship-release`, `post-mortem`, `address-review`,
`ideate-search`). `harness-audit` checks 30
(reason presence, WARN) and 44 (`ship-merge` specifically, CRIT) enforce this.

**Why:** this is the only mechanism blocking the model from self-invoking a real,
irreversible external action — a human must type the literal `/name` themselves. It
matches the same confirm-before-destructive-step convention Anthropic's own guidance and
other agentic tools (Cursor, Windsurf) converge on.

## 4. Frontmatter fields — what's actually functional

Confirmed recognized and functional (per the unified skills/commands frontmatter schema at
`code.claude.com/docs/en/skills`): `name`, `description`, `argument-hint`,
`disable-model-invocation`, `allowed-tools`, `model`,
`agent` (only meaningful when paired with `context: fork` — setting `agent:` alone, without
`context: fork`, does nothing at the schema level; any delegation you see happening is
carried entirely by the command's prose telling the model to invoke that agent).
`disable-model-invocation-reason` is **not** part of that schema — it's a non-standard-but-harmless
kbg convention that Claude Code tolerates as unrecognized frontmatter, same as CLAUDE.md's own
"Skill/agent/command mechanics" note says. Keep using it for the documentation value, but don't
call it "recognized and functional" the way the schema-backed fields above are.

**Do not add `subtask:`** — it does not appear in Anthropic's documented command-frontmatter
schema and is very likely inert (an ECC-port artifact). `metadata:` (freeform, e.g.
`origin:`/`ecc_commit:`) is tolerated but non-standard — fine for provenance notes, never
load-bearing.

**Why:** a frontmatter field nobody reads is a false signal to the next editor — this repo
has already caught and retired exactly this class of dead field once (`harness-audit`
check 06's retired `type: command`).

## 5. Grow on proven need, not speculatively

Before adding a new command, check whether an existing one already covers the task, and
whether the task is better served as a skill (bundled scripts/reference files/`paths:`
scoping — see §2 above for when that's actually warranted) or an agent (a specialist a
command delegates to, per `agent-authoring-conventions.md`).

**Why:** Rule 2 (CLAUDE.md) — the same discipline that merged the former `/ship-task` and `kbg:ship-change` surfaces into one `/ship` once the two-surfaces-for-one-tail problem was named, rather than letting the fleet carry both indefinitely. (`/ship` itself was later retired in the 2026-08-24 matt-harness migration, ticket #86, once `/mattpocock-skills:implement` covered the same job — the principle the merge illustrates outlived the surface.)

## When authoring a new command — quick checklist

1. Default to a flat `commands/<name>.md` file. Reach for a directory only if the
   procedure genuinely won't fit one file.
2. If directory-form: **no frontmatter in any `references/` file** — plain heading only.
3. Set `disable-model-invocation` + a reason if the effect is irreversible or external.
4. Use only the confirmed-functional frontmatter fields (§4). Don't carry `subtask:` or
   an unpaired `agent:` into a new command.
5. Run `bash skills/harness-audit/scripts/audit.sh` — checks 06 (frontmatter
   completeness), 20 (description length + duplicate-surface), 30 (disable-model-invocation
   reason), 46 (reference-file frontmatter leak) all touch new commands directly.
6. Bump `.claude-plugin/plugin.json` + `marketplace.json` per root `CLAUDE.md`
   § "Adding or removing a surface".

## Cross-references

- `[[command-vs-skill-equivalence-2026-07-07]]` memory — the equivalence claim in full,
  verified against `code.claude.com/docs` and `anthropics/claude-plugins-official`.
- [`agent-authoring-conventions.md`](./agent-authoring-conventions.md) — the same kind of
  doc for `agents/`; several principles here (grow on proven need, dead-field hygiene)
  mirror it directly.
- Root `CLAUDE.md` § "Adding or removing a surface" — the mechanical add/remove/bump
  procedure for any auto-discovered surface, commands included (inlined there when the
  `add-surface` skill was removed, 2026-08-24 #80).
- `skills/harness-audit/scripts/checks/` — 06, 20, 30, 44, 46 are the mechanical checks
  over this doc's §2–§4. As with the agent doc, there is deliberately no structural
  body-regex check (heading presence, phase-count, etc.) — that class was tried for
  skills and retired after a 5/5 false-positive rate; this doc is prose guidance for the
  parts that aren't already mechanically checked.
