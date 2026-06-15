---
name: article-mine
description: "Mine an article / repo / RFC / doc for doctrine via 5-agent fan-out, then ship in-session. Use when the user pastes a URL / file / text and says 'mine this', 'analyze this article', 'extract lessons', 'read this and apply', or 'what can we take from this' — to harvest doctrine for the harness. Don't use for: pure Q&A (kbg:research-brief), reasoning review (kbg:critical-eval), systems-thinking (kbg:probe), security (kbg:security-auditor), or PR review (kbg:review-pr)."
disable-model-invocation: true
---

# Article Mine

Codified 5-agent fan-out for the recurring ritual of dropping an article / repo / RFC into Claude Code and harvesting doctrine for the harness. The hard parts are **verify-before-asserting** and **shipping in-session** — the agent-fan-out itself is the cheap part.

This skill writes the ledger row, updates memory, and (if doctrine moved) commits and pushes. Run it from the same session where the user pasted the source — do not punt to a follow-up.

**When to use:** the user has shared an article / repo / external doc and the goal is **transferable lessons + harness changes**, not "summarize this for me" or "explain this concept." A signal phrase like *"mine this," "what can we take," "apply to harness,"* or the pattern of *"here's the link — go"* confirms the intent.

**When NOT to use:** pure research (no doctrine transfer), reasoning audit (no fan-out), security review of a diff (use `kbg:security-auditor`), or PR review (use `kbg:review-pr`). For a single-doc deep-read with no harness application, `research-brief` is cheaper.

---

## Input Contract

- **Needs:** the source itself — a URL, a local file path, or text pasted in chat. The user has either pasted it, or it is a single line in the message.
- **When the source is missing:** ask once with a specific question. Never silently guess the article from context.
- **Defaults:** assume the source is a third-party article / repo / RFC (Verify-tier per `feedback_subagent_output_verify_tier`). Local repo paths are Trusted-tier but claims about *what the repo says* are still Verify-tier.
- **Scope hint (optional):** if the user says "focus on X" or "compare with Y," pass that hint to all 5 agents verbatim.

---

## Procedure

### 1. Stage the source

- **Local path:** `Read` the file fully first. If the file is >500 lines, scan headings + summarize structurally before fanning out — agents don't need to re-read the whole file.
- **URL:** `WebFetch` once. If the page is paywalled / auth-walled / a redirect loop, **HALT and tell the user** — do not synthesize from a title alone. Auth-walled URLs are a frequent failure mode (see `feedback_dismissed_3_real_features_as_fabricated` — confabulating from titles is a real recurring failure).
- **Pasted text:** already in context, no fetch needed.
- **Multi-source ("compare X and Y"):** read both fully, then proceed.

**Gate:** if the source cannot be read end-to-end, **HALT** — do not fan out on a guess.

### 2. Fan out 5 agents in parallel

Spawn all five in one message. Each gets the same source + scope hint, plus a specific done-when. Each returns a structured digest, not prose.

| # | Agent | Lens | Done-when |
|---|---|---|---|
| 1 | `general-purpose` | **Synthesis** | 3–5 sentences: what is the author's core claim, in the author's own framing? No opinion, no application. |
| 2 | `general-purpose` | **Apply** | Concrete list: which canon files / memory entries / skills would change if this is true? Cite `file:line` or `memory/<name>.md`. |
| 3 | `general-purpose` | **Gaps** | What does the article miss? What would a skeptical reviewer say? Where are the weak links, unstated assumptions, or counter-examples? |
| 4 | `general-purpose` | **Suggestions** | 0–3 *specific* small changes to the dotfiles harness (a rule, a memory note, a skill patch, a hook). If none are warranted, say "no suggestion" — do not invent. |
| 5 | `general-purpose` | **Security/Doctrine** | Does this collide with any explicit doctrine (METHODOLOGY rules, ACLI, DBGATE, file-trust levels, dispatch-skill capability gate)? Any risk of importing a contradictory framework? |

**Why 5 and not 1:** a single agent will blend synthesis with opinion and produce a confident-but-wrong digest. The fan-out forces the lenses to be claimed separately, then verified against each other.

