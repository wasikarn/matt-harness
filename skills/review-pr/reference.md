# review-pr Reference

Static lookup tables for kbg:review-pr skill. Loaded on-demand when the skill is invoked; not part of the session prefix cache.

---

## Review Aspects Reference

| Aspect arg | Routes to | Notes |
|---|---|---|
| `code` | `code-reviewer` (general-quality lens, unconditional), plus a language specialist and/or `nextjs-reviewer` if applicable (see Agent Descriptions) | general quality pass always dispatches even when a specialist also does — see Routing Rule Detail |
| `tests` | `code-reviewer` (behavioral test-coverage lens) | test files changed, OR the diff touches a Claude Code surface dir — see Routing Rule Detail |
| `comments` | `code-reviewer` (comment-accuracy lens) | only if docs/comments added |
| `errors` | `silent-failure-hunter` | only if error handling changed |
| `security` | `security-reviewer` | auth/secrets/external input/payment code/dependency manifests (`package.json`, lockfiles, `go.mod`, `requirements.txt`, `Gemfile`, etc.) touched |
| `types` | `code-reviewer` (type-design lens) | only if types/interfaces/DTOs/schemas/models changed |
| `db` | `code-reviewer` (DB/SQL query-safety lens) | migrations/schema/query files changed (`.sql`, Drizzle schema, query-builder calls) OR a raw driver call (`db.query(sqlString)`) against any engine |
| `simplify` | NOT a reviewer | run native `/simplify` (clarity-only) separately after review decisions land (Phase 7 next-step) |
| `all` | every applicable agent per Phase 3 routing | default if no aspect arg |
| *(not an aspect arg — detected from a Jira ticket reference)* | `requirement-analyst` (Phase 1.5) + `code-reviewer` (requirement-coverage lens) | fires on `jira` keyword + a ticket-key-shaped token anywhere in the prompt (e.g. "review #2606 with jira TP-871"), regardless of aspect narrowing |

### Routing Rule Detail

Supplementary detail for `SKILL.md § Phase 3` — full rationale behind the table above.

