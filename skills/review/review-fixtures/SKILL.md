---
name: review-fixtures
description: "Dispatch 2 independent staff-engineer agents to adversarially review skill-creator-style fixture outputs (with_skill vs baseline) for a skill, agent, or command before deciding a fix. Use when fixtures already exist mid an improve+optimize loop. Don't use for PR review (mattpocock-skills:code-review) or skill-creator's own quantitative grading/benchmark step."
argument-hint: <skill/agent/command-name> [iteration-path]
model: inherit
effort: high
---

# /review-fixtures — 2-agent independent fixture review

Runs the qualitative review step of a `skill-creator:skill-creator`-style improve+optimize
loop with 2 independent agents instead of a single solo read — an adversarial 2-agent pass
whose convergence and disagreement both carry signal (grading/benchmark steps unchanged).

**Not skill-only.** The `<name>-workspace/iteration-N/eval-*/` layout is surface-agnostic —
used for a Skill, an Agent, and a Command alike; Step 1 resolves which the target is. Naming
pairs by build path: `skill-creator`-built Skill loops produce `with_skill/` +
`no_skill|without_skill|old_skill/` + `eval_metadata.json`; ad-hoc Agent loops produce
`with_agent/` + `baseline/` + `prompt.md` (often a pre-written `review.md`). Step 3 tolerates
both — don't assume Skill-side names apply to an Agent or Command target.

## Steps

### 0. Read the reference doc first

**Why 2 agents, not 1**, and the exact prompt skeleton this command fills in: read
`${MH_PLUGIN_ROOT}/docs/reference/skill-fixture-review-prompt-template.md` before Step 5 —
the single source of truth for the prompt text, the fixture-construction hygiene checklist,
and the 5 instructions that must not be cut; this command only orchestrates around it.

### 1. Parse arguments and resolve the target surface

The user names a skill/agent/command (strip a leading `mh:` if present) when invoking this
skill, optionally followed by an iteration path. If whitespace makes it ambiguous which part
is the name vs the path, take the first token as the target name and the rest as the
iteration path — Step 2's auto-glob-highest-N already covers the common no-path case.

If no target name was given, show usage and stop — do not guess which target:
```
Usage: mh:review-fixtures <skill/agent/command-name> [iteration-path]
Example: mh:review-fixtures backend-patterns backend-patterns-workspace/iteration-2
```

Resolve which surface the name is by checking, in order: `skills/<name>/SKILL.md`,
`agents/<name>.md`. Whichever exists is the **target file** referenced in Steps 4 and 8.
Neither exists → stop and report that, don't guess a path or default to skill. (No
`commands/` check any more — that surface retired, spec #101.) Steps 2–3's
workspace/eval-case discovery don't need this resolution — the `<name>-workspace/` and
`eval-*/` conventions are identical across surface types.

### 2. Locate the workspace

Workspace root is `<skill-name>-workspace/` relative to the repo root — a dev-workspace
sibling of `skills/<skill-name>/`, not inside the installed plugin; never resolve it from
`${MH_PLUGIN_ROOT}`.

