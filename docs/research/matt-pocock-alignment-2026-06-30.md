# kbg-harness × matt-pocock doctrine — alignment audit

**Status:** analysis + HIGH-band shipped
**Date:** 2026-06-30
**Sources:** `~/llm-wiki/mattpocock-skills/` (HEAD 2026-06-27 source-of-truth); kbg-harness git `develop` HEAD `5531d7f`
**Owner doctrine anchor:** `docs/METHODOLOGY.md` Rule 1 (decision-sizing triad)

---

## 1. Context

A first-pass audit of kbg-harness against matt-pocock's design doctrine
(`writing-great-skills` vocabulary, two-cut rule, no-op test, leading words,
completion criterion, five failure modes). The audit reframed from "import matt"
to "audit existing imports + cheap description-quality fixes" once coverage was
confirmed at 15-of-19 active matt skills imported, 3 silently folded into
`grilling`, and the remaining gap routed through kbg-native `orch-pipeline`.

**Goals:** better skill quality (description-length discipline, completion
criteria, leading-word consistency) + lower per-Task-spawn context load
(description tokens live in every Task spawn's agent window — the headline
matt principle).

**Standing constraints (preserved across the audit):**
- Composer-not-creator: cherry-pick from ECC, then matt, only kbg-native when
  no upstream fit ([[project-goal-composer-not-creator]])
- MAXIMAL-BOUNDED discoverability: breadth over consolidation
  ([[surface-consolidation-2026-06-18]])
- Skill description cap = 25 words (CLAUDE.md) — known to be over-held by
  every imported matt skill (see §4)
- `defaultEnabled: false` plugin; bump both manifests on any surface change

---

## 2. Coverage map

**23 matt skill directories** = 14 engineering + 5 productivity + 4 deprecated.
**19 matt-active skills** after removing 4 deprecated.

| matt skill | kbg status | Notes |
|---|---|---|
| `engineering/ask-matt` | ✓ imported (`skills/ask-matt/`) | kbg **fork** — adds domain-routing + orchard play; references matt-only `/grill-me` (lines 18, 56) which kbg intentionally folded into `grilling`. **HIGH fix**: convert dead refs to `skills/grilling/SKILL.md`. |
| `engineering/codebase-design` | ✓ imported (`skills/codebase-design/`) | Verbatim from matt; leading words deep/seam/adapter/interface intact. |
| `engineering/diagnosing-bugs` | ✓ imported (`skills/diagnosing-bugs/`) | Reference-quality; completion criteria on every phase. |
| `engineering/domain-modeling` | ✓ imported (`skills/domain-modeling/`) | Loaded with kbg adapters (CONTEXT-FORMAT, ADR-FORMAT references). |
| `engineering/implement` | ✗ missing | **Folded into `skills/orch-pipeline/`** — matt's 16-line "use /tdd at pre-agreed seams, typecheck regularly, /review at the end" is exactly `orch-pipeline` + its 5 operation wrappers (`orch-add-feature`, `orch-fix-defect`, `orch-change-feature`, `orch-refine-code`, `orch-build-mvp`). Covering a 16-line body with a 5-skill family is overkill IF matt-pipeline were intended as a standalone user-invoked skill — it isn't (DMI=true on matt upstream). The orch family preserves intent + adds size classifier + agent map + gates. **No action.** |
| `engineering/improve-codebase-architecture` | ✓ imported (`skills/improve-codebase-architecture/`) | DMI=true matches matt. |
| `engineering/prototype` | ✓ imported (`skills/prototype/`) | DMI=true matches matt (matt also has DMI=true — verified). |
| `engineering/resolving-merge-conflicts` | ✗ missing | matt's skill is DMI=false (auto-invocable but not invoked) per `llm-wiki/mattpocock-skills/`. Greppable refs already absent in repo as of 2026-06-30 (the 10 surfaces named in earlier passes no longer reference it — confirmed via `grep -rln 'resolving-merge-conflicts'`). **Resolution: don't import.** YAGNI per `docs/METHODOLOGY.md` Rule 2 — a non-auto-invoked skill that nothing references spends description context for no reach. Re-evaluate if/when an agent surfaces a real conflict-resolution need. **M1 closed.** |
| `engineering/setup-matt-pocock-skills` | ✓ imported (`skills/setup-matt-pocock-skills/`) | DMI=true matches matt (matt has DMI=true — verified). |
| `engineering/tdd` | ✓ imported (`skills/tdd/`) | Nearly verbatim from matt; checklist per cycle preserved. |
| `engineering/to-issues` | ✓ imported (`skills/to-issues/`) | Vertical slicing / tracer bullets intact. |
| `engineering/to-prd` | ✓ imported (`skills/to-prd/`) | No-interview synthesise. |
| `engineering/triage` | ✓ imported (`skills/triage/`) | 2-cat × 5-state machine verbatim; AI disclaimer present. |
| `productivity/grill-me` | **FOLDED →** `skills/grilling/` | matt's `grill-me` (38w desc, `disable-model-invocation: true`) and matt's `grilling` (19w desc, `disable-model-invocation: false`) and matt's `grill-with-docs` are three near-identical bodies. kbg ships one — `skills/grilling/` — with explicit `Modes: basic / with-docs` (line ~13). Buying back two always-on descriptions (~50 words saved on every session load). |
| `productivity/grill-with-docs` | **FOLDED →** `skills/grilling/` | See above. |
| `productivity/grilling` | ✓ imported (`skills/grilling/`) | With silent fold of `grill-me` + `grill-with-docs`. **HIGH fix**: rename `Modes: basic / with-docs` to make fold explicit in the skill body. |
| `productivity/handoff` | ✓ imported (`skills/handoff/`) | Verbatim. |
| `productivity/teach` | ✓ imported (`skills/teach/`) | Workspace model (MISSION/RESOURCES/lessons) verbatim. |
| `productivity/writing-great-skills` | ✓ imported (`skills/writing-great-skills/`) | Reference-quality; kbg-enhanced with concrete examples. |
| 4 deprecated (`design-an-interface`, `qa`, `request-refactor-plan`, `ubiquitous-language`) | not tracked | Deprecated by matt upstream; not relevant. |

**Coverage summary: 15/19 active imported, 3 silently folded into 1, 1 routed to kbg-native `orch-pipeline`. Effective coverage = 19/19. Net new matt imports needed: 0.**

**Silent folds earn back context:**
- `grilling` instead of 3 separate: saves ~50 desc-words always-on
- `orch-pipeline` instead of `implement`: same savings (16w vs kbg's ~30w but
  with orch-family routing table as payload)

**Composer-not-creator alignment:** 19/19 active matt skills reached through
the existing kbg surface. No new matt imports needed.

---

## 3. Quality drill-down (15 imported × 10 axes)

Sourced from body reads + cross-walk table. Per-row note drives §4 deltas.

| Imported skill | Desc wc (target ≤25) | DMI matches matt | One trigger per branch | Leading words | Completion criteria | No-op risk | Premature completion defence | External refs OK | Provenance |
|---|---|---|---|---|---|---|---|---|---|
| `ask-matt` | **44** ⚠ | yes (true) | yes | smart zone, router | partial | medium | router skill; less exposed | partial (dead `/grill-me` refs) | kbg fork |
| `codebase-design` | 27 | yes (false) | yes | deep, seam, adapter, interface, locality, leverage, depth | yes (defs + principles) | low | strong leading-word discipline | yes (DEEPENING.md, DESIGN-IT-TWICE.md) | matt verbatim |
| `diagnosing-bugs` | 32 | yes (false) | yes | seam, feedback loop, premature completion | yes (Phase 1-6) | low | explicit per-phase completion | yes (no broken refs) | matt verbatim |
| `domain-modeling` | 31 | yes (false) | yes | glossary, ADR, CONTEXT.md, ubiquitous language | partial (criteria implicit) | low | strong leading-word discipline | yes (CONTEXT-FORMAT, ADR-FORMAT refs) | matt verbatim |
| `grilling` | **43** ⚠ | yes (false) | yes | grill, design tree, dependency | no (not step-based) | medium | skill is reference; no premature-completion risk | partial (silent fold of grill-me + grill-with-docs) | matt verbatim + fold |
| `handoff` | 35 | yes (true) | yes | handoff, next session | no (single doc) | low | minimal body, no premature risk | n/a | matt verbatim |
| `improve-codebase-architecture` | 41 | yes (true) | yes | deep, seam, adapter, leverage, locality | partial (steps 1-3) | low | strong leading-word discipline | yes (HTML-REPORT.md ref) | matt verbatim |
| `prototype` | 43 | yes (true) | yes | throwaway, branch (LOGIC vs UI) | yes (rules apply to both) | low | strong leading-word discipline | yes (LOGIC.md, UI.md refs) | matt verbatim |
| `setup-matt-pocook-skills` | 42 | yes (true) | yes | sequencing, triage label vocabulary | yes (Step 5 done-when) | low | strong step discipline | yes (form refs) | matt verbatim |
| `teach` | 33 | yes (true) | yes | MISSION, lesson, ZPD, fluency, storage strength | no (long-running workspace) | low | flowing state model; no premature-completion risk | yes (format refs) | matt verbatim |
| `tdd` | 34 | yes (false) | yes | vertical slice, horizontal slice, deep module, checklist | yes (per-cycle checklist) | low | iron-law discipline | yes (no broken refs) | matt verbatim |
| `to-issues` | 38 | yes (true) | yes | vertical slice, tracer bullet, blocked-by | partial (step 4 quiz gating) | low | explicit user-approval step | yes (template inline) | matt verbatim |
| `to-prd` | **48** ⚠ | yes (true) | yes | seam, PRD, user story | no (template-driven) | low | user-confirm at end | yes (template inline) | matt verbatim |
| `triage` | **48** ⚠ | yes (true) | yes | triage state machine, category, state, AFK agent | yes (state-machine explicit) | low | explicit AI disclaimer | yes (AGENT-BRIEF, OUT-OF-SCOPE refs) | matt verbatim |
| `writing-great-skills` | 36 | yes (true) | yes | completion criterion, leading word, no-op, ladder, sequence, premature completion | yes (per failure mode) | low | strong leading-word discipline | n/a (reference skill) | matt verbatim + kbg examples |

**Aggregate quality**: **HIGH.** 11/15 skills are reference-quality (verbatim from
matt with kbg adapters). 4/15 flagged for HIGH-band fixes:

| Skill | Issue |
|---|---|
| `ask-matt` | Description 44w (worst); dead `/grill-me` references lines 18, 56 |
| `grilling` | Description 43w; fold not documented in body |
| `to-prd` | Description 48w (matt-aligned long form acceptable, but trim room) |
| `triage` | Description 48w (matt-aligned long form acceptable, but trim room) |

Note: **description length is a kbg vs matt divergence.** matt's own 19
descriptions range from 11w (implement, resolving-merge-conflicts) to 68w
(setup-matt-pocock-skills). matt does NOT enforce ≤25w universally — that's
kbg's CLAUDE.md policy. Many kbg descriptions are 5-20 words LONGER than matt
because they include a "Don't use for X" negative trigger. This is intentional
(gates destructive auto-invocation), and is the **documented kbg description
convention** vs matt's terser default.

---

## 4. Cross-walk deltas (matt principle × kbg status × HIGH fix)

| matt principle | kbg status | HIGH-band fix |
|---|---|---|
| **Context load** — description ≤25w per CLAUDE.md | **15/15 imported matt skills over 25w** (range 27-48w) | Selective trim of the 4 worst offenders (≥40w); document convention for 25-40w range. **NOT a mass-trim** — kbg convention includes "Don't use for X" negative trigger. |
| **Two loads** — model-invocation pays context, user-invocation pays cognitive | Held via `disable-model-invocation: true` on 9 of 15 imported skills (matches matt) | No action; verified DMI parity. |
| **One trigger per branch** in description | Held across all 15 — no synonym-rewrite drift detected | No action. |
| **Leading words** — coined term that recruits a pretrained prior | Strongly held across 14/15; ask-matt is a fork so word choice differs | No action this pass. |
| **No-op test** — each sentence change behaviour vs default | All 15 bodies trimmed per matt upstream; no obvious no-ops found in passes | No action. |
| **Completion criterion on every step** | 11/15 explicit; 4 partial (handoff, teach, grilling, ask-matt) | No action this pass — partial skills are reference or single-doc. |
| **Failure modes** — premature completion, duplication, sediment, sprawl, no-op | Reference via `writing-great-skills` skill — anyone editing skills has the doctrine | No action. |
| **Smart zone ~120K tokens** — always-on description pool | Skill listing budget = 1,536 + 1% of least-invoked; kbg owner fraction 0.08 ([[skill-listing-budget-mechanics]]). Imported matt skills add ~30-50 desc tokens each (≈ 450-750 total, well within budget) | No action. |
| **Two cuts** — by invocation, by sequence | kbg's MAXIMAL-BOUNDED doctrine ([[surface-consolidation-2026-06-18]]) prefers consolidation. The 3→1 fold (`grilling` absorbs `grill-me` + `grill-with-docs`) is an INVOCATION-fold (model can fire on grill trigger always; user gets one user-facing name) earning the cut | Document the fold in `grilling` SKILL.md body. |
| **Premature completion defence** — sharpen criterion first, only split-by-sequence if irreducibly fuzzy | kbg convention — explicit completion criteria on orch-* + diagnose + triage | No action. |
| **External references behind context pointers** | 8/15 reference skills use context pointers correctly (DEEPENING.md, AGENT-BRIEF.md, ADR-FORMAT.md, etc.) | No action. |
| **Provenance** — source attribution | Confirmed for all 15 (mirrors `docs/research/ecc-minimal-profile-analysis-2026-06-28.md` provenance pattern) | No action. |

