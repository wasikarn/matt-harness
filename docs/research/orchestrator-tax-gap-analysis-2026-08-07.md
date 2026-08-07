# The Orchestrator's Tax — gap analysis against kbg-harness

**Date:** 2026-08-07
**Sources:**
- Rahul Garg, *The Orchestrator's Tax*, martinfowler.com, 2026-07-16 (`~/llm-wiki/raw/The Orchestrator's Tax.md`)
- vibecodingthailand.com Thai explainer, 2026-08-04 (`~/llm-wiki/raw/The Orchestrator's Tax ปล่อย subagent 4 ตัว…md`)
- `subagent-cost-economy.md` gist (techygarg/f8f98a2f…), fetched 2026-08-07
- Primary source for platform behavior: `code.claude.com/docs/en/sub-agents`, fetched 2026-08-07

**Scope:** analysis only. No surface was edited in producing this file.

---

## Framing

kbg already runs the loop the article closes on — notice a failure, ask what it cost,
write the rule that would have caught it. `kbg:learn`, `/post-mortem`,
`docs/harness-decay-cadence.md`, and `/compliance-audit` are that flywheel, already built.
**The gap is this lesson's content, not the loop.**

The article's thesis: the scarce resource in a long agent session is not tokens and not
wall-clock — it's the *quality of the orchestrator's working memory*. Tokens are spent once;
context shapes every decision after it. kbg has a surface for the static half of that
(`kbg:context-budget` — what's installed and loaded at session start) and **nothing for the
dynamic half** (what the main thread pulls in mid-session and then carries forever).

Each finding below is labeled per the article's own authoring heuristic:

> Before adding a line to a standing instruction file, ask whether a reasonably competent
> orchestrator would make the right decision once it knew the one missing fact. If yes, the
> rule should just state the fact.

**fact** = states a missing fact. **process** = specifies a decision procedure. Anything in
the second bucket has to clear kbg's own bar (gates for the irrecoverable set; everything else
advises) before it earns a place.

---

## F1 — Live contradiction: the advisory floor of 3 pushes the wrong way

**`skills/orchestrate/SKILL.md:165`** · **fact** · **verified**

