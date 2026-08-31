---
name: accessibility
description: WCAG 2.2 AA accessibility, ARIA patterns, React a11y fixes for forms/focus/keyboard nav. Use when building web UI. Don't use for React architecture (mh:frontend-patterns).
metadata:
  origin: ECC + community (via ECC)
model: inherit
effort: high
---

# Accessibility (WCAG 2.2)

Ensures Web interfaces are Perceivable, Operable, Understandable, and Robust (POUR) for users on
screen readers, switch controls, or keyboard-only navigation. This skill covers the conceptual
WCAG layer and the React/Next.js code fixes most commonly flagged in code review; full code
examples live in `reference.md`.

Web-scoped only — kbg's fleet has no native-mobile (iOS/Android) skills or agents, so this skill
doesn't cover SwiftUI/Compose accessibility traits. If that changes, port the cross-platform
mapping from ECC's own `accessibility` skill at that point rather than carrying unused content
now.

## When to Activate

- Defining or reviewing a UI component's accessibility spec.
- Auditing existing code for accessibility barriers or WCAG gaps.
- Building or reviewing forms, modals, dropdowns, tooltips, or tabs.
- Adding `aria-*` attributes to any element, or reviewing PRs with a11y feedback (CodeRabbit,
  ESLint a11y plugin).
- Implementing newer WCAG 2.2 criteria — Target Size (Minimum), Focus Appearance, Redundant
  Entry.

## Core Concepts

- **POUR** — Perceivable, Operable, Understandable, Robust: WCAG's four foundational principles.
- **Semantic mapping** — native elements (`<button>`, `<a>`) over generic containers; native
  elements carry built-in accessibility for free.
- **Accessibility tree** — the representation of the UI assistive technologies actually read,
  distinct from the visual DOM.
- **Focus management** — controlling the order and visibility of the keyboard/screen-reader
  cursor.

## Web Implementation Checklist

- Text contrast meets **4.5:1** (normal text) or **3:1** (large text/UI components).
- Content reflows at up to **400% zoom** without loss of function.
- Interactive elements meet a minimum **24×24 CSS pixel** target size (WCAG 2.2 SC 2.5.8).
- Every interactive element is keyboard-reachable with a visible focus indicator (SC 2.4.7).
- Dragging interactions offer a single-pointer alternative.
- Error messages are descriptive and suggest a correction (SC 3.3.3).
- Forms don't ask for the same data twice across a flow (Redundant Entry, SC 3.3.7).
- Dynamic status updates use `aria-live` or a live region.

## Anti-Patterns

- **Div-buttons** — a `<div>`/`<span>` with a click handler and no role or keyboard support.
- **Color-only meaning** — signaling error/status with color alone (e.g. a red border with no
  icon or text).
- **Uncontained modal focus** — a modal that doesn't trap `Tab`/`Shift+Tab`, letting keyboard
  users reach the page behind it while it's open. Focus must be contained *and* escapable via
  `Escape` or a close button (SC 2.1.2).
- **Redundant alt text** — "Image of…" or "Picture of…" in `alt` text; screen readers already
  announce the image role.

## Best Practices Checklist

- [ ] Interactive elements meet the 24×24px target size.
- [ ] Focus indicators are clearly visible and high-contrast.
- [ ] Modals contain focus while open and release it cleanly on close.
- [ ] Dropdowns and menus restore focus to their trigger element on close.
- [ ] Forms provide text-based error suggestions.
- [ ] All icon-only buttons have a descriptive text label.
- [ ] Content reflows properly when text is scaled.

Full React/Next.js code — form labeling, ARIA attribute reference, semantic HTML swaps, images,
`prefers-reduced-motion` — lives in `reference.md`.

## Verify before use

A checklist item marked done still needs confirming with an actual assistive-tech pass — run
`axe-core`/Lighthouse and, for anything load-bearing (a modal, a form flow), a real screen reader
or keyboard-only pass. A component that "looks compliant" against the checklist can still fail
in practice if `aria-live` timing or focus order doesn't match what the markup implies.

## Related

- Skill: `mh:frontend-patterns` — already covers the keyboard-nav combobox
  (`mh:frontend-patterns/reference.md#keyboard-navigation`) and modal focus-restoration
  (`mh:frontend-patterns/reference.md#focus-management`) examples; this skill doesn't duplicate those.
- Skill: `mh:design-system` — dimension 8 (Accessibility) of its visual audit reads on this
  skill's checklist.
- This skill IS the fleet's accessibility audit surface — the former `a11y-architect` agent
  (deleted 2026-09-01, near-verbatim overdub of this checklist) has no successor; work the
  checklist inline or hand this file's path to a dispatched general-purpose agent.

## References

- [WCAG 2.2 Guidelines](https://www.w3.org/TR/WCAG22/)
- [WAI-ARIA Authoring Practices](https://www.w3.org/TR/wai-aria-practices/)
