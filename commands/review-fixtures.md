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

**Not skill-only.** The underlying fixture-loop and workspace convention are already
surface-agnostic in this fleet's own practice — it's been run against a Skill
(`backend-patterns`, `frontend-patterns`, `tech-humanize`), an Agent
(`silent-failure-hunter`, v0.68.36), and a Command (`ship-merge`, v0.68.34) alike, all using
the identical `<name>-workspace/` layout. This command just needs to resolve which of the
three the target actually is — see Step 1.

**Why 2 agents, not 1**, and the exact prompt skeleton this command fills in: read
`${KBG_PLUGIN_ROOT}/docs/reference/skill-fixture-review-prompt-template.md` before Step 5
below. That file is the single source of truth for the prompt text and the 3 instructions
that must not be cut — this command only orchestrates around it.

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

- Read `eval_metadata.json` for the original task `prompt` and any `assertions`. If
  assertions are empty, note that as a gap rather than inventing some — the reviewers can
  still do a general-quality pass, just without assertion-level scoring.
- Find the `with_skill/` subdirectory and whichever baseline sibling actually exists —
  check for `no_skill/`, `without_skill/`, and `old_skill/` in that order, since all three
  names have shown up in this repo's own history depending on whether the loop was
  creating a new skill or improving an existing one. Use whichever is present; don't
  assume one name.
- Determine the output shape per config directory: a single `outputs/implementation.md`,
  or a full `outputs/` directory with multiple files plus a `SUMMARY.md`. List whatever's
  actually there.

If `eval_metadata.json` is missing or no `eval-*/` directories are found, stop and report
exactly what's missing — don't guess eval names or prompts from context.

### 4. Best-effort prior-fix context

Run `git log --oneline -- <target file resolved in Step 1>` filtered to commits after the
workspace directory's mtime. If this turns up fix commits, they're worth telling the
reviewers about (so they don't re-flag something already closed, and don't misattribute a
fixture-only bug as a live gap or vice versa). If nothing turns up, or the target has no
prior fix history, omit that context entirely rather than padding the prompt.

### 5. Pick agent 2's differentiation angle

Read the eval prompts from Step 3 and name ONE concrete failure mode that's plausible for
this domain but easy for a single reviewer to skim past — concurrency/race conditions for
anything concurrent or multi-replica, injection/boundary handling for anything taking user
input, accessibility/memoization/stale-closures for UI, N+1/index cases for anything
DB-facing, atomicity for anything read-then-write. State the pick and the one-line reason
before moving on — this is a judgment call, not a coin flip, and a silent pick is how you
end up with two copies of the same prompt instead of complementary coverage.

### 6. Fill and dispatch both agents

Using the template from the reference doc (Step 0 above): fill in the target name, domain
description, file list (from Step 3), eval prompts, assertions, prior-fix context (Step
4, or omit), and the agent-2-only differentiation line (Step 5).

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
double-confirmed. Don't edit the target file as part of this command — that's a separate
decision the user makes from the reconciled findings, not an automatic next step.

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
