---
name: review-fixtures
description: "Dispatch 2 independent staff-eng agents to adversarially review skill-creator-style fixture outputs (with_skill vs baseline) for a skill, agent, or command before deciding a fix. Use mid an improve+optimize loop once fixtures exist. Don't use for PR review (kbg:code-reviewer) or skill-creator's own quantitative grading/benchmark step."
argument-hint: <skill/agent/command-name> [iteration-path]
---

# /review-fixtures — 2-agent independent fixture review

Runs the qualitative review step of a `skill-creator:skill-creator`-style improve+optimize
loop with 2 independent agents instead of a single solo read. This is a refinement of that
skill's own Step 4 ("grade, aggregate, launch the viewer") — it doesn't replace grading or
the benchmark step, it replaces *solo eyeballing of the fixture outputs* with an
adversarial 2-agent pass whose convergence and disagreement both carry signal.

**Not skill-only.** The `<name>-workspace/iteration-N/eval-*/` layout itself is already
surface-agnostic in this fleet's own practice — used for a Skill (`backend-patterns`,
`frontend-patterns`, `tech-humanize`), an Agent (`silent-failure-hunter`, `blind-spot-hunter`,
`code-reviewer`, `plan-reviewer`, `summarizer`, `requirement-analyst`), and a Command
(`ship-merge`) alike. This command just needs to resolve which of the three the target
actually is — see Step 1. **The two conventions inside that layout differ, though**: Skill
loops built via `skill-creator`'s own spawn template consistently produce `with_skill/` +
`no_skill|without_skill|old_skill/` + `eval_metadata.json`; every Agent-target loop run ad hoc
in this repo instead produces `with_agent/` + `baseline/`, a per-eval `prompt.md` in place of
`eval_metadata.json`, and often a pre-written `review.md`. Step 3 below has to tolerate both —
don't assume the Skill-side names apply to an Agent or Command target.

**Why 2 agents, not 1**, and the exact prompt skeleton this command fills in: read
`${KBG_PLUGIN_ROOT}/docs/reference/skill-fixture-review-prompt-template.md` before Step 5
below. That file is the single source of truth for the prompt text, the fixture-construction
hygiene checklist, and the 4 instructions that must not be cut — this command only
orchestrates around it.

## Steps

### 1. Parse arguments and resolve the target surface

`$1` = skill/agent/command name (strip a leading `kbg:` if present). `$2` = optional iteration path.

If `$1` is empty, show usage and stop — do not guess which target:
```
Usage: /review-fixtures <skill/agent/command-name> [iteration-path]
Example: /review-fixtures backend-patterns
Example: /review-fixtures backend-patterns backend-patterns-workspace/iteration-2
```

Resolve which surface `$1` actually is by checking, in this order: `skills/$1/SKILL.md`,
`agents/$1.md`, `commands/$1.md`. Whichever exists is the **target file** referenced in
Steps 4 and 8 below. If none of the three exist, stop and report exactly that — don't guess
a path or default to assuming it's a skill. Steps 2–3's workspace/eval-case discovery don't
need this resolution at all — the `<name>-workspace/` and `eval-*/` conventions are already
identical across all three surface types.

### 2. Locate the workspace

