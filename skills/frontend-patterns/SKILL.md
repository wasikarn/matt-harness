---
name: frontend-patterns
description: Frontend architecture, component design, and rendering optimization for React/TS. Use when building a React/TS frontend. Don't use for Vue/Svelte/Angular, backend (kbg:backend-patterns), or WCAG/a11y audits (kbg:accessibility).
bucket: patterns
metadata:
  origin: ECC
model: inherit
effort: high
---

# Frontend Development Patterns

Modern frontend patterns for React and performant user interfaces — component design,
state management, custom hooks, rendering performance, forms, and accessibility. Full
code for every pattern below lives in `reference.md` — this file carries the trigger
conditions and the gotchas that aren't obvious from the code alone.

**Not this skill's job:** Next.js App Router rendering/caching, Server Actions, middleware,
route handlers, or the metadata API — that's `kbg:nextjs-reviewer`. TypeScript compiler
choices and `tsconfig.json` underneath these patterns — that's `kbg:typescript-patterns`
(composes with this skill; a component using both loads this skill for the React layer and
that one for the TS layer underneath). Post-hoc review of a diff — that's
`mattpocock-skills:code-review`/`kbg:typescript-reviewer`. Non-React UI frameworks (Vue, Svelte, Angular)
have a different component model entirely and aren't covered here.

## When to Activate

- Building React components (composition, compound components, render props)
- Managing local state (`useState`, `useReducer`) or global state (Context, Zustand)
- Writing custom hooks for reusable logic (data fetching, debouncing, toggles)
- Optimizing rendering (memoization, code splitting, virtualization)
- Building and validating forms (manual validation, or Zod schemas via react-hook-form)
- Structuring error boundaries and loading/error UI states
- Building accessible keyboard navigation and focus management

## Component Patterns

- **Composition over inheritance** — small, composable pieces (`Card`/`CardHeader`/
  `CardBody`) instead of a prop-driven monolith. `reference.md#composition-over-inheritance`.
- **Compound components** — a shared context lets sibling components (`Tabs`/`TabList`/
  `Tab`) coordinate without prop drilling. `reference.md#compound-components`.
- **Render props** — a component receives a function-as-children to control what it
  renders. `reference.md#render-props-pattern`.

**Race-condition guard in the render-props data loader:** without a `cancelled` flag set
in the effect's cleanup, a slow response for an abandoned `url` can resolve after a newer,
faster request already set the current data — the stale response silently wins because
nothing checks which request is still current. Confirmed by direct reproduction: an effect
for 'A' (slow) started, then 'B' (fast) replaces it before 'A' resolves — without the
guard, 'A's data overwrites 'B's on screen.

## Custom Hooks Patterns

- **State management hook** — a `useToggle` wrapping `useState` + `useCallback`.
  `reference.md#state-management-hook`.
- **Async data fetching hook** — a hand-rolled `useQuery` with refetch, loading, and error
  state. `reference.md#async-data-fetching-hook`.
- **Debounce hook** — delay a value update until input settles.
  `reference.md#debounce-hook`.

**The fetching hook needs a stale-response guard, same failure mode as the render-props
loader above:** a `requestIdRef` bumped on every `refetch()` call lets a fast response for
a newer key win over a slower older one landing after it — without it, 'A' (slow) starting
before 'B' (fast) can still have 'A's result clobber 'B's once it finally resolves.
Confirmed by direct reproduction.

**Reach for TanStack Query or SWR before this hand-rolled hook in production.** The guard
above closes the race condition, but a maintained data-fetching library also gives you
request deduplication, caching, retries, and background refetching — none of which this
hook attempts. Keep `useQuery`/`useDebounce` here for the dependency-free case, or for
understanding what the library is doing underneath; don't reach for the hand-rolled
version by default once a real data-fetching library is already a viable dependency.

## State Management Patterns

- **Context + reducer** — a `useReducer` store exposed through Context.
  `reference.md#context--reducer-pattern`.
- **Zustand vs Context** — a selector-based store for global state.
  `reference.md#global-state-zustand-vs-context`.

Every consumer of a context re-renders on any update to that context's value — a
`MarketProvider` covering a large subtree means every component calling `useMarkets()`
re-renders when *any* field in `state` changes, even fields it never reads. Zustand's
selector API sidesteps this: a component subscribes to exactly the slice it reads (a
component selecting `markets` only re-renders when `markets` itself changes, not on every
store update).

