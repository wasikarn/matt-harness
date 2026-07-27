---
name: frontend-patterns
description: Frontend architecture, component design, and rendering optimization for React/TS — the kept TS/frontend base. Use when building a React/TS frontend. Don't use for Vue/Svelte/Angular frontends.
metadata:
  origin: ECC
---

# Frontend Development Patterns

Modern frontend patterns for React and performant user interfaces — component design,
state management, custom hooks, rendering performance, forms, and accessibility.

**Not this skill's job:** Next.js App Router rendering/caching, Server Actions, middleware,
route handlers, or the metadata API — that's `kbg:nextjs-reviewer`. TypeScript compiler
choices and `tsconfig.json` underneath these patterns — that's `kbg:typescript-patterns`
(composes with this skill; a component using both loads this skill for the React layer and
that one for the TS layer underneath). Post-hoc review of a diff — that's
`kbg:code-reviewer`/`kbg:typescript-reviewer`. Non-React UI frameworks (Vue, Svelte, Angular)
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

### Composition Over Inheritance

```typescript
// PASS: GOOD: Component composition
interface CardProps {
  children: React.ReactNode
  variant?: 'default' | 'outlined'
}

export function Card({ children, variant = 'default' }: CardProps) {
  return <div className={`card card-${variant}`}>{children}</div>
}

export function CardHeader({ children }: { children: React.ReactNode }) {
  return <div className="card-header">{children}</div>
}

export function CardBody({ children }: { children: React.ReactNode }) {
  return <div className="card-body">{children}</div>
}

// Usage
<Card>
  <CardHeader>Title</CardHeader>
  <CardBody>Content</CardBody>
</Card>
```

### Compound Components

```typescript
interface TabsContextValue {
  activeTab: string
  setActiveTab: (tab: string) => void
}

const TabsContext = createContext<TabsContextValue | undefined>(undefined)

export function Tabs({ children, defaultTab }: {
  children: React.ReactNode
  defaultTab: string
}) {
  const [activeTab, setActiveTab] = useState(defaultTab)

  return (
    <TabsContext.Provider value={{ activeTab, setActiveTab }}>
      {children}
    </TabsContext.Provider>
  )
}

export function TabList({ children }: { children: React.ReactNode }) {
  return <div className="tab-list">{children}</div>
}

export function Tab({ id, children }: { id: string, children: React.ReactNode }) {
  const context = useContext(TabsContext)
  if (!context) throw new Error('Tab must be used within Tabs')

  return (
    <button
      className={context.activeTab === id ? 'active' : ''}
      onClick={() => context.setActiveTab(id)}
    >
      {children}
    </button>
  )
}

// Usage
<Tabs defaultTab="overview">
  <TabList>
    <Tab id="overview">Overview</Tab>
    <Tab id="details">Details</Tab>
  </TabList>
</Tabs>
```

### Render Props Pattern

```typescript
interface DataLoaderProps<T> {
  url: string
  children: (data: T | null, loading: boolean, error: Error | null) => React.ReactNode
}

export function DataLoader<T>({ url, children }: DataLoaderProps<T>) {
  const [data, setData] = useState<T | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  useEffect(() => {
    let cancelled = false
    setLoading(true)

    fetch(url)
      .then(res => res.json())
      .then(result => { if (!cancelled) setData(result) })
      .catch(err => { if (!cancelled) setError(err) })
      .finally(() => { if (!cancelled) setLoading(false) })

    // Without this flag, a slow response for an abandoned `url` can resolve
    // after a newer, faster request already set the current data — the
    // stale response silently wins because nothing checks which request is
    // still current. Confirmed by direct reproduction: an effect for
    // 'A' (slow) started, then 'B' (fast) replaces it before 'A' resolves —
    // without the guard, 'A's data overwrites 'B's on screen.
    return () => { cancelled = true }
  }, [url])

  return <>{children(data, loading, error)}</>
}

// Usage
<DataLoader<Market[]> url="/api/markets">
  {(markets, loading, error) => {
    if (loading) return <Spinner />
    if (error) return <Error error={error} />
    return <MarketList markets={markets!} />
  }}
</DataLoader>
```

## Custom Hooks Patterns

### State Management Hook

