# Operating Model

matt-harness's core operating model — the gate-vs-advisory split and the verifier-separation
principle behind it. This is a self-contained excerpt of CLAUDE.md's own "Architecture" section,
built for surfaces that read it at runtime via Bash
(`cat "${MH_PLUGIN_ROOT}/docs/reference/operating-model.md"`) without pulling in the rest of
CLAUDE.md's repo-development guidance (contributor workflow, this machine's tool-composer clone
paths, etc.) — none of which a plugin user's session needs. CLAUDE.md itself stays the canonical
source for anyone developing this repo directly.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects
`docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via
`$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC
variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise
on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The
L2–L5 autonomy ladder is retired. Anthropic states this same deny-vs-advise split as platform
guidance, not just kbg's own doctrine: *"To block an action regardless of what Claude decides, use
a PreToolUse hook instead"* (`code.claude.com/docs/en/memory.md`, confirmed 2026-08-20) —
CLAUDE.md/memory are context the model can weigh; a hook is the only layer that can't be argued
with.

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
where no code layer exists to hold a real reducer (a markdown-only command like `bug-sweep`/
`ideate` has no backing script — the dispatching model's own step-by-step discipline is the only
mechanism available there); it is not an equivalent-strength substitute for code where a script
already exists, and doctrine text should say plainly which one a given fix actually is. Default:
never silently blend or drop overlap. `memory-lint`'s pattern-cluster mode and `deep-research.js`'s
claim-dedup step (both pure code, zero LLM calls inside the reduction itself) are the real
reference implementations. `skills/orchestrate/reference.md`'s `fan-out-and-synthesize` row
enforces the same discipline via prompt instruction instead — real and load-bearing, but a weaker
mechanism than code, and should be named as such rather than blurred together with it. The
context-economy cost of a synthesis call reading unfiltered fan-out output is covered by
`docs/METHODOLOGY.md` Rule 13's context-economy block.

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).
