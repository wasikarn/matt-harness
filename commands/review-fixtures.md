---
name: review-fixtures
description: "Dispatch 2 independent staff-eng agents to adversarially review skill-creator-style fixture outputs (with_skill vs baseline) for a skill, agent, or command before deciding a fix. Use mid an improve+optimize loop once fixtures exist. Don't use for PR review (kbg:code-reviewer) or skill-creator's own quantitative grading/benchmark step."
argument-hint: <skill/agent/command-name> [iteration-path]
model: inherit
effort: high
---

# /review-fixtures — 2-agent independent fixture review

Runs the qualitative review step of a `skill-creator:skill-creator`-style improve+optimize
loop with 2 independent agents instead of a single solo read. Refines that skill's own Step 4
("grade, aggregate, launch the viewer") — doesn't replace grading or the benchmark step, just
replaces *solo eyeballing of the fixture outputs* with an adversarial 2-agent pass whose
convergence and disagreement both carry signal.

**Not skill-only.** The `<name>-workspace/iteration-N/eval-*/` layout is surface-agnostic in
this fleet's practice — used for a Skill, an Agent, and a Command alike. This command
resolves which of the three the target is (Step 1). Naming conventions inside the layout
pair by build path, not by choice: `skill-creator`-built Skill loops produce `with_skill/` +
`no_skill|without_skill|old_skill/` + `eval_metadata.json`; ad-hoc Agent loops instead
produce `with_agent/` + `baseline/` + `prompt.md` (often a pre-written `review.md`). Step 3
tolerates both — don't assume Skill-side names apply to an Agent or Command target.

## Steps

### 0. Read the reference doc first

**Why 2 agents, not 1**, and the exact prompt skeleton this command fills in: read
`${KBG_PLUGIN_ROOT}/docs/reference/skill-fixture-review-prompt-template.md` before Step 5.
That file is the single source of truth for the prompt text, the fixture-construction hygiene
checklist, and the 5 instructions that must not be cut — this command only orchestrates
around it.

### 1. Parse arguments and resolve the target surface

`$1` = skill/agent/command name (strip a leading `kbg:` if present). `$2` = optional iteration path.

**Via the `Skill` tool's `args` param (not a typed slash command), `$2` may not populate** —
a whitespace-containing `args` string can bind wholly to `$1` (confirmed on `deep-audit`,
2026-08-09: `args: "deep-audit deep-audit-workspace/iteration-2"` left `$2` empty). If `$1`
has whitespace, split on the first space: target name, then `$2`. This is a fallback only —
Step 2's auto-glob-highest-N already covers the common no-path case.

If `$1` is empty, show usage and stop — do not guess which target:
```
Usage: /review-fixtures <skill/agent/command-name> [iteration-path]
Example: /review-fixtures backend-patterns
Example: /review-fixtures backend-patterns backend-patterns-workspace/iteration-2
```

Resolve which surface `$1` is by checking, in order: `skills/$1/SKILL.md`, `agents/$1.md`,
`commands/$1.md`. Whichever exists is the **target file** referenced in Steps 4 and 8. None
exist → stop and report that, don't guess a path or default to skill. Steps 2–3's
workspace/eval-case discovery don't need this resolution — the `<name>-workspace/` and
`eval-*/` conventions are identical across all three surface types.

### 2. Locate the workspace