```typescript
export function useToggle(initialValue = false): [boolean, () => void] {
  const [value, setValue] = useState(initialValue)

  const toggle = useCallback(() => {
    setValue(v => !v)
  }, [])

  return [value, toggle]
}

// Usage
const [isOpen, toggleOpen] = useToggle()
```

### Async Data Fetching Hook

```typescript
interface UseQueryOptions<T> {
  onSuccess?: (data: T) => void
  onError?: (error: Error) => void
  enabled?: boolean
}

export function useQuery<T>(
  key: string,
  fetcher: () => Promise<T>,
  options?: UseQueryOptions<T>
) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [loading, setLoading] = useState(false)

  // Keep the latest fetcher/options in refs so refetch stays referentially
  // stable even when callers pass inline functions and object literals.
  // Without this, every render creates a new refetch, and the effect below
  // re-runs after each state update - an infinite fetch loop.
  const fetcherRef = useRef(fetcher)
  const optionsRef = useRef(options)
  useEffect(() => {
    fetcherRef.current = fetcher
    optionsRef.current = options
  })

  // Bumped on every refetch() call. refetch is a stable useCallback (not
  // re-created per key), so nothing else marks a call "abandoned" when key
  // changes mid-flight — a stale call compares its captured id against the
  // live ref before touching state, so a fast response for a newer key
  // can't be clobbered by a slower older one landing after it. Confirmed by
  // direct reproduction: 'A' (slow) starts, 'B' (fast) starts 10ms later —
  // without this guard, 'A's result overwrites 'B's.
  const requestIdRef = useRef(0)

  const refetch = useCallback(async () => {
    const requestId = ++requestIdRef.current
    setLoading(true)
    setError(null)

    try {
      const result = await fetcherRef.current()
      if (requestIdRef.current !== requestId) return
      setData(result)
      optionsRef.current?.onSuccess?.(result)
    } catch (err) {
      if (requestIdRef.current !== requestId) return
      const error = err as Error
      setError(error)
      optionsRef.current?.onError?.(error)
    } finally {
      if (requestIdRef.current === requestId) setLoading(false)
    }
  }, [])

  const enabled = options?.enabled !== false

  useEffect(() => {
    if (enabled) {
      refetch()
    }
  }, [key, enabled, refetch])

  return { data, error, loading, refetch }
}

// Usage
const { data: markets, loading, error, refetch } = useQuery(
  'markets',
  () => fetch('/api/markets').then(r => r.json()),
  {
    onSuccess: data => console.log('Fetched', data.length, 'markets'),
    onError: err => console.error('Failed:', err)
  }
)
```

**Reach for TanStack Query or SWR before this hand-rolled hook in production.** The guard
above closes the race condition, but a maintained data-fetching library also gives you
request deduplication, caching, retries, and background refetching — none of which this hook
attempts. Keep `useQuery`/`useDebounce` here for the dependency-free case, or for
understanding what the library is doing underneath; don't reach for the hand-rolled version
by default once a real data-fetching library is already a viable dependency.

### Debounce Hook

```typescript
export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value)

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value)
    }, delay)

    return () => clearTimeout(handler)
  }, [value, delay])

  return debouncedValue
}

// Usage
const [searchQuery, setSearchQuery] = useState('')
const debouncedQuery = useDebounce(searchQuery, 500)

useEffect(() => {
  // The `if (debouncedQuery)` guard only skips the pointless fetch on initial
  // mount (empty string, nothing to search yet). Drop it if clearing the box
  // should reset the list back to unfiltered results -- keeping it here would
  // leave the previous search's results on screen after the user clears input.
  if (debouncedQuery) {
    performSearch(debouncedQuery)
  }
}, [debouncedQuery])
```

## State Management Patterns

### Context + Reducer Pattern

```typescript
interface State {
  markets: Market[]
  selectedMarket: Market | null
  loading: boolean
}

type Action =
  | { type: 'SET_MARKETS'; payload: Market[] }
  | { type: 'SELECT_MARKET'; payload: Market }
  | { type: 'SET_LOADING'; payload: boolean }

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'SET_MARKETS':
      return { ...state, markets: action.payload }
    case 'SELECT_MARKET':
      return { ...state, selectedMarket: action.payload }
    case 'SET_LOADING':
      return { ...state, loading: action.payload }
    default:
      return state
  }
}

const MarketContext = createContext<{
  state: State
  dispatch: Dispatch<Action>
} | undefined>(undefined)

export function MarketProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(reducer, {
    markets: [],
    selectedMarket: null,
    loading: false
  })

  return (
    <MarketContext.Provider value={{ state, dispatch }}>
      {children}
    </MarketContext.Provider>
  )
}

export function useMarkets() {
  const context = useContext(MarketContext)
  if (!context) throw new Error('useMarkets must be used within MarketProvider')
  return context
}
```

