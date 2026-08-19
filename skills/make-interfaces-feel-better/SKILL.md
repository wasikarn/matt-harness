---
name: make-interfaces-feel-better
description: Catalog of UI-polish details — spacing, borders, shadows, motion, hit areas, text wrapping. Use when a UI feels flat. Don't use for direction choices (kbg:frontend-design-direction).
bucket: design
metadata:
  origin: community PR #1659 (via ECC)
---

# Make Interfaces Feel Better

The small design-engineering details that compound into a polished interface.

Source: salvaged from a stale community PR (#1659, author `linus707`) — vendored via ECC, not
authored by ECC itself.

## When to Activate

- The UI feels off, flat, generic, cramped, jumpy, or unfinished.
- Building controls, cards, lists, dashboards, navigation, forms, or toolbars.
- A component needs hover, active, focus, enter, exit, loading, or empty states.
- A frontend review needs specific before/after recommendations.

## Core Principles

### Concentric Radius

For nearby nested rounded surfaces: `outer radius = inner radius + padding`. If padding is
large, treat the layers as separate surfaces instead of forcing the math — the goal is optical
coherence, not formula worship.

### Optical Alignment

Geometric centering isn't always visual centering. Icon buttons, play triangles, arrows, stars,
and asymmetric icons often need a small offset. Fix the SVG when possible; otherwise adjust with
a pixel-level margin or padding change.

### Shadows and Borders

Use borders for separation and focus rings. Use layered shadows when a card, button, dropdown,
or popover needs depth. Keep shadows transparent and subtle enough to work across backgrounds.

### Text Wrapping

- `text-wrap: balance` on headings and short titles.
- `text-wrap: pretty` on short-to-medium body text, captions, descriptions, and list items.
- Avoid both on long prose, code, and preformatted content.
- `font-variant-numeric: tabular-nums` for counters, timers, prices, tables, and other updating
  numbers.

### Font Smoothing

On macOS, apply antialiased font smoothing at the root layout when the project doesn't already:

```css
html {
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
```

### Image Outlines

Images often need a subtle inset outline so their edges don't blur into the surface. Use neutral
black/white alpha — don't tint image outlines with the brand palette.

```css
img {
  outline: 1px solid rgba(0, 0, 0, 0.1);
  outline-offset: -1px;
}
@media (prefers-color-scheme: dark) {
  img { outline-color: rgba(255, 255, 255, 0.1); }
}
```

### Motion

Use CSS transitions for interactive state changes — they retarget when the user changes intent
mid-motion. Reserve keyframes for staged one-shot entrances or loading sequences.

Good defaults: enter with opacity + small `translateY` (optionally blur); exit shorter and
quieter than enter (~150ms); press with `scale(0.96)` for tactile buttons, with a way to disable
it when the movement distracts; cross-fade icon swaps with opacity/scale/blur instead of instant
visibility toggles.

### Transition Scope

Never use `transition: all` — specify the changed properties:

```css
.button {
  transition-property: transform, background-color, box-shadow;
  transition-duration: 150ms;
  transition-timing-function: ease-out;
}
```

Use `will-change` only for first-frame stutter on compositor-friendly properties (`transform`,
`opacity`, `filter`). Never `will-change: all`.

### Hit Areas

Interactive controls need at least a 40×40px hit area, ideally 44×44px where layout allows — an
ergonomic comfort target above WCAG's 24×24px compliance floor (SC 2.5.8), not a replacement for
it. Expand with a pseudo-element when the visible icon is smaller than that — don't let expanded
hit areas overlap each other.

## Review Output

Report concrete changes in before/after rows, with file paths and properties when they aren't
obvious from the snippets. Omit principles you checked but didn't need to change.

| Principle | Before | After |
| --- | --- | --- |
| Concentric radius | Same radius on parent and child | Parent radius accounts for padding |
| Tabular numbers | Counter shifts as digits change | Counter uses `tabular-nums` |
| Transition scope | `transition: all` | Explicit transition properties |

## Checklist

- [ ] Nested rounded elements are optically coherent.
- [ ] Icons are visually centered.
- [ ] Buttons, cards, and popovers use borders/shadows for a reason, not decoration.
- [ ] Headings and short text avoid awkward wrapping.
- [ ] Dynamic numbers use tabular numerals.
- [ ] Images have neutral outlines where needed.
- [ ] Enter/exit animations are split, subtle, and interruptible where appropriate.
- [ ] Buttons have tactile active states without exaggerated motion.
- [ ] `transition: all` and `will-change: all` are absent.
- [ ] Small controls still have usable hit areas.

## Verify before use

Don't take a before/after row on faith — confirm each change by rendering the component (both
color schemes if the fix touches shadows/outlines, and at least one narrow viewport if it touches
hit areas or wrapping) before marking the checklist item done.

## Related

- Skill: `kbg:frontend-design-direction` — run that first to set the overall visual/interaction
  direction; this skill polishes the details once components already exist.
- Skill: `kbg:accessibility` — hit-area and focus-indicator requirements here overlap WCAG SC
  2.5.8 (Target Size, AA) and SC 2.4.13 (Focus Appearance, AAA) — check both when either applies.
