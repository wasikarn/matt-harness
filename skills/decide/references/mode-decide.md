## Mode: decide (default)

Interactive walk through the 5-rung Judgment Ladder. Pause with `AskUserQuestion`
only at a genuine fork where guessing wrong is expensive (same bar as `clarify`);
otherwise narrate the rungs straight through and flag open assumptions inline rather
than blocking on each one.

Match depth to stakes (reversibility, magnitude, time pressure, uncertainty,
precedent — judgment-ladder.md's Proportionality rule) — reversible low-stakes
choices need only rungs 1–2 (Recognize + Frame), not the full climb (completion
criterion below has the matching exception for what a rungs-1–2 response still owes).

Even a rungs-1–2 shortcut still owes one thing from rung 4/5's playbook: if the
request leans on an unverified quantitative or certainty claim (a stated cost, a
"zero risk," a time estimate), spot-check that specific claim before accepting it.
Skipping the full bias-guard checklist (reserved for rung 5's closing pass) is not
the same as skipping anchoring on a load-bearing number the request handed you — a
lightweight decision is exactly where an unverified number is most likely to just
get accepted at face value.

### 1. Recognize
Name the actual choice, its owner, its timing, and its trigger.
> Quick check: "What would happen if we did nothing for 30 days?"

### 2. Frame
Objectives, constraints (hard limits vs preferences), stakeholders, scope in/out.
> Reframe test: "If our favorite option did not exist, how would we solve this?"

### 3. Test assumptions
List load-bearing beliefs. For each: what evidence would refute it? Then answer a
second, separate question: which ONE assumption, if it resolved against the current
pick, reverses Selected → Rejected? This is not the "genuine fork → AskUserQuestion"
test above — that asks whether to pause and ask now; this asks whether the pick is
falsifiable at all. Failing the fork test says nothing about this one — an assumption
can be too cheap to block on now and still be exactly what would flip the decision
later. Carry the answer into the Decision record's Flip condition line (§ Output
format); "none of these would flip it" is a framing-bias smell, not a default answer.
> "Who disagrees with us, and what do they know that we don't?"

### 4. Estimate risk
Express uncertainty as ranges, not point estimates. Name compound/tail scenarios.
> "What is the 90% confidence interval, and would we bet money on it?"

### 5. Decide, commit, follow through
Document chosen and rejected options, trade-offs, revisit trigger, progress metric.
> Bias guards before closing: framing, anchoring, confirmation, sunk-cost.
> "If we had not already started, would we start today?"

**Full rung detail and decision record template:** read via Bash — `cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"` (the bare repo-relative path resolves nowhere in a foreign-project CWD; the plugin cache is the stable anchor).
