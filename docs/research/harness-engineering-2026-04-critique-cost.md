---
lens: cost-overengineering
article: martinfowler.com/articles/harness-engineering.html
date: 2026-06-15
---

# Adversarial Review: "Harness engineering for coding agent users" (Böckeler, 2026)

Useful cybernetic framing, one-sided article. Hardest category punted, costs unquantified, LLM-judge circularity unaddressed.

## 1. Top weak claims

- **L309** — *"part of the harness is already built in (e.g. via the system prompt … or even a sophisticated orchestration system)"*. Quietly assumes rich retrieval; bare CLI agents lack these.
- **L326** — *"it should reduce the review toil and increase the system quality, all with the added benefit of fewer wasted tokens."* The "should" does all the work. OpenAI/Stripe (L542–L544) are the only data, linked not analysed.
- **L448** — *"Correctness is outside any sensor's remit if the human didn't clearly specify what they wanted."* The most loaded claim. It lets the harness off the hook for the highest-stakes failure (silent spec ambiguity) by blaming the spec author.
- **L531** — *"A good harness should … direct [human input] to where our input is most important."* Central thesis as slogan; "most important" is undefined.

## 2. Hidden costs and missing trade-offs

- **Coherence tax.** L553 raises *"How do we keep a harness coherent as it grows?"* and drops it. N guides × M sensors yield N×M checks. Additive framing, multiplicative reality.
- **Sensor maintenance.** L342's linter messages with self-correction instructions are a prompt that drifts against model updates. Who maintains inferential sensors is never answered.
- **Per-commit token spend.** L359 admits inferential sensors are "slower and more expensive." Three LLM judges can double wall-clock per PR. Breakeven is never quantified.
- **False positives / reviewer fatigue.** Quality-left (L397–L427) means earlier and noisier signals. Linters already generate ignored warnings; pre-commit LLM judges (L404) compound this. Signal vs. noise is never distinguished.
- **Locked-in topology.** L507 notes the downside (orgs picking tech for "what harnesses are available") without interrogating the path-dependency trap.
- **Spec vs. harness for behaviour.** L468–L478 punts; L527–L531 says harnesses externalise what humans bring — and most of what humans bring *is* behavioural judgment. The framework cannot deliver the autonomy promised.

## 3. Behaviour-harness cop-out and LLM-judge circularity

Two related cop-outs. On behaviour: one pattern (approved-fixtures, L476), otherwise defer. A reader shipping a behaviour harness today gets: classify, write a spec, run green tests, accept the risk — the pre-article baseline. On LLM-as-judge: the most glaring circularity, unaddressed. L356–L359 endorses "LLM as judge" on "a strong model, or rather a model that is suitable." The article assumes the *coding* and *judging* models are independent — an unstated dependency. A judge with the generator's blind spots cannot catch those blind spots. L393's *"we can of course also use AI to improve the harness"* compounds the same model class across generation, judgment, and meta-engineering — a single-model failure mode propagating through layers.

## 4. Quality-left and "shift feedback left"

"Shift feedback left" (L544) is cited from Stripe without a counterweight. Pre-commit feedback forces a fast, low-context decision point. Unaddressed: **cost shifting to developers** (slower local vs. cheaper CI), **reviewer fatigue** (noisy judges get disabled, then a Critical CVE gets a "tool said fine" stamp), and **false confidence** (green mutation test + green LLM review ≠ correctness — L448 admits this for the spec case but never generalises).

## 5. What a practitioner would object to

1. **"Harnesses are an attempt to externalise … human developer experience" (L531)** — externalised rules are not experience. A senior spotting a 300-line function that "feels wrong" pattern-matches against thousands of prior failures, often uncodifiable. The article implicitly claims the gap is smaller than it is.
2. **Harness-as-additive model.** Real harness work is overwhelmingly *removing* affordances (forbidding destructive commands, narrowing what the agent can do). The article's guides/sensors are all *additions*. A security-audit reader sees the asymmetry.
3. **No failure case study.** OpenAI and Stripe are cited only as successes. A worked example of a harness that failed — added friction, became a maintenance liability, was bypassed by agents — would be more useful than the upbeat summary.

## 6. The metaphors

- **"Harness on a dog" (L315).** The author concedes it doesn't work — *"wrapping harnesses around harnesses doesn't make sense"* — and proceeds anyway. "Steering loop" (L389) is the better metaphor.
- **Cybernetic governor (L433, L518).** Ashby's Law is correctly cited. But a steam-engine governor is a closed loop with a known plant model; the agent's "plant" is non-deterministic and updating — closer to herding than governing.

## Summary

A useful glossary and first-pass mental model. As engineering guidance it is thin: costs unquantified, the LLM-judge circularity unaddressed, behaviour punted, toil reduction asserted rather than demonstrated. A practitioner building a real harness from this alone would over-invest in inferential sensors and underestimate the coherence maintenance burden.
