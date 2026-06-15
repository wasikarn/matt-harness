---
lens: gaps-open-questions
article: martinfowler.com/articles/harness-engineering.html
date: 2026-06-15
---

# Harness Engineering — Gap Analysis

## 1. Top 5 questions the article does NOT ask

1. **Versioning & installation API.** Lines 506–521 name "harness templates" but no install/update/rollback surface. Is it a git repo, package, plugin manifest, MCP bundle? Without stable identity (semver, content-hash, lockfile) the "teams pick stacks based on harnesses" claim (line 507) is unfalsifiable.
2. **Cost & token budget as a regulation axis.** Cost appears only as "fewer wasted tokens" (line 326). Real harnesses need budget sensors (per-task spend, ceiling-breach halts). The table at lines 363–379 has *Direction* and *Computational/Inferential* columns but no *Cost class*.
3. **The harness's own test suite.** Inferential sensors are non-deterministic (line 359); the article never asks how you regression-test a non-deterministic harness.
4. **Failure isolation & blast-radius controls.** What happens when a sensor lies? No sensor trust scores, cross-validation, or kill-switches for sensor disagreement.
5. **Provenance & accountability.** When AI iterates the harness itself (line 393), who signs off? "Change log of harness changes that produced this code" is the traceability regulated domains require; the article is silent.

## 2. The article's 4 open questions (line 553)

- **"Keep harness coherent as it grows."** Right question, wrong scope. Answer is *modular composition with typed contracts* — an API design problem.
- **"Trust agents to resolve contradicting signals."** Weakest. The inverse is the right question: *should the harness ever let an agent resolve conflicts at all, or must conflict resolution be deterministic policy?*
- **"Sensors never fire — high quality or inadequate detection?"** Already answered by the "ambient affordances" sidebar (line 493). Dead sensors are coverage gaps.
- **"Harness coverage tooling like code coverage / mutation testing."** The right question, and the right last one. Everything else is a sub-problem.

## 3. External references cited

LangChain *"Anatomy of an Agent Harness"* (line 309) — vocabulary. Anthropic *"Effective harnesses for long-running agents"* (line 309) — vendor example. OpenAI write-up (line 542) — layered architecture, "garbage collection" scans. Stripe *"minions"* (line 544) — heuristic-routed pre-push linters, "blueprints". Lexler *"approved-fixtures"* (line 476) — goldens for AI outputs. Thoughtworks *Architectural Fitness Function* (line 454) — non-AI ancestor. Ashby's Law (line 518) — variety-reduction. OpenRewrite (373), ArchUnit (375), LSPs (548), mutation testing (406). CI/CD (line 399) for the quality-left axis.

## 4. Concrete tools/patterns MISSING

- **Sandboxing** (Firecracker, nsjail, gVisor) — a *precondition* for trusting any behaviour-harness feedback, entirely unmentioned.
- **Property-based testing** (QuickCheck, Hypothesis, fast-check) as a third sensor class.
- **Supply-chain sensors** (SBOM, Syft, Grype) — dependency-graph as its own regulation dimension.
- **Eval-driven development tooling** (promptfoo, Braintrust, LangSmith) — meta-harness for A/B-testing new guides.
- **Adversarial sensor testing** — red-team fixtures and fault injection into the sensor pipeline.

## 5. The "test suite" assumption

The behaviour harness (lines 465–479) is structurally test-suite-dependent. This collapses for ML code (held-out metric), infrastructure-as-code (real-cloud provisioning), hardware (24-hour soak), security-critical code (red-team), and large refactors (green CI *is* the spec). The model holds in form, but the sensor vocabulary needs: held-out eval sets, canary deploys, shadow traffic, differential fuzzing, formal proofs. The article's "elephant in the room" concession (line 468) is the most important sentence — but it underweights how much of *all* harness work lives in that room for non-CRUD codebases.

## 6. Multi-agent / orchestration

Almost entirely single-agent. When an outer harness coordinates multiple agents (planner / coder / reviewer / tester), *each agent needs its own harness* and *there must be a meta-harness* regulating inter-agent contracts and reviewer-vs-coder conflicts. "Harness templates" (line 504) generalise across *service* topologies, not *agent-team* topologies. A "harness for an agent team" is the obvious next article.

## 7. Market for off-the-shelf harnesses

The article gestures at templates (line 504) and a topology-based ecosystem (line 507) but ignores *market dynamics*. Is the harness economy like npm (small, composable, versioned), Docker Hub (image-based trust), or GitHub Actions (serverless, marketplace, billing)? The "service templates" analogy (line 507) is well-chosen; the failure modes of that market (forking, abandonment, drift) are exactly what harness templates will inherit — named (line 521) but unsolved.

## 8. Local vs CI boundary

The article distributes sensors along a timeline (lines 404–407, 415–420) but never delineates *which sensors are user-side vs CI-side*. A clearer model: *computational sensors run everywhere they can; inferential sensors default to CI; only the most-trusted inferential sensors are local.* The split also matters for cost attribution (Q2): who pays for the inferential sensors' tokens?

---

**Verdict:** strong first-pass mental model. Central weakness: treats the harness as a *configuration* (lines 326, 537) rather than a *system* — which is why the four open questions are *consistency problems of a config* rather than *engineering problems of a software system*. A harness with versioning, cost sensors, its own test suite, a sandbox, and a market is a different object than "guides + sensors + human"; the next article should treat it that way.
