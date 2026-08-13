# Agents need an AST layer — argument, convergence with kbg doctrine, and the one under-argued assumption

Grounding for a future "should kbg-harness build a deterministic structural (AST/binding) layer?"
decision. Trigger: Dev Agrawal's article
["Agents Need an AST Layer"](https://x.com/devagrawal09/article/2087640940593000767)
(published 2026-08-13), which argues the biggest unlock for coding agents is not a bigger model or
better prompting but a deterministic program-view layer (ASTs, binding graphs, resolved imports,
exact locations) between the model and the repository.

**Method note:** the article was read in full from `~/llm-wiki/raw/Agents Need an AST Layer.md`
(operator-curated clipping). Claims below are cited to the article's own wording where they are the
article's, and to kbg-harness's own docs/research where they are kbg's. The pushback in §3 is this
author's analysis, not the article's — flagged as such.

---

## 1. The article's argument

Agrawal built two read-only, deterministic codemods — one for framework-major-version migration,
one for architecture review — and argues they are the most important tools he has built for working
with coding agents. The argument has six load-bearing claims:

1. **Agents are held back by text-shaped views of code.** The unlock is deterministic program
   views — ASTs, binding graphs, resolved imports, exact locations — not a bigger context window
   or better prompting. An agent receiving `file:42, why, guidance, stop conditions` does review;
   one receiving "here is the repo, figure it out" does archaeology. "Review is a skill you can
   verify. Archaeology is a hope."

2. **Binding resolution is the whole point.** Shallow AST matching is "regex with extra steps" —
   it matches text that looks like code and cannot tell whether a call site is real. The reliable
   method is to resolve the import binding first, then follow its references to real call sites. A
   shadowing local variable or an unrelated same-name function never matches, because binding
   resolution knows which declaration every reference resolves to. "A bigger model does not make a
   finding auditable. A resolved binding does."

3. **Classify before you transform — three classes.** The codemod never edits the target; it
   classifies each site and prints a sorted, deterministic manifest. Repeated runs produce the
   same ordered output; fixture tests prove the target is unchanged.
   - **Provable** — mechanically certain (an import moved, the old path no longer exists, the
     rewrite is mechanical). The codemod handles these alone, no model involved.
   - **Agent-guided** — the codemod can detect the site but cannot decide the replacement. The
     finding carries the exact location, the why, guidance with explicit stop conditions, and one
     instruction: ask for the smallest focused test or runtime observation that would settle it.
   - **Manual review** — neither tool can decide (precedence rules changed; several valid
     replacements and the right one depends on author intent). The finding says why and names a
     next action. No code change.

4. **Honesty by construction.** Deterministic tools say "I don't know" by construction — their
   limits are part of the output format ("manual review required," "coverage is deliberately
   limited," every record stamped as an observation never a verdict). "An LLM does not reliably
   say 'I don't know.' A deterministic analyzer says it by construction." The classification is
   made before the model sees anything and does not change, so the agent cannot quietly upgrade a
   manual-review finding into a provable transform.

5. **Read-only is a property, not a promise.** The analysis layer returns nothing; only an outer
   writer can create the report, through staging plus rename. "There is no other write path." The
   artifacts are deterministic (stable ordering, identical output across runs); the verification
   contract is executable (fixture tests + proof the target files are untouched).

6. **LLMs are for judgment, not guarantees.** "A codemod is a compiler for the agent's perception
   and action space." Guarantees belong to the deterministic layer, judgment to the model, and
   decisions neither can make to a human. "Build that layer before you chase the next model. The
   model will get smarter. The layer is what makes its work mean something."

Agrawal explicitly notes the convergence with his own harness philosophy: "a deterministic harness,
a prompt is not a boundary, shrink the action space." kbg-harness is in the same school.

---

## 2. Convergence with kbg-harness doctrine

The article's *principle* is already held by kbg — this is convergence on the same split, not a
new idea to adopt. The mapping (cross-referenced against
[`docs/research/graph-engineering-agent-systems-2026-07-27.md`](graph-engineering-agent-systems-2026-07-27.md),
which established the same convergence against Anthropic's own multi-agent research system):

| Article claim | kbg-harness analogue | Status |
|---|---|---|
| Guarantees → deterministic layer; judgment → model | `hooks/gates/` (verifier) vs model (maker); "Score, not feel" (CLAUDE.md §Architecture) | Already held |
| Read-only by construction, not a promise | deny-gates are computational; advisory sensors journal but never emit `permissionDecision` | Already held — strongest parallel |
| Honesty by construction (limits in the output format) | `force_human`/`convergence_state` written by shell, read by the gate; fail-closed fallback (`write-review-state.sh:204-218`) | Already held in spirit, weaker in substrate |
| Binding resolution > shallow AST > regex | compliance-audit's adversarial mandate: naming a bypass category without tracing the actual validation code misses real bypasses (HMAC-against-parsed-body; absent-claim-passing — see [`compliance-audit-check-39-49-bypass`](../../) memory) | Already discovered the failure the article predicts — but kbg catches it with fresh-context model verifiers, not a structural layer |
| 3-way split: Provable / Agent-guided / Manual | gate (deny) / advisory (nudge) / human-decision (`AskUserQuestion`) | Isomorphic |
| Build the AST layer before the next model | — | **The real gap** |

**The gap is substrate, not philosophy.** kbg's verifiers operate on text and git state — file
paths, line counts, JSON fields, `git diff`. The article argues for a verifier that operates on
code structure: resolved bindings, call-site provenance, hunk classification. kbg's convergence
gate already hit this ceiling and named it: the `ponytail:` comment in
`skills/review-pr/scripts/write-review-state.sh:148-152` admits file-level finding identity misses
same-file regressions and sketches the line-level (`file:start_line-end_line`) upgrade. The article
is the principled case for why that upgrade matters; the ponytail ceiling (stop at the first rung
that holds) is the principled case for why kbg stopped at file-level for now. Both are right at
their altitude.

---

## 3. The one under-argued assumption (this author's pushback, not the article's)

The article treats the deterministic layer as ground truth: "a resolved binding does" make a
finding auditable. But binding resolution is ground truth *modulo the toolchain*. The verifier is
no longer a ~60-line shell script a human can read in one pass; it is tree-sitter + a name resolver
+ (for true binding resolution) a type checker, each with its own bugs, versions, and language
coverage.

kbg's maker/verifier split derives its force from the verifier being a **small, auditable surface**
— shell returning a branchable score. An AST layer trades a small trusted surface for a large
trusted surface that *behaves* like a small one. The "honesty by construction" is honesty **given
the toolchain is honest**, which is a much bigger assumption than the article admits, and it is
the exact assumption that bites in polyglot or transpiled codebases where no single resolver covers
the whole graph. The article's two codemods are single-framework, single-language — the case where
the toolchain assumption is cheapest. Generalize it and the trust-surface cost rises
non-linearly.

This is the concrete reason kbg does not have an AST layer and should not rush to build one as a
**harness-level** surface: kbg is language-agnostic (shell gates, prose skills). There is no one
AST layer for a polyglot harness.

**Where this pushback may be wrong:** mature language servers (tsserver, rust-analyzer) are
battle-tested enough that "trust the resolver" may be a better bet than "trust a fresh-context
model verifier" for structural questions — the model verifier is itself an LLM with its own failure
modes, and the article's point is that the resolver is *deterministic*. If the resolver is right,
it is strictly better than a second model. The deciding factor is language coverage of the
codebase under review — empirical, not philosophical.

---

## 4. Application to kbg-harness — now/later split (ponytail-filtered)

| Application | Cost | Trigger to build |
|---|---|---|
| **This research note** (capture the argument + pushback + triggers) | low | now — cheap, durable, feeds a future decision |
| **Line-level finding identity** (`finding_files` path → `path:start_line-end_line` tuples in `write-review-state.sh`) | medium (script + review-pr Phase 5 + regression test) | when file-level identity is shown to miss a real same-file regression — not yet (compliance audit passed on file-level) |
| **classify-before-transform** (provable/agent-guided/manual in review-pr) | high — the "provable" class requires a deterministic checker, which *is* the structural layer | gated on the per-stack structural skill below |
| **Per-stack structural skill** (tree-sitter/binding resolution, starting from a stack with a real codebase) | high | later — two gates first (see below) |

**Line-level identity — the cheapest structural improvement (no AST).** The change: `finding_files`
currently stores one path per line; upgrade to `path:start_line-end_line` tuples. The set-diff
`any(f not in prev for f in cur)` would then catch a new finding in a file that already had one
(the same-file-regression ceiling the `ponytail:` comment admits today). review-pr Phase 5 already
emits findings with locations, so the line ranges are available without a structural pass. This is
the article's "exact locations" principle applied at the cheapest rung.

**Per-stack structural skill — the full thesis, gated.** Before building:
1. **composer-not-creator first** — check `mattpocock-skills` (installed plugin + local clone,
   `git fetch` first — it has lagged origin by a whole minor release before) and ECC/superpowers
   for an existing code-analysis/AST skill before building kbg-native. (Confirmed precedent:
   `code-implementer` collided with matt's own `engineering/implement` by skipping this check,
   CLAUDE.md §Composer-not-creator.)
2. **A real codebase where the structural check beats a fresh-context model verifier** on the same
   question — not a spec in search of a task.

If both gates pass, scope it as a per-stack skill (`typescript-patterns`-shaped, etc.), **not** a
harness-level gate — kbg is language-agnostic, and the article's own "coverage is deliberately
limited" stamp is honest about per-stack coverage limits. The large-toolchain trust lives on the
language-specific skill where it can declare its own coverage, not on a universal gate that
pretends to cover everything.

---

## 5. Decision triggers (when to reopen this)

- **Line-level identity**: a real PR where file-level finding-identity misses a regression in the
  same file (file appeared in both rounds' `finding_files`, so `regressed` stayed false, but a new
  distinct finding landed in it). At that point the `ponytail:` comment's upgrade path activates.
- **Structural skill**: a concrete review task where the question is structural ("is this call site
  really bound to that import?") and a resolver-based check is available for the language in scope.
  Until then, fresh-context model verifiers (compliance-audit Phase 3) remain the mechanism.

No action required now beyond this note. The article reinforces doctrine kbg already holds; the
one new substrate (structural verification) is correctly deferred until evidence of need, with the
cheapest rung (line-level identity) pre-positioned as the trigger-gated next step.