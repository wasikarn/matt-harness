# Operating model

Three ideas hold the plugin up. Everything else is a consequence.

## 1. Deny the irrecoverable set computationally; advise on the rest

A hook can deny a tool call before it runs. That is the only place a rule is a guarantee
instead of a hope, so the deny list is kept small and literal: the set of actions no later
step can undo. the PreToolUse entries in `hooks/hooks.json` are the whole list:

| gate | denies or asks |
|---|---|
| `gate:bash:irrecoverable` | `rm -rf`, `find -delete`, `--no-verify`, `hooksPath` edits, `push --force`, `reset --hard`, `clean -f`, discarding `restore`/`checkout`, `branch -D`, `stash drop/clear`, `commit --amend`, `dd`, SQL `DROP`, `git add -A` outside a merge, nested `claude` spawns from a subagent |
| `gate:bash:subagent-git-guard` | `git stash`/`reset`/`clean` from a dispatched subagent |
| `gate:agent:subagent-spawn-guard` | a subagent calling the Agent tool to spawn its own reviewer/validator |
| `gate:task:complete-separation` | a subagent marking its own task complete |
| `gate:write:test-integrity` | asks before a write that weakens a test |
| `gate:write:config-guard` | asks before a write to Claude Code settings `hooks`/`enabledPlugins` |
| `gate:skill:codex-setup-guard` | asks before a model-invoked `Skill(codex:setup)` call carrying `--enable-review-gate` |

Everything not in that table is advice: METHODOLOGY.md text, skill prose, agent guardrails.
Advice is honest about being advice; no doc claims a check enforces a rule unless a file in
`hooks/gates/` does.

Each gate owns its error path, and the policy is written in the gate, not assumed: input it
cannot tokenize asks (`could not safely tokenize`); a missing `python3` always allows, announced
on stderr (#93); a missing sibling script denies (exit 2) for `irrecoverable.py`, but allows
(same stderr-note posture) for the three subagent-scoped gates (`subagent-git-guard`,
`task-complete-separation`, `subagent-spawn-guard`). `scripts/gate-canary.sh` proves
every staged gate still allows benign payloads. The table is the contract; the hook type is
not. Claude Code's proposed function hooks (anthropics/claude-code#91870, prototype behind
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` since 2.1.260; `claude plugin validate` already lists a
module's hooks and `$` calls on 2.1.263) skip a hook that throws, turn every function hook off
for the session when the hooks worker crashes, and evaluate matchers once before the chain. A
gate ported there must catch and deny on its own error and sit above any hook that rewrites
the event.

**The principle behind that per-gate table, stated once:** fail closed when the verdict
authorizes an action; fail open to the native/no-op path when the verdict only optimizes one
that was already going to happen anyway. `irrecoverable.py` denies on a missing sibling because
its verdict gates an irreversible command; the three subagent-scoped gates allow on the same
failure because their absence just returns the session to unguarded-but-otherwise-normal
behavior, not to a worse state than before the gate existed. A new gate's error path is decided
by which side of that line its verdict sits on, not by copying an existing wrapper's style.

## 2. The maker never grades its own work

An LLM cannot reliably judge output it produced in the same context (self-preference bias;
task-completion self-grading tops out near chance). So:

- A builder that touched 2+ files or a test gets a fresh-context validator (METHODOLOGY Rule 13).
- Reviewer agents are read-only (`harness-audit` check 32) and return findings, never a verdict
  that ships the work by fiat.
- Every `harness-audit` check has a fires/silent pair in `tests/skills/harness-audit/` (fixture
  pairs; check 43 varies the budget env against the clean fleet, with the ceiling pinned);
  a full run WARNs when a top-level surface dir (`agents/`, `skills/`, `hooks/`) is missing. An
  empty surface dir still passes its checks vacuously; the guard names only the missing dir.
- The six review agents (`plan-reviewer`, `blind-spot-hunter`, `silent-failure-hunter`,
  `requirement-analyst`, `test-gap-analyzer`, `type-design-analyzer`) have a planted-defect case and a clean control each
  under `evals/`, in `claude plugin eval`'s native layout, graded on their own Output Format
  (`evals/README.md`). `tech-humanize` has five more (three planted, a human-written control, a
  file-input case graded on the file's bytes); `harness-audit`, `memory-lint`, `deep-audit`,
  `post-mortem`, and `cost-report` have a planted case and a clean control each; `ideate` has a
  run and an abort case. Count drifts as suites are added; recompute with
  `find evals -mindepth 1 -maxdepth 1 -type d ! -name results | wc -l` rather than trust a
  literal number here (`evals/README.md`). The runner is early-access gated;
  `tests/evals/test-eval-cases.sh` keeps the cases loadable until it opens and proves every
  regex grader against its fixture or verdict sample.
- `gate:task:complete-separation` makes the rule mechanical for task state.

The same rule at fan-in: when N subagent outputs feed one synthesis, agreement and conflict are
surfaced explicitly and malformed entries are dropped by a stated rule, not by the synthesizing
model's unaided judgment.

## 3. Score, not feel

An important decision carries stated criteria, weights, a numeric result, a pass/fail reason, and
a confidence band (high/medium/low) with its reason (METHODOLOGY Rule 14). "Important" means the
Rule 1 triad flagged it (one-way door, wide blast radius) or the user asked for a ranking. Routine
calls get one line with the reason. Insufficient data is marked `ข้อมูลไม่เพียงพอ` and blocked on
the operator; a guessed score is worse than none.

Evidence is read in order: deterministic results first (a test exit code, a grep count), then
the trajectory of this run, then how often work from this source has been rolled back before,
and the model's own confidence last. Confidence is the weakest input because it is the only one
the model controls.

## What this plugin deliberately does not do

- No autonomous loop: the model never starts work on its own; every wave begins with a human.
  `/goal` and `/loop` are the operator's to type. `/goal`'s evaluator is a session-scoped
  prompt-based Stop hook on the small fast model; it reads only the transcript and never calls
  tools (`code.claude.com/docs/en/goal`), so it checks that the stated condition appears met,
  not that the work is right. It does not replace the Rule 13 fresh-context validator, and it
  has no native turn cap: the cap is a clause in the condition.
- No orchestration layer of its own: dispatch shape is one page (`spawn-brief.md`); Claude
  Code's native Agent tool does the rest.
- No response style of its own: the `ponytail` plugin is the only style layer.