**Why 5 and not 10:** beyond 5, the lenses blur. Insights data shows the 10-agent variant is reserved for re-runs / re-validations, not first-pass mining. If a re-run is wanted, run article-mine a second time with a different scope hint.

### 3. Verify, then combine

For each agent's digest:

1. **Cross-reference against canon.** Does the "Apply" lens point to files that actually exist? (`Read` the cited `file:line`.) Does the "Gaps" lens match the agent's own "Synthesis" framing?
2. **Check for fabrication.** Numbers, version strings, named people, citations — if the agent gives a precise stat, run `WebSearch` or `WebFetch` to corroborate. Per `feedback_subagent_output_verify_tier`, this is the only gate for non-code output.
3. **Doctrine check.** Agent 5's output is the highest-stakes — confirm any claimed collision is real, not a false alarm from a too-strict reading.

**Combine rule:** the final synthesis is the main agent's job, not the agents'. State what is verified, what is unverified, and what is contradicted. Do not launder unverified claims into the ledger.

**Gate:** if any of the 5 digests has a Critical-severity unverified claim that would change the verdict, **HALT and tell the user** before writing anything to the ledger. Do not patch forward.

### 4. Write the ledger row

Append a row to `memory/project_external_evals_ledger.md` (or create a per-article `_archive/<subject>_<date>.md` if the row is long). The row is the audit trail — keep it terse, ~3–5 lines:

```
| **<subject>** | <YYYY-MM-DD> | SKIP / MINE N / INSTALL | <one-line why> |
```

- **SKIP** = no canon changes, no memory updates
- **MINE N** = N specific kernels salvaged into canon, with `file:line` or `memory/<name>.md` citations
- **INSTALL** = an artifact was added to the harness (rare — see the `session-report` row for the only current precedent)

**Pattern check:** the ledger is the master catalog. **Never re-litigate a row that already exists** — if the article is in the ledger under a different framing, link to it and explain the new angle, don't duplicate.

### 5. Update memory (only if doctrine moved)

If the article surfaces a **new transferable rule** that isn't already in memory or canon:

- Write a new `memory/<name>.md` file (one fact per file, per `feedback_memory_pointer_vs_content`).
- Add a one-line pointer in `MEMORY.md` under the correct section.
- Run `python3 claude/skills/memory-lint/scripts/memory-lint.py` and require 0 findings before commit.

If the article is **already covered** by an existing memory entry, **do not write a duplicate** — link the ledger row to the existing entry instead. The "80% overlap is the norm" pattern (see `feedback_evaluating_third_party_claude_frameworks` and the recurring lessons in the ledger) means most articles re-confirm what we already know; that is a valid outcome, not a failure to find something.

**Gate:** if `memory-lint` reports any finding (dangling link, orphan, index drift), **fix before committing** — do not push a broken memory store. Per `feedback_memory_pointer_vs_content` and `reference_memory_store_optimization`.

### 6. Commit and push (only if doctrine or code moved)

If steps 4–5 produced a real change:

1. `git status` to confirm the changed files match the ledger row's claim.
2. `git add` the specific files (never `git add -A` per `feedback_concurrent_session_commit_index_bleed`).
3. `git commit -- <path1> <path2> -m "feat(article-mine): <subject> — <verdict>"` (always `--` + paths; arg order matters per friction data).
4. `git push origin develop`.

If nothing moved (SKIP verdict, no memory update), **no commit** — the ledger row is the artifact, and the session ends there.

---

## Output Format

End the run with this block, verbatim. Downstream memory-lint / commit logic depends on the fields being present and named exactly:

```
article-mine verdict
  subject: <one-line title>
  source: <URL | file path | "pasted">
  verdict: SKIP | MINE N | INSTALL
  ledger: <row added | row updated | no change (already in ledger)>
  memory: <new file written | updated existing | no change>
  canon: <files changed | none>
  unverified: <list of claims not corroborated THIS turn — or "none">
  commit: <sha | "no commit (nothing moved)">
  push: <ok | skipped>
```

If `unverified` is non-empty, **do not** push — surface the unverified claims to the user first and let them decide whether to ship the verified portion or wait.

---

## Failure Modes to Avoid