> "Hard cap = 5 agents per wave; advisory floor = 3 (F8.4). … Below 3: under-parallelized
> (F8.4 advisory only — a fixed diverse-lens panel like code-review + security-review = 2 sets
> `panel: true` on the `parallel` stage to opt out; that's not an under-split builder fan-out)."

This is the only finding where kbg is actively steering *against* the article rather than
merely silent. Cognitive locality says consolidating five tasks down to two — or one — is
frequently the correct answer, not a defect to flag. A floor that treats "under 3" as a
problem is a count-based heuristic sitting exactly where a grouping criterion belongs.

**The existing `panel: true` escape hatch does not cover this case.** It exempts a *fixed
diverse-lens panel* — N agents deliberately looking at the same artifact through different
lenses, where 2 was the plan all along. Consolidation-by-cognitive-locality is the opposite
shape: N tasks that started out genuinely distinct and collapse to 1–2 *because* they share a
mental model. That has no opt-out, so it still trips the floor and reads as a defect.

**Fix:** delete or re-scope the floor. Replace with the grouping criterion (F4). The floor's
one legitimate use — catching a genuinely under-split builder fan-out — survives as prose
without a number attached.

**Do not lower the cap of 5.** Both sources disclaim their own 2–4 explicitly (calibrated to
Sonnet 5 and one author's workload). kbg's 5 came from kbg's own measured incident —
a "20–35 items" prompt that spawned 44, then doubled to 105 agents through audit+verify
(2026-06-12, cited at `SKILL.md:161`). Swapping kbg's evidence for someone else's calibration
is a downgrade. The portable part is orthogonal to the number: **group before you count.**

---

## F2 — The measurement the article couldn't do, kbg is one small patch away from

**`hooks/stop/cost-tracker.sh`** · **fact** · **verified by direct measurement**

The article ends on an unanswered question: *how do I measure this instead of relying on the
orchestrator grading itself?* That question matters more here than in the source, because an
orchestrator self-grading its delegation is precisely the circularity kbg's own
verifier-separation crux forbids (CLAUDE.md §Architecture: "score, not feel"). Every other
finding in this document is prose. This one produces a number.

**What's on disk today.** Claude Code writes the main session to
`~/.claude/projects/<project>/<session-id>.jsonl`, and each subagent to its own file under a
sibling `<session-id>/subagents/agent-*.jsonl`. `cost-tracker.sh` reads only `.transcript_path`
— the main file. Verified on the session below: the main transcript contains **0** rows with
`isSidechain: true` (655 rows carry the key, all `false`), so subagent turns are genuinely
absent from it rather than merely unflagged. Two consequences:

1. `/cost-report` has never counted subagent spend at all.
2. The main-thread row it *does* write is, by accident, an exact isolated measurement of the
   orchestrator's own context cost.

**Measured on one real session** (`7940e684-…`, tathep worktree, 2026-07-18, Claude Sonnet 5 on
both sides — 309 main-thread turns, 15 subagents, 562 subagent turns):

| Stream | Main thread | All 15 subagents |
|---|---:|---:|
| `input` | 628 | 1,799 |
| `output` | 489,854 | 168,904 |
| `cache_write` | 1,536,177 | 2,704,377 |
| `cache_read` | 62,428,995 | 38,420,055 |
| **Total tokens** | **64,455,654** | **41,295,135** |
| **Est. cost** (Sonnet 5 intro rates) | **~$21.23** | **~$16.14** |

The headline number is the last row of the first column divided by turns: **~202K tokens of
context carried per main-thread turn, re-read on every single one.** That is the article's
scarce resource, measured — `cache_read` is the rent meter, because polluted context isn't paid
once, it's re-read for the remainder of the session.

**Two things the table does not say.** First, the 1.56× token-volume ratio (64.5M vs 41.3M) is
**not** a cost ratio — `cache_read` bills at roughly a tenth of `input` ($0.20 vs $2.00/MTok on
Sonnet 5), and both columns are >90% `cache_read`. Priced with `cost-tracker.sh`'s own rate
table, the main thread is ~$21.23 against the subagents' ~$16.14, so the orchestrator does still
dominate — by ~1.3×, not 1.56×, and its `cache_read` alone ($12.49) is 59% of its own bill and
the largest single line item in the session. Cite the dollar figures, not the token ratio, for
any cost claim. Second, the subagents' own `cache_read` averages ~68K/turn, about a third of the
orchestrator's — which is the isolation working exactly as designed, and the reason the fix is
"protect the main thread," not "spawn fewer agents."

**Fix:** extend `cost-tracker.sh` to glob the sibling `subagents/` dir and emit an
`orchestrator` vs `subagent` split, with `cache_read` and `cache_read ÷ turns` surfaced as
their own fields. `/cost-report` gets a derived "orchestrator tax" line. This is an extension
of a hook that already exists, not a new surface — the jq is a few lines, and it fixes the
undercount bug in the same patch.

**Caveat:** one session, from a worktree project, not kbg-harness. Nothing here establishes
whether ~202K/turn is high — against a 1M window and kbg's own session-start load it may be
unremarkable. That baseline comes from the patch, not from this file. Treat the numbers above as
an existence proof that the effect is measurable, not as a kbg reference point.

---

## F3 — Context economy: no rule anywhere in the repo

**`docs/METHODOLOGY.md`, `CLAUDE.md`** · **fact** · **verified (grep: zero hits)**

The gist's highest-leverage rule has no counterpart in kbg:

> Reading >~3 files or unfamiliar territory to ground a task? Delegate to an
> Explore/general-purpose subagent with a tight question. Its reads stay in throwaway context;
> only the synthesis returns. Direct reads in the main thread persist for the entire session.

kbg's standing instructions currently push the other way without meaning to. CLAUDE.md's
research rule ("search qmd first, then context7, then WebSearch") and its verify-technical-claims
rule ("deep-read the relevant qmd/llm-wiki content first") both describe main-thread reads, and
say nothing about where those reads land. Same for `docs/common-mistakes.md`'s read-before-edit
guidance. Every one of them is correct about *what* to read and silent about *who reads it*.

**Fix:** three lines, stating the fact — main-thread reads persist for the session, subagent
reads don't; over ~3 files or in unfamiliar territory, send the read out and take back the
synthesis; grep-then-offset/limit instead of whole-file reads. This belongs in
`METHODOLOGY.md` (injected every session, so it reaches foreign projects) rather than in
`orchestrate/SKILL.md`, because it governs ordinary work, not just multi-agent waves.

---

## F4 — Cognitive locality: absent as a term and as a criterion

**`skills/orchestrate/SKILL.md:291–299` ("Pick the matrix")** · **fact** · **verified**

All three of kbg's matrices — Eisenhower, Impact×Effort, Value×Risk — score tasks on their
*own attributes*. None asks what mental model a task requires before it can start. So kbg
partitions by task, which is exactly the split the article identifies as the source of the
duplicated-orientation cost: two agents rebuilding the same understanding because the work was
divided by to-do item rather than by knowledge required.

**Fix:** one grouping step *before* the matrix — merge items that share a subsystem, a file set,
or a convention, then prioritize the merged set. Note the direction it points: overlapping file
ownership is a **consolidation** signal, not a cue to spawn another agent. That reads as a
correction to F1's floor, and to the `FILES YOU OWN` block's implicit framing that overlap is a
coordination problem to be partitioned around rather than a sign the split was wrong.

---

## F5 — Skills don't cross the subagent boundary — kbg's fleet is worse off than the article's case, and has a better fix available

**`agents/*.md` (all 19)** · **fact** · **verified against primary source**

The article's claim, confirmed verbatim at `code.claude.com/docs/en/sub-agents`:

> "Each subagent starts with a fresh, isolated context window. It doesn't see your conversation
> history, the skills you've already invoked, or the files Claude has already read."

Precise scope: a skill *loaded in the parent turn* does not carry into the child. Subagents
still get their own skill listing and can invoke skills through the `Skill` tool — **if they
hold it.** Three verified facts about kbg's fleet:

- **0 of 19 agents use the native `skills:` frontmatter field**, which preloads full skill
  content into a subagent's context at startup. This field is the platform's first-class
  answer to exactly this problem and kbg uses none of it.
- **18 of 19 omit `Skill` from their `tools:` allowlist.** Per the docs, "To prevent a subagent
  from invoking skills entirely, omit `Skill` from the `tools` list." kbg's agents are not
  merely failing to inherit skills — most are hard-blocked from loading one. Only
  `code-implementer.md:4` grants it.
- Two agents name kbg skills they cannot load: `code-reviewer.md:295` scopes itself to
  `kbg:mysql-patterns` / `kbg:drizzle-patterns`; `typescript-reviewer.md:130` points at
  `kbg:typescript-patterns` / `kbg:backend-patterns`. Read strictly these are handoff pointers
  for a human reader, not load instructions — but they are indistinguishable from load
  instructions to the agent reading its own file, and the agent has no way to act on them.

**Fix, two parts:**
1. The F9 spawn-prompt template (`SKILL.md:48–86`) gains a **`## Skills`** slot. Because most
   of the fleet can't invoke skills, the slot's value must be a **file path to `Read`**, not a
   skill name to invoke — the article's "point at the file, don't paste it inline," adapted to
   kbg's actual tool grants.
2. For single-stack agents, `skills:` preload is strictly better than either: content arrives
   at startup with no discovery turns burned inside the subagent. It fits `typescript-reviewer`
   and `nextjs-reviewer` cleanly. It does **not** fit `code-implementer`, whose stack-detection
   table (`code-implementer.md:24–34`) is conditional by design — preload can't branch, so its
   current `Skill`-tool approach stays correct.

**Before shipping part 2:** `skills:` is a documented frontmatter field, but it is new to this
repo — run `claude plugin validate . --strict` (the repo's primary gate, per CLAUDE.md) on the
first agent that gets it, before adding it to the rest. Do not assume the change is free.

**Status as of v0.68.209 (shipped 2026-08-07):** `typescript-reviewer` gets
`kbg:typescript-patterns`, `nextjs-reviewer` gets `kbg:frontend-patterns`. Both pass
`plugin validate --strict` and audit check 25, and neither preloaded skill carries
`disable-model-invocation: true` (which would make it ineligible).

**Injection verified 2026-08-07**, after `claude plugin update` + restart landed
v0.68.210 in the installed cache (confirmed: `installed_plugins.json`'s `gitCommitSha`
matched local `HEAD`). Two live dispatches of `typescript-reviewer` (no `Skill` tool
grant, so it cannot self-load the skill; no path to it in either prompt):

1. A review task surfaced findings matching the skill's own worked examples (the
   exhaustiveness-check fix used the exact variable name `exhaustive` from the skill's
   `satisfies`/discriminated-union example) — suggestive but not conclusive on its own,
   since the agent's own body text already names `baseUrl`/`node10` in passing.
2. A pure factual probe ("what does `npx tsc --version` resolve to today, is
   `@typescript/native-preview` worth depending on?") returned, with **zero tool
   calls**, the skill's exact dated claims: the "Corsa" rewrite codename,
   `typescript@7.0.2`/`7.1.0`-nightly, and `@typescript/native-preview`'s last publish
   date of `2026-07-07`. None of this exists in the agent's own body text (confirmed
   by grep — no hits for `TypeScript 7`, `tsgo`, `native-preview`, `Corsa`, or `GA`),
   nowhere else in this repo, and could not be produced with zero tool calls unless it
   was already sitting in context at spawn. This is decisive: the `skills:` field
   injects real content into the subagent's system prompt, as documented.

---

## F6 — Large subagent output should return a path, not a payload

**`skills/orchestrate/SKILL.md:63–64`** · **fact** · **verified**

The F9 `## Deliverable` slot already *permits* a file ("a file at `<path>`, a commit at
`<sha>`, a verdict at `<location>`") but never forbids returning content inline. The gist's
reasoning is the part kbg is missing: routed through the orchestrator, a large output is copied
twice — produced, then relayed — and then sits in context for the rest of the session whether
it's needed again or not.

**Fix:** one clause on the existing slot. Note that kbg's validation chain already does this
right by accident — the Validator writes its structured verdict to
`.scratch/<task>/verdict.md` (`SKILL.md:144`). The rule generalizes what that one case already
proves.

---

## F7 — Status polling: encode the principle, not the tool name

**`skills/orchestrate/SKILL.md`** · **fact** · **verified**

The gist says "Don't call `TaskOutput`; it may return the full raw transcript." Do **not** port
that literally — it encodes a tool name on its way out, and two platform facts change its scope:

- `TaskOutput` is **removed from every subagent** by the platform's first tool filter
  (`code.claude.com/docs/en/sub-agents`). The rule is main-thread-only by construction.
- The tool is documented as deprecated, "Prefer `Read` on the task's output file path."

**Fix:** state the surviving principle — answer background-task status from what you already
know; never pull a raw agent transcript into the main thread; if you need an artifact, `Read`
the file the agent wrote. One line, no tool name.

---

## F8 — Repo-wide git in concurrent subagents: mostly already gated; resist gating the rest

**`hooks/gates/irrecoverable.sh:262–299`** · **process, deliberately declined**

The article's third culprit was a subagent running `git stash` / `git stash pop` while siblings
were writing in the same tree. kbg's gate already denies, globally and in every subagent:
`push --force` (262), `reset --hard` (263), `clean -f` (265), `restore` targeting the worktree
(278), `checkout --` / `checkout .` / `checkout <tree> <file>` (286), `switch --force` (288),
`branch -D` (293), `stash drop|clear` (294), `commit --amend` (297), `add -A|.` (299).

The delta is exactly plain `git stash` and `git stash pop` — the two commands from the incident,
and the two that are *recoverable*. kbg's gate stack covers the irrecoverable set; a recoverable
race belongs in prose. `agent_type` is available in the `PreToolUse` payload (proven by
`hooks/gates/task-complete-separation.sh:58`), so a subagent-scoped stash gate is technically
buildable — and shouldn't be built. Adding a gate for a recoverable operation, in response to an
article whose central warning is against adding ritual, would fail its own review.

**Fix:** one line in the F9 template's constraints — no repo-wide git in a concurrent
subagent's prompt; use scoped alternatives. No hook.

---

## F9 — advisor() batching: noted, not ranked

**`docs/METHODOLOGY.md` Rule 1** · **fact** · low value

The gist notes that transcript-forwarding tools (advisor, critic) cost in proportion to
transcript length, so the same call is cheaper earlier. kbg's Rule 1 already prescribes roughly
two calls per task — before committing to an approach, and before declaring done — which *is*
the batched shape. Worth a half-sentence ("batch open questions into one call rather than
splitting them across turns"), not a section.

---

## Explicitly not recommended

Three things a naive port would adopt, and shouldn't:

| Tempting | Why not |
|---|---|
| Lower the fan-out cap from 5 to 2–4 | Both sources disclaim their numbers as calibrated to their own model + workload. kbg's 5 came from kbg's own measured incident (105 agents). Porting the number discards kbg's evidence; port the grouping criterion instead. |
| Add a confirm-before-spawn gate listing agents + skills | The article proposed this, then withdrew it as "another ritual" with no evidence bad spawn plans were slipping through. kbg already gates every write-capable dispatch behind `AskUserQuestion` (`SKILL.md:25`). More would be the ritual the article warns about. |
| Trim `orchestrate/SKILL.md` for standing-instruction cost | Aims at the wrong file. Skill *bodies* load on demand — 351 lines cost only when orchestration actually happens. The recurring-cost argument aims at `CLAUDE.md` (22.9K) and `METHODOLOGY.md`, which load every single session. If F1–F7 add lines, that's the budget they come out of. |

One calibration note: the platform already enforces kbg's "a dispatched sub-agent must not
re-orchestrate" rule (METHODOLOGY Rule 13) — `Agent` is removed at the depth limit, and
`Workflow`, `AskUserQuestion`, `EnterPlanMode`, and `ExitPlanMode` are removed from every
subagent. kbg's prose preamble at `orchestrate/SKILL.md:8–12` is belt-and-suspenders over a
platform guarantee, not the load-bearing control it reads as. Not a defect; worth knowing before
anyone strengthens it further.

---

## Suggested sequence

Ordered by evidence-per-line-added, not by size:

1. **F2** — the measurement patch. It's the only item that produces a score rather than a rule,
   it fixes a real undercount bug in `/cost-report`, and it turns F1/F3/F4 from borrowed
   opinions into locally-testable claims. Do this first so the rest can be verified rather than
   believed.
2. **F1** — delete the floor of 3. One line removed. Highest-value line change in the set.
3. **F3 + F4** — context economy and cognitive locality. Together, ~5 lines across
   `METHODOLOGY.md` and `orchestrate/SKILL.md`.
4. **F5** — the `## Skills` slot plus `skills:` preload on the single-stack reviewers. The only
   item that touches multiple agent files.
5. **F6 + F7 + F9** — three clauses on existing slots.
6. **F8** — one constraint line. No hook.

Every item above is a content change to `orchestrate/SKILL.md`, `METHODOLOGY.md`/`CLAUDE.md`,
`cost-tracker.sh`, or a few `agents/*.md` frontmatter blocks. **No new skill, agent, command, or
gate is warranted** (Rule 2).
