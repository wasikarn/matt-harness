---
name: article-mine
description: "Mine an article / repo / RFC / doc for doctrine via 5-agent fan-out, then ship in-session. Use when the user pastes a URL / file / text and says 'mine this', 'analyze this article', 'extract lessons', 'read this and apply', or 'what can we take from this' — to harvest doctrine for the harness. Thai: 'mine บทความ', 'สรุปบทความนี้', 'เอาบทความนี้มาใช้', 'วิเคราะห์บทความ'. Don't use for: pure Q&A (/deep-dive), reasoning review (kbg:critical-eval), security (kbg:security-auditor), or PR review (kbg:review-pr)."
---

# Article Mine

Codified 5-agent fan-out for the recurring ritual of dropping an article / repo / RFC into Claude Code and harvesting doctrine for the harness. The hard parts are **verify-before-asserting** and **shipping in-session** — the agent-fan-out itself is the cheap part.

This skill records the verdict, updates memory, and (if doctrine moved) commits and pushes. Run it from the same session where the user pasted the source — do not punt to a follow-up.

**When to use:** the user has shared an article / repo / external doc and the goal is **transferable lessons + harness changes**, not "summarize this for me" or "explain this concept." A signal phrase like *"mine this," "what can we take," "apply to harness,"* or the pattern of *"here's the link — go"* confirms the intent.

**When NOT to use:** pure research (no doctrine transfer), reasoning audit (no fan-out), security review of a diff (use `kbg:security-auditor`), or PR review (use `kbg:review-pr`). For a single-doc deep-read with no harness application, `research-brief` is cheaper.

---

## Input Contract

- **Needs:** the source itself — a URL, a local file path, or text pasted in chat. The user has either pasted it, or it is a single line in the message.
- **When the source is missing:** ask once with a specific question. Never silently guess the article from context.
- **Defaults:** assume the source is a third-party article / repo / RFC — **Verify-tier** (sub-agent claims about what a source says are never trusted blind). Local repo paths are Trusted-tier for *existence*, but claims about *what the repo says* are still Verify-tier.
- **Scope hint (optional):** if the user says "focus on X" or "compare with Y," pass that hint to all 5 agents verbatim.
- **Directory / corpus source:** if the path is a directory of many articles, treat the corpus as **one source** and bound the fan-out to 5 lens-agents that each read the whole set — do **not** run 5 lenses × N files (that violates [[bounded-agent-spawning]]; clamp the work-list in code, not in the prompt).

---

## Procedure

### 1. Stage the source

- **Local path:** `Read` the file fully first. If the file is >500 lines, scan headings + summarize structurally before fanning out — agents don't need to re-read the whole file.
- **URL:** `WebFetch` once. If the page is paywalled / auth-walled / a redirect loop, **HALT and tell the user** — do not synthesize from a title alone. Auth-walled URLs are a frequent failure mode (confabulating from a title is a real recurring failure).
- **Pasted text:** already in context, no fetch needed.
- **Multi-source ("compare X and Y") / corpus directory:** read all sources fully (skim any already cataloged in memory), then proceed.

**Gate:** if the source cannot be read end-to-end, **HALT** — do not fan out on a guess.

### 2. Fan out 5 agents in parallel

Spawn all five in one message. Each gets the same source + scope hint, plus a specific done-when. Each returns a structured digest, not prose.

| # | Agent | Lens | Done-when |
|---|---|---|---|
| 1 | `general-purpose` | **Synthesis** | 3–5 sentences: what is the author's core claim, in the author's own framing? No opinion, no application. |
| 2 | `general-purpose` | **Apply** | Concrete list: which canon files / memory entries / skills would change if this is true? Cite `file:line` or `<name>.md`. |
| 3 | `general-purpose` | **Gaps** | What does the article miss? What would a skeptical reviewer say? Where are the weak links, unstated assumptions, or counter-examples? |
| 4 | `general-purpose` | **Suggestions** | 0–3 *specific* small changes to the kbg harness (a rule, a memory note, a skill patch, a hook). If none are warranted, say "no suggestion" — do not invent. |
| 5 | `general-purpose` | **Security/Doctrine** | Does this collide with any explicit doctrine (METHODOLOGY rules, ACLI, DBGATE, file-trust levels, ADR 0002 autonomy invariant, dispatch-skill capability gate)? Any risk of importing a contradictory framework? |

**Why 5 and not 1:** a single agent will blend synthesis with opinion and produce a confident-but-wrong digest. The fan-out forces the lenses to be claimed separately, then verified against each other.

**Why 5 and not 10:** beyond 5, the lenses blur. The 10-agent variant is reserved for re-runs / re-validations, not first-pass mining. If a re-run is wanted, run article-mine a second time with a different scope hint.