Workspace root is `<skill-name>-workspace/` relative to the current repo root (this is
where `skill-creator` writes fixtures — it is a dev-workspace sibling of `skills/<skill-name>/`,
not inside the installed plugin, so don't resolve it from `${KBG_PLUGIN_ROOT}`).

- If `$2` was given, use it as the iteration path directly.
- Otherwise glob `iteration-*` under the workspace root and pick the highest N.
- If the workspace root doesn't exist at all: stop and tell the user to run
  `skill-creator:skill-creator`'s fixture-generation steps (1–4) first. This command
  reviews fixtures that already exist — it does not generate them.

### 3. Discover eval cases

For each `eval-*/` directory under the iteration path:

- Get the original task prompt and any `assertions`, checking sources in this order:
  `eval_metadata.json` (`prompt` + `assertions` fields — the Skill-loop convention); a bare
  `prompt.md` file in the eval directory (seen in Agent-loop workspaces like
  `plan-reviewer-workspace`/`requirement-analyst-workspace`); an iteration-level shared
  `prompts.md` sitting one level up at `<iteration-path>/prompts.md` (NOT inside the eval
  directory — used across all evals in that iteration in `silent-failure-hunter-workspace`,
  `blind-spot-hunter-workspace`, `code-reviewer-workspace`, `summarizer-workspace`,
  `typescript-reviewer-workspace`, and `code-implementer-workspace`; look up the entry
  matching this eval's name inside it); then, only if none of those exist, a task
  description embedded in an existing `review.md`'s opening section — treat this last source
  as a paraphrase, not the verbatim original prompt, and say so if you use it. If none of the
  four exist, or assertions specifically are empty/absent, note that as a gap rather than
  inventing one — the reviewers can still do a general-quality pass, just without
  assertion-level scoring. A missing prompt source is a gap to note, not a reason to stop the
  whole command (see below).
- Find the with-run subdirectory and the baseline sibling, checking names in this order —
  don't assume either pair applies to a target type it wasn't observed on: with-run —
  `with_skill/`, `with_agent/`, `with_command/`; baseline — `no_skill/`, `without_skill/`,
  `old_skill/`, `baseline/`. Use whichever pair is present. If the eval directory has exactly
  one subdirectory that isn't a recognized baseline name, treat that as the with-run
  directory even if its name doesn't match the list above, rather than failing outright.
- Determine the output shape per config directory: a single `outputs/implementation.md`; a
  full `outputs/` directory with multiple files plus a `SUMMARY.md`; or — the most common
  shape for Agent-target loops in this repo — a flat `output.md` directly inside the
  with-run/baseline directory, no `outputs/` wrapper at all. List whatever's actually there.

If no `eval-*/` directories are found at all, stop and report exactly that — don't guess eval
names. A missing `eval_metadata.json`/`prompt.md`/`review.md` on an otherwise-valid eval
directory is not itself a stop condition — proceed with the general-quality pass noted above
and flag the missing prompt context in the dispatched agents' prompts and in Step 8's report.

### 3.5. Check for an existing reconciliation

Before generating anything new, check whether `<iteration-path>/feedback.json` already
exists. If it doesn't, skip straight to Step 4 — this is the common case and needs no
special handling.

If it does exist, read it. Then tell the user plainly: a reconciliation already ran against
this workspace (name the eval names and, if visible from the file's own content or a quick
`git log` check, roughly when), and ask how to proceed rather than silently either re-doing
the work or silently skipping it:
- **Scope to the gap** — if the existing file only covers some evals, or a fix landed since
  it was written (check via Step 4's `git log`), dispatch fresh reviewers only for what's
  actually uncovered, with Step 5's differentiation angle aimed at what the prior pass
  didn't check.
- **Re-run anyway** — appropriate right after applying a fix, to measure whether it held;
  say so explicitly when this is the reason.
- **Treat the existing file as current** — if nothing has changed since it was written,
  report its findings back to the user instead of re-dispatching, and stop here.

**Why this matters:** running fresh reviewers against a workspace that already has a
reconciliation burns two full agent dispatches to re-derive a verdict that's already
recorded, with no way to tell from the output alone whether the second pass found something
genuinely new or just repeated the first. Confirmed once (`plan-reviewer`, 2026-07-27) — a
second pass independently re-derived a conclusion the existing `feedback.json` already had,
only caught after the fact because `git diff` on the target file happened to come back
empty.

### 4. Best-effort prior-fix context

Run `git log --oneline -- <target file resolved in Step 1>` filtered to commits after the
workspace directory's mtime. If this turns up fix commits, they're worth telling the
reviewers about (so they don't re-flag something already closed, and don't misattribute a
fixture-only bug as a live gap or vice versa). If nothing turns up, or the target has no
prior fix history, omit that context entirely rather than padding the prompt.

### 5. Pick agent 2's differentiation angle

Read the eval prompts from Step 3 — or, if a given eval had no prompt source at all, skim
its with-run/baseline `output.md` files directly to infer the domain — and name ONE concrete
failure mode that's plausible for
this domain but easy for a single reviewer to skim past — concurrency/race conditions for
anything concurrent or multi-replica, injection/boundary handling for anything taking user
input, accessibility/memoization/stale-closures for UI, N+1/index cases for anything
DB-facing, atomicity for anything read-then-write. State the pick and the one-line reason
before moving on — this is a judgment call, not a coin flip, and a silent pick is how you
end up with two copies of the same prompt instead of complementary coverage.

### 6. Fill, persist, and dispatch both agents

Using the template from the reference doc (Step 0 above): fill in the target name, domain
description, file list (from Step 3), eval prompts, assertions, prior-fix context (Step
4, or omit), and the agent-2-only differentiation line (Step 5).

**The eval prompts must be quoted verbatim from their true source — never paraphrased or
summarized.** "True source" means whichever of `eval_metadata.json`, `prompt.md`, or the
iteration-level `prompts.md` Step 3 actually found, or (if none exist) the literal text of
the original `Agent` tool call that dispatched the fixture-generation agent. A reviewer has
no way to tell your compressed restatement from the real thing, and will treat any
qualifying phrase your paraphrase happened to drop as evidence the with-run output invented
something — producing a "fabrication" finding that looks double-confirmed when two
reviewers converge on it, but is really one shared blind spot (your paraphrase) counted
twice. Confirmed the hard way on `score-decision` (v0.68.93): both reviewers independently
flagged the same 3 "invented" details, and none of them held up once checked against the
actual dispatch text — every one traced to a fact genuinely given, just dropped from the
compressed reviewer prompt. If the true source is long, quote the relevant portion in full
rather than trimming it — a shortened-but-verbatim excerpt is fine; a reworded one is not.

**Before dispatching, write both composed prompts verbatim to
`<iteration-path>/dispatch-prompts.md`** (one clearly-labeled section per agent, plus
today's date). This is the only record of the literal text an agent actually received —
`feedback.json`'s reconciled paragraph is a summary written *after* the fact, not a
reproducible artifact, and a fixture-data-inlined prompt (the shape used when a scenario
tests raw doc-reasoning against inlined data instead of critiquing pre-generated
with_skill/baseline outputs) can run to thousands of words with no other copy anywhere. Like
everything else under `<name>-workspace/`, this file is gitignored and local-only — it
doesn't survive a machine loss or a fresh clone — but it survives context compaction, which
is the failure mode that has actually bitten twice: a code-implementer eval-set pass
(2026-07-25) and a `ship-merge` 2-reviewer pass (2026-07-28) both lost their dispatch
prompts to compaction, recoverable only by grepping the raw session transcript afterward — a
source that is not guaranteed to still exist by the time anyone needs it. If a later run in
the same iteration reuses an unchanged prompt (e.g. a re-verification dispatch against the
same fixtures), append a dated section recording that the prompt is unchanged from the run
of `<that date>` — don't re-paste it, and don't silently skip the note.

Dispatch both as `Agent` tool calls with `subagent_type: general-purpose` (needs
Read/Grep/Glob/Bash — Bash specifically for the "verify empirically" instruction, e.g.
running a quick Node snippet to check a numeric/timing claim) **in the same message**, so
they run independently with no shared context. Running them in separate turns defeats the
entire point of independent review.

### 7. Reconcile

Once both return, follow the reference doc's "After both agents return" section:

- A finding both agents hit independently → high confidence it's real; still separate
  "the bug exists" from "here's why the target caused it."
- A finding only one agent hit → record it, single-sourced.
- Before crediting anything to the target itself, grep the *current* target file
  (resolved in Step 1) for the relevant example/rule. No trace found → it's a fixture
  artifact, not a real gap.

Write the reconciled findings to `<iteration-path>/feedback.json` in this shape (matches
what `skill-creator`'s own eval-viewer feedback file looks like, so it drops into the same
place in the loop):

```json
{
  "reviews": [
    {"run_id": "<eval-name>-<config>", "feedback": "<reconciled paragraph>", "timestamp": "<today, ISO date>"}
  ],
  "status": "complete"
}
```

### 8. Report

Summarize to the user: which findings are target-attributable (traced to a specific
clause in the resolved target file) vs fixture-only, and which are single-sourced vs
double-confirmed. If any eval in Step 3 had no prompt source at all (no
`eval_metadata.json`/`prompt.md`/`review.md`), say so explicitly — findings from that eval
rest on inferred context, not a stated task, so they warrant more skepticism. Don't edit the
target file as part of this command — that's a separate decision the user makes from the
reconciled findings, not an automatic next step. Confirm `<iteration-path>/dispatch-prompts.md`
was actually written (Step 6) before reporting completion — a skipped save here is a silent
loss of the only reproducible record of what the reviewers actually saw.

Suggested next step:
- Findings trace to specific content in the target file → open it (Step 1's resolved path)
  and apply the fix, then re-run fixtures to measure the change (don't ship an unmeasured
  fix as if it were proven). **When re-running, don't hand the re-verification agent a
  name-based reference to the fixed surface** — not `Skill(<name>)`, and not `subagent_type:
  <name>` for a plugin-scoped Agent either, since `agents/`, `commands/`, and `skills/` all
  ship inside the same single versioned bundle (`~/.claude/plugins/cache/kobig/kbg/<version>/`
  — confirmed identical layout, 2026-07-27). Until the fix is version-bumped and the plugin
  reinstalled, any of those name-based resolutions will silently serve the stale cached
  version instead of the live edit, no error (confirmed the hard way, tech-humanize
  v0.68.59 — see CLAUDE.md's "Plugin lifecycle & install" gotchas). Instruct the
  re-verification agent to `Read` the repo file path directly instead, regardless of which
  of the three surface types it is.
- Nothing traces to the target → say so plainly. A clean reconciliation is a valid result,
  not a failure to find something.
