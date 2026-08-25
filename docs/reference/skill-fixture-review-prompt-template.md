# Skill Fixture-Review Prompt Template — 2-agent independent review

A fill-in prompt skeleton for the "review the fixture outputs" step of a
`skill-creator:skill-creator`-style improve+optimize loop (Step 4 in that skill's own flow).
Use it instead of reading the with-skill/without-skill outputs solo — solo review is the
default the model falls back to unless told otherwise. The loop this template serves isn't
skill-only — this fleet has run it against a Skill, an Agent (`silent-failure-hunter`,
v0.68.36), and a Command (`ship-merge`, v0.68.34) alike, all with the same fixture shape.
"Skill" below is used loosely for whichever of the three is the actual target.

## Why this shape, not solo review

Confirmed twice in the same session (frontend-patterns v0.68.55, backend-patterns
v0.68.56), not theory:

- **Independent convergence confirms a finding.** Both backend-patterns reviewers found
  the same real bug (an API key used unhashed as a literal Redis key) via two different
  verification paths — one from the installed package's own type declarations, one from
  Context7 docs. Two independent routes to the same conclusion is a stronger signal than
  either alone.
- **Cross-checking catches the reviewer's own blind spot.** A solo frontend-patterns
  review had praised a scroll-reset as a real fix; two fresh agents with no knowledge of
  that read both caught it was actually dead code from component remount timing. The
  correction only happened because the second pass had zero context to anchor on.
- **Complementary coverage, not redundant coverage.** Across backend-patterns' 6 fixture
  outputs, nearly every one had each agent catching a real, distinct bug the other missed.

**Caveat, also confirmed the hard way:** convergence on a *finding* is not convergence on
a *causal story*. Two agents agreeing a bug exists doesn't license a claim about *why* the
skill produced it — that still needs separate evidence (e.g. a same-topic baseline run
that got it right unprompted is counter-evidence to "the rule wasn't sticky enough," not
supporting evidence).

**Second caveat (2026-08-22, research-sourced):** convergence carries weight in proportion
to how *different* the two routes were. The backend-patterns example above counted because
the reviewers arrived via different verification paths (package type declarations vs
Context7 docs). Two same-model-family reviewers reaching the same verdict through the same
route is one signal counted twice, not two votes — measured directly: 9 same-question
frontier judges carried ~2 effective votes' worth of information, and the best single judge
matched or beat the full panel (arXiv:2605.29800; see
`docs/research/judge-panel-correlation-vs-tiered-final-review-2026-08-22.md`). Rule 4 below
records the in-repo instance of the same effect (two reviewers double-flagging one shared
paraphrase). The per-agent PRIMARY lens below exists to force route diversity.

## When to use it (and when not)

| Situation | Use |
|---|---|
| Grading/reviewing fixture outputs from a `skill-creator`-style improve loop (skill, agent, or command target), ≥2 eval cases | **This template**, 2 agents |
| A single eval case, or a quick sanity check with no downstream content decision riding on it | Solo review — the 2-agent cost isn't earning its keep |
| Reviewing a PR / production diff (not a fixture from this kind of loop) | Use `mattpocock-skills:code-review` instead — different tool, same "don't review solo" instinct doesn't transfer verbatim |

## Fixture-construction hygiene (before you dispatch)

This section covers fixture *construction*, which happens before this command's Step
1 — `skill-creator:skill-creator` (or an ad hoc dispatch built the same way, the common
case in this repo) is what actually builds the fixtures this template reviews. Three
mistakes, confirmed multiple times across loops in this repo, make a fixture's result read
as clean regardless of what's actually true. Check for all three before trusting any output
this template helps you review.

1. **Answer-key contamination.** Nothing that states or implies the correct fix —
   `eval_metadata.json`'s `assertions` field, `prompts.md`, ground-truth notes, even a
   task-scaffolding section bundled into the same file as the data — may sit anywhere a
   dispatched agent's normal `ls`/`Glob`/`Read` can reach. Confirmed 4 times
   (security-reviewer, build-error-resolver, ship-merge, deep-audit): a dispatched agent doing
   ordinary orientation reads it, and an instruction to "ignore section X" doesn't work once
   the read already happened — the whole file loads before the "ignore it" instruction can
   take effect. **"Sibling to `with_skill`/`baseline`, not inside either" is not sufficient on
   its own** — confirmed insufficient on `deep-audit` (2026-08-09): placed exactly per that
   rule, `eval_metadata.json` still got read by a fixture-gen agent's ordinary orientation
   pass, since a sibling file is still one `ls`/`Glob` away. The verified fix: don't write the
   answer-key file at all until *after* every fixture-gen agent has completed and returned —
   derive prompts/assertions from the dispatch prompts you already composed, not from a file
   that exists on disk during the fixture-gen window. Add "do not read any file outside your
   assigned fixture directory" to each dispatch prompt as defense in depth, but treat the
   withhold-until-after-generation timing as the actual fix, not the instruction. Or,
   alternatively, withhold the fixtures directory from filesystem access entirely and inline
   only the data into the dispatch prompt. Even filenames can leak the mechanism
   (`scenario-5-freshness-mismatch-data.md` names the bug before the file opens) — use
   neutral labels ("PR A," "PR B") instead of descriptive ones.

2. **A benchmark/timing script must import the real function, never inline-copy it.** A
   copy-pasted duplicate looks correct and produces real-looking numbers at fixture-build
   time, but silently disconnects the benchmark from whatever the dispatched agent actually
   edits — confirmed on `performance-optimizer`. Before trusting any before/after number,
   grep the bench script for the function's definition; if it appears there instead of an
   `import`/`require`, the fixture is broken and every number it produces is meaningless
   regardless of what the dispatched agent did.

3. **Trap file-locality.** If a masking-trap fixture puts the correct fix in the same file
   the compiler or error message points to, a diff-only pass/fail check can't distinguish
   "the agent reasoned about which side of the bug was real" from "the agent never looks
   past the file it was handed" — both produce the identical correct diff. For a fixture
   meant to test diagnosis under genuine ambiguity, put the trap fix and the correct fix in
   the same file and surface the error somewhere else, or note the weaker claim explicitly
   in the fixture's own ground truth rather than letting a diff-only pass read as stronger
   evidence than it is. Related: a trap and the loop-mechanic it's also meant to exercise
   (e.g. "catch a self-introduced regression on re-run") can turn out to be the same
   branch — an agent that correctly avoids the trap then never triggers the loop-mechanic
   path either. Build those as two separate fixtures, not one.

4. **In a closed-book fixture, only workflow-convention rules can discriminate — not
   evidence-discovery, and not judgment quality.** Confirmed on `address-review` (iteration-1
   → iteration-2, 2026-07-31; see `address-review-workspace/iteration-1/feedback.json` and
   `iteration-2/feedback.json` for the full run). A "dry run, no live commands, all data you
   need is below" fixture format — the norm for this repo's command/agent evals — means every
   fact the correct answer depends on has to be inlined into *both* the with-skill and the
   baseline prompt regardless of how deeply it's supposedly buried (a code comment vs. a git-log
   entry vs. a `git blame` result someone would have to go dig for in a real repo). Two design
   axes both failed for this reason: (a) making the answer harder to *find* — moving the
   justification from an inline comment to commit history didn't work, because the commit
   history had to be handed to the baseline in the prompt text anyway, same as the with-skill
   arm; (b) making the *judgment call* harder — a near-miss where surface evidence looks like a
   fix but isn't (an author-matched, later commit that relocates a bug instead of fixing it)
   also didn't work, because a generically diligent agent applies ordinary due diligence
   ("does this diff actually contain what I think it contains?") and reaches the same
   conclusion the skill's specific rule would have produced. The one thing that did
   discriminate, found in iteration-1 by accident rather than by this design intent: a rule
   about how the *target skill/command itself* operates — its classification taxonomy, an
   auto-resolve eligibility rule, a reply-template selection rule, a "surface this to the user
   before doing X" checkpoint — something no amount of code/data reasoning can derive, because
   it isn't a fact about the code, it's a fact about the workflow. When designing a fixture
   meant to discriminate, aim the trap at one of those workflow-only rules, not at hiding or
   complicating the underlying evidence — and verify the design by asking "could a competent
   engineer with zero knowledge of this skill's existence, given the exact same inlined data,
   reach a different conclusion than the correct one?" If the honest answer is no, the fixture
   will not discriminate no matter how it's dressed up, and it's worth saying so rather than
   iterating on data-hiding variants.

