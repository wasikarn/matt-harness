---
name: frontend-design-direction
description: "Frontend-design-direction: typography, layout, tone, and motion. Use when building or restyling UI. Don't use for React architecture (kbg:frontend-patterns) or HTML artifacts (plannotator-effective-html)."
bucket: design
metadata:
  origin: community PR #1659 (via ECC)
---

# Frontend Design Direction

Use this skill when the work is not just making UI function, but making it feel purposeful,
polished, and appropriate to the product domain.

Source: salvaged from a stale community PR (#1659, author `linus707`) — vendored via ECC, not
authored by ECC itself. Anthropic ships its own `frontend-design` skill under `anthropics/skills`;
install that separately if you want the official upstream version. This skill is a distinct,
smaller salvage of the same idea, not a substitute for it.

## When to Activate

- Building a web page, app, dashboard, artifact, or component from scratch.
- Making an existing interface more polished, distinctive, or less generic.
- Choosing visual hierarchy, typography, color, motion, layout, or interaction direction.
- The current UI works but reads as flat, generic, templated, or mismatched to its audience.

## Design Direction

Decide these five things before writing markup:

1. **Purpose** — what job does the interface do?
2. **Audience** — who repeats this workflow, and what do they need to scan first?
3. **Tone** — utilitarian, editorial, playful, industrial, refined, technical, maximal, minimal,
   dense, calm, or another explicit direction.
4. **Memorable detail** — one design idea that makes the result feel intentional.
5. **Constraints** — framework, accessibility, performance, responsiveness, existing design
   system.

Match the direction to the domain. A SaaS operations tool should usually be dense, quiet, and
scannable. A portfolio, launch page, or editorial piece can be more expressive. Don't force a
landing-page composition onto a tool built for repeated daily use.

## Implementation Guidance

- Build the actual usable experience as the first screen, not marketing copy, unless the user
  explicitly asked for the latter.
- Use existing project components, tokens, icon libraries, and routing patterns before
  introducing a new visual system.
- Use real or generated visual assets when the interface depends on images, products, places,
  people, or inspectable media.
- Prefer contextual typography and spacing over generic oversized hero text.
- Keep palettes multi-dimensional — avoid a UI dominated by one hue family.
- Use CSS variables or existing design tokens so the direction stays coherent across states.
- Design responsive constraints explicitly: grids, aspect ratios, min/max sizes, stable
  toolbars, and fixed-format controls shouldn't shift when labels or hover states appear.
- Use motion sparingly and deliberately — prefer high-signal transitions that clarify state
  over decorative animation.
- Verify text fit on mobile and desktop. Long labels must wrap or resize cleanly, not overflow.

## Anti-Patterns

- Purple gradients, decorative blobs, oversized cards, vague hero copy, or stock-like
  atmospheric media as the default.
- Cards nested inside other cards.
- One decorative style everywhere when the domain calls for restraint.
- Hiding the primary product, tool, or workflow behind generic marketing sections.
- A new dependency for a design flourish that doesn't clearly pay for itself.
- Describing the UI's features inside the UI when the controls can speak for themselves.

## Review Checklist

- [ ] The first viewport immediately communicates the product, workflow, or object.
- [ ] Visual hierarchy supports scanning and repeated use.
- [ ] Typography fits its container without overlapping adjacent content.
- [ ] Color choices have contrast and don't collapse into a one-note palette.
- [ ] Icons are used for familiar tool actions where available.
- [ ] Responsive layout has stable dimensions for boards, grids, toolbars, and counters.
- [ ] Assets render and carry the subject matter instead of acting as filler.
- [ ] Motion improves orientation and doesn't mask sluggishness.
- [ ] The result matches the repo's existing frontend conventions unless there's a clear reason
      to depart.

## Related

- Skill: `kbg:design-system` — once a direction is chosen, audit or generate the token set that
  encodes it project-wide.
- Skill: `kbg:make-interfaces-feel-better` — the polish-detail checklist for after the direction
  is set and the components exist.
- Skill: `kbg:frontend-patterns` — the React component/state/rendering architecture underneath
  whatever this skill decides the UI should look like.
