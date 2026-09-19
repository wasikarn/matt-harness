# "The AI-Native SDLC playbook" (Anthropic, Louis Claxton) vs matt-harness

**Date:** 2026-08-28
**Source:** https://claude.com/blog/the-ai-native-sdlc-playbook
**Verdict (superseded — see Round 2 below):** ~~Mostly *confirms* architecture matt-harness
already shipped. One active conflict (not a gap — already litigated). Two optional, non-urgent
candidates named for the user to decide; nothing built.~~ Round 1 (this section) was a
single-pass audit and overstated several "already covered" claims. A same-day 4-agent deep
re-pass (below) found two independently-corroborated hook regressions and corrected the
Stage-6 framing to be starker, not narrower. Read Round 2 first.

## Method

Anthropic's own Applied AI playbook, six SDLC stages (Plan/Design/Build/Test/Deploy/Maintain),
each with a committed `.md` artifact and a named play. Mapped each play against matt-harness's
actual mechanisms (verified against source this session — not assumed from prior memory) and
against the ADR history in `docs/research/`.

## Stage-by-stage mapping

| Playbook stage/play | matt-harness equivalent | Status |
|---|---|---|
| **Plan** — `intent.md`, brainstorm-with-Claude | `hooks/advisory/flow-nudge.sh`'s chain: `grilling` (bare, model-tier) | Already covered — grilling *is* the intent-capture play, just not written to a committed file by convention |
| **Design** — `spec.md`, requirements+design in one session, guided by skills | `/to-spec` (same chain) | Already covered |
| **Build** — plan mode as default start, `plan.md`, CLAUDE.md, skills as institutional knowledge, hooks as build-time guardrails, parallel sessions/subagents | Claude Code plan mode (used natively all session, e.g. the diagram-overhaul plan just shipped), `CLAUDE.md` (this repo's own, extensively iterated), `hooks/gates/*` (deny) + `hooks/advisory/*` (journal), `Agent` tool + `git worktree add -b` convention | Already covered, more formalized than the playbook's version — mh's gate/advise split (CLAUDE.md's "unifying crux") is a stricter doctrine than the playbook's plain "allow/ask/block" |
| **Test** — feedback loop, continuous evals in CI | TDD-required-for-bugfix rule, `scripts/run-gauntlet.sh` (6 parallel layers) | Feedback loop: covered. Continuous evals-in-CI on agent-config change: **not currently present** — see Candidate 1 below |
| **Deploy** — AI in PR review loop, `REVIEW.md` w/ severity caps, hooks as approval gates | `contexts/review.md` (near-identical shape: Critical/Important/Minor triage, file:line + fix, no hedging), `mattpocock-skills:code-review` (full pipeline), `skills/review/risk-check` (LOW/MED/HIGH scoping, advisory-only), `skills/review/address-review` (reply-to-reviewer loop), `skills/*/ship-merge` (gated merge, `disable-model-invocation`) | Already covered, and more separated: review / risk-scope / address / merge are four distinct gated skills, not one blended loop |
| **Maintain** — autonomous headless invocation on a control-band breach, confidence gates between stages, `bands.yaml` | The retired L2–L5 autonomy ladder | **Active conflict, not agreement** — see below |

## The one real conflict: Stage 6 "Maintain" is the retired ladder

The playbook's Stage 6 — a deterministic trigger invokes Claude with no human in the loop,
Claude diagnoses and acts up to a gate, output re-enters the pipeline as a new `intent.md` — is
structurally the same shape as mh's own L2–L5 autonomy ladder, retired by **ADR 0006**
(`docs/reference/env-vars.md:26`, `docs/harness-decay-cadence.md:242`, reconfirmed 5+ times per
`docs/research/loop-graph-engineering-trend-audit-2026-08-02.md` and 9+ other articles this repo
already checked it against). This isn't new information arriving — it's the same proposal this
repo already tested, found unreliable in exactly this form, and walked back.

The one narrow exception: **ADR 0009** (`docs/research/adr-0009-bounded-review-fix-auto-loop.md`)
re-armed a *bounded* slice of this — per-round human-gated auto-continue for a review→fix loop,
explicitly *not* the ladder's structural definition (no flag, no notches, no self-launch, no
OS-scheduler trigger). The playbook's `bands.yaml` / 1σ-2σ-3σ pattern goes further than even
ADR 0009 permits (autonomous *trigger*, not just autonomous *continue* within an already-started
session) — and it's aimed at a deployed service's live production metrics, which matt-harness
(a plugin/skill repo, not a deployed service) doesn't have. **No build from this stage.**