## The template

Copy once per agent. Fill every `[bracket]`. Send **both** agent calls in the same
message as two parallel `Agent` tool invocations — if they run in separate turns they
stop being independent, which is the entire point.

```text
You are doing a PR-style code review of fixture-test outputs from a skill-creator-style
improve loop for a Claude Code [skill / agent / command — pick the actual type] called
[TARGET_NAME] ([one-line domain description, e.g. "Express/Next.js/plain Node-TS backend
patterns: async jobs, retries, rate limiting, transactions, repositories, RBAC, etc"]).

Read these [N] files directly (each is [describe the actual output artifact — a single
implementation.md, or a full output directory with generated code files plus a
SUMMARY.md — whatever this loop actually produced]):

1. [path to eval-0 with_skill output]
2. [path to eval-0 no_skill/baseline output]
[... one pair per eval case]

The prompts each output responds to (quoted **verbatim** from the original fixture-agent
dispatch or from `prompts.md`/`eval_metadata.json`/`prompt.md` — never paraphrased; see
"What not to cut" below for why):
- [eval-0 name]: "[the original task prompt given to the fixture agent]"
- [eval-1 name]: "[...]"
[...]

Do NOT read any grading.json files in those directories — form your own independent
judgment from the actual code first, to avoid anchoring on prior grading. After you've
formed your own view, you may read the current target file at [path to the skill's
SKILL.md or the agent's agents/<name>.md — whichever
this target actually is] for calibration — specifically to check whether a bug you spot
in a with_skill output is something the CURRENT content would still teach, or whether it's
already been fixed since these fixtures were generated ([if this target has had bug-fix
rounds since the fixtures were generated, list them here by version + one-line description,
so the reviewer can rule out re-flagging closed bugs — omit this sentence entirely on a
target's first iteration]).

Separately: if the target file's own body makes a claim about how another skill, agent,
command, or doc in this fleet works — a named phase, a described mechanism, a cross-reference
used to justify a design choice — that claim is independently checkable against the file it
names. Grep it and confirm the target's description is accurate; a mismatch is a
target-attributable finding on its own, whether or not it shows up in any with_skill output.

For each of the [N] outputs, write a genuine, critical, real-findings paragraph — the way
a staff engineer would comment on a pull request. Actually trace the logic ([1-2
domain-specific tracing examples, e.g. "if there's a retry loop, walk through what
happens on the Nth failure; if there's a rate limiter, check the actual Redis key
construction and TTL/window math"]). Verify claims empirically where you can (run a quick
[Node/Python/shell] snippet if a specific numeric/timing claim is checkable). Call out
both real bugs/gaps AND genuine strengths — don't manufacture criticism if the code is
actually solid, and don't rubber-stamp it as fine if it silently fails the assertions
below.

Each eval has assertions the with_skill output is expected to satisfy (the no_skill
baseline is not expected to, necessarily — that's the point of comparison):
- [eval-0 name]: (1) [assertion], (2) [assertion], (3) [assertion]
- [eval-1 name]: [...]
[...]

Check each assertion against the actual code, not just whether the right library or
pattern name appears in text. A common failure mode in code generated by an LLM is
claiming to do something in prose while the code either doesn't do it, does it partially,
or does it in a way that doesn't survive an edge case.

Return your findings as [N] clearly-labeled sections (one per file, using the eval-name +
with_skill/no_skill), each a real paragraph of substantive findings — not a checklist,
not hedged filler. This is going to be reconciled against a second, independent
reviewer's take, so be concrete and specific (line-level where it matters) rather than
vague.
```