Workspace root is `<skill-name>-workspace/` relative to the repo root (where `skill-creator`
writes fixtures — a dev-workspace sibling of `skills/<skill-name>/`, not inside the installed
plugin, so don't resolve it from `${KBG_PLUGIN_ROOT}`).

- If `$2` was given, use it as the iteration path directly.
- Otherwise glob `iteration-*` under the workspace root and pick the highest N.
- If the workspace root doesn't exist: stop and tell the user to run
  `skill-creator:skill-creator`'s fixture-generation steps (1–4) first — this command
  reviews fixtures that already exist, it does not generate them.

### 3. Discover eval cases

For each `eval-*/` directory under the iteration path:

- Get the original task prompt and any `assertions`, checking sources in this order:
  `eval_metadata.json` (`prompt` + `assertions` — the Skill-loop convention); a bare
  `prompt.md` in the eval directory (seen in Agent-loop workspaces, e.g.
  `plan-reviewer-workspace`); an iteration-level shared `prompts.md` one level up at
  `<iteration-path>/prompts.md` (NOT inside the eval directory — used across all evals in an
  iteration in several Agent-loop workspaces here; look up the matching entry); then, only
  if none exist, a task description in an existing `review.md`'s opening section — treat this
  as a paraphrase, not the verbatim prompt, and say so if used. If none of the four exist, or
  assertions are empty/absent, note that as a gap rather than inventing one — the reviewers
  can still do a general-quality pass, just without assertion-level scoring. Not a stop
  condition (see below).
- Find the with-run subdirectory and the baseline sibling, checking names in this order —
  don't assume either pair applies to a target type it wasn't observed on: with-run —
  `with_skill/`, `with_agent/`, `with_command/`; baseline — `no_skill/`, `without_skill/`,
  `old_skill/`, `baseline/`. Use whichever pair is present. Exactly one subdirectory that
  isn't a recognized baseline name → treat it as the with-run directory rather than failing
  outright.
- Determine the output shape per config directory: a single `outputs/implementation.md`; a
  full `outputs/` directory with multiple files plus `SUMMARY.md`; or — most common for
  Agent-target loops here — a flat `output.md` directly inside the with-run/baseline
  directory, no `outputs/` wrapper. List whatever's actually there.

If no `eval-*/` directories are found, stop and report that — don't guess eval names. A
missing `eval_metadata.json`/`prompt.md`/`review.md` on an otherwise-valid eval directory is
not a stop condition — proceed with the general-quality pass above, and flag the missing
prompt context in the dispatched prompts and Step 8's report.

### 3.5. Check for an existing reconciliation

Before generating anything new, check whether `<iteration-path>/feedback.json` already
exists. If it doesn't, skip straight to Step 4 — this is the common case and needs no
special handling.

If it does exist, read it, then tell the user plainly: a reconciliation already ran (name
the evals and, if visible from the file or a quick `git log`, roughly when), and ask how to
proceed rather than silently redoing or skipping the work:
- **Scope to the gap** — if the existing file only covers some evals, or a fix landed since
  (check via Step 4's `git log`), dispatch fresh reviewers only for what's uncovered, with
  Step 5's differentiation angle aimed at what the prior pass missed.
- **Re-run anyway** — right after applying a fix, to measure whether it held; say so when
  this is the reason.
- **Treat the existing file as current** — if nothing's changed since, report its findings
  back instead of re-dispatching, and stop here.

**Why this matters:** fresh reviewers on an already-reconciled workspace burn two dispatches
re-deriving a recorded verdict, with no way to tell after the fact whether the second pass
found anything new. Confirmed once (`plan-reviewer`, 2026-07-27) — a second pass re-derived
a conclusion `feedback.json` already had, caught only because `git diff` came back empty.

### 4. Best-effort prior-fix context

Run `git log --oneline -- <target file resolved in Step 1>` filtered to commits after the
workspace's mtime. Fix commits are worth telling reviewers about (so they don't re-flag
something already closed, or misattribute a fixture-only bug as a live gap). Nothing found →
omit the context rather than padding the prompt.

### 5. Pick agent 2's differentiation angle

Read the eval prompts from Step 3 — or, if an eval had no prompt source, skim its
with-run/baseline `output.md` files to infer the domain — and name ONE concrete failure mode
plausible for this domain but easy for a single reviewer to skim past: concurrency/race
conditions for anything concurrent or multi-replica, injection/boundary handling for user
input, accessibility/memoization/stale-closures for UI, N+1/index cases for DB-facing code,
atomicity for read-then-write. State the pick and the one-line reason — a silent pick is how
you end up with two copies of the same prompt instead of complementary coverage.

### 6. Fill, persist, and dispatch both agents

Using the template from the reference doc (Step 0): fill in the target name, domain
description, file list (from Step 3), eval prompts, assertions, prior-fix context (Step 4,
or omit), and the agent-2-only differentiation line (Step 5).

**Quote eval prompts verbatim from their true source — never paraphrase or summarize.** True
source = whichever of `eval_metadata.json`, `prompt.md`, or the iteration-level `prompts.md`
Step 3 found, or (if none exist) the literal text of the original `Agent` tool call that
dispatched the fixture-generation agent. A reviewer can't tell your compressed restatement
from the real thing, and will read any qualifying phrase your paraphrase dropped as evidence
the with-run output invented something — a "fabrication" finding that looks
double-confirmed when two reviewers converge on it, but is really one shared blind spot
(your paraphrase) counted twice. Confirmed the hard way on `score-decision` (v0.68.93): both
reviewers independently flagged the same 3 "invented" details, and none held up once checked
against the actual dispatch text — every one traced to a fact genuinely given, just dropped
from the compressed prompt. If the true source is long, quote the relevant portion in full —
a shortened-but-verbatim excerpt is fine; a reworded one is not.

**Before dispatching, write both composed prompts verbatim to
`<iteration-path>/dispatch-prompts.md`** (one labeled section per agent, plus today's date).
This is the only record of what an agent actually received — `feedback.json`'s reconciled
paragraph is a summary written after the fact, and a fixture-data-inlined prompt (raw
doc-reasoning scenarios, not with_skill/baseline critique) can run to thousands of words with
no other copy. Gitignored and local-only like the rest of `<name>-workspace/` — won't survive
a machine loss, but does survive context compaction, which has actually bitten twice
(code-implementer 2026-07-25, `ship-merge` 2026-07-28 — both recoverable only by grepping the
raw transcript, not guaranteed to still exist). If a later run reuses an unchanged prompt,
append a dated section noting it's unchanged from `<that date>` — don't re-paste, don't skip
the note.

Dispatch both as `Agent` tool calls with `subagent_type: general-purpose` (needs
Read/Grep/Glob/Bash — Bash for the "verify empirically" instruction, e.g. a quick Node
snippet to check a numeric/timing claim) **in the same message**, so they run independently
with no shared context. Separate turns defeat the point of independent review. Each copy
carries its own PRIMARY-lens line per the reference template — two identical prompts to
two same-family agents is one reviewer counted twice, not two.

### 7. Reconcile

Once both return, follow the reference doc's "After both agents return" section:

- Both agents hit it independently *via different routes/lenses* → high confidence it's
  real; a same-route double-hit is one signal counted twice (same-family reviewers
  correlate — see the reference doc's correlation caveat). Still separate "the bug exists"
  from "here's why the target caused it."
- Only one agent hit it → record it, single-sourced.
- Before crediting anything to the target, grep the *current* target file (Step 1) for the
  relevant example/rule. No trace found → fixture artifact, not a real gap.

For each target-attributable finding (survived the grep-trace check above — fixture-only
artifacts never count here), tag a severity: **critical** = wrong or unsafe result for a real
user (a bug, missed assertion, fabricated claim); **major** = a real guidance gap that
degrades quality without a wrong result (missing edge case, unclear guidance the model
improvises badly on); **minor** = stylistic, current text isn't wrong. Different scale from
`harness-audit`'s CRIT/WARN/INFO — same repo, different axis — don't conflate the two.

Write the reconciled findings to `<iteration-path>/feedback.json` in this shape (matches
`skill-creator`'s own eval-viewer feedback file, so it drops into the same place in the loop;
`target_attributable` is additive on top of that shape — existing consumers reading
`feedback`/`run_id`/`timestamp`/`status` are unaffected):

```json
{
  "reviews": [
    {"run_id": "<eval-name>-<config>", "feedback": "<reconciled paragraph>", "timestamp": "<today, ISO date>",
     "target_attributable": {"critical": 0, "major": 0, "minor": 0}}
  ],
  "status": "complete"
}
```

### 8. Report

Summarize to the user: which findings are target-attributable (traced to a specific clause in
the resolved target file) vs fixture-only, and single-sourced vs double-confirmed. If any
eval in Step 3 had no prompt source (no `eval_metadata.json`/`prompt.md`/`review.md`), say so
— those findings rest on inferred context, not a stated task, and warrant more skepticism.
Don't edit the target file as part of this command — that's a separate user decision, not an
automatic next step. Confirm `<iteration-path>/dispatch-prompts.md` was actually written
(Step 6) before reporting done — a skipped save is a silent loss of the only reproducible
record of what the reviewers saw.

Suggested next step:
- Findings trace to the target file → open it (Step 1's resolved path), apply the fix, then
  re-run fixtures to measure the change (don't ship an unmeasured fix as proven). **When
  re-running, don't hand the re-verification agent a name-based reference**
  (`Skill(<name>)`, `subagent_type: <name>`, or the slash command) — same stale-cache gotcha
  as CLAUDE.md's "Plugin lifecycle & install" section (confirmed tech-humanize v0.68.59):
  `Read` the repo file path directly instead.
- Nothing traces to the target → say so plainly. A clean reconciliation is a valid result.