## Candidates named, not built

**1. Config-change-triggered regression evals.** The playbook's CI job (`.github/workflows/
agent-evals.yml`, runs on `CLAUDE.md`/`.claude/**` diffs) is narrower than what mh deleted —
the removed 204-test suite was bound up with L3/L4/L5 autonomy-machinery testing per
`CLAUDE.md`'s Validation section, not a generic "did this skill edit regress behavior" check.
Worth a look if skill/hook edits ever start regressing silently; not urgent — no such incident
on record.

**2. Reusable release-gate hook template.** The playbook's `production-gate.sh` (block a
`deploy...production` Bash command without `$RELEASE_APPROVAL` set) is a clean pattern for a
downstream project *with* a deploy stage. matt-harness itself has none — no build here, but
worth keeping as a pointer if a future skill ever needs to hand a consuming project a
starter hook.

## What's already stronger than the playbook describes

- The gate/advise split (`docs/reference/operating-model.md`) is a harder invariant than the
  playbook's "hooks can allow/ask/block" — mh's own doctrine forbids a model ever grading its
  own gate (maker≠checker), which the playbook doesn't address at all.
- Review is four separably-gated skills (`code-review` / `risk-check` / `address-review` /
  `ship-merge`), not one blended "Claude reviews and fixes" loop — each irreversible step
  (`ship-merge`, `address-review`) individually carries `disable-model-invocation`.

---

## Round 2 — 4-agent deep re-analysis (same day, corrected verdict)

**Method:** 4 independent fresh-context agents, one per stage cluster (Plan+Design /
Build+Test / Deploy / Maintain+measurement), each re-read the article and re-derived evidence
from source directly — instructed to check Round 1's claims last, not lean on them. Two
findings were corroborated independently by different agents working different scopes, which is
the strongest confidence signal this doc has.

**Corrected verdict:** Round 1 was too generous. Several "already covered" rows described the
*doctrine* mh states about itself rather than what's actually wired. The real picture: mh's
design intentions are frequently ahead of matt-harness's own enforcement of them — a pattern
that shows up three separate times below.

### Corroborated finding: retired hooks, never replaced (2 independent hits)

The same 2026-08-24 commit (`b31eaa13`, "retire the review pipeline, route to
mattpocock-skills:code-review") removed two different enforcement mechanisms and replaced
neither:

- **`gh pr merge` has no hook anymore.** `convergence-merge-gate.sh` used to intercept raw
  `gh pr merge` outside the `ship-merge` skill flow. It's gone, and `skills/workflow/ship-merge/
  SKILL.md:53` says so in its own words: "this command's in-flow gates are now the only
  merge-door protection." No `PreToolUse` hook matches `gh pr merge` today — `disable-model-invocation`
  on `ship-merge` blocks the *Skill tool call*, not a raw Bash merge. This is a real regression
  against the article's own worked example (`production-gate.sh`, a hard unbypassable block) —
  mh's merge door is currently *less* hook-enforced than the pattern it's being compared to.
- **The ADR 0009 bounded auto-loop is dead code.** Round 1 cited it as a live, narrow exception
  to ADR 0006. It isn't, as of the same commit: `should-continue-loop.sh` / `write-review-state.sh`
  no longer exist anywhere in the tree, and `~/.local/share/kbg/metrics/review-pr-loop-gate.jsonl`
  has exactly 3 rows, all from before the retirement, none since. **The Stage 6 gap vs. the
  article is starker than Round 1 stated, not narrower** — matt-harness currently has zero live
  auto-continue loop machinery of any kind, bounded or not.

Both losses trace to the same commit and the same cause: retiring a subsystem removed its
enforcement without a replacement being scoped in the same change. Worth naming as a pattern,
not just two isolated facts.

### New confirmed gaps (not in Round 1 at all)

| Finding | Evidence | Article claim it contradicts |
|---|---|---|
| Gates log no verdict anywhere | `grep -rl "jsonl\|metrics" hooks/gates/` → zero hits across all 9+ gates | "Every hook decision is written to the OpenTelemetry export with a timestamp and an allow or block verdict" (Deploy, Hooks as approval gates) — mh cannot currently answer "how often did gate X block" |
| Test-file-edit protection during a bugfix is prose-only | `docs/METHODOLOGY.md` Rule 4 has no backing hook/gate/audit-check anywhere in `hooks/` or `skills/meta/harness-audit/scripts/checks/` | Article step 4/7 (Test): "a hook that blocks edits to test files during a fix task" — self-inconsistent with mh's own maker≠checker doctrine, since this is exactly the "same role grades its own work" case that doctrine argues against |
| Formatter/linter-after-edit and credential-in-diff hooks don't exist | No `PostToolUse` hook matches `Write\|Edit`; `credential-guard.sh` blocks *reading* known secret paths, not scanning `Write`/`Edit` content for secret-shaped strings | Article's build-guardrail play names both explicitly |
| mh doesn't use worktree-per-session isolation, contra Round 1's framing | `CLAUDE.md`'s own "Concurrent sessions" section: "no worktree design... There's no isolation to fall back on, so discipline substitutes for it"; `irrecoverable.sh`'s gate blocks *creating new branches*, and by its own documentation doesn't even cover the native `claude --worktree` flag the article recommends | Article's parallel-sessions play assumes `claude --worktree <name>` per task |
| `contexts/review.md` isn't a REVIEW.md match — it says so itself | `contexts/review.md:25-27`: "lighter posture for ad hoc review conversation... load `mattpocock-skills:code-review` instead of hand-replicating its pipeline" | Round 1 called this "near-identical shape" — wrong comparison target |
| Real review pipeline can't do what the article claims | `mattpocock-skills:code-review/SKILL.md:76`: "Do not merge or rerank findings, because the two axes are deliberately separate"; no automated trigger fires any review on PR open (`.github/workflows/` has only plugin-validate) | "All PRs get an identical set of review passes, with findings ranked by severity" — mh's coverage is developer-remembered, not uniform, and one of its three review surfaces explicitly refuses cross-axis ranking |
| `costs.jsonl` has a schema break (pre/post 2026-08-07) | `skills/meta/cost-report/SKILL.md` itself warns never to read a pre/post difference as a spending change | Breaks the article's trend-based lagging-indicator pattern for mh's own longest-running metric |

### Corrections to Round 1's specific claims

- **"Already covered — grilling *is* the intent-capture play, just not written to a file by
  convention"** (Plan row) — understated. There's no committed artifact, no product-owner
  accept/reject gate recorded as a merge, and neither of the article's two intent-stage metrics
  are derivable. Sharper finding: matt-pocock's own `ask-matt` routing already prefers
  `grill-with-docs` (stateful, writes `CONTEXT.md`/ADRs) over bare `grilling` for exactly this
  reason, and it's installed in the plugin cache — `flow-nudge.sh` just doesn't point to it. A
  missing pointer, not a missing capability.
- **"Already covered, more formalized... hooks as build-time guardrails"** (Build row) —
  overstated; see the guardrail-gaps row in the table above.
- **"Not currently present... narrower than what mh deleted... bound up with L3/L4/L5
  autonomy-machinery testing"** (Test row, Candidate 1) — the "narrower" framing doesn't hold up.
  The actual deleted `eval/` directory (`git show c452102 --stat`) was mostly general skill/hook
  regression tests; only 2-3 of ~17 regression files were autonomy-specific. It was lost as
  collateral in a full-repo reset for an unrelated rebuild, not a considered rejection of
  CI-gated evals. `skills/meta/eval-harness/SKILL.md` still exists today as an honest
  "prose-only... no CI job enforces it" design doc — the capability was designed for, then never
  wired, not walked back on purpose.
- **"Already covered, and more separated"** (Deploy row) — the four-skills-not-one-loop
  structure is real, but "identical passes... ranked by severity" and "near-identical shape" to
  REVIEW.md are both overstated per the table above.
- **"The one narrow exception: ADR 0009"** (Maintain section) — dead code as of `b31eaa13`, see
  the corroborated finding above. Also a secondary framing fix: ADR 0009's own text draws a
  categorical wall at self-launch, not a continuum the article's `bands.yaml` merely "goes
  further" along — different axis, not more of the same one.

### Build candidates — status as of 2026-08-28

Planned via `EnterPlanMode`, revised once after an adversarial `mh:plan-reviewer` pass (2 Critical
+ 6 High findings, all folded in — see the plan's own "Revised after..." note), then built.
Full plan: `~/.claude/plans/proud-cooking-meteor.md` (session-local, not in this repo).

1. **Built.** `hooks/gates/merge-door.sh` (`gate:bash:merge-door`) — `ask` tier, reuses
   `irrecoverable.sh`'s argv-tokenizing classifier (the original "word-boundary regex" precedent
   was factually wrong and would have false-positived on HEREDOC/commit-message prose). 9-case
   test battery, `tests/hooks/test-merge-door.sh`.
2. **Built.** `hooks/gates/test-integrity.sh` (`gate:write:test-integrity`) — stateless
   content-diff classifier (assertion-line removed, or skip marker added), narrowed to real
   test-root path shapes. The original path-substring-only design was zero-signal (~100% ask
   rate on both the desired and undesired case) — fixed per a follow-up AskUserQuestion decision.
   5-case test battery, `tests/hooks/test-test-integrity.sh`.
3. **Built.** Gate-verdict journal in `hooks/dispatch-pretooluse.py` (non-`allow` decisions only,
   try/except-wrapped so an unwritable journal path can never flip the dispatch's own verdict —
   the review's sharpest Critical finding: the original "one line" design would have silently
   failed *open* across all 11 gates on any I/O error). 3 new regression tests in
   `tests/hooks/test-dispatch-pretooluse.sh`, including the fail-safe itself.
4. **Built.** `hooks/advisory/flow-nudge.sh`'s spec-flow branch now names
   `/mattpocock-skills:grill-with-docs` as a user-typed step; bare `grilling` (model-invocable,
   correct as-is) on the line above is unchanged. The original plan would have flipped `grilling`
   to `grill-with-docs` outright — `grill-with-docs` carries `disable-model-invocation: true`,
   so that swap would have nudged the model at a call the platform hard-blocks.
5. **Built, rescoped.** No new eval infrastructure — `harness-audit` added as a new CI job
   (`.github/workflows/validate.yml`). Required a real prerequisite fix first: checks 02/03's
   loadability assertions depended on the local plugin cache/`~/.claude` symlink farm and went
   from 0 CRIT locally to 76 CRIT reproduced under an isolated `$HOME` (a fresh CI checkout has
   neither) — fixed by downgrading to one aggregated WARN when neither delivery mechanism is
   configured at all, verified against the same isolated-`$HOME` reproduction (now 0 CRIT).
6. **Dropped**, per an AskUserQuestion decision — no downstream project asking for it.

**Known side effect, not fixed in this pass**: adding gates 1-2 changed the live hook-count fact
(11 → 13 PreToolUse table entries) that `docs/diagrams/mh-core-workflow.html` and
`mh-hook-profile-stack.html` hardcode — harness-audit check 56 now WARNs on both (2 new WARNs,
confirmed via a `git stash` before/after diff). Diagram content edits are out of this plan's
scope (they need the `diagram-design` skill's own re-export pipeline) — named here so it doesn't
get silently lost.

### Deep-audit hardening pass (2026-08-28, same day)

`mh:deep-audit` treated the "Built" verdicts above as unverified and dispatched 4 fresh-context
verifiers against them. They found real bypasses in items 1-3, not just polish gaps — closed in
3 commits, `ba390e06`/`0045414e`/`86856525` (v0.68.540-542):

- **Item 1/2 classifier (`irrecoverable.sh`, `merge-door.sh`)**: `shlex.split()` without
  `punctuation_chars` needs whitespace around `;`/`&&`/`||`/`|`/`&`/`(`/`)`/`{`/`}` to see them as
  separators — `echo hi;rm -rf x` tokenized as one glued word and skipped the check entirely.
  Bundled short-flag sudo (`sudo -nu alice`, `-Sku`) also evaded the value-flag scan. Both fixed
  by reusing `verifier-protect.sh`'s existing `punctuation_chars=True` tokenizer and real getopt
  bundling semantics, not invented from scratch.
- **Item 2 (`test-integrity.sh`)**: the `check()` assertion oracle was redefinable to a no-op
  with zero call-site diff; exit-gate deletion, duplicate-assertion-line collapse (set vs.
  multiset), and heredoc/`: '...'`-noop relocation all evaded the original diff classifier. Fixed
  with `collections.Counter` multisets and two new inertness strippers.
- **Item 3 (dispatcher journal)**: only the `rc==2` deny path was journaled; the other 4
  dispatcher exits (non-blocking error, empty/unparseable stdout, missing `hookSpecificOutput`)
  were silently unrecorded. Fixed — all 5 exit points now set a named per-entry decision
  variable and route through one journal call. **Precision correction (2026-08-29, third-pass
  re-audit):** "all 5 paths now journal" reads as "5 rows written," which overstates it — by
  design only non-`allow` decisions (`rc==2` deny, `rc!=0` error) actually write a row; the other
  3 exits are allow-equivalent (no verdict to log) and correctly produce none. Accurate framing:
  all 5 exits are now *decision-tracked*; only the non-allow ones journal.
- **Disclosure fix**: `merge-door.sh`'s non-goal comment named the REST-API gap
  (`gh api .../pulls/N/merge`) but not the xargs/docker-exec unwrap gap it also has (unlike
  `irrecoverable.sh`, which unwraps both) — added, not built (different, larger unwrap shape per
  wrapper, out of this pass's scope).

Score: 5.8→9.2/10 (+59%) on Correctness/Completeness/Documentation-accuracy/Test-coverage/
Failure-mode-safety, evidence-backed via red→green tests per fix. Live-smoke-tested afterward
against the actual running plugin cache (v0.68.542, not just the repo working tree) — 6/6 cases
correct, including the gate-verdict journal itself recording the right decision at the right
timestamp for each trigger.

### Third-pass re-audit (2026-08-29) — clean, all fixes hold

A fresh-context fork independently re-read all 4 gate files (`merge-door.sh`, `test-integrity.sh`,
`irrecoverable.sh`, `dispatch-pretooluse.py`) and re-ran their tests fresh rather than trusting
this doc's own claims: `test-merge-door.sh` 20/20, `test-integrity.sh` 19/19,
`test-dispatch-pretooluse.sh` 23/0, `test-gates.sh` (covers `irrecoverable.sh`) 210/210 — all
pass. Confirmed the `HOME=$TMP` test-isolation fix is real (13 occurrences in
`test-dispatch-pretooluse.sh`), not just claimed. One imprecise line found and fixed above (the
"all 5 paths journal" wording). Also swept two article items no prior pass had checked — managed
settings for a regulated enterprise (`allowManagedHooksOnly` etc.) and recurring codebase
security scans — both judged not-a-gap: the former is infrastructure for an org *consuming* the
plugin under MDM, not something this repo builds for itself; the latter has a structural analog
in `.github/workflows/harness-audit-drift.yml` (weekly cron, zero-human-in-path), just scoped to
harness-structure drift rather than CVE-style scanning — partial credit, not a miss. No new
findings; nothing to build.

**Closing the plan's own open questions.** The implementation plan (session-local, not in this
repo) named 2 unverified items: whether `audit.sh`'s individual checks would survive Ubuntu's
BSD-vs-GNU tool differences, and whether the CI job would actually behave correctly on a real
GitHub runner rather than just the isolated-`$HOME` local simulation. Both are now empirically
closed: `.github/workflows/validate.yml`'s `harness-audit (0 CRIT)` job runs on `ubuntu-latest`
and has gone green on every push since it shipped (checked via `gh run list` — 5/5 recent runs
succeeded, most recently run `33193283597`). The diagram hook-count drift named as a known side
effect (11→13) is also already fixed — both `mh-core-workflow.html` and
`mh-hook-profile-stack.html` say 13, and a fresh local `audit.sh` run right now is fully clean (0
CRIT, 0 WARN, 2 INFO-only budget trackers). The one item that's genuinely still open, and likely
to stay that way: whether an `ask`-tier gate prompt behaves sensibly in a non-interactive/
background session with nobody to answer it — a standing property of the ask-tier design itself,
not unique to this build, and not something this repo can verify without a real unattended
background run to observe.

## Round 3 — post-rebuild gap re-scan (2026-09-19)

### What happened on 2026-09-12, and why this section exists

A separate session ran a fresh 10-agent drill-down (5 analysts + 5 attackers) against this same
article, independently of this doc — it had no visibility into Round 1/2/3 above. It found that
the 2026-09-05 v1.0.0 rebuild (commit `10b6230f`) had deleted several of the items this doc's
Round 1/2 built, including the gate-verdict journal and the weekly `harness-audit-drift.yml`
cron, with no per-item rationale in the rebuild's own commit message. It restored both
(v1.1.89, commit `b2134aea`), plus a follow-up fixing 3 gaps a `mh:deep-audit` pass found in that
restore (`51762591`).

**That session's own tier list was never committed anywhere.** It exists only inside the raw
session transcript:
`/Users/kobig/.claude/projects/-Users-kobig-Codes-Personals-matt-harness/83f7669a-6271-4c87-834a-02f99430bb5d.jsonl`,
assistant message timestamp `2026-09-12T11:48:05.453Z`. This is itself a finding: the article's
central thesis is that every SDLC stage ends in a committed artifact, and the audit process
*about* that article failed to follow its own thesis. The tier list below is **reconstructed from
that transcript**, not independently re-derived — treat it as a faithful summary of what that
session concluded, not as freshly re-verified evidence in its own right.

### The reconstructed 2026-09-12 tier list

**Recommend building (all 3 shipped):**
| Item | Status |
|---|---|
| Restore gate-verdict logging | Shipped as `hooks/gates/_journal.py`, wired into all 7 gates (v1.1.89) |
| Restore the weekly harness-audit cron | Shipped as `.github/workflows/harness-audit-drift.yml` (v1.1.89) |
| Add `run-gauntlet.sh` as a real CI job | Shipped independently by a peer session the same day (`aa5059b5`/`1238e83a`, v1.1.87/88, closing GH #159) |

**Worth a quick decision, cheap either way — silently dropped, not decided:**
- **`grill-with-docs` pointer** restore (lost in the rebuild with the rest of `hooks/advisory/`).
  Still absent today.
- **Run `claude plugin eval` once for real** to check whether the early-access gate that blocked
  it in August had lifted. Never done.
- **Cost-report σ-tiers, human-triggered only** (narrower than what ADR 0006 actually rejected,
  which is *unattended* triggering). Never built or explicitly declined.

**Reject — already tried, or already decided against:**
- Push-gate / token release gate (built and killed before — 2026-06-25, "paralyzed sessions").
- σ-band monitoring that auto-writes `intent.md` unattended (forbidden by ADR 0006).
- REVIEW.md / PR-gated review mechanics (contradicts the single-branch, no-PR model).
- CI triage + MCP deploy/rollback tools (no deploy target exists in this repo).
- Verifier-subagent template (same shape already declined 2026-08-28 above).
- Claude Tag / on-call (no chat-channel integration exists anywhere in the repo).

**Flagged, not resolved:**
- **Credential-in-diff content scanning** — one analyst in that session wrongly marked this
  "already declined." It is not: the rebuild only moved *path-read* blocking
  (`~/.ssh`, `~/.aws`) to native `permissions.deny`; *scanning edit content* for secrets was
  never addressed, and `credential-guard.sh` itself was deleted in the same rebuild with no
  rationale. Genuinely open.
- **Post-edit fast lint** (`PostToolUse` on every edit) — real gap; as a plugin hook it would
  fire in every project mh loads into, so it needs a repo-scope guard, not a trivial addition.
- **Doc hygiene**: this doc listed deleted hooks as "Built" (now stale at the time), and
  `evals/README.md`'s case count had already drifted. Both partially addressed below.

### Today's fresh gap re-scan (2026-09-19)

A stage-by-stage re-read of the article against current repo state (two independent Explore
passes), classifying each item as **(a)** already does it, **(b)** built by an audit, **(c)**
explicitly considered and rejected/deferred, or **(d)** never evaluated at all.

**Never evaluated at all (d) — blind spots in every prior pass:**
1. **Claude Tag / channel-based incident intake** (article's "Claude on call") — zero coverage.
2. **"Auto mode"** — a distinct claim from the retired L2-L5 autonomy ladder (ADR 0006), never
   separated from it in any prior pass.
3. **Legacy systems / source-of-truth linkage** — `hooks/advisory/jira-route-nudge.sh`, the
   repo's only such linkage mechanism, was deleted with the rest of `hooks/advisory/` in the
   2026-09-05 rebuild.
4. **The committed-artifact chain itself** (the article's core mechanic) — evaluated
   stage-by-stage in every pass, never as its own claim. This Round 3 section's own existence is
   the proof of the gap: the 09-12 drill-down left no artifact until now.
5. **The design stage, post-rebuild** — Round 1 (2026-08-28) mapped it to `/to-spec`; that
   command no longer exists (`commands/` is gone from the repo entirely). No pass has revisited
   this row since.

**Regressed since this doc's Round 1/2 build (deleted 2026-09-05, no per-item rationale):**
6. **`merge-door.sh`** — the article's own flagship worked example (a hard block on `gh pr
   merge`), built for exactly that purpose, then swept in the bulk delete list. No replacement.
7. **`credential-guard.sh`** — Round 2 (above) flagged the underlying gap; the partial mitigation
   that existed was then deleted. Zero secret-scanning in this repo today.
8. **`flow-nudge.sh` grill-with-docs pointer** — the Plan-stage fix from Round 1, gone.
9. **`address-review`** (the article's `@claude`-reply-loop analog) — deleted in the same rebuild.

**Built, but not closing the article's actual loop:**
10. **`evals/` exists (70 cases as of today — see the `evals/README.md` fix below) but never runs
    in CI and gates nothing.** `.github/workflows/` has no job invoking `claude plugin eval`; only
    a static loader (`tests/evals/test-eval-cases.sh`) runs in CI, and `develop` has no
    branch-protection rule regardless. This is the single largest gap between "the repo has the
    thing" and "the repo does the play" found in any pass to date.
11. **Gate journal has a write path and no reader** — deliberately, per the v1.1.89 commit
    message and `CHANGELOG.md`: "error/timeout decisions and a jsonl reader are deliberately out
    of scope." The article's per-gate wait-time metric stays underivable without one. This is
    (c)-deferred-with-rationale, not a silent gap — noted here for completeness, not as new.
12. **`harness-audit-drift.yml`'s operator-facing GH-issue-comment text told readers to run
    `/mh:recursive-improve`** — a direct consequence of restoring the file "near-verbatim" from
    before the rebuild that deleted that skill; that skill no longer exists anywhere in the repo.
    **Fixed in this same session** (see below). The file's separate, static top-of-file comment
    also names two already-deleted scripts, `gate-journal-summary.sh` and
    `feedback-surface-scan.py` — those were never part of the live GH-issue-comment text and were
    correctly left untouched (doc/historical framing, not an operator-facing pointer), so they are
    not part of this finding.

**Not gaps — documented decisions, unchanged since Round 1-3 above:**
13. Managed settings for a regulated enterprise — rejected 2026-08-29 with rationale (this doc,
    third-pass re-audit).
14. Stage 6 autonomous loop / `bands.yaml` — rejected across ADR-0006, ADR-0009 (dead code),
    ADR-0011. The accepted alternative is the weekly drift cron itself.
15. Release-gate hook template — dropped by `AskUserQuestion` on 2026-08-28.
16. Worktree isolation — a stated position (`docs/reference/branching-model.md`) but **not
    written as an ADR** — the weakest-documented of the deliberate divergences from the article.

### This session's actual scope, and what's deferred

The user was shown the ranked list above and explicitly chose **doc/hygiene fixes only** for this
pass — not the "real candidates" bucket (credential-scanning gate, grill-with-docs pointer,
gate-journal reader, a real `claude plugin eval` probe), not the "bigger scope" bucket
(evals-in-CI, post-edit lint), and not the "needs-decision" bucket (items 1-5 above, formally
undecided rather than built or rejected). Those three buckets are handed to a future session as a
concrete, already-ranked starting point — the explicit point of writing this section at all is so
they don't need to be re-derived, and don't silently drop out of scope again the way the 09-12
drill-down's own findings did.

What this session did fix, all doc/hygiene, no behavior change to any hook/skill/agent (no
plugin-cache version bump needed):
- Corrected and linked the orphaned Round 1/2/3 memory (`ai-native-sdlc-playbook-audit-2026-08-28`
  had zero index entries anywhere in the auto-memory store's `MEMORY.md` — confirmed via grep —
  which is exactly why its "candidate list is closed" claim never got caught as stale).
- Added a new memory recording this Round 3 (`ai-native-sdlc-playbook-round3-gap-scan-2026-09-19`).
- Fixed `evals/README.md`'s two drifted case counts (was "29"/"76", real count 70 as of today —
  `find evals -mindepth 1 -maxdepth 1 -type d ! -name results | wc -l`).
- Fixed `harness-audit-drift.yml`'s dead-pointer text (finding 12 above): removed the instruction
  to run `/mh:recursive-improve`, and the possessive reference to that skill's name, from the
  live GH-issue-comment body — that skill doesn't exist anywhere in the repo (confirmed via grep
  across `skills/`, `scripts/`, `hooks/`).