**Append a PRIMARY-lens line to EACH copy — a different lens per agent.** One appended
sentence on one agent is a nudge, not a lens split: same-family models given near-identical
prompts converge on the same reads (correlation caveat above), so each agent gets a
distinct primary emphasis while keeping the full instructions for coverage — the same
mechanism as `scripts/workflows/deep-research.js`'s `VOTER_LENSES`:

```text
[agent 1's copy] Your PRIMARY lens — weight it above everything else: assertion-vs-code
verification. Trace each stated assertion through the actual code path and test checkable
claims empirically; treat prose claims about behavior as unverified until the code shows it.
```

```text
[agent 2's copy] Your PRIMARY lens — weight it above everything else: [ONE specific domain
failure-mode angle the assertions don't name — e.g. concurrency/race conditions across
the replicas mentioned in eval-0's prompt, or whether the rate limiter in eval-2 is
atomic under concurrent requests (a classic read-then-write race in a naive Redis
INCR-without-expire implementation)].
```

Picking that angle takes judgment — read the eval prompts and name the failure mode
that's plausible for *this* domain but easy for a single reviewer to skim past (race
conditions for anything concurrent, boundary/injection cases for anything handling user
input, accessibility/memoization for UI, N+1/index cases for anything DB-facing).

## What not to cut when adapting this

