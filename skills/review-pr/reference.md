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
| native `/simplify` (post-review polish, **not** a reviewer) | Clarity/readability refactor without behavior change |

## Phase 5 step 3.6 — standalone form

Supplementary detail for `SKILL.md § Phase 5, step 3.6 (Zero-findings adversarial re-hunt)`.

The standalone, dispatchable form of this exact discipline — usable outside a review-pr run, e.g.
on a self-authored delta mid-session — is `agents/blind-spot-hunter.md`, which also carries the
enriched hunt-shape checklist. Step 3.6 still dispatches an inline-framed `general-purpose` agent
rather than the named agent — keep the two in sync until a follow-up single-sources them by having
3.6 dispatch `blind-spot-hunter` directly.

## Integration Notes — full detail

Supplementary detail for `SKILL.md § Integration Notes (Project-Specific)`.

- **Token budget**: Each agent review fits 4K task / 30K session budget. Parallel mode (Phase 4 default) is fastest; sequential is available for interactive sessions that need lower cognitive load. Phase 5 step 3.5's verifier dispatches are additional — one fresh agent per unique Critical/Important finding, so a review with several such findings roughly doubles total dispatches for that session. Phase 5 step 3.6 fires only on the zero-surviving-findings path with a non-trivial diff — one hunter dispatch, plus one 3.5-style refuter for each Critical/Important finding the hunter raises (usually zero). So the zero-findings path costs 1 + N dispatches where N is small; the several-findings path costs 3.5's ~one-per-finding. They're near-exclusive by trigger (3.6 only when nothing survived 3.5), so a single review never pays both at full volume. Phase 1.5 (opt-in, only when `JIRA_KEY` is detected) adds one `jira-acli:acli` fetch + one `requirement-analyst` dispatch, flat cost regardless of diff size — negligible next to the per-finding verifier cost above.
- **Agent teams**: Not recommended for PR review — latency too high for a task that needs quick iteration.
- **Hooks active**: `hooks/gates/verifier-protect.sh` asks for approval on edits to the gate/audit verifier surfaces during the session; it does not cover CLAUDE.md/METHODOLOGY.md directly. There is no dedicated secret-scanning hook today.
- **GH CLI**: Use `gh pr view` to check PR state before launching review. `review-pr` reviews code, not CI status — plenty of repos have no CI wired up at all, so this skill never checks or gates on `gh pr checks` (that belongs to `/ship-merge`'s own required-checks gate, which only runs against repos that actually have branch protection configured). Reviewing by number fetches `pull/<#>/head` into a throwaway `git worktree` (removed in Phase 7). Submitting the review uses `gh api repos/{owner}/{repo}/pulls/<n>/reviews` with a JSON payload containing `commit_id`, `event`, `body`, and `comments[]` — posting findings as individual line-level comments. "Summary only" fallback uses `gh pr review --comment/--request-changes/--approve`. Both paths are gated on user confirmation (requires `Bash(gh api ...)` allow in settings.json).
- **Review routing reference**: Code that touches auth/secrets → `kbg:security-auditor` for full audit. General code → code-reviewer, plus `typescript-reviewer` / `python-reviewer` when that language dominates the changed files (Phase 3). Tests, comments, types, db → code-reviewer with its behavioral test-coverage / comment-accuracy / type-design / DB-query-safety lens. A detected Jira ticket → `requirement-analyst` (Phase 1.5, ticket-quality report) + code-reviewer's requirement-coverage lens (Phase 3/4, diff-vs-requirements). Error handling → silent-failure-hunter. Polish → native `/simplify` with clarity-only scope (post-review opt-in, **not** part of kbg:review-pr).
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
```
(Clarify blends the same way — swap the last two lines for Clarify's `[Specific question]. I'm not sure I understand [aspect]...` line.)

### Anti-patterns (author)

- **Performative agreement** — "Great catch!" / "You're absolutely right!" / "Good point, thanks!" violates technical rigor. The sha citation + one-line change summary IS the acknowledgment.
- **Silent push** — pushing fix commits without replying. Reviewer has to re-read the diff to find what changed.
- **Defensive tone** — "Actually..." / "But the spec says..." triggers adversarial loops. State the rationale plainly, cite evidence, move on.