### 3. Verify, then combine

For each agent's digest:

1. **Cross-reference against canon.** Does the "Apply" lens point to files that actually exist? (`Read` the cited `file:line`.) Does the "Gaps" lens match the agent's own "Synthesis" framing? An agent claiming "X already covers this" is itself Verify-tier — read X before trusting it (an Apply agent over-claimed "all 16 are named in the ADR" on the 2026-06-17 loop-engineering re-mine; reading the ADR refuted it).
2. **Check for fabrication.** Numbers, version strings, named people, citations — if the agent gives a precise stat, run `WebSearch` / `WebFetch` or `grep` the source to corroborate. This is the only gate for non-code output.
3. **Doctrine check.** Agent 5's output is the highest-stakes — confirm any claimed collision is real, not a false alarm from a too-strict reading.

**Combine rule:** the final synthesis is the main agent's job, not the agents'. State what is verified, what is unverified, and what is contradicted. When agents disagree, **resolve with judgment, don't average** (METHODOLOGY Rule 7) — read the underlying file and pick. Do not launder unverified claims into the record.

**Gate:** if any of the 5 digests has a Critical-severity unverified claim that would change the verdict, **HALT and tell the user** before writing anything. Do not patch forward.

### 4. Record the verdict

kbg has **no separate ledger file** — `MEMORY.md` (the memory-store index) is the master catalog. Record the verdict where it will be found again:

- **MINE / SKIP on an existing topic** → append a dated note to the existing `<name>.md` memory (and refresh its `MEMORY.md` pointer if the hook changed). Don't duplicate — see Step 5.
- **MINE N on a new topic** → a new memory file + `MEMORY.md` pointer (Step 5) *is* the record.
- **Pure SKIP, nothing worth remembering** → the in-session `article-mine verdict` block is the artifact; no file write.

Verdict vocabulary:

- **SKIP** = no canon changes, no memory updates.
- **MINE N** = N specific kernels salvaged into canon, with `file:line` or `<name>.md` citations.
- **INSTALL** = an artifact (skill / hook / agent) was added to the harness (rare).

**Pattern check:** `MEMORY.md` is the master catalog. **Never re-litigate an entry that already exists** — if the topic is already cataloged under a different framing, link to it and explain the new angle, don't duplicate. (Most articles on a known topic are ~80% overlap — re-confirming existing doctrine is a valid outcome, not a failure to find something.)

### 5. Update memory (only if doctrine moved)

The memory store for this repo lives **outside** the repo (the directory holding `MEMORY.md`, under `~/.claude/projects/<repo-slug>/memory/`). Writes there persist on their own and are **not** part of the repo's git history.

If the article surfaces a **new transferable rule** that isn't already in memory or canon:

- Write a new `<name>.md` memory file in the store (one fact per file; frontmatter per the memory format).
- Add a one-line pointer in `MEMORY.md` under the correct section.
- Run `bash "${CLAUDE_SKILL_DIR}/scripts/memory-lint.sh" <memory-store-dir>` and require 0 findings before commit.

If the article is **already covered** by an existing memory entry, **do not write a duplicate** — append a dated update note to the existing entry instead.

**Gate:** if `memory-lint` reports any finding (dangling link, orphan, index drift), **fix before committing** — do not leave a broken memory store.

### 6. Commit and push (only if in-repo canon moved)

The memory store is outside the repo (Step 5) — those writes need no git commit. Step 6 is for **in-repo canon** changes (METHODOLOGY, ADRs, skills, hooks, docs). If steps 2–5 produced one:

1. `git status` to confirm the changed files match the verdict's claim — and that no **concurrent-session** edits are mixed in (only commit your own files).
2. Stage the specific files — **never `git add -A`** (concurrent sessions can bleed unrelated changes into the index).
3. `git commit -m "feat(article-mine): <subject> — <verdict>" -- <path1> <path2>` — note the order: **`-m` before `--`**; everything after `--` is a pathspec, so a message placed after it is read as a filename and fails.
4. A docs/ADR/skill-content edit needs **no plugin version bump** (not a new/removed surface); adding or removing a component does. If you touched a plugin surface, follow the cache-invalidation steps in `CLAUDE.md`.
5. `git push origin develop`.

If nothing moved (SKIP, no memory update), **no commit** — the in-session verdict block is the artifact, and the session ends there.

---

## Output Format

End the run with this block, verbatim. Keep the field names exactly — they are the audit trail:

