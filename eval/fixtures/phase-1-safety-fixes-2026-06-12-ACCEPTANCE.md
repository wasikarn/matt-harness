# ACCEPTANCE — Phase 1 T1 safety fixes from the 2026-06-12 audit (F1 + F2 + F4 + F11 + F12 + D5)

- **Start SHA:** b29085563f754d22f5d340b9701c76f9ab39794c
- **Locked:** 2026-06-12
- **Author:** Team-lead (kbg-harness)
- **Source:** `.scratch/audit-2026-06-12/SPEC.md` Phase 1 (4-8h base) merged with `.scratch/article-revalidation-2026-06-12/delta-vs-REPORT-v2.md` extensions (F11, F12, D5) → effective 6-11h, 6 fixes.
- **Status:** SHIPPED 2026-06-12 (last Phase 1 ship SHA `3dd7a6b` — boundary regen with 11 commands). All 37 acceptance items ticked.

## Scope (6 fixes)

### FIX-F1 — `validator-bash-guard.sh` PreToolUse hook (safety, REPORT §3 F1)

The single biggest latent safety gap: 7 validator-class agents (`code-reviewer`, `code-explorer`, `code-architect`, `comment-analyzer`, `pr-test-analyzer`, `silent-failure-hunter`, `security-reviewer`) hold `Bash`. The `orchestrate` skill gates Bash-holding dispatch behind `AskUserQuestion` (per `skills/orchestrate/SKILL.md:16-23`), but a direct `Task` spawn with `Bash` granted is unconstrained. Behavioral hook (deny mutation patterns) over `disallowedTools: [Bash]` — preserves read-only inspection (`git diff`, `git log`, `npm test`, `pytest`) the validators need.

**Acceptance:**
- [x] New file `hooks/gates/validator-bash-guard.sh` exists, `bash -n` clean, executable bit set.
- [x] Logic: reads `tool_input.command` from stdin JSON via `_lib.sh`; reads `agent_type` (vendor-confirmed field in PreToolUse input when fired inside a subagent — see `https://code.claude.com/docs/en/hooks#common-input-fields`).
- [x] If `agent_type` ∉ validator list → exit 0, no decision (fail-open for main-thread / non-validator agents; user has already approved).
- [x] If command matches one of 11 deny patterns (`git\s+(push|reset\s+--hard|clean\s+-fd)`, `rm\s+`, `sed\s+-i`, `>\s*[^\s|;&]+\s*$`, `mv\s+.*\s+/`, `chmod\s+`, `chown\s+`, `:\(\)\s*\{.*:\|.*\}`, `\bcurl\s+.*-X\s+(POST|PUT|DELETE|PATCH)`, `\bnpm\s+(publish|uninstall)`, `\bpip\s+uninstall`) AND `agent_type` in validator list → `hook_decision deny "VALIDATOR-BASH: <agent_type> attempted mutation: <command>"` (helper emits JSON + exits 0 per codebase convention — `_lib.sh:18`).
- [x] If `agent_type` is validator but command matches one of the 7 allow-prefixes (`git diff|log|show|status`, `ls|cat|head|tail|wc|grep|rg|find|jq`, `node -p`, `python3 -c "..."`, `npm test`, `pytest`, `cargo test`, `go test`) → exit 0, no decision (fast path; deny patterns are checked first to avoid bypass).
- [x] Registered in `hooks/hooks.json` PreToolUse Bash matcher (appended to the 5-hook matcher at `hooks.json:74-99`; preserves existing matcher order — `secret-read-guard`, `block-dangerous-git`, `block-bash-doctrine-write`, `block-alias-shadowing`, then new `validator-bash-guard`).
- [x] 6/6 test fixtures added to `tests/hooks/runners/test-critical-hooks.sh` covering: (a) `code-reviewer` + `git diff HEAD` → `permissionDecision: "none"`, (b) `code-reviewer` + `git push origin main` → `permissionDecision: "deny"`, (c) `code-reviewer` + `rm -rf /tmp/foo` → `permissionDecision: "deny"`, (d) `backend-engineer` + `git push origin feature` → `permissionDecision: "none"` (writer not gated), (e) `code-reviewer` + `npm test` → `permissionDecision: "none"`, (f) `code-reviewer` + `sed -i 's/x/y/' file` → `permissionDecision: "deny"`. **All tests assert on `hookSpecificOutput.permissionDecision` (not exit code) per `test-critical-hooks.sh:14-15` contract.**
- [x] Manual smoke: `claude --agent code-reviewer` → `git push` returns `permissionDecision: "deny"` with the VALIDATOR-BASH reason.

