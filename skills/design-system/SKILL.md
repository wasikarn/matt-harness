---
name: design-system
description: Generate or audit a design system for token/visual consistency and AI-slop detection. Use when starting a project. Don't use for scraping other sites.
metadata:
  origin: ECC
---

# Design System — Generate & Audit Visual Systems

## When to Activate

- Starting a new project that needs a design system.
- Auditing an existing codebase for visual consistency.
- Before a redesign — understand what's already there.
- The UI looks "off" but you can't pinpoint why.
- Reviewing a PR that touches styling.

## Mode 1: Generate

Scan the codebase's CSS/Tailwind/styled-components for existing patterns, extract colors,
typography, spacing, border-radius, shadows, and breakpoints, then propose a coherent token set.
Write it up as:

- `DESIGN.md` — the token set with rationale for each decision.
- `design-tokens.json` — the tokens as data (CSS custom properties or a JS/TS token module,
  whichever the project already uses).

Don't invent tokens from nothing — extract what the codebase already leans toward and make it
explicit and consistent, filling gaps only where no existing pattern exists.

## Mode 2: Visual Audit

Score the UI across 10 dimensions (0–10 each), each with specific examples and a fix pointing to
an exact `file:line`:

1. **Color consistency** — palette values or random hex codes?
2. **Typography hierarchy** — clear h1 > h2 > h3 > body > caption?
3. **Spacing rhythm** — a consistent scale (4px/8px/16px) or arbitrary values?
4. **Component consistency** — do similar elements look similar?
5. **Responsive behavior** — fluid, or broken at breakpoints?
6. **Dark mode** — complete, or half-done?
7. **Animation** — purposeful, or gratuitous?
8. **Accessibility** — contrast ratios, focus states, touch targets.
9. **Information density** — cluttered, or clean?
10. **Polish** — hover states, transitions, loading states, empty states.

## Mode 3: AI-Slop Detection

Flag generic AI-generated design patterns specifically:

- Gratuitous gradients on everything.
- Purple-to-blue defaults.
- "Glass morphism" cards with no functional purpose.
- Rounded corners on elements that shouldn't be rounded.
- Excessive scroll-triggered animation.
- A generic hero with centered text over a stock gradient.
- A sans-serif font stack with no personality.

## Verify before use

A 10-dimension score or a proposed token set only means something once it's checked against the
live UI — render the `design-preview.html` output (or the audited pages) at a couple of real
breakpoints and confirm the tokens actually render as scored before calling the pass done.

## Related

- Skill: `kbg:frontend-design-direction` — the design-judgment layer this skill's tokens and
  audit scores get measured against; run that first when there's no direction yet to audit
  against.
- Skill: `kbg:make-interfaces-feel-better` — concrete polish fixes for dimension 10 (Polish)
  findings.
- Skill: `firecrawl-website-design-clone` — extracting a *different* site's design system from
  its live pages. This skill only reads the current project's own codebase.