- **Skipping verification because the agent "sounded confident."** Confabulation is the #1 failure of sub-agent research output (`feedback_subagent_output_verify_tier`). Re-state every quantitative or named-entity claim against a real source.
- **Confusing "source = trusted" with "claims about source = trusted."** A local file's *existence* is Trusted-tier; what the file *says* is Verify-tier — the author can be wrong, outdated, or misread.
- **Mining a 5%-overlap article as if it were novel.** Check the ledger first. If the row exists, the work is *verify the existing verdict* (sometimes the article's claim is the inverse of the prior verdict — flag it), not "discover something new."
- **Writing a duplicate memory entry** because the new framing *feels* different. If a memory `<name>.md` already covers it, link to it and explain the new angle, don't create a sibling.
- **Forgetting the `disable-model-invocation: true` gate.** This skill dispatches write-capable agents (`general-purpose` inherits `Bash`/`Edit`/`Write`) and writes memory + commits. Auto-invoking it on any URL in chat would create a side-effect storm. The `description` is for human scanning — the gate keeps it manual.
- **Treating the ledger row as the whole artifact.** The row is the audit trail. The real deliverable is the canon change (or the explicit decision not to change canon). If the row exists but no doctrine moved, the verdict is "no action" — say so, don't pad.
- **Punting the commit to "next session."** This skill's whole point is closing the loop in-session (`project_close_session` is the user's #1 top goal per `/insights`). If the verdict is MINE and the change is real, commit + push before reporting back.
- **Halt-on-fail ignored:** if a Critical claim is unverified and the verdict would flip, **HALT**. Don't ship a confident-sounding digest with a quietly-omitted unverified claim.

---

## Integration Notes (Project-Specific)

### METHODOLOGY alignment

- **Rule 1 (Think before coding):** the Apply lens exists *before* any file edit, not after.
- **Rule 4 (Goal-driven):** every agent gets an explicit done-when, not a topic.
- **Rule 5 (Use the model for judgment only):** the 5-lens split is a routing decision, not 5 model "opinions" averaged.
- **Rule 7 (Surface conflicts, don't average):** the Gaps lens is a forcing function for the Synthesis lens's hidden assumptions.
- **Rule 8 (Read before you write):** the Apply lens's `file:line` claims must be `Read`-verified before they go in the ledger.
- **Rule 12 (Fail loud):** `unverified: ...` in the output is mandatory, not optional — even when the list is empty, the field is emitted.
- **Rule 13 (Orchestrate, don't solo):** the fan-out is a 5-piece decomposition with a verify/combine step. Don't substitute a single agent "summarize and apply" — that collapses the lenses.

### Skills / commands this composes with

- **`kbg:research-brief`** — single-agent deep-read, no doctrine application. Cheaper when the goal is "explain this" not "extract lessons."
- **`kbg:critical-eval`** — stress-tests an argument. Use when the article makes a strong claim worth probing before mining.
- **`kbg:probe`** — systems-thinking lens on a design decision. Use when the article *is* a design proposal.
- **`kbg:security-auditor`** — security review of a code change, not an article. Don't conflate.
- **`kbg:review-pr`** — PR review flow. Article-mine is for external content, not internal diffs.

### Project conventions

- Skill lives in `skills/article-mine/SKILL.md`; delivered via the `kbg@kobig` plugin (no symlink needed).
- This is a **manual-invocation** skill — `disable-model-invocation: true`. The `description` line is for human scanning in `/skills`, not for auto-trigger.
- The ledger row format is set by `project_external_evals_ledger.md` — match the column shape (Subject | Date | Verdict | Why) when adding a row.
- Commit prefix: `feat(article-mine):` for the first commit, then `docs(article-mine):` / `fix(article-mine):` for follow-ups, per the dotfiles commit convention.

### Anti-collision guards (do not change without good reason)

- The 5-lens split (synthesis / apply / gaps / suggestions / security) is the **only** stable shape. Don't reduce to 3 (loses Gaps vs Suggestions distinction). Don't expand to 7+ (lenses blur, no marginal value per the 5-vs-10 lesson).
- The `disable-model-invocation: true` gate is load-bearing — see Failure Modes.
- The HALT-on-Critical-unverified-claim gate is load-bearing — see Failure Modes and Rule 12.