### FIX-F2 — `orchestrate` validation chain section (capability, REPORT §3 F2)

Articles `task-distribution`, `team-orchestration`, `agent-teams-workflow` all describe the builder → validator → fix → re-validator chain. Current `skills/orchestrate/SKILL.md` has 4 routing paths + Bash-gate but **no `TaskCreate` example**. A user reading the skill has no template to copy. Fix: add worked `TaskCreate` + `addBlockedBy` example between "Procedure" and "Fast Path Gate" sections.

**Acceptance:**
- [x] New `## Validation chain (TaskCreate + addBlockedBy)` section in `skills/orchestrate/SKILL.md`, inserted between current "Procedure" section and "Fast Path Gate" section (verify exact line boundaries by Reading the file at phase start).
- [x] Section contains a worked example: `TaskCreate(..., subject: "Implement X", status: "pending")` → `TaskCreate(..., subject: "Validate X", status: "pending")` → `TaskUpdate(taskId="<validator-id>", addBlockedBy=["<builder-id>"])` → re-validator as 3rd task.
- [x] Section cites the article URL in a footnote (matches the existing "Cite the source" pattern in `skills/orchestrate/SKILL.md`).
- [x] Cross-reference from `skills/orchestrate/reference.md` "Scripted Execution Modes (L4)" section pointing to the new section.
- [x] Optional anti-pattern line: "Don't use `TaskCreate` for trivial single-task dispatch (Rule 2). Don't use `addBlockedBy` for ordering that should be inline in one prompt."
- [x] No new test (skill is prose, not code); `harness-audit` exit 0.

### FIX-F4 — `code-explorer` nest-down prompt (doctrine, REPORT §3 F4)

Article `nested-subagents` (vendor v2.1.172, 2026-06-09) — "push noisy tool calls down so only signal flows up." `code-explorer` currently uses Read/Grep/Glob/WebFetch/WebSearch/Bash directly; every noisy call lands in its context. Nesting is a vendor capability (depth=5, hard cap) but models don't reliably self-nest — must be **explicitly ordered in prompt** (article: "model still isn't stable at self-nesting").

**Acceptance:**
- [x] New `## Nest-down pattern` section in `agents/code-explorer.md`, inserted after the existing `## Why this role exists` section (which all 27 agents have per `REPORT.md §1.2`).
- [x] Section content matches SPEC.md F4 #2-#4 (3 bullet examples + 1 anti-pattern line + 1 capacity note about depth=5).
- [x] No new test (behavior is in the model, not the file); `harness-audit` exit 0.

### FIX-F11 — extend F2 with 4-step merge recipe (capability, delta F11)

Article `agent-teams-use-cases` and `sub-agents-split-tasks` formalize a 4-step consolidation after parallel fan-in: **Reports → Conflict Resolution → Priority Ranking → Action Plan**. v2 F2 covers pairwise chain sequencing but not the merge after parallel fan-out. Without this, two parallel validators finishing at the same time produce parallel action plans with no protocol for reconciling.

**Acceptance:**
- [x] Sub-section `### Consolidation (4-step merge)` appended to the F2 section in `skills/orchestrate/SKILL.md` (same edit as FIX-F2).
- [x] 4 steps listed with one-line example each: (1) collect per-validator Reports, (2) Conflict Resolution — surface disagreements with file:line citations, (3) Priority Ranking — P0/P1/P2 by blast-radius, (4) Action Plan — concrete file:line edits.
- [x] Inline example: "Validator A flags `SKILL.md:42` overstates nesting depth; Validator B flags same line. Conflict Resolution: confirm both → de-dup → Priority Ranking: P0 (load-bearing doctrine) → Action Plan: edit + test."
- [x] No new test; `harness-audit` exit 0.