- **`code`**: a specialist never substitutes for `code-reviewer` — confirmed failure mode: PR #2603
  dispatched only `typescript-reviewer`, so general quality went unreviewed. On a trivial diff
  (single non-test file — same predicate as Phase 5 step 3.6 / Phase 6's proof check), only the
  *specialist* may be skipped as a Rule-2 economy; `code-reviewer` stays mandatory regardless.
- **Next.js**: `nextjs-reviewer` fires on path match (`app/**`, `middleware.ts`, `proxy.ts`,
  `next.config.*`) independent of the extension-plurality rule that picks the language specialist
  — a Next.js diff can touch few files by extension count and still carry framework-specific risk
  (e.g. the Server Action IDOR pattern `nextjs-reviewer.md` documents). Confirmed gap: `review-pr`
  never routed to `nextjs-reviewer` at all before this fix.
- **`tests`**: the Claude Code surface dir trigger (`.claude/{agents,skills,commands,hooks}/`, or
  this repo's own root `{agents,skills,commands,hooks}/`) fires even with zero test files changed
  — the harness's own code is the one place an untested change is highest-risk, so the
  behavioral test-coverage lens defaults on for harness diffs.
- **`security`**: dependency-manifest triggers match `security-reviewer`'s own "When to Run"
  section — a payments-only or lockfile-only diff still needs it, not just `code-reviewer`'s
  general lens.
- **Aspect narrowing vs. a dispatched specialist's own judgment**: an aspect arg narrows *which
  agents get dispatched*, not what a dispatched specialist judges within its own brief —
  `security-reviewer` may still surface a reliability-adjacent finding (missing audit logging,
  fail-open error handling) it judges security-relevant, even under a narrowed `security` request.

## Phase 1 — Auto-Parallel Rationale (`ACS:auto-parallel`)

Supplementary detail for `SKILL.md § Phase 1, step 3`.

A gate approved on autopilot is ceremony, not judgment (The Orchestrator's Tax,
`harness-decay-cadence.md` §gate-discipline) — the deterministic score behind this auto-decide
(routed-agent count, diff size, an auth-touch grep) already fully covers the parallel-vs-sequential
call whenever none of the ambiguous conditions (auth-heavy, docs-only, >5 agents) are present, so
asking anyway would just be the same autopilot-approval anti-pattern in reverse.

## Fowler Smell Baseline

Always-on background for the `code` aspect's general-quality lens — alongside whatever CLAUDE.md or repo docs already specify, not a new axis. Two binding rules: a documented repo standard always overrides the baseline; every smell below is a judgement call ("possible Feature Envy"), never a hard violation. Skip anything tooling already enforces.

| Smell | What it is | Fix |
|---|---|---|
| Mysterious Name | Name doesn't reveal what it does or holds | Rename; if no honest name comes, the design's murky |
| Duplicated Code | Same logic shape in more than one hunk/file | Extract the shared shape, call it from both |
| Feature Envy | A method reaches into another object's data more than its own | Move the method onto the data it envies |
| Data Clumps | Same fields/params keep travelling together | Bundle into one type, pass that |
| Primitive Obsession | A primitive/string standing in for a domain concept | Give the concept its own small type |
| Repeated Switches | Same switch/if-cascade on the same type recurs | Replace with polymorphism, or one shared map |
| Shotgun Surgery | One logical change forces scattered edits across many files | Gather what changes together into one module |
| Divergent Change | One file/module edited for several unrelated reasons | Split so each module changes for one reason |
| Speculative Generality | Abstraction/params/hooks added for needs the spec doesn't have | Delete it; inline back until a real need shows |
| Message Chains | Long `a.b().c().d()` navigation the caller shouldn't depend on | Hide the walk behind one method on the first object |
| Middle Man | A class/function that mostly just delegates onward | Cut it, call the real target direct |
| Refused Bequest | A subclass/implementer that ignores or overrides most of what it inherits | Drop the inheritance, use composition |

Source: Fowler, *Refactoring* ch.3.

**Sync seam:** `kbg:review-lens-code-quality`'s own Fowler section (extracted from `agents/code-reviewer.md` 2026-08-18 to clear harness-audit check 60's size threshold, still called from that agent's checklist) carries 11 of these 12 — it deliberately omits Duplicated Code (and Long Method) because `code-reviewer`'s checklist already covers them elsewhere under different names ("Duplicated helper/util", "Large functions"). That's a legitimate per-file difference, not drift — if you edit one table, check whether the other needs the matching edit or is correctly diverging on purpose.

## Agent Descriptions

One-line orientation; **see kbg:inventory for current frontmatter descriptions and the agent file (plugin-delivered or project-local) for full body** (single source of truth — these blurbs intentionally stay terse to avoid drift).

| Agent | Specialty |
|---|---|
| `silent-failure-hunter` | Silent failures + broad catches + unjustified fallbacks |
| `security-reviewer` | OWASP + auth + secrets + supply chain — flags with severity, doesn't fix |
| `code-reviewer` | General quality + CLAUDE.md compliance — issues-only at confidence ≥80. Also carries the **comment-accuracy lens** (comment accuracy + rot + doc completeness), the **type-design lens** (type/DTO/schema encapsulation + invariants + illegal-states-unrepresentable), the **behavioral test-coverage lens** (test gaps by criticality, not line %), the **DB/SQL query-safety lens** (MySQL/MariaDB + Drizzle query and migration safety), and the **requirement-coverage lens** (does the diff satisfy the requirements a referenced Jira ticket asked for — opt-in, Phase 1.5) |
| `requirement-analyst` | Senior-level requirement analysis of a Jira ticket's own body — ambiguities, missing ACs, edge cases, readiness verdict. Dispatched by Phase 1.5 when a ticket is referenced; never fetches, never touches the diff (that's the coverage lens above) |
| `typescript-reviewer` | TS/JS type safety, async correctness, security, idiomatic patterns — routed alongside `code-reviewer` when `.ts`/`.tsx`/`.js`/`.jsx` is the dominant changed-file language |
| `python-reviewer` | PEP 8, Pythonic idioms, type hints, security, performance — routed alongside `code-reviewer` when `.py` is the dominant changed-file language |
| `nextjs-reviewer` | App Router rendering/caching, Server Actions, middleware — routed alongside `code-reviewer` (and `typescript-reviewer`, if still dominant) when the diff touches `app/**`, `middleware.ts`, `proxy.ts`, or `next.config.*` |
| native `/simplify` (post-review polish, **not** a reviewer) | Clarity/readability refactor without behavior change |

## Per-Reviewer Worktree Isolation

Supplementary detail for `review-pr/SKILL.md § Phase 4, step 3 (No-mutate instruction)`.

The light fix shipped today is advisory: every dispatched reviewer is told it must not mutate
the shared `$WT` (or working tree, own-branch review) — no `git checkout`, no file writes, no
`git stash`. Review agents are read-only by frontmatter (no Edit/Write), so the only mutation
vector is Bash, and that advisory instruction is the whole guard. A reviewer reviews, it doesn't
fix — a hypothesis that needs code run to confirm becomes a finding with the repro command, not
an in-place execution; a mutated worktree would corrupt the other parallel reviewers' reads.

A heavier, deterministic alternative was evaluated and NOT shipped: per-reviewer worktrees —
`git worktree add --detach "$TMPDIR/review-pr-<#>-r<i>" "$HEAD_SHA"`, one per dispatched agent
(`i` up to N≤5, `orchestrate`'s fan-out cap), with `kbg:review-pr-finish`'s Phase 7 cleaning a
`review-pr-<#>-*` glob instead of a single `$WT`. Reasons it wasn't shipped: the only mutation
vector is Bash (agents hold no Edit/Write), and the convergence gate + sibling-generalization
fixes address the actual >10-loop failure mode this repo has seen in production — a higher-rank
problem than a clobber that has never been observed happening. Upgrade to the heavier version if
a clobber is ever confirmed.

## Phase 5 step 3.6 — standalone form

Supplementary detail for `review-pr-tier/SKILL.md § Phase 5, step 3.6 (Zero-findings adversarial re-hunt)`.

The standalone, dispatchable form of this exact discipline — usable outside a review-pr run, e.g.
on a self-authored delta mid-session — is `agents/blind-spot-hunter.md`, which also carries the
enriched hunt-shape checklist. Step 3.6 now dispatches `blind-spot-hunter` directly (fixed
2026-08-09 — it previously dispatched an inline-framed `general-purpose` agent instead, the gap
this note used to track).

Why it exists: step 3.5 only checks findings that already exist — it does nothing when reviewers
return zero Critical/Important findings, exactly the shared-blind-spot case (a false *negative*
no refutation can catch). On a clean, non-trivial-diff pass, an adversarial re-hunt for that
shared blind spot means the clean verdict is a second pair of eyes', not just the absence of a
finding — the same reviewers that found nothing share whatever blind spot let the defect through
in the first place. Re-reviewing with the same lens just reproduces the zero; the reframe from "check this" to "there
is a bug here — locate it" is what gives a shared blind spot a chance to surface. `blind-spot-hunter`
is step 3.6's purpose-built agent for this — pinned `opus`, trace-to-earned-severity, a "Cleared
decoys" list, fail-closed refutation already built in — not a generic agent re-framed by the
step's own prompt. A hunter told "assume a bug exists" is primed to manufacture a weak one — the
exact false positive step 3.5's fail-closed refutation exists to kill, which is why every hunter
finding gets that same refutation applied before it counts.

**Reading the Phase 5 checkpoint — why `$HEAD_SHA` isn't git-derived.**
`read-review-checkpoint.sh` doesn't call `git` itself — it mirrors `should-continue-loop.sh`'s
own pure string-compare convention. A live git-derive here would reject every legitimate
PR-by-number hand-off, since Phase 2 works from an isolated worktree.

**Step 4 — what makes a zero-findings verdict "clean" vs. "didn't check."** `agents/code-reviewer.md`
explicitly sanctions a bare zero-findings APPROVE ("do not withhold approval to appear rigorous")
— don't demand narration a clean pass doesn't need. What actually distinguishes "checked and
clean" from "didn't check" is that Phase 4 hands every agent the exact pinned range
(`$BASE_SHA..$HEAD_SHA`): a zero-findings return against a known, scoped diff *is* the clean
signal — backed, on a non-trivial diff, by step 3.6's adversarial re-hunt so the clean verdict
isn't just the reviewers' shared blind spot restated.

**Why step 3.5 exists (independence).** SCRUTINIZE-4 (step 2) is self-graded: the same
orchestrator context that ran the checklist decides whether its own checklist passed — the maker
grading its own work, the exact pattern CLAUDE.md's verifier-separation principle rejects
everywhere else in this harness. Step 3.5 is the actual independent check. It closes the
*independence* gap, not the *empirical-grounding* gap (a correlated hallucination across
same-distribution reviewers can still survive) — that second gap is `kbg:review-pr-finish`'s
Phase 6 proof-verification check (own-branch flow) and `/ship-merge` Phase 1 step 6's distrust of
same-session self-tiering on sensitive diffs.

## write-review-state.sh — Field Contract & Amend Mode

Supplementary detail for `review-pr-finish/SKILL.md § Phase 7, step 1 (write-review-state.sh)`.

   **stdout contract.** Prints the written state-file path on success, then a second stdout line
   — `round=N prev_critical=X prev_important=X prev_minor=X stalled=true|false
   regressed=true|false force_human=true|false
   convergence_state=converged|regressed|churning|stalled|progressing churn_files=a.ts,b.ts`
   — that step 2's round-aware footer renders from directly; don't re-derive these by re-reading
   the state file back. `churning` = a file has held a Critical/Important finding 3+ rounds
   running (regardless of whether it's the same issue each time) — `churn_files` names which;
   empty when not churning.
   On failure, don't proceed to step 4's worktree cleanup — but a non-zero exit doesn't always
   mean nothing was written: the worktree-escape trap catches a bad `REVIEW_PR_STATE_DIR` only
   after the file is already written to the (about-to-be-deleted) wrong path. Fix the state dir
   and re-run rather than assuming the write never happened.

   **Run the script exactly as shown — don't paraphrase its output into hand-authored JSON.** The
   7 field names (`clean`, `critical_count`, `rehunt`, `last_sha`, `branch`, `review_mode`, `ts`)
   are the machine-readable contract `/ship-merge`'s gate depends on. Confirmed against real
   production state files: sessions that skip the script and narrate their own richer summary
   routinely rename or drop these exact keys — silently breaking the downstream gate even though
   the review itself was fine. **Adding extra fields alongside the required 7 is fine** (a `note`,
   or the `important_count`/`minor_count`/`round`/`stalled`/`finding_files`/`regressed`/
   `force_human`/`convergence_state`/`file_streaks`/`churn_files` fields this script now writes and
   step 2 below reads back to render the round-aware footer) — just never rename or omit the 7. Full
   script (canonicalization rule, keying scheme, the worktree-escape safety check, and the incident
   history behind each): `scripts/write-review-state.sh`.

   **Realized you passed a wrong value (e.g. the wrong `HEAD_SHA`) after the write already
   happened?** Re-run the same command with `amend` appended as a 9th argument — it corrects the
   fields you re-pass on the round already in the state file, in place, without advancing the round
   counter or comparing that round's counts against themselves. Do NOT hand-edit the JSON to fix it
   and do NOT just re-run the script normally (that treats the correction as a brand-new round,
   compares the round against its own already-written counts as "prior round," and produces a false
   `stalled:true` — confirmed in production, session e34b6832/PR #2754 round 9, 2026-08-11). `amend`
   ignores `finding_files_path`; `regressed`/`churning`/`finding_files`/`file_streaks`/`churn_files`
   carry through unchanged from the round being corrected. For an own-branch review, `amend` refuses
   (fails closed) if the shared state file's `branch` doesn't match the current branch — it corrects
   the current branch's own round, never a different branch's (found by `/kbg:deep-audit`,
   2026-08-14: with no guard, switching branches then running `amend` silently adopted the other
   branch's round/prev_*/streaks).

   `CRITICAL_COUNT`/`IMPORTANT_COUNT`/`MINOR_COUNT` = number of Critical/Important/Minor findings
   from Phase 5. `rehunt` records step 3.6's outcome (`clean` / `skipped-trivial` / `incomplete` / `n/a`) so the downstream gate can tell a certified-clean review from one whose blind-spot hunt never returned — an `incomplete` re-hunt (or any `dispatch_failures`) writes `clean:false` even at `critical_count:0`, because an unfinished review has not certified zero criticals. Always write this file; it is the machine-readable input to `/ship-merge`'s Rule-14-scored review gate. A reviewer-flow run on a PR by number still writes it (using the PR's HEAD SHA) so the author can see the verdict — to `review-pr-<#>.json`, not the shared `review-last.json`. `review_mode` records provenance: `pr-by-number` means Phase 2 ran the review in an isolated worktree (severity tiering wasn't done by a session that could be the diff's own author); `own-branch` means an author-flow self-review. Phase 5 step 3.5 now runs an independent verifier per Critical/Important finding regardless of `review_mode` — but that verifier is still dispatched and its verdict interpreted by the same session that may have authored the diff, so `own-branch` still doesn't fully close the self-review gap (see `/ship-merge` Phase 1 step 6 — this still gates same-session self-tiering on sensitive diffs).

   **`FINDING_FILES` repo-relative-path rationale.** Entries must be repo-relative (matching Phase
   7 step 3's `comments[].path` convention) — the same file reported as `$WT`-absolute in one round
   and repo-relative in another reads as two different identities to both `regressed` and the
   churn-streak tracker (both are exact-string set comparisons). The script normalizes a leading
   `/` defensively, but don't rely on that — report repo-relative at the source.

   **Why positional args, not inherited env.** Pass the actual values you're holding at that point
   in the phase (`CRITICAL_COUNT`/`IMPORTANT_COUNT`/`MINOR_COUNT` derived from `tier_list`,
   `REHUNT_STATUS` from `kbg:review-pr-tier`'s step 3.6, `DISPATCH_FAILURES` from the checkpoint,
   `HEAD_SHA`/`WT` from the checkpoint) as literal arguments — an inherited-but-unexported shell
   variable fails silently across the nested bash invocation this script call is.

## Loop Reason Stop Messages

Supplementary detail for `review-pr-finish/SKILL.md § Phase 7, step 2` — the per-`$LOOP_REASON` message text
step 2 renders when `should-continue-loop.sh` returns non-zero (`$LOOP_EXIT != 0`). Moved here
2026-08-17 (a pure lookup table, not branch logic — the `should-continue-loop.sh` invocation
itself and the `$LOOP_EXIT`/`$LOOP_REASON` branch skeleton stay inline in SKILL.md, satisfying
harness-audit check 59's requirement that the literal string stay grep-visible there).

- `converged`: `Review clean — Critical 0, rehunt clean. Non-blocking Important/Minor may
  be addressed in a follow-up; merge via /kbg:ship-merge. Do not re-run review-pr on
  non-blocking findings.` This is the loop's stop condition: a clean review does not need
  another pass. (The merge-path deny-gate in `hooks/gates/convergence-merge-gate.sh`
  blocks a raw `gh pr merge` on a non-clean review; this carve-out is the advisory half
  that stops the loop from re-running past clean.)
- `regressed`: `{round} rounds — fixes are introducing new findings in files not flagged
  last round, a fix in one place is breaking another. Needs a human call, not another
  automatic pass (check for missed sibling call sites — see address-review Phase 4).`
- `churning`: `{round} rounds — the same file(s) have held a Critical/Important finding
  {N} rounds running ({churn_files}) — fixes in this module keep producing new findings
  there. This is fix-induced churn, not slow convergence — needs a human call; have
  someone read the file's recent diffs before another pass.` `{N}`/`{churn_files}` come
  from step 1's own second stdout line (same source as `{round}`/`{prev}`/`{now}` above —
  no new variable, just don't drop the interpolation). (Neutral framing on WHY it's
  churning: a module that keeps generating findings may be fix-induced churn or a
  genuinely deep problem area — the file set alone can't tell which; but THAT it's
  fix-induced churn rather than a stalled-but-different problem is worth naming, since
  `stalled` gets its own distinct message below.)
- `stalled`: `{round} rounds — counts not moving across rounds, the remaining findings
  aren't responding to fixes. Needs a human call (accept as-is / wontfix the remainder /
  escalate), not another automatic pass.` This now fires uniformly whenever the
  convergence gate reads `stalled` — deliberately stricter than a passive suggestion a
  human could ignore: auto-continue must not advance past a state that isn't
  `progressing`, full stop, matching the ADR's literal continue condition.
- `ceiling`: `Round ceiling ({round}) reached with findings still open. Needs a human
  call (accept as-is / wontfix the remainder / escalate), not another automatic pass.`
- `reviewer-flow`: this is a PR-by-number review — auto-continue only applies to
  own-branch self-review (a reviewer can't act on someone else's diff). Fall back to the
  passive suggestion: `Round {round} on PR #{n} — Critical {prev}→{now} → re-run
  kbg:review-pr`, same as before this ADR.
- `missing-state` / `malformed-state` / `stale-sha` / `malformed-round` /
  `malformed-force-human` / `malformed-convergence-state` / `malformed-finding-files`:
  `should-continue-loop.sh detected a state-file integrity problem ({reason}) — a human
  should inspect $STATE_FILE directly before another round runs.` Don't auto-continue on
  any of these; they're fail-closed by design.
- `no-findings-nonclean`: `{round} rounds, review not clean but no Critical/Important
  findings were tracked this round — the convergence gate can't verify regression/churn
  without a file set to compare. Needs a human call before another automatic pass.`

Any non-`converged` reason above that blocks a merge does so via `/ship-merge`'s
Critical-findings/`force_human` scoring (0 → hits the 40 floor → STOP) — the human
decision is required before merge, not optional.

## Phase 6 — Code Findings Presentation Templates

Supplementary detail for `review-pr-finish/SKILL.md § Phase 6, step 1` — the exact templates and
their rationale for presenting code findings, moved here to keep `review-pr-finish/SKILL.md`
under the fleet's size threshold.

**Tier format:**

```markdown
# PR Review Summary

## Critical (X found) — must fix before merge
- [agent-name]: Issue description [file:line]

## Important (X found) — should fix before merge
- [agent-name]: Issue description [file:line]

## Minor (X found) — nice to have
- [agent-name]: Suggestion [file:line]
```

**Fix/Revisit-if must survive onto the tier-table line.** `agents/code-reviewer.md`'s per-issue
template (via `Skill(kbg:review-lens-code-quality)`) requires a `Fix:` and `Revisit if:` field at
authoring time — this is the artifact a user makes a fix-now/fix-later/ship call from, so those
fields (or a compressed equivalent, e.g. `Issue description [file:line] — fix: <short>, revisit
if: <short>`) must survive compression onto the line above, not just the bare description.

**Demoted findings.** A finding demoted by `kbg:review-pr-tier`'s Phase 5 step 3.5 verifier
carries its tag into whichever tier it landed in: `- [code-reviewer] [verifier-refuted,
confidence: 0.85]: Issue description [file:line]` — still visible, just at a lower tier, never
silently dropped.

**Zero-finding tiers.** List as `Critical: 0 ✅` (explicit green light — agents are issues-only by
frontmatter, so empty tier = clean signal, not "we forgot to check"). Carry step 3.6's provenance
onto the green light so the user stamps the code, not the summary — a bare `Critical: 0 ✅` is
exactly the rubber-stamp the verifier-separation principle warns about. Append the re-hunt
outcome: `Critical: 0 ✅ · adversarial re-hunt ran clean` (non-trivial diff, hunter found
nothing), `Critical: 0 ✅ · re-hunt skipped — trivial diff` (single non-test file), or `Critical:
0 — re-hunt did not return, verdict incomplete` (hunter errored/timed out; do not print an
all-clean verdict). If the checkpoint recorded any `dispatch_failures`, list them first and do
not print an all-clean verdict — `Dispatch: security-reviewer did not return — verdict
incomplete, do not treat as clean` — a non-returning agent blocks the green light regardless of
what the other agents found.

**Ledger trend.** After the tier table, surface a 1-line ledger trend (read `../review-pr/ledger.md`
§ Aggregation — rolling 10 sessions, computed by the awk helper in `../review-pr/policy.md`):

```markdown
**Trend (last 10 sessions)**: Q1: 12% (was 8%) — stable · Q2: 18% (was 22%) — improving · Q3: 67% (was 45%) — WORSENING · Q4: 8% (was 6%) — stable
```

A `WORSENING` flag means the policy is *eligible* to tighten the Q this session (see
`kbg:review-pr-tier`'s Phase 5 step 5). The user already saw the tightening note there; the trend
line here is the *delta* since the last session. If fewer than 5 sessions of history exist,
surface `insufficient data` instead of percentages.

## Phase 6 — Minor-only auto-proceed rationale (`ACS:minor-only-auto-proceed`)

Supplementary detail for `review-pr-finish/SKILL.md § Phase 6, step 2.A`.

This auto-proceed is the non-mutating default the skill's header names for the unattended case —
taken without asking only where the deterministic tier-count fully covers the decision. Important
findings stay human-gated even when Critical is 0: Important = "should fix before merge" (a real
but contained issue where fix-now-vs-defer is a judgment call the deterministic score does NOT
vouch for — `harness-decay-cadence.md:102`: "Automate past the point where you can still vouch
for the output and you ship agent slop"). The Critical/Important tier counts this auto-proceed
rests on are already independently verified by `kbg:review-pr-tier`'s Phase 5 step 3.5 fresh-agent
verifier, so they are not the maker's self-report.

## Requirement Analysis Presentation

Supplementary detail for `review-pr-finish/SKILL.md § Phase 6, step 1` — the opt-in
JIRA-ticket-quality presentation, moved here 2026-08-17 to keep `review-pr-finish/SKILL.md`
under the fleet's size threshold. Rarely-executed (only when Phase 1.5 ran, i.e. `JIRA_KEY` was
set) and template-shaped, so it costs nothing on the common path.

If `JIRA_KEY` was set (Phase 1.5 ran), present the ticket-quality report first, as its own
section before the code findings — never blended into the Critical/Important/Minor tiers (same
"don't blend across agents" principle as Phase 5 step 1; this is a report on the *ticket*, the
tiers below are about the *code*):

```markdown
## Requirement Analysis — TP-871 (verdict: <verdict>)
- Business trace: <business_trace, or "not stated — flagged as gap">
- Ambiguities: <count> — <one line each, or "none">
- Bundled requirements: <count> — <one line each, or "none">
- Open questions: <count> — <one line each, or "none">
```

If `JIRA_FETCH_FAILED`, show `## Requirement Analysis — <key> — fetch failed, cross-check
skipped` instead and continue with the ordinary code review. **Skip this sub-step entirely
when `JIRA_KEY` is unset** — go straight to presenting code findings.

**Terminal-only — never part of the posted review body.** This section critiques the *ticket*
(ambiguities, open questions, bundling); posting a critique of someone else's ticket onto their
PR is out of scope for a code review, and this repo is public, so ticket content (names,
internal detail) landing in a public GitHub comment is a real consequence, not a hypothetical.
Phase 7's review-body construction starts from the code findings only — this section never
feeds it, on either review target. **This constraint is safety-load-bearing and is repeated
inline in `review-pr-finish/SKILL.md` itself, not left as a lazy-loaded fact only visible here**
— it must survive on the common path even if this reference file is never read.

## Build the Review Payload

Supplementary detail for `review-pr-finish/SKILL.md § Phase 7, step 3 (Submit the review to GitHub)`.

   **Build the review payload** (canonical procedure — Phase 6 branch B builds its preview from this):
   - **Event**: `REQUEST_CHANGES` if any Critical findings, `COMMENT` if only Important/Minor, `APPROVE` if zero findings.
   - **Review body**: The Phase 6 summary's tier table + trend + proof-check (top-level overview) — **excludes** the Requirement Analysis section (ticket ambiguities/open questions). That section critiques the ticket, not the diff, and is terminal-only (Phase 6 step 1) — it never goes into a posted GitHub body on either review target.
   - **Comments array**: For every finding that has `file` + `line`, create:
     ```json
     {"path": "<file-path>", "line": <line-number>, "side": "RIGHT", "body": "[<severity>] <message>"}
     ```
     Findings without file:line go into the review body instead.

     `<message>` must be built from the Review Comment Templates section below (Impact +
     Recommendation), never the bare tier-table description — a posted GitHub comment is
     effectively permanent, so the author needs the causal content, not just the claim.

   **Two entry points — the gate is never asked twice:**
   - **Reviewer flow (PR #N):** the submit decision (preview + prior-review check + choice) already happened in **Phase 6 branch B**. **Do not re-ask.** Execute the recorded choice: *Post line-level* → JSON + `gh api` (below); *Post summary only* → single `gh pr review --body`; *Fix + push* → already applied/pushed in Phase 6, nothing to post; *Skip* → nothing to post.
   - **Author flow (current branch):** Phase 6 was a fix decision, so offer submit **here**, only if a PR exists for the branch. **Prior-review check**: `gh pr view <#> --json reviews -q ".reviews[].author.login"` vs `gh api user -q .login`; if you already reviewed, warn that GitHub stacks new reviews. **Preview** event type + comment count + 2–3 samples + body, then **AskUserQuestion** single-select: `Post line-level review now` / `Post summary only` / `Skip — post manually`. If no PR exists yet, skip (nothing to submit to).

   **If posting line-level comments**, build JSON (`commit_id: $HEAD_SHA`, `event`, `body`, `comments[]`) and submit:
   ```bash
   python3 -c "import json,sys; print(json.dumps({'commit_id':sys.argv[1],'event':sys.argv[2],'body':sys.argv[3],'comments':json.loads(sys.argv[4])}))" \
     "$HEAD_SHA" "$EVENT" "$REVIEW_BODY" "$COMMENTS_JSON" \
     | gh api repos/{owner}/{repo}/pulls/<n>/reviews --method POST --input -
   ```
   `<#>` = target PR number, or current branch's PR (`gh pr view --json number -q .number`). If no PR exists yet, skip (nothing to submit to).

## Integration Notes — full detail

Supplementary detail for `review-pr/SKILL.md`, `review-pr-tier/SKILL.md`, and `review-pr-finish/SKILL.md`'s Integration Notes sections (spans all three — phases named per bullet below).

- **Token budget**: Each agent review fits 4K task / 30K session budget. Parallel mode (Phase 4 default) is fastest; sequential is available for interactive sessions that need lower cognitive load. Phase 5 step 3.5's verifier dispatches are additional — one fresh agent per unique Critical/Important finding, so a review with several such findings roughly doubles total dispatches for that session. Phase 5 step 3.6 fires only on the zero-surviving-findings path with a non-trivial diff — one hunter dispatch, plus one 3.5-style refuter for each Critical/Important finding the hunter raises (usually zero). So the zero-findings path costs 1 + N dispatches where N is small; the several-findings path costs 3.5's ~one-per-finding. They're near-exclusive by trigger (3.6 only when nothing survived 3.5), so a single review never pays both at full volume. Phase 1.5 (opt-in, only when `JIRA_KEY` is detected) adds one `jira-acli:acli` fetch + one `requirement-analyst` dispatch, flat cost regardless of diff size — negligible next to the per-finding verifier cost above.
- **Agent teams**: Not recommended for PR review — latency too high for a task that needs quick iteration.
- **Default-branch resolution** (Phase 2, current-branch path): `skills/pr/scripts/resolve-default-branch.sh` is the canonical way to find the default branch — never assume `develop`. Extracted 2026-08-15, shared with `skills/pr/SKILL.md`'s own hotfix-guard resolution, including a fallback chain a pre-extraction copy of this logic had omitted.
- **Hooks active**: `hooks/gates/verifier-protect.sh` asks for approval on edits to the gate/audit verifier surfaces during the session; it does not cover CLAUDE.md/METHODOLOGY.md directly. There is no dedicated secret-scanning hook today.
- **GH CLI**: Use `gh pr view` to check PR state before launching review. `review-pr` reviews code, not CI status — plenty of repos have no CI wired up at all, so this skill never checks or gates on `gh pr checks` (that belongs to `/ship-merge`'s own required-checks gate, which only runs against repos that actually have branch protection configured). Reviewing by number fetches `pull/<#>/head` into a throwaway `git worktree` (removed in Phase 7). Submitting the review uses `gh api repos/{owner}/{repo}/pulls/<n>/reviews` with a JSON payload containing `commit_id`, `event`, `body`, and `comments[]` — posting findings as individual line-level comments. "Summary only" fallback uses `gh pr review --comment/--request-changes/--approve`. Both paths are gated on user confirmation (requires `Bash(gh api ...)` allow in settings.json).
- **Review routing reference**: Code that touches auth/secrets → `security-reviewer`'s fast in-review flag (Phase 3); a deeper standalone threat-model audit is `kbg:security-auditor`, run directly when the diff warrants one. General code → code-reviewer, plus `typescript-reviewer` / `python-reviewer` when that language dominates the changed files (Phase 3). Tests, comments, types, db → code-reviewer with its behavioral test-coverage / comment-accuracy / type-design / DB-query-safety lens. A detected Jira ticket → `requirement-analyst` (Phase 1.5, ticket-quality report) + code-reviewer's requirement-coverage lens (Phase 3/4, diff-vs-requirements). Error handling → silent-failure-hunter. Polish → native `/simplify` with clarity-only scope (post-review opt-in, **not** part of kbg:review-pr).
- **Severity tier rubric** (Phase 5): Critical / Important / Minor are canonical across `/ship`, `/fix-bug`, and `kbg:review-pr`.
- **SCRUTINIZE-4 rubric** (Phase 5): Challenge intent / Trace call graph / Verify execution branches / Evidence requirement. Named + tabular (4 falsifiable checks) so the gate is a yes/no per finding, not prose that gets skipped — the prose version of this gate was skipped in real runs because it was exhausting; naming the checks turns "did I scrutinize?" from a vibe into a per-finding yes/no. Dropped findings go to `.scratch/review-pr-<UTC-timestamp>/rejected.md` (ephemeral audit log, not an `issue.md`) with a per-question tally surfaced to the user — the reject-and-log path means dropping a finding is *auditable* (vs. an agent's confidence-threshold, which is invisible). **Q3's test-reach precedent**: the tathep `compliance-audit-round-2` gap — a CRITICAL hid through 9 review rounds because no test exercised the defeating state-transition, so every pass read "code path covered" as "safe" while the transition that actually defeated the fix was never reached. That's why Q3 requires noting test-reach per branch, not just tracing the branch.
- **Rejection-rate ledger** (Phase 5+6): per-session per-Q counters written to `ledger.md` (sibling of `rejected.md`). Rolling 10-session window drives a 1-line trend + tightening eligibility. Spec: `ledger.md`. Policy (threshold, tightening action, hard caps, reversibility, awk aggregation helper): `policy.md`. Cap: 200 sessions FIFO, 1 tightening per Q per 90 days, 1 tightening per session max.

## Tips

- **Run early**: Before creating PR, not after
- **Focus on changes**: Phase 2's pinned window makes this concrete
- **Address Critical first**: Phase 6's tier prioritization is the gate
- **Re-run after fixes**: Verify issues are resolved (new HEAD_SHA = fresh window)
- **Use specific aspects**: Target specific reviewers when you know the concern (e.g., kbg:review-pr errors after touching exception handling)
- **Cheap review, not a weaker one**: `kbg:review-pr <n> code` is the answer to "review this but keep it cheap" — it narrows to `code-reviewer`'s general-quality lens (plus a language specialist when one applies), taking the median run from ~4 dispatches to ~2. It's a narrowing, not a weakening: the mandatory general-quality lens still runs, unlike an improvised skip.

## Workflow Integration

Phase 2 pins a committed range (`BASE_SHA..HEAD_SHA`) and Phase 4 hands agents exactly that range — there's no uncommitted-diff mode. Review after you commit (even a WIP commit), not before.

**Before creating PR:**
```
1. Stage all changes
2. Run: kbg:review-pr all
3. Address all Critical and Important findings
4. Run specific reviews again to verify (Phase 2 pins new window)
5. Create PR
```

**After PR feedback:**
```
1. Use /address-review for reviewer threads (not kbg:review-pr — that's for YOUR review of the diff)
2. Make requested changes (delegate bug-shaped to /fix-bug per /address-review Phase 4)
3. Verify issues are resolved
4. Push updates
```

---

## Review Comment Templates (Reviewer → Author)

Loaded when the skill is invoked; not part of the session prefix cache. Use as starting points — adapt to context.

### Structure
Every review comment should contain:
1. **Observation** — what you see (`file:line` reference)
2. **Impact** — why it matters (bug? security? maintainability?)
3. **Recommendation** — concrete fix or alternatives
4. **Falsifying fact** (judgment calls only — skip on objective bugs) — the one fact that would
   change this recommendation, e.g. "if this endpoint has no external caller, this isn't a
   breaking change"

### Code citation
- **Terminal/local review output, and line-level GitHub comments** — the `gh api …/pulls/<n>/reviews`
  path anchors each comment at `path`+`line` already, so a bare `file:line` is enough; a permalink there is redundant.
- **Summary-only comments and any cross-reference to *other* code** (a line the comment is not anchored
  to — e.g. "similar handling exists at …") — cite a **full-SHA permalink** so it renders and links:
  `https://github.com/<owner>/<repo>/blob/<full-sha>/<path>#L<start>-L<end>`, centered with ≥1 line of context.
  Two gotchas (both silently break the link): a bare `file:line` does **not** hyperlink in posted markdown,
  and `blob/$(git rev-parse HEAD)/…` does **not** render — the shell isn't evaluated in a posted comment, so
  resolve `git rev-parse HEAD` first and paste the literal SHA. (Convention: Anthropic's official `code-review` plugin.)

### Templates by category

**Bug / Correctness**
> This will [fail / behave incorrectly] when [condition] because [mechanism].
> [Concrete fix or reference to similar handling elsewhere].

**Style / Convention**
> Doesn't match [convention] used in [file/scope]. This project uses [pattern]; follow that.

**Architecture / Design**
> [Concern] because [reason]. Consider [alternative A] or [alternative B]. Trade-off: A gives [X] but costs [Y].

**Security**
> [Vulnerability] — [OWASP category if applicable]. Impact: [what goes wrong]. Fix: [concrete recommendation].

**Nit / Optional**
> Optional: [suggestion]. Not blocking.

### Anti-patterns (reviewer)

| Don't write | Why | Write instead |
|---|---|---|
| "Great catch!" / "Good point!" | Performative agreement wastes reader time | Skip ceremony; state observation directly |
| "I think maybe this could be..." | Hedge language signals low confidence | State observation plainly or skip |
| "This is wrong" (without why) | Author can't learn or fix | Add "because..." + concrete alternative |
| "Just do X" | Dismissive; may miss context | "Consider X — here's why it fits..." |

---

## Reply Comment Templates (Author → Reviewer)

Phase 5 of `/address-review` requires every thread gets a reply. Use these as starting points.

### Fixed
```
Fixed in `<short-sha>`: [one-line change summary].
[Optional: reason why this fix is correct / what changed].
```

### Wontfix
```
[Rationale in 1-3 sentences].
This is [intentional / out of scope for this PR / addressed in <other-place>] because [reason].
[Revisit if: <the fact or event that would reopen this — even a permanent design call names
what would change it>].
```

### Clarify
```
[Specific question]. I'm not sure I understand [aspect] — could you clarify [specific thing]?
```

### Out-of-scope
```
Tracked as #<issue-number>. Out of scope for this PR — [reason]. Will pick up in follow-up.
```

### Blending a sha into Wontfix / Clarify

The Wontfix and Clarify shapes aren't mutually exclusive with citing a sha. If a commit landed and genuinely fixed part of the concern before the cluster stalled or got reclassified (e.g. `/address-review` Phase 4 step 3's one-retry-then-stop), lead with the Fixed template's sha + one-line summary, then follow with the full Wontfix or Clarify body — don't drop the citation, and don't abbreviate the body, just because the category ended up Wontfix/Clarify instead of Fixed:
```
Fixed in `<short-sha>`: [what that commit changed].
[Rationale in 1-3 sentences].
This is [intentional / out of scope for this PR / addressed in <other-place>] because [reason].
[Revisit if: <the fact or event that would reopen this>].
```
(Clarify blends the same way — swap the "This is... because..." and "Revisit if" lines for
Clarify's `[Specific question]. I'm not sure I understand [aspect]...` line.)

### Anti-patterns (author)

- **Performative agreement** — "Great catch!" / "You're absolutely right!" / "Good point, thanks!" violates technical rigor. The sha citation + one-line change summary IS the acknowledgment.
- **Silent push** — pushing fix commits without replying. Reviewer has to re-read the diff to find what changed.
- **Defensive tone** — "Actually..." / "But the spec says..." triggers adversarial loops. State the rationale plainly, cite evidence, move on.
