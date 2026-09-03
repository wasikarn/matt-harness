# Operating Model

matt-harness's core operating model — the gate-vs-advisory split and the verifier-separation
principle behind it. This is the canonical source for that doctrine: CLAUDE.md's own
"Architecture" section holds only a short summary and a pointer here, so the doctrine lives in
one place instead of two hand-synced copies. Runtime surfaces read this file directly via Bash
(`cat "${MH_PLUGIN_ROOT}/docs/reference/operating-model.md"`) without pulling in the rest of
CLAUDE.md's repo-development guidance (contributor workflow, this machine's tool-composer clone
paths, etc.) — none of which a plugin user's session needs.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects
the core of `docs/METHODOLOGY.md` (everything above the `<!-- core-end -->` marker: decision-sizing
triad + reasoning scaffold) into session context — the rest stays on disk as pointer + `Read` — via
`$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC
variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise
on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The
L2–L5 autonomy ladder is retired: no autonomy flag, no maker-checker ship-gate, no model
self-start (the **no-model-self-start rule** — the harness never routes unattended LLM dispatch
to itself; every loop that remains needs a human to re-invoke it, pass by pass). Anthropic states
this same deny-vs-advise split as platform guidance, not just kbg's own doctrine: *"To block an
action regardless of what Claude decides, use a PreToolUse hook instead"*
(`code.claude.com/docs/en/memory.md`, confirmed 2026-08-20) — CLAUDE.md/memory are context the
model can weigh; a hook is the only layer that can't be argued with.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable
**score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging
its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate,
and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier.
**Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch
on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see
`docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

**Same crux, N-worker fan-in:** when parallel subagent outputs feed one synthesis/judge call, the
merge is the same problem — dropping malformed entries and surfacing agreement/conflict is
deterministic code's job, not the synthesizing model's. A fixed instruction is a fallback only
where no code layer exists to hold a real reducer (a markdown-only skill like `bug-sweep`/
`ideate` has no backing script — the dispatching model's own step-by-step discipline is the only
mechanism available there); it is not an equivalent-strength substitute for code where a script
already exists, and doctrine text should say plainly which one a given fix actually is. Default:
never silently blend or drop overlap — confirmed the hard way 2026-08-17, when `bug-sweep`'s
Consolidate step and `deep-research.js`'s Synthesize step both silently blended before a fix, and
a follow-up audit found that fix was itself mostly prompt-only and had missed cutting what the
downstream synthesis call actually reads. `memory-lint`'s pattern-cluster mode and `deep-research.js`'s
claim-dedup step (both pure code, zero LLM calls inside the reduction itself) are the real
reference implementations. `skills/workflow/orchestrate/reference.md`'s `fan-out-and-synthesize` row
enforces the same discipline via prompt instruction instead — real and load-bearing, but a weaker
mechanism than code, and should be named as such rather than blurred together with it. The
context-economy cost of a synthesis call reading unfiltered fan-out output is covered by
`docs/METHODOLOGY.md` Rule 13's context-economy block.

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Loop design essentials (folded from the retired `loop-design-check` skill, 2026-09-01)

Any agent loop this repo builds (write→test, test→fix, retry-on-failure) needs the same three
guardrails, condensed here since the standalone authoring/review skill was deleted as dead weight
(zero lifetime dispatches):

**Damping.** Negative feedback with no damping oscillates — spinning in place, burning tokens.
Damping = a retry cap, a hard stop, and a human flipping the last switch. For a periodic/regulator
loop, damping also covers overlapping invocations (a lock or a skip-if-already-running check) —
a cron interval shorter than one run's duration is a different way to lose control than
oscillation, and just as real.

**Retry cap: 3, then escalate.** 3 fix attempts on the same finding set; the 4th is an escalation
to a human, not a round. This is the one retry-cap number this repo's loop doctrine has ever
written down — don't invent a different one per loop without a stated reason. (A recurring,
unattended loop where a human is unreachable by definition is the one carve-out: retry cap 1,
exhaustion degrades to log-and-continue instead of escalating.)

**Five failure modes to check before trusting any loop:**

| # | Failure mode | Red flag | Antibody |
|---|---|---|---|
| 1 | Goal is a correct platitude → spins, burns money | Can the exit condition be machine-judged yes/no? | Replace with a decidable result condition |
| 2 | "Verification" is "check if it looks ok" → agent confidently says fine and stops | Is the judge the defendant itself? | Reconcile + exit-code rules + independent judge |
| 3 | (worst) Only gates on "all tests pass" → agent deletes the tests | Is there a boundary ("what it must NOT do")? | Done-criterion **+ boundary** together (the Goodhart antibody) |
| 4 | Counts on the agent asking mid-run → runs the wrong answer to the end | Any "clarify only at runtime" point? | Front-load every clarification before launch |
| 5 | Bloated CLAUDE.md + stale memory → the faster it loops, the more it errs | Are the docs/memory it depends on fresh? | Layered memory + periodic lint (`mh:memory-lint`, `/context`, `mh:harness-audit`) |

Rows 2-3 are the same verifier-separation crux as this file's own "unifying crux" above, applied
to a loop specifically: the judge role must never be filled by the agent under review.