### Global State: Zustand vs Context

Every consumer of a context re-renders on any update to that context's value — a
`MarketProvider` covering a large subtree means every component calling `useMarkets()`
re-renders when *any* field in `state` changes, even fields it never reads. Zustand's
selector API sidesteps this: a component subscribes to exactly the slice it reads.

```typescript
interface MarketStore {
  markets: Market[]
  selectedMarketId: string | null
  setMarkets: (markets: Market[]) => void
  selectMarket: (id: string) => void
}

export const useMarketStore = create<MarketStore>((set) => ({
  markets: [],
  selectedMarketId: null,
  setMarkets: (markets) => set({ markets }),
  selectMarket: (id) => set({ selectedMarketId: id })
}))

// Usage — selector form: only re-renders when `markets` itself changes, not
// on every store update (selecting `selectedMarketId` too would also
// re-render this component whenever that field changes)
function MarketList() {
  const markets = useMarketStore(s => s.markets)
  const selectMarket = useMarketStore(s => s.selectMarket)

  return (
    <ul>
      {markets.map(m => (
        <li key={m.id} onClick={() => selectMarket(m.id)}>{m.name}</li>
      ))}
    </ul>
  )
}
```

Reach for Context when the state is genuinely scoped to one part of the tree (a `Tabs`
group, a `Modal`) and doesn't need cross-tree access. Reach for Zustand when the state is
global (current user, feature flags, a shopping cart) and unrelated parts of the tree read
different slices of it.

## Performance Optimization

### Memoization

```typescript
// PASS: useMemo for expensive computations
// Copy before sorting - Array.prototype.sort mutates in place
const sortedMarkets = useMemo(() => {
  return [...markets].sort((a, b) => b.volume - a.volume)
}, [markets])

// PASS: useCallback for functions passed to children
const handleSearch = useCallback((query: string) => {
  setSearchQuery(query)
}, [])

// PASS: React.memo for pure components
export const MarketCard = React.memo<MarketCardProps>(({ market }) => {
  return (
    <div className="market-card">
      <h3>{market.name}</h3>
      <p>{market.description}</p>
    </div>
  )
})
```

### Code Splitting & Lazy Loading

```typescript
import { lazy, Suspense } from 'react'

// PASS: Lazy load heavy components
const HeavyChart = lazy(() => import('./HeavyChart'))
const ThreeJsBackground = lazy(() => import('./ThreeJsBackground'))

export function Dashboard() {
  return (
    <div>
      <Suspense fallback={<ChartSkeleton />}>
        <HeavyChart data={data} />
      </Suspense>

      <Suspense fallback={null}>
        <ThreeJsBackground />
      </Suspense>
    </div>
  )
}
```

### Virtualization for Long Lists

```typescript
import { useRef } from 'react'
import { useVirtualizer } from '@tanstack/react-virtual'

export function VirtualMarketList({ markets }: { markets: Market[] }) {
  const parentRef = useRef<HTMLDivElement>(null)

  const virtualizer = useVirtualizer({
    count: markets.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 100,  // Initial guess only -- measureElement below corrects it per row
    overscan: 5,  // Extra items to render
    // Key by the market's own id, not the row index. If `markets` can change
    // identity under the same index (a new search, a reorder, an item
    // removed), an index key makes React reuse a row's DOM node for a
    // different market -- any per-row local state or in-flight animation
    // sticks to the wrong item.
    getItemKey: index => markets[index].id
  })

  return (
    <div ref={parentRef} style={{ height: '600px', overflow: 'auto' }}>
      <div
        style={{
          height: `${virtualizer.getTotalSize()}px`,
          position: 'relative'
        }}
      >
        {virtualizer.getVirtualItems().map(virtualRow => (
          <div
            key={virtualRow.key}
            data-index={virtualRow.index}
            ref={virtualizer.measureElement}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              transform: `translateY(${virtualRow.start}px)`
            }}
          >
            <MarketCard market={markets[virtualRow.index]} />
          </div>
        ))}
      </div>
    </div>
  )
}
```

