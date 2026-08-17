# review-pr Reference

Static lookup tables for kbg:review-pr skill. Loaded on-demand when the skill is invoked; not part of the session prefix cache.

---

## Review Aspects Reference

| Aspect arg | Routes to | Notes |
|---|---|---|
| `code` | `code-reviewer` (general-quality lens), plus a language specialist if the dominant changed-file language matches one (see Agent Descriptions) | general quality pass, doesn't include test / security / etc |
| `tests` | `code-reviewer` (behavioral test-coverage lens) | only if test files changed (Phase 3 condition) |
| `comments` | `code-reviewer` (comment-accuracy lens) | only if docs/comments added |
| `errors` | `silent-failure-hunter` | only if error handling changed |
| `security` | `security-reviewer` | only if auth/secrets/input touched |
| `types` | `code-reviewer` (type-design lens) | only if types/interfaces/DTOs/schemas/models changed |
| `db` | `code-reviewer` (DB/SQL query-safety lens) | only if migrations/schema/query files changed (`.sql`, Drizzle schema, or query-builder calls) |
| `simplify` | NOT a reviewer | run native `/simplify` (clarity-only) separately after review decisions land (Phase 7 next-step) |
| `all` | every applicable agent per Phase 3 routing | default if no aspect arg |
| *(not an aspect arg — detected from a Jira ticket reference)* | `requirement-analyst` (Phase 1.5) + `code-reviewer` (requirement-coverage lens) | fires on `jira` keyword + a ticket-key-shaped token anywhere in the prompt (e.g. "review #2606 with jira TP-871"), regardless of aspect narrowing |

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

**Sync seam:** `agents/code-reviewer.md`'s own Fowler section carries 11 of these 12 — it deliberately omits Duplicated Code (and Long Method) because its checklist already covers them elsewhere under different names ("Duplicated helper/util", "Large functions"). That's a legitimate per-file difference, not drift — if you edit one table, check whether the other needs the matching edit or is correctly diverging on purpose.

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

## Phase 5 step 3.6 — standalone form

Supplementary detail for `SKILL.md § Phase 5, step 3.6 (Zero-findings adversarial re-hunt)`.

The standalone, dispatchable form of this exact discipline — usable outside a review-pr run, e.g.
on a self-authored delta mid-session — is `agents/blind-spot-hunter.md`, which also carries the
enriched hunt-shape checklist. Step 3.6 now dispatches `blind-spot-hunter` directly (fixed
2026-08-09 — it previously dispatched an inline-framed `general-purpose` agent instead, the gap
this note used to track).

## write-review-state.sh — Field Contract & Amend Mode

Supplementary detail for `SKILL.md § Phase 7, step 1 (write-review-state.sh)`.

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

## Loop Reason Stop Messages

Supplementary detail for `SKILL.md § Phase 7, step 2` — the per-`$LOOP_REASON` message text
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

## Build the Review Payload

Supplementary detail for `SKILL.md § Phase 7, step 3 (Submit the review to GitHub)`.

   **Build the review payload** (canonical procedure — Phase 6 branch B builds its preview from this):
   - **Event**: `REQUEST_CHANGES` if any Critical findings, `COMMENT` if only Important/Minor, `APPROVE` if zero findings.
   - **Review body**: The Phase 6 summary's tier table + trend + proof-check (top-level overview) — **excludes** the Requirement Analysis section (ticket ambiguities/open questions). That section critiques the ticket, not the diff, and is terminal-only (Phase 6 step 1) — it never goes into a posted GitHub body on either review target.
   - **Comments array**: For every finding that has `file` + `line`, create:
     ```json
     {"path": "<file-path>", "line": <line-number>, "side": "RIGHT", "body": "[<severity>] <message>"}
     ```
     Findings without file:line go into the review body instead.

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

Supplementary detail for `SKILL.md § Integration Notes (Project-Specific)`.

- **Token budget**: Each agent review fits 4K task / 30K session budget. Parallel mode (Phase 4 default) is fastest; sequential is available for interactive sessions that need lower cognitive load. Phase 5 step 3.5's verifier dispatches are additional — one fresh agent per unique Critical/Important finding, so a review with several such findings roughly doubles total dispatches for that session. Phase 5 step 3.6 fires only on the zero-surviving-findings path with a non-trivial diff — one hunter dispatch, plus one 3.5-style refuter for each Critical/Important finding the hunter raises (usually zero). So the zero-findings path costs 1 + N dispatches where N is small; the several-findings path costs 3.5's ~one-per-finding. They're near-exclusive by trigger (3.6 only when nothing survived 3.5), so a single review never pays both at full volume. Phase 1.5 (opt-in, only when `JIRA_KEY` is detected) adds one `jira-acli:acli` fetch + one `requirement-analyst` dispatch, flat cost regardless of diff size — negligible next to the per-finding verifier cost above.
- **Agent teams**: Not recommended for PR review — latency too high for a task that needs quick iteration.
- **Hooks active**: `hooks/gates/verifier-protect.sh` asks for approval on edits to the gate/audit verifier surfaces during the session; it does not cover CLAUDE.md/METHODOLOGY.md directly. There is no dedicated secret-scanning hook today.
- **GH CLI**: Use `gh pr view` to check PR state before launching review. `review-pr` reviews code, not CI status — plenty of repos have no CI wired up at all, so this skill never checks or gates on `gh pr checks` (that belongs to `/ship-merge`'s own required-checks gate, which only runs against repos that actually have branch protection configured). Reviewing by number fetches `pull/<#>/head` into a throwaway `git worktree` (removed in Phase 7). Submitting the review uses `gh api repos/{owner}/{repo}/pulls/<n>/reviews` with a JSON payload containing `commit_id`, `event`, `body`, and `comments[]` — posting findings as individual line-level comments. "Summary only" fallback uses `gh pr review --comment/--request-changes/--approve`. Both paths are gated on user confirmation (requires `Bash(gh api ...)` allow in settings.json).
- **Review routing reference**: Code that touches auth/secrets → `security-reviewer`'s fast in-review flag (Phase 3); a deeper standalone threat-model audit is `kbg:security-auditor`, run directly when the diff warrants one. General code → code-reviewer, plus `typescript-reviewer` / `python-reviewer` when that language dominates the changed files (Phase 3). Tests, comments, types, db → code-reviewer with its behavioral test-coverage / comment-accuracy / type-design / DB-query-safety lens. A detected Jira ticket → `requirement-analyst` (Phase 1.5, ticket-quality report) + code-reviewer's requirement-coverage lens (Phase 3/4, diff-vs-requirements). Error handling → silent-failure-hunter. Polish → native `/simplify` with clarity-only scope (post-review opt-in, **not** part of kbg:review-pr).
- **Severity tier rubric** (Phase 5): Critical / Important / Minor are canonical across `/ship`, `/fix-bug`, and `kbg:review-pr`.
- **SCRUTINIZE-4 rubric** (Phase 5): Challenge intent / Trace call graph / Verify execution branches / Evidence requirement. Named + tabular (4 falsifiable checks) so the gate is a yes/no per finding, not prose that gets skipped. Dropped findings go to `.scratch/review-pr-<UTC-timestamp>/rejected.md` (ephemeral audit log, not an `issue.md`) with a per-question tally surfaced to the user.
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
