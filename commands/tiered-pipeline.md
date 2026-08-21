---
name: tiered-pipeline
description: "Run a bounded task through the Fable→Sonnet→Opus maker/checker pipeline (capped fixes, bug-hunt, gated final review). Don't use for quick edits or PR review."
disable-model-invocation: true
disable-model-invocation-reason: Spawns a multi-agent Workflow that edits real files with no in-flow AskUserQuestion gate, and the Workflow tool's own doctrine requires explicit user opt-in for multi-agent orchestration — the typed command IS that opt-in. Ambient prose like "run the pipeline on this" must never trigger 4-10 agents unprompted.
model: inherit
effort: low
---

# The tiered-pipeline command

Wraps `scripts/workflows/tiered-pipeline.js` — the 5-stage tiered maker/checker
pipeline — so an installed user can run it from any project without knowing the
plugin-cache path: **Fable plans → Sonnet executes → Opus reviews (fix loop,
cap 3, counted in code) → Opus bug-hunts (shared cap) → Fable final review
(triage-gated)**. Every branch decision is computed in the script, never taken
from model prose; verdicts are schema-forced and fail-closed. Nothing commits,
pushes, or ships — the result returns to the human.

## Usage

```
/kbg:tiered-pipeline Add input validation to the /signup endpoint; acceptance: bad-email POST returns 400, tests pass
/kbg:tiered-pipeline --final-always Refactor the retry helper to exponential backoff
```

## Behaviour

1. Take everything after the command as the task text. If it starts with
   `--final-always`, strip that flag and set `finalReview: 'always'` (forces the
   unconditional Fable final tier; default is triage-gated — it runs only when
   fixes were used or min confidence < 0.75).
2. A task with no verifiable acceptance criteria in it is still runnable — the
   Fable plan stage derives mechanical criteria itself — but if the task text is
   empty, stop and ask for one; never invent a task.
3. Resolve the script path first — `${KBG_PLUGIN_ROOT}` is a shell env var
   (bridged at SessionStart by `command-root-anchor.sh`), and the Workflow
   tool's `scriptPath` is a plain JSON parameter that no shell ever expands.
   Never paste the unexpanded variable into the tool call:

   ```bash
   echo "${KBG_PLUGIN_ROOT}/scripts/workflows/tiered-pipeline.js"
   ```

   Then invoke the Workflow tool with the literal absolute path that printed:

   ```
   Workflow({
     scriptPath: "<the absolute path printed above>",
     args: { task: "<task text>", cwd: "<absolute path of the current project>", finalReview: "always"? }
   })
   ```

   In an installed session the path lands in the versioned plugin cache (so
   the script always matches the installed version); in the kbg-harness dev
   repo it resolves to the repo itself. Always pass `cwd` — the pipeline's
   agents work there, not in the session's own working directory.
4. The Workflow runs in the background; report its result when the completion
   notification arrives — never predict it.
5. Relay the returned object honestly:
   - `status: 'approved'` — done; name the files changed and the verification evidence.
   - `status: 'needs-human'` — the final tier declined; surface `finalReview.reasoning` + `residual_risks`.
   - `status: 'escalated'` — a stage failed closed or the 3-fix cap exhausted; surface `stage`, `reason`, and `openFindings` verbatim. Do NOT re-dispatch on your own — the cap exists so a human decides.

## Caveats (say these when relevant, don't re-derive)

- **Tier separation is declared intent, not a runtime guarantee.** A
  `CLAUDE_CODE_SUBAGENT_MODEL` env var overrides every per-stage pin, and an
  `availableModels` allowlist substitutes silently. If the user asks whether
  tiers actually separated, check the run's recorded `model` metadata — never
  claim it from the pins.
- The Workflow tool must exist in the session (current Claude Code builds ship it).

## What this command does NOT do

- Does **not** commit, push, merge, or ship anything.
- Does **not** loop past the shared 3-fix cap — exhaustion stops and reports.
- Does **not** substitute for PR review (`/kbg:review-pr`) or a quick inline edit.

**Suggested next step:** on `approved`, review the diff yourself and commit;
on `needs-human`/`escalated`, read the open findings and decide — rerun with a
sharper task, fix by hand, or drop it.