Real row content (a card with a variable-length name/description) rarely matches a fixed
estimate exactly. Leaving the row's height hardcoded to `virtualRow.size` -- the estimate --
clips or overlaps any row whose actual content runs taller than the guess; wiring
`ref={virtualizer.measureElement}` and dropping the hardcoded height lets each row's real
rendered height correct the layout instead. Skip `measureElement` only when every row is
genuinely fixed-height by design (a table row with `overflow: hidden` and no wrapping text) --
that's the exception, not the default, and the fixed-size version is slightly cheaper when it
truly applies.

## Form Handling Patterns

### Manual Validation (small forms)

```typescript
interface FormData {
  name: string
  description: string
  endDate: string
}

interface FormErrors {
  name?: string
  description?: string
  endDate?: string
}

export function CreateMarketForm() {
  const [formData, setFormData] = useState<FormData>({
    name: '',
    description: '',
    endDate: ''
  })

  const [errors, setErrors] = useState<FormErrors>({})

  const validate = (): boolean => {
    const newErrors: FormErrors = {}

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required'
    } else if (formData.name.length > 200) {
      newErrors.name = 'Name must be under 200 characters'
    }

    if (!formData.description.trim()) {
      newErrors.description = 'Description is required'
    }

    if (!formData.endDate) {
      newErrors.endDate = 'End date is required'
    }

    setErrors(newErrors)
    return Object.keys(newErrors).length === 0
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!validate()) return

    try {
      await createMarket(formData)
      // Success handling
    } catch (error) {
      // Error handling
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      <input
        value={formData.name}
        onChange={e => setFormData(prev => ({ ...prev, name: e.target.value }))}
        placeholder="Market name"
      />
      {errors.name && <span className="error">{errors.name}</span>}

      {/* Other fields */}

      <button type="submit">Create Market</button>
    </form>
  )
}
```

### Schema-Validated Forms with Zod + react-hook-form (recommended default)

```typescript
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const createMarketSchema = z.object({
  name: z.string().trim().min(1, 'Name is required').max(200, 'Name must be under 200 characters'),
  description: z.string().trim().min(1, 'Description is required'),
  endDate: z.string().min(1, 'End date is required')
})

type CreateMarketFormValues = z.infer<typeof createMarketSchema>

export function CreateMarketForm() {
  const {
    register,
    handleSubmit,
    formState: { errors }
  } = useForm<CreateMarketFormValues>({
    resolver: zodResolver(createMarketSchema)
  })

  const onSubmit = handleSubmit(async (values) => {
    await createMarket(values)
  })

  return (
    <form onSubmit={onSubmit}>
      <input {...register('name')} placeholder="Market name" />
      {errors.name && <span className="error">{errors.name.message}</span>}

      <textarea {...register('description')} placeholder="Description" />
      {errors.description && <span className="error">{errors.description.message}</span>}

      <input {...register('endDate')} type="date" />
      {errors.endDate && <span className="error">{errors.endDate.message}</span>}

      <button type="submit">Create Market</button>
    </form>
  )
}
```

Manual state and validation (above) is proportionate for a one- or two-field form. Once a
form has several fields, cross-field rules, or needs the same validation on both client and
server, centralize it in a Zod schema and let `react-hook-form` own field registration and
re-render scoping — and reuse that same schema to validate the payload again on the server.
Client-side validation is a UX convenience, not a security boundary; never trust it alone.

## Error Boundary Pattern

```typescript
interface ErrorBoundaryState {
  hasError: boolean
  error: Error | null
}

export class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  ErrorBoundaryState
> {
  state: ErrorBoundaryState = {
    hasError: false,
    error: null
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('Error boundary caught:', error, errorInfo)
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="error-fallback">
          <h2>Something went wrong</h2>
          <p>{this.state.error?.message}</p>
          <button onClick={() => this.setState({ hasError: false })}>
            Try again
          </button>
        </div>
      )
    }

    return this.props.children
  }
}

// Usage
<ErrorBoundary>
  <App />
</ErrorBoundary>
```