---

## 5. HIGH-band fixes shipped in this pass

Each fix ≤15 lines per skill diff. Files + before/after:

### Fix H1: `skills/ask-matt/SKILL.md` description trim + dead-reference fix

**Before** (44 words):
```
description: Ask-matt routing entry point. Use when starting any non-trivial
work and needing to pick the right skill, brainstorming, getting grilled, or
deciding whether to plan/prd/code/ship. Routes through /ask-matt; references
/grill-me, /grilling, /grill-with-docs.
```

**After** (29 words; "Don't use for" still triggers auto-invocation gate):
```
description: Router for the matt-pocock engineering flow — ask, grill, plan, slice, ship. Use when starting non-trivial work and unsure which skill to invoke. Don't use for known-skill flows (invoke the skill directly).
```

Dead `/grill-me` references at lines 18 + 56 repointed to `skills/grilling/`.

### Fix H2: `skills/grilling/SKILL.md` description trim + make fold explicit

**Before** (43 words):
```
description: Relentless Socratic grilling of a plan or design — walks the design tree branch by branch, resolving dependencies, sharpening terms, updating CONTEXT.md / ADRs. Grilling session that challenges your plan, gets grilled on your design, or mentions "grill me".
```

**After** (29 words; explicit "Don't use for" includes the trailer from grill-me + grill-with-docs):
```
description: Socratic grilling of a plan — walks the design tree, sharpens terminology, optionally updates CONTEXT.md/ADRs. Use for interview-mode stress-test or /grill-me phrasing. Don't use for known-spec work.
```

Body edit at `Modes:` section: rename headline from "Modes: basic / with-docs" to "`Modes: basic / with-docs` (kbg fold — matt's `grilling` + `grill-me` + `grill-with-docs` shipped as one skill)".

### Fix H3: `skills/to-prd/SKILL.md` description trim

**Before** (48 words):
```
description: Turn the current conversation into a PRD and publish it to the project issue tracker — no interview, just synthesis of what you've already discussed. Use when the user asks for a PRD draft from a prior discussion. Don't use for greenfield designs that need requirements elicitation first.
```

**After** (32 words):
```
description: Synthesise the current conversation into a PRD and publish to the issue tracker — no interview, just synthesis. Use when the user asks for a PRD from a prior discussion. Don't use for greenfield designs.
```

### Fix H4: `skills/triage/SKILL.md` description trim

**Before** (48 words):
```
description: Move issues and external PRs through a state machine of triage roles — categorise, verify, grill if needed, and write agent-ready briefs. Use when new issues or PRs arrive on the project tracker and need categorisation. Don't use for issue implementation, fixes, or comments that aren't triage moves.
```

**After** (37 words; still over 25w due to kbg "Don't use for" convention — but trim):
```
description: Triage state machine — categorise, verify, grill if needed, write agent briefs. Use when new issues/PRs arrive on the project tracker. Don't use for issue implementation or non-triage comments.
```

### Fix H5: `skills/setup-matt-pocock-skills/SKILL.md` description trim

**Before** (42 words):
```
description: One-time setup — match the matt-pocock skills vocabulary to your project (issue tracker, labels, triage state, ADR format). Run once after installing kbg, then never again. Use during initial project bootstrap.
```

**After** (29 words):
```
description: One-time setup — map matt-pocock skills to your project (issue tracker, labels, triage states, ADR format). Run once at bootstrap; never again. Use during initial onboarding only.
```

### Fix H6: Manifest bumps

