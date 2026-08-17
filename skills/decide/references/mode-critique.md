## Mode: critique

Adversarial stress-test of reasoning that **already exists** — a plan, an ADR, an RFC,
a proposal on the table. Not for generating a new decision from scratch (`decide`/
`strategize` do that); this mode only audits one that's already made.

1. **Skeptic.** Argue against the proposal on its own terms: what load-bearing
   assumption, if false, collapses it? What would a competent rival or reviewer
   attack first? (red-team)
2. **Steel-man.** State the strongest version of the opposing case, not the weakest —
   the version that would actually change the decision if true. (steel-manning)
3. **Synthesis.** Name any unconsidered alternative the Skeptic/Steel-man pass
   surfaced. If the proposal survives, say why the strongest objection doesn't hold.
   If it doesn't survive, name what changes.

**Bias to guard:** confirmation bias — the proposal's author is structurally
motivated to find it sound. If that author is this session itself (drafted or
reasoned through earlier in this conversation), the mode-selection table's skeptic
row applies instead — critique's own guard isn't strong enough for that case. Ask:
"what evidence would prove this proposal wrong, and did we look for it or just for
evidence it's right?"

Output: a verdict — the reasoning holds, holds with a named caveat, or needs rework —
plus the one assumption most worth re-verifying, and, when the verdict carries a
caveat or needs rework, what specifically would need to change (per step 3) — a
verdict without a concrete next step leaves the reader with a red flag and no path
forward.
