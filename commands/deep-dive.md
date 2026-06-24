---
name: deep-dive
description: "Research a topic thoroughly across codebase, docs, and web, then synthesize findings into a concise actionable brief with sources. This is the single kbg research surface — both user-typed (/deep-dive) and auto-routed. Use when the user says 'research this', 'deep dive on X', 'compare Z approaches', 'how does Y work in this codebase', or any open-ended exploration. Thai: 'research', 'deep dive', 'วิจัย', 'สำรวจ', 'หาข้อมูล', 'compare วิธี', 'ศึกษา'. Don't use for: single-file lookups (just Read it), known answers (ask directly), implementation tasks (use /ship-task or /fix-bug), or security audits (use kbg:security-auditor)."
argument-hint: Optional topic or question
---

# Deep Dive

Single kbg research surface. Produces an actionable brief with cited sources (file:line, URL, commit sha). This command is the user-typed entry (`/deep-dive`); the model routes here directly on open-ended research prompts.

## Core Principles

- **Scope upfront.** A vague question produces a vague answer. Define the research question before opening files.
- **Start local, go external.** Read the codebase first; only search the web for gaps.
- **Synthesize, don't summarize.** The output should connect findings to decisions, not just list what you found.
- **Cite sources.** Every claim links to a file:line, doc URL, or commit sha.

---

## Phase 1: Scope

**Goal**: Define the research question and boundaries.

**Actions**:
1. Parse `$ARGUMENTS` as the research question.
2. Ask clarifying questions if needed:
   - What decisions will this research inform?
   - What's the depth — overview, implementation detail, or competitive analysis?
   - Any time budget?
3. Output: one-sentence research thesis + scope boundaries.

**Example**: "How does authentication work in this codebase?" → thesis: "Map the auth flow from request → session → validation, identify extension points for OAuth2."

**Next**: Phase 2 (Local Exploration).

---

## Phase 2: Local Exploration

**Goal**: Extract everything relevant from the codebase.

**Actions**:
1. Launch `code-explorer` agent(s) with focused angles:
   - "Find all auth-related files and trace the request flow"
   - "Identify patterns for session management"
   - "Find tests that exercise auth behavior"
2. Read the key files identified by agents.
3. Map: components, data flow, dependencies, extension points, known limitations.

**Next**: Phase 3 (External Search).

---

## Phase 3: External Search (Conditional)

**Goal**: Fill gaps the codebase can't answer.

**Actions**:
1. If the codebase doesn't answer the thesis fully, search the web for:
   - Official documentation of relevant libraries/frameworks
   - Known issues or patterns
   - Comparative approaches
2. Use `mcp__plugin_context7_context7__query-docs` if relevant library docs are indexed in QMD.
3. Summarize external findings with URLs.

**Gate**: Skip this phase if the thesis is fully answered by the codebase.

**Next**: Phase 4 (Synthesize).

---

## Phase 4: Synthesize

**Goal**: Produce a brief that informs decisions.

**Actions**:
1. Structure findings:
   - **Summary** (3-5 bullets)
   - **Key Findings** (file:line references + what they mean)
   - **Gaps / Uncertainties** (what's still unclear)
   - **Recommendations** (what to do next, with tradeoffs)
2. Every claim cites a source. No unsupported assertions.
3. **Analyze**: coverage of the original research question — are there remaining gaps or uncertainties? Are the recommendations actionable? Does the user have capacity to act now or need more depth? **Recommend** archive when findings are sufficient for a decision; recommend deeper dive when gaps block action.
4. **AskUserQuestion** single-select: "Phase 4 complete: the research brief has [N] findings, [M] gaps, and [P] recommendations. What do you want to do with it?"
   - `Archive — findings are sufficient to act (Recommended when recommendations are actionable and no gaps block a decision)`
   - `Go deeper — specify which section needs more work (Recommended when gaps remain that block a decision)`

**Next**: Phase 5 (Archive).

---

## Phase 5: Archive

**Goal**: Make the research discoverable later.

**Actions**:
1. If the brief is reusable, offer to save it as a project memory or note:
   - "Save this as `.scratch/research/<topic>.md` for future reference?"
2. If the user agrees, write the brief to disk with frontmatter: date, question, sources.

**Done.**

---

## Implementation Note

This command is the **research surface**. It runs the 5-phase UX (Scope → Local → External → Synthesize → Archive) inline, forking the `researcher` agent for the external-search phase and the `code-explorer` agent for the local phase as needed. The formerly separate `research-brief` skill was merged into this command; all cross-references now resolve to `/deep-dive`.

Cross-references from `skills/perf/SKILL.md`, `skills/migrate/SKILL.md`, `skills/adr/SKILL.md`, and `commands/team-plan.md` all point at `/deep-dive` as the user-invoked entry point. They remain valid because this command still ships and still produces a brief.

## Handoff Reference

| Phase | Command / Action | When |
|---|---|---|
| 1 → 2 | Launch `code-explorer` agents | After thesis defined |
| 2 → 3 | Web search / QMD query | If gaps remain |
| 3 → 4 | Synthesize brief | After all sources gathered |
| 4 → 5 | Save to `.scratch/research/` | If user wants archival |

## Anti-Patterns

- **Reading everything** — Research is bounded by the thesis. Don't read unrelated files.
- **Web-first** — Always check the codebase first. Web answers may not match your actual dependencies or patterns.
- **No synthesis** — A list of file paths is not research. Connect dots.
- **No gaps section** — Hiding uncertainty produces overconfidence. Flag what's unknown.
