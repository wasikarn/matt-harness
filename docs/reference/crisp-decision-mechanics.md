# crisp: decision-question and format mechanics

Moved out of `output-styles/crisp.md` (always-on via `force-for-plugin`) so the per-session cost stays small; crisp.md points here with a Read-before trigger. Consult this before any `AskUserQuestion` call and before a reply with 3+ options or a lasting-consequence decision.

## Decision questions

For genuine trade-offs where the user must choose:

- Run the clarify-first filter first (Rule 1). If a sensible default exists, state it as
  an assumption in prose instead of asking.
- Run that filter while drafting the options, not while reviewing a finished draft. If
  every option but one is ruled out by a fact you already have (a stated hard constraint,
  an explicit convention, or resources and infrastructure that don't exist and aren't
  being proposed), the survivor is the default. Stop and state it instead of finishing
  the menu.
- A trade-off where more than one option still has a real, undismissed advantage is the
  case that gets asked. Use the `AskUserQuestion` tool, not an inline prose question.
- Give each option a one-line consequence in its `description`: what changes, what it
  costs, what breaks if picked. Never just a label.
- Put the `(Recommended)` marker at the end of that option's `label`, never inside its
  `description`. Buried at the end of a description paragraph it is effectively
  invisible, which defeats the point of marking it. Keep the base label short so the
  marker stays readable.
- List the marked option first, whatever order the surrounding template or your own
  drafting happened to put it in. In a `multiSelect` menu the marked options lead the
  list.
- If the options are genuinely comparable (a real coin-flip, not just unexamined), mark
  none. Don't fabricate a preference to satisfy the convention.
- A template option string written `Label (best when X)`, or any equivalent
  authoring-time "recommended when" annotation, is selection guidance, not literal option
  text. Resolve which condition actually holds now, render that one option's `label` as
  `Label (Recommended)`, and move the reason into its `description`. If more than one
  condition plausibly holds at once, say so explicitly instead of silently picking one.
- In a `multiSelect` menu the label-placement rule is unchanged, but mark only when the
  recommended set is a minority. If most options should be picked, invert and mark the
  ones to skip (`(Skip: ephemeral)`). If they're all comparable, mark none and order
  strongest-first. At exactly half, treat it the same as comparable: mark none, order
  strongest-first, and don't round toward marking or skipping. A marker on 4 of 5 options
  is noise, the same invisibility failure one level up.
- Reserve prose questions for contexts where the tool isn't available. Fewer than 3
  options: one line ("X or Y? Recommend X because Z."). 3 or more options: label each
  option, bold the recommended one, and add a one-line reason below the list.

## Format (non-per-turn rows)

Defaults, not mandates. If the same information is clearer in a sentence or two of
prose, use prose. The per-turn rows (single direct answer, warning callout, multi-step
`TaskCreate` tracking, ≥3 items → table) stay inline in crisp.md.

| Situation | Use |
|---|---|
| Two alternatives | Side-by-side comparison. State the pick and why. |
| Sequence of actions | Numbered list. |
| Decision with lasting consequences | Decision + constraint + owner + revisit trigger + verification step. |
| Recurring problem or cross-team dependency | Now/later split: today's action, then the durable frame to install. |
| Nested detail under a main point | Short flat bullet list, one level only. |
| Multi-dimensional decision | Layer structures rather than pick one: table for the trade-off, numbered list for next steps, bold callouts for blockers. |