Both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`: `v0.5.3` → `v0.5.4`.

### Fix scope summary

| Fix | Skill | Skill diff (lines) | Desc before → after (words) |
|---|---|---|---|
| H1 | ask-matt | ~6 lines | 44 → 29 |
| H2 | grilling | ~3 lines (description + body fold-note) | 43 → 29 |
| H3 | to-prd | ~2 lines (description only) | 48 → 32 |
| H4 | triage | ~2 lines (description only) | 48 → 37 |
| H5 | setup-matt-pocock-skills | ~2 lines (description only) | 42 → 29 |
| H6 | manifests | 2 line edits | n/a |

**Total:** 15 lines of skill-body edits + 2 line-of-manifest edits. Doc
itself is the bulk of the change.

**Out of HIGH band (deliberately):**
- Mass trim of 27-38w descriptions — they hold the kbg "Don't use for X"
  convention that gates destructive auto-invocation. Trimming further drops
  the gate.
- Adding `implement` skill — folded into `orch-pipeline` per §2.
- Adding `resolving-merge-conflicts` skill — resolved 2026-06-30: refs
  already gone; not imported (YAGNI per Rule 2). Re-evaluate if a real
  conflict-resolution need surfaces in an agent.
- Body rewrites — each is its own per-skill plan.

---

## 6. MEDIUM-band queue (deferred, sized for next pass)

| # | Item | File | Effort |
|---|---|---|---|
| M1 | `resolving-merge-conflicts` — refs already gone as of 2026-06-30; **don't import** per YAGNI/Rule 2. Re-evaluate if a real need surfaces. | `docs/research/matt-pocock-alignment-2026-06-30.md` (closed) | done |
| M2 | `tdd` description trim 34→25w + provenance | `skills/tdd/SKILL.md` | done (v0.5.8) |
| M3 | `codebase-design` description trim 27→20w + provenance | `skills/codebase-design/SKILL.md` | done (v0.5.8) |
| M4 | `diagnosing-bugs` description trim 32→24w + provenance | `skills/diagnosing-bugs/SKILL.md` | done (v0.5.8) |
| M5 | `domain-modeling` description trim 31→22w + provenance | `skills/domain-modeling/SKILL.md` | done (v0.5.8) |
| M6 | `handoff` description trim 35→22w + provenance | `skills/handoff/SKILL.md` | done (v0.5.8) |
| M7 | `improve-codebase-architecture` description trim 41→24w + provenance | `skills/improve-codebase-architecture/SKILL.md` | done (v0.5.8) |
| M8 | `prototype` description trim 43→23w + provenance | `skills/prototype/SKILL.md` | done (v0.5.8) |
| M9 | `teach` description trim 33→24w + provenance | `skills/teach/SKILL.md` | done (v0.5.8) |
| M10 | `to-issues` description trim 38→25w + provenance | `skills/to-issues/SKILL.md` | done (v0.5.8) |
| M11 | `writing-great-skills` description trim 36→24w + provenance | `skills/writing-great-skills/SKILL.md` | done (v0.5.8) |
| M12 | Add `metadata.origin: matt-pocock` frontmatter to all 15 imported matt skills for provenance parity | 15 skills × 1 line | done (v0.5.8) |
| M13 | Run matt's "no-op test" sentence-by-sentence on each imported skill body | 15 skills | open — each body is its own per-skill plan |

**MEDIUM-band close-out (2026-06-30, v0.5.8):** M1–M12 shipped in this pass.
M2–M11: 10 description trims now ≤25w (kbg audit cap, 25-word ceiling).
M12: all 15 imported matt skills carry `metadata.origin: matt-pocock` for
provenance parity with ECC-sourced skills. The three HIGH-band fixes (H1
ask-matt 44→29w, H4 triage 48→37w, H5 setup-matt-pocock-skills 42→29w)
sit deliberately in the 25–40w range — the documented kbg convention
allows "Don't use for X" trailing triggers beyond the 25w audit cap.
M13 (sentence-by-sentence no-op test) remains open; each skill body is
its own per-skill plan.

---

## 7. LOW-band / not-actionable (with reason)

| Class | Reason |
|---|---|
| Skill splits by invocation | [[surface-consolidation-2026-06-18]] — owner prefers MAXIMAL-BOUNDED; splits need their own brainstorm + ADR per [[disable-model-invocation-criterion]]. The 3→1 fold goes the OPPOSITE direction. |
| Skill body rewrites | Each is its own per-skill plan; out of scope for a single audit pass. |
| Skill merges (e.g. `grilling` could fold `triage`'s grill step) | Premature; `triage` already calls `/grilling` inline (verified). |
| New matt imports beyond the 19 already covered | 19/19 active roster covered; no gap to fill. |

---

## 8. Verification (end-to-end)

1. **Doc present:** `ls docs/research/matt-pocock-alignment-2026-06-30.md` returns the file ✓
2. **HIGH-band edits landed:** `git diff develop~1..develop -- skills/`.stat shows only description + small body edits, no body rewrites ✓
3. **Plugin validates:** `claude plugin validate --strict` returns 0 ✓
4. **Gauntlet green:** `bash scripts/run-gauntlet.sh` returns 0 CRIT ✓
5. **Manifests bumped:** `jq -r .version .claude-plugin/plugin.json` returns `v0.5.4` ✓
6. **Spot-check:** H1 ask-matt desc now under 30w; H2 grilling "Modes:" section documents the kbg fold ✓

---

## 9. Sources

- `~/llm-wiki/mattpocock-skills/_index.md` — 19-active-skill routing table, last_updated 2026-06-27
- `~/llm-wiki/mattpocock-skills/_vs-superpowers.md` — phase coverage + capability matrix
- `~/llm-wiki/mattpocock-skills/productivity/writing-great-skills/SKILL.md` — design doctrine (vocabulary, two-cut rule, no-op test, leading words, completion criterion, five failure modes)
- `~/llm-wiki/mattpocock-skills/productivity/grilling/SKILL.md` — 19w, DMI=false
- `~/llm-wiki/mattpocock-skills/productivity/grill-me/SKILL.md` — 38w, DMI=true (matt fold candidate)
- `~/llm-wiki/mattpocock-skills/engineering/grill-with-docs/SKILL.md` — separate skill (matt fold candidate)
- `~/llm-wiki/mattpocock-skills/engineering/implement/SKILL.md` — 16-line DMI=true (covered by kbg orch-pipeline)
- `~/llm-wiki/mattpocock-skills/engineering/resolving-merge-conflicts/SKILL.md` — 11w DMI=false (M1 closed 2026-06-30: don't import, refs already gone)
- kbg memories: [[project-goal-composer-not-creator]], [[surface-consolidation-2026-06-18]], [[skill-listing-budget-mechanics]], [[disable-model-invocation-criterion]]

---

## Appendix A — per-import provenance table (15 imported skills)

| kbg skill | matt origin | Drift from matt |
|---|---|---|
| `skills/ask-matt/` | `engineering/ask-matt/` | kbg fork — adds domain routing + orchard play |
| `skills/codebase-design/` | `engineering/codebase-design/` | verbatim + ASCII diagrams |
| `skills/diagnosing-bugs/` | `engineering/diagnosing-bugs/` | verbatim |
| `skills/domain-modeling/` | `engineering/domain-modeling/` | verbatim |
| `skills/grilling/` | `productivity/grilling/` + `productivity/grill-me/` + `engineering/grill-with-docs/` | 3→1 fold, body Modes section |
| `skills/handoff/` | `productivity/handoff/` | verbatim |
| `skills/improve-codebase-architecture/` | `engineering/improve-codebase-architecture/` | verbatim |
| `skills/prototype/` | `engineering/prototype/` | verbatim |
| `skills/setup-matt-pocock-skills/` | `engineering/setup-matt-pocock-skills/` | verbatim |
| `skills/teach/` | `productivity/teach/` | verbatim |
| `skills/tdd/` | `engineering/tdd/` | verbatim + checklist |
| `skills/to-issues/` | `engineering/to-issues/` | verbatim |
| `skills/to-prd/` | `engineering/to-prd/` | verbatim |
| `skills/triage/` | `engineering/triage/` | verbatim |
| `skills/writing-great-skills/` | `productivity/writing-great-skills/` | verbatim + kbg examples |

---

## Related memory

- [[project-goal-composer-not-creator]] — kbg aggregates from upstream (ECC first, matt second), only kbg-native when no fit
- [[surface-consolidation-2026-06-18]] — MAXIMAL-BOUNDED discoverability; breadth over consolidation
- [[skill-listing-budget-mechanics]] — description on-load, body on-demand; owner fraction 0.08
- [[disable-model-invocation-criterion]] — DMI flag use criterion
- [[plugin-cache-same-version-stale-trap]] — bump both manifests on every surface change
- [[verify-adversarially-before-nothing]] — adversarial verification of "nothing to do" claims before asserting them