An error boundary only catches errors thrown during rendering, in lifecycle methods, and in
constructors of the tree below it — not in event handlers, not in async code (a rejected
promise in a `useEffect` or an `onClick` handler), and not in the boundary component itself.
Those need their own `try/catch` or `.catch()` handling; a boundary alone won't see them.

## Animation Patterns

### Framer Motion Animations

```typescript
import { motion, AnimatePresence } from 'framer-motion'

// PASS: List animations
export function AnimatedMarketList({ markets }: { markets: Market[] }) {
  return (
    <AnimatePresence>
      {markets.map(market => (
        <motion.div
          key={market.id}
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -20 }}
          transition={{ duration: 0.3 }}
        >
          <MarketCard market={market} />
        </motion.div>
      ))}
    </AnimatePresence>
  )
}

// PASS: Modal animations
export function Modal({ isOpen, onClose, children }: ModalProps) {
  return (
    <AnimatePresence>
      {isOpen && (
        <>
          <motion.div
            className="modal-overlay"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />
          <motion.div
            className="modal-content"
            initial={{ opacity: 0, scale: 0.9, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 20 }}
          >
            {children}
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
```

The library ships under two package names at the same version — `framer-motion` (the
original name, kept as a compatibility package) and `motion` (its current name upstream).
Either import path works; pick one per project and stay consistent.

## Accessibility Patterns

### Keyboard Navigation

```typescript
export function Dropdown({ options, onSelect }: DropdownProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)

  const handleKeyDown = (e: React.KeyboardEvent) => {
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault()
        setActiveIndex(i => Math.min(i + 1, options.length - 1))
        break
      case 'ArrowUp':
        e.preventDefault()
        setActiveIndex(i => Math.max(i - 1, 0))
        break
      case 'Enter':
        e.preventDefault()
        onSelect(options[activeIndex])
        setIsOpen(false)
        break
      case 'Escape':
        setIsOpen(false)
        break
    }
  }

  return (
    <div
      role="combobox"
      aria-expanded={isOpen}
      aria-haspopup="listbox"
      onKeyDown={handleKeyDown}
    >
      {/* Dropdown implementation */}
    </div>
  )
}
```

This covers the keyboard-navigation skeleton, not a complete accessible combobox: a
screen-reader user also needs `aria-activedescendant` on the combobox pointing at the active
option's id, and each option needs `role="option"` plus that matching id — without them, a
sighted keyboard user sees the highlight move but a screen-reader user hears nothing change
as `activeIndex` updates.

### Focus Management

```typescript
export function Modal({ isOpen, onClose, children }: ModalProps) {
  const modalRef = useRef<HTMLDivElement>(null)
  const previousFocusRef = useRef<HTMLElement | null>(null)

  useEffect(() => {
    if (isOpen) {
      // Save currently focused element
      previousFocusRef.current = document.activeElement as HTMLElement

      // Focus modal
      modalRef.current?.focus()
    } else {
      // Restore focus when closing
      previousFocusRef.current?.focus()
    }
  }, [isOpen])

  return isOpen ? (
    <div
      ref={modalRef}
      role="dialog"
      aria-modal="true"
      tabIndex={-1}
      onKeyDown={e => e.key === 'Escape' && onClose()}
    >
      {children}
    </div>
  ) : null
}
```

`tabIndex={-1}` is what makes `modalRef.current?.focus()` work at all — a plain `<div>` isn't
focusable without it. This example moves focus in and restores it on close, but still lacks a
focus trap: `Tab` can move focus out of the modal and onto the page behind it while open. A
production modal needs to trap `Tab`/`Shift+Tab` within its own focusable elements, or use a
library (Radix, Headless UI) that already does.

**Remember**: Modern frontend patterns enable maintainable, performant user interfaces.
Choose patterns that fit your project complexity.

## Verify before use

1. A pattern that reads correct on paper can still hit an edge this file doesn't cover.
   Before relying on any hook or component here in production, exercise it against the
   actual failure mode it claims to handle (a fast-changing `key`/`url` for the fetching
   hooks, a rapid Tab press for the focus trap) — don't take the fix on faith for anything
   load-bearing.
2. `npm view <package> version` shows the real current version if a pattern needs to know
   whether an API (Zustand's `create`, TanStack Query's `useQuery` options, TanStack
   Virtual's `useVirtualizer`) has moved since this was written.