- If the user gave an iteration path (Step 1's parse), use it directly.
- Otherwise glob `iteration-*` under the workspace root and pick the highest N.
- If the workspace root doesn't exist: stop and tell the user to run
  `skill-creator:skill-creator`'s fixture-generation steps (1–4) first — this command
  reviews fixtures that already exist, it does not generate them.

### 3. Discover eval cases

For each `eval-*/` directory under the iteration path:

- Get the original task prompt and any `assertions`, checking sources in this order:
  `eval_metadata.json` (`prompt` + `assertions` — the Skill-loop convention); a bare
  `prompt.md` in the eval directory (Agent-loop workspaces); an iteration-level shared
  `prompts.md` one level up at `<iteration-path>/prompts.md` (NOT inside the eval directory —
  look up the matching entry); then, only if none exist, a task description in an existing
  `review.md`'s opening section — treat this as a paraphrase, not the verbatim prompt, and say
  so if used. If none of the four exist, or assertions are empty/absent, note that as a gap
  rather than inventing one — the reviewers can still do a general-quality pass, just without
  assertion-level scoring. Not a stop condition (see below).
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
exists. If it doesn't, skip straight to Step 4 — the common case, no special handling.

If it does exist, read it, then tell the user plainly: a reconciliation already ran (name
the evals and, if visible from the file or a quick `git log`, roughly when), and ask how to
proceed rather than silently redoing or skipping the work:
- **Scope to the gap** — if the existing file only covers some evals, or a fix landed since
  (Step 4's `git log`), dispatch fresh reviewers only for what's uncovered.
- **Re-run anyway** — right after applying a fix, to measure whether it held; say so when
  this is the reason.
- **Treat the existing file as current** — if nothing's changed since, report its findings
  back instead of re-dispatching, and stop here.

**Why this matters** (confirmed re-derivation incident, 2026-07-27):
`references/rationale.md#why-the-step-35-reconciliation-check-exists`.

### 4. Best-effort prior-fix context

Run `git log --oneline -- <target file resolved in Step 1>` filtered to commits after the
workspace's mtime. Tell reviewers about fix commits (so they don't re-flag something closed,
or misattribute a fixture-only bug as a live gap). Nothing found → omit, don't pad the prompt.

### 5. Pick agent 2's differentiation angle

Read the eval prompts from Step 3 — or, if an eval had no prompt source, skim its
with-run/baseline `output.md` files to infer the domain — and name ONE concrete failure mode
plausible for this domain but easy for a single reviewer to skim past (concurrency/races,
injection/boundary handling, accessibility/memoization/stale-closures for UI, N+1/index for
DB-facing code, atomicity for read-then-write). State the pick and the one-line reason — a
silent pick is how you end up with two copies of the same prompt instead of complementary
coverage.

### 6. Fill, persist, and dispatch both agents

Using the template from the reference doc (Step 0): fill in the target name, domain
description, file list (from Step 3), eval prompts, assertions, prior-fix context (Step 4,
or omit), and the agent-2-only differentiation line (Step 5).

**Quote eval prompts verbatim from their true source — never paraphrase or summarize.** True
source = whichever of `eval_metadata.json`, `prompt.md`, or the iteration-level `prompts.md`
Step 3 found, or (if none exist) the literal text of the original `Agent` tool call that
dispatched the fixture-generation agent. If the true source is long, quote the relevant
portion in full — a shortened-but-verbatim excerpt is fine; a reworded one is not. Why a
paraphrase manufactures double-confirmed "fabrication" findings (confirmed on
`score-decision`, v0.68.93): `references/rationale.md#why-eval-prompts-must-be-quoted-verbatim-step-6`.

**Before dispatching, write both composed prompts verbatim to
`<iteration-path>/dispatch-prompts.md`** (one labeled section per agent, plus today's date).
If a later run reuses an unchanged prompt, append a dated section noting it's unchanged from
`<that date>` — don't re-paste, don't skip the note. Why this file is the only reproducible
record (compaction has eaten the transcript copy twice):
`references/rationale.md#why-dispatch-promptsmd-must-be-persisted-step-6`.

Dispatch both as `Agent` tool calls with `subagent_type: general-purpose` (needs
Read/Grep/Glob/Bash — Bash for the "verify empirically" instruction) **in the same message**,
so they run independently with no shared context — separate turns defeat the point. Each copy
carries its own PRIMARY-lens line per the reference template — two identical prompts to two
same-family agents is one reviewer counted twice, not two.

### 7. Reconcile

Once both return, follow the reference doc's "After both agents return" section:

- Both agents hit it independently *via different routes/lenses* → high confidence it's real;
  a same-route double-hit is one signal counted twice (same-family reviewers correlate). Still
  separate "the bug exists" from "here's why the target caused it."
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
`skill-creator`'s own eval-viewer feedback file; `target_attributable` is additive — existing
consumers reading `feedback`/`run_id`/`timestamp`/`status` are unaffected):

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
the resolved target file) vs fixture-only, and single-sourced vs double-confirmed. If any eval
in Step 3 had no prompt source, say so — those findings rest on inferred context and warrant
more skepticism. Don't edit the target file as part of this command — that's a separate user
decision. Confirm `<iteration-path>/dispatch-prompts.md` was actually written (Step 6) before
reporting done — a skipped save silently loses the only reproducible record.

Suggested next step:
- Findings trace to the target file → open it (Step 1's resolved path), apply the fix, then
  re-run fixtures to measure the change (don't ship an unmeasured fix as proven). **When
  re-running, hand the agent the repo file path, never a name-based reference** — the
  stale-cache trap: `references/rationale.md#the-stale-cache-re-test-trap-step-8`.
- Nothing traces to the target → say so plainly. A clean reconciliation is a valid result.