Reach for Context when the state is genuinely scoped to one part of the tree (a `Tabs`
group, a `Modal`) and doesn't need cross-tree access. Reach for Zustand when the state is
global (current user, feature flags, a shopping cart) and unrelated parts of the tree read
different slices of it.

## Performance Optimization

- **Memoization** — `useMemo`/`useCallback`/`React.memo` for expensive computations, stable
  callback identity, and pure components. `reference.md#memoization`.
- **Code splitting & lazy loading** — `lazy()` + `Suspense` for heavy components.
  `reference.md#code-splitting--lazy-loading`.
- **Virtualization** — render only the visible slice of a long list.
  `reference.md#virtualization-for-long-lists`.

Real row content (a card with a variable-length name/description) rarely matches a fixed
size estimate exactly. Leaving the row's height hardcoded to the estimate clips or
overlaps any row whose actual content runs taller than the guess; wiring
`ref={virtualizer.measureElement}` and dropping the hardcoded height lets each row's real
rendered height correct the layout instead. Skip `measureElement` only when every row is
genuinely fixed-height by design (a table row with `overflow: hidden` and no wrapping
text) — that's the exception, not the default, and the fixed-size version is slightly
cheaper when it truly applies.

## Form Handling Patterns

- **Manual validation** — proportionate for a one- or two-field form.
  `reference.md#manual-validation-small-forms`.
- **Schema-validated forms (Zod + react-hook-form)** — the recommended default once a
  form grows past a couple of fields. `reference.md#schema-validated-forms-with-zod--react-hook-form`.

Once a form has several fields, cross-field rules, or needs the same validation on both
client and server, centralize it in a Zod schema and let `react-hook-form` own field
registration and re-render scoping — and reuse that same schema to validate the payload
again on the server. Client-side validation is a UX convenience, not a security boundary;
never trust it alone.

## Error Boundary Pattern

`reference.md#error-boundary-pattern`.

An error boundary only catches errors thrown during rendering, in lifecycle methods, and in
constructors of the tree below it — not in event handlers, not in async code (a rejected
promise in a `useEffect` or an `onClick` handler), and not in the boundary component itself.
Those need their own `try/catch` or `.catch()` handling; a boundary alone won't see them.

## Animation Patterns

**Framer Motion animations** — `AnimatePresence` for enter/exit transitions on lists and
modals. `reference.md#framer-motion-animations`.

The library ships under two package names at the same version — `framer-motion` (the
original name, kept as a compatibility package) and `motion` (its current name upstream).
Either import path works; pick one per project and stay consistent.

## Accessibility Patterns

- **Keyboard navigation** — arrow-key/Enter/Escape handling for a combobox-shaped
  dropdown. `reference.md#keyboard-navigation`.
- **Focus management** — save and restore focus around a modal open/close.
  `reference.md#focus-management`.

The keyboard-navigation example covers the keyboard skeleton, not a complete accessible
combobox: a screen-reader user also needs `aria-activedescendant` on the combobox pointing
at the active option's id, and each option needs `role="option"` plus that matching id —
without them, a sighted keyboard user sees the highlight move but a screen-reader user
hears nothing change as the active index updates.

`tabIndex={-1}` is what makes `modalRef.current?.focus()` work at all in the focus example
— a plain `<div>` isn't focusable without it. That example moves focus in and restores it
on close, but still lacks a focus trap: `Tab` can move focus out of the modal and onto the
page behind it while open. A production modal needs to trap `Tab`/`Shift+Tab` within its
own focusable elements, or use a library (Radix, Headless UI) that already does.

**Remember**: Modern frontend patterns enable maintainable, performant user interfaces.
Choose patterns that fit your project complexity.

## Related

- Agent: `kbg:performance-optimizer` - once a client-side computation (not just rendering) is
  the confirmed bottleneck, for the algorithmic fix underneath it
- Skill: `kbg:accessibility` — the WCAG conformance layer and generic React a11y fixes (forms,
  labels, ARIA) this file's own Accessibility Patterns section doesn't cover

## Verify before use

1. A pattern that reads correct on paper can still hit an edge this file doesn't cover.
   Before relying on any hook or component here in production, exercise it against the
   actual failure mode it claims to handle (a fast-changing `key`/`url` for the fetching
   hooks, a rapid Tab press for the focus trap) — don't take the fix on faith for anything
   load-bearing.
2. `npm view <package> version` shows the real current version if a pattern needs to know
   whether an API (Zustand's `create`, TanStack Query's `useQuery` options, TanStack
   Virtual's `useVirtualizer`) has moved since this was written.