### FIX-F12 — `orchestrate` anti-patterns catalog (doctrine, delta F12)

Articles `custom-commands`, `sub-agents-parallel-vs-sequential`, `sub-agents-split-tasks`, `task-management-distribute-work` describe 4 distribution mistakes that compound: (1) over-fragmentation, (2) under-specification, (3) resource conflicts, (4) context duplication. Add as a teachable anti-pattern frame inside `skills/orchestrate/reference.md`.

**Acceptance:**
- [x] New `## Anti-patterns (distribution mistakes)` section in `skills/orchestrate/reference.md`.
- [x] 4-mistake taxonomy with one-line example each, sourced from the 4 articles.
- [x] Plus 3 named anti-patterns: over-parallelizing (2-file task → 5 agents), under-parallelizing (5-file task → 1 agent), output-format-mismatch (validator returns prose, builder wants JSON).
- [x] No new test; `harness-audit` exit 0.

### FIX-D5 — extend F4 to `researcher.md` (doctrine, delta D5)

Verified 2026-06-12: `agents/researcher.md` is 9.7K, heavy web-search agent missed in v2 F4 nest-down list. Same delegation pattern as `code-explorer` applies per `nested-subagents` article's "research with claim verification" workflow. **Spot-check verified** — `ls -la agents/researcher.md` confirmed size 9.7K.

**Acceptance:**
- [x] New `## Nest-down pattern` section in `agents/researcher.md`, inserted after `## Why this role exists` (same pattern as FIX-F4).
- [x] Section content is research-specific (article/web fetch delegation), not a copy-paste of the code-explorer section.
- [x] Includes a claim-verification note: "When research surfaces a claim, spawn a layer-2 `Explore` agent to verify it against the local codebase before returning it. Return the verified claim + file:line citation, not the raw search results."
- [x] No new test; `harness-audit` exit 0.

## Green bar

- [x] `bash skills/harness-audit/scripts/audit.sh /Users/kobig/Codes/Personals/kbg-harness` → exit 0, findings ≤ baseline (re-capture baseline first; current 31 checks baseline).
- [x] `claude plugin validate --strict .` → exit 0.
- [x] `bash tests/hooks/runners/test-critical-hooks.sh` → all pass (existing N + 6 new fixtures for F1).
- [x] Per-fix `bash -n` parses; manual invocation of `validator-bash-guard.sh` against the 6 fixtures matches the AC.
- [x] Fresh-context adversarial pass: 1 verifier agent (kbg:code-reviewer role) per fix, fresh context, no access to my reasoning — confirms the new hook/check behaves per AC.

## Deliberately NOT in this PR

- **F3, F7, D1, D2 (Phase 2 capability)** — separate phase with own ACCEPTANCE.md.
- **F5, F6, D3 (Phase 3 polish)** — separate phase.
- **D6, D9 (Phase 4 deferred)** — `usage-monitor/` skill + personality-injection commands not part of this epic.
- **D7 (TECH-LEAD-THAI conflict with F5)** — Phase 3 open question; not blocking Phase 1.
- **D4, D8, D10 (Phase 2 doc adds)** — F2/F3 spec extensions, ship with Phase 2.

## Autonomy invariant check

- [x] FIX-F1 is a **deterministic deny** for validator mutations — **compatible** with the invariant (autonomy is for human gating of irreversible ops, not for inverting safety hooks; deny is appropriate here because validators have no legitimate use for destructive mutation commands like push or recursive delete).
- [x] FIX-F2, FIX-F4, FIX-F11, FIX-F12, FIX-D5 are **doctrine/prose** changes — **compatible** (no behavior change, no human gate).
- [x] No new write-tools granted; no `disallowedTools` removed; no new MCP server added.

## Out of scope (per owner signal)

- 12 revalidation findings (F8/F9/F10/D4/D8/D10) being merged into Phase 2 (deferred to F2/F3 spec writes, not Phase 1).
- 6 v1 audit corrections (REPORT.md §7) — these are doc-side, already addressed in v2 of the audit.
- New agents / new commands / new skills — none in this phase.
- Permission allowlist changes — none.