Five instructions are the load-bearing part — they're what separated this from two
shallow, agreeing summaries in both confirmed runs. Domain specifics (file paths, eval
names, assertions) change every time; these five don't:

1. **No `grading.json` before forming an independent view.** Anchoring on a prior grade
   is exactly what a second reviewer is supposed to correct for.
2. **Verify empirically where checkable.** A numeric/timing claim in a code comment is a
   claim, not a fact — run it.
3. **Check against the *current* target file before crediting or blaming it.** A bug
   in a fixture generated before a fix round isn't evidence the target still has the
   problem — and skipping this step is how a fixture-only bug gets misattributed as a
   real content gap (or vice versa).
4. **Quote the original task prompt verbatim — never paraphrase it.** A reviewer checking
   whether an output "invented" a detail can only trust that check against the actual text
   the fixture agent saw. A paraphrase that drops a qualifying phrase ("their own status
   page confirms it," "directly checkable from...") makes a faithfully-restated fact look
   fabricated — and two reviewers independently checking the *same* paraphrase will both
   flag it, which reads as double-confirmation but is really one shared blind spot counted
   twice. Confirmed on `score-decision` (v0.68.93): a whole cluster of "fabrication"
   findings dissolved once checked against the true dispatch text. If the source prompt is
   long, quote a shortened excerpt rather than trimming it to a summary — cut length, not
   fidelity.
5. **Verify the target's own cross-fleet claims, not just its fixture-output teaching.**
   Rule 3 above checks whether the target's *guidance* is still current; it says nothing
   about whether the target's *prose describing other files* is true. If the body names a
   phase, mechanism, or design choice in another skill/agent/command/doc, grep that file and
   confirm it. Missed twice by this exact process on `loop-design-check` (deep-audit,
   2026-08-15): two full fixture-review rounds both passed clean while the skill's own body
   mischaracterized `recursive-improve`'s mechanism and named a `review-pr` phase that
   doesn't exist — neither showed up in any with_skill output, because fixture review never
   reads the target file looking for this.

## After both agents return

Reconcile before touching the target file:

- A finding **both** agents hit independently → high confidence *when they arrived via
  different routes/lenses* (different evidence, different verification path); a same-route
  double-hit from two same-family reviewers is one signal counted twice, not two (see the
  correlation caveat above) — treat it as single-sourced with two copies. Either way, still
  separate "the bug exists" from "here's why the target caused it."
- A finding **one** agent hit → record it, but it's single-sourced — worth fixing if it
  traces to a specific clause in the target file, worth noting as fixture-only otherwise.
- Before crediting any finding to the target itself, grep the current target file for the
  relevant example/rule — a bug that doesn't trace to any of its content is a fixture
  artifact, not a real gap, and shouldn't drive an edit to it.