```
article-mine verdict
  subject: <one-line title>
  source: <URL | file path | "pasted">
  verdict: SKIP | MINE N | INSTALL
  record: <new memory file | updated existing | MEMORY.md only | in-session only>
  memory: <new file written | updated existing | no change>
  canon: <files changed | none>
  unverified: <list of claims not corroborated THIS turn — or "none">
  commit: <sha | "no commit (nothing moved)">
  push: <ok | skipped>
```

If `unverified` is non-empty, **do not** push — surface the unverified claims to the user first and let them decide whether to ship the verified portion or wait.

---

## Failure Modes to Avoid

- **Skipping verification because the agent "sounded confident."** Confabulation is the #1 failure of sub-agent research output. Re-state every quantitative or named-entity claim against a real source — including an agent's claim that "canon already covers this."
- **Confusing "source = trusted" with "claims about source = trusted."** A local file's *existence* is Trusted-tier; what the file *says* is Verify-tier — the author can be wrong, outdated, or misread.
- **Mining a 5%-overlap article as if it were novel.** Check the catalog (`MEMORY.md`) first. If the topic exists, the work is *verify the existing verdict* (sometimes the article's claim is the inverse of the prior verdict — flag it), not "discover something new."
- **Writing a duplicate memory entry** because the new framing *feels* different. If a memory `<name>.md` already covers it, append a dated note and explain the new angle, don't create a sibling.
- **Auto-firing this heavy skill on a bare URL.** This skill dispatches write-capable agents (`general-purpose` inherits `Bash`/`Edit`/`Write`) and writes memory + commits. Invoke it deliberately on an explicit "mine this" intent — not as a reflex on any URL pasted in chat, which would create a side-effect storm.
- **Treating the verdict record as the whole artifact.** The record is the audit trail. The real deliverable is the canon change (or the explicit decision not to change canon). If no doctrine moved, the verdict is "no action" — say so, don't pad.
- **Punting the commit to "next session."** This skill's whole point is closing the loop in-session. If the verdict is MINE and the change is real, commit + push before reporting back.
- **Halt-on-fail ignored:** if a Critical claim is unverified and the verdict would flip, **HALT**. Don't ship a confident-sounding digest with a quietly-omitted unverified claim.

---

## Integration Notes (Project-Specific)

### METHODOLOGY alignment

- **Rule 1 (Think before coding):** the Apply lens exists *before* any file edit, not after.
- **Rule 4 (Goal-driven):** every agent gets an explicit done-when, not a topic.
- **Rule 5 (Use the model for judgment only):** the 5-lens split is a routing decision, not 5 model "opinions" averaged.
- **Rule 7 (Surface conflicts, don't average):** the Gaps lens is a forcing function for the Synthesis lens's hidden assumptions; when lenses disagree, read the file and resolve.
- **Rule 8 (Read before you write):** the Apply lens's `file:line` claims must be `Read`-verified before they enter the record.
- **Rule 12 (Fail loud):** `unverified: ...` in the output is mandatory, not optional — even when the list is empty, the field is emitted.
- **Rule 13 (Orchestrate, don't solo):** the fan-out is a 5-piece decomposition with a verify/combine step. Don't substitute a single agent "summarize and apply" — that collapses the lenses.

### Skills / commands this composes with

- **`/deep-dive`** — single-agent deep-read, no doctrine application. Cheaper when the goal is "explain this" not "extract lessons."
- **`kbg:critical-eval`** — stress-tests an argument. Use when the article makes a strong claim worth probing before mining.
- **`kbg:decide` probe mode** — systems-thinking lens on a design decision. Use when the article *is* a design proposal.
- **`kbg:security-auditor`** — security review of a code change, not an article. Don't conflate.
- **`kbg:review-pr`** — PR review flow. Article-mine is for external content, not internal diffs.

### Project conventions

- Skill lives in `skills/article-mine/SKILL.md`; delivered via the `kbg@kobig` plugin (no symlink needed).
- The `description` triggers are deliberately narrow (explicit "mine this" / "extract lessons" intents) — this is a heavy, write-capable skill, so it should not fire on a bare URL in chat.
- There is no ledger file — record verdicts in the memory store (`MEMORY.md` is the catalog; see Step 4).
- Commit prefix: `feat(article-mine):` for the first commit, then `docs(article-mine):` / `fix(article-mine):` for follow-ups, per the kbg commit convention.

### Anti-collision guards (do not change without good reason)

- The 5-lens split (synthesis / apply / gaps / suggestions / security) is the **only** stable shape. Don't reduce to 3 (loses Gaps vs Suggestions distinction). Don't expand to 7+ (lenses blur, no marginal value per the 5-vs-10 lesson).
- The HALT-on-Critical-unverified-claim gate is load-bearing — see Failure Modes and Rule 12.
