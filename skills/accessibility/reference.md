# Accessibility — React/Next.js code reference

Full code for the patterns `SKILL.md` triggers on. Keyboard-nav combobox and modal
focus-restoration examples live in `mh:frontend-patterns/reference.md` instead of here — see that
skill's `#keyboard-navigation` and `#focus-management` anchors.

## Form Accessibility

Missing `htmlFor`/`id` pairing and disconnected error messages are the most common issues flagged
in code review.

### Label Connection

```tsx
// BAD: label has no connection to input — screen readers cannot associate them
<label>Email</label>
<input type="email" />

// GOOD: htmlFor matches input id
<label htmlFor="email">Email</label>
<input id="email" type="email" />
```

### Required Fields

```tsx
// BAD: visual-only asterisk conveys nothing to screen readers
<label htmlFor="email">Email *</label>
<input id="email" type="email" />

// GOOD: required enables native browser validation; aria-required signals it to screen readers
<label htmlFor="email">
  Email <span aria-hidden="true">*</span>
</label>
<input id="email" type="email" required aria-required="true" />
```

### Error Messages

```tsx
// BAD: error text exists visually but is not linked to the input
<input id="email" type="email" />
<span className="error">Invalid email address</span>

// GOOD: aria-describedby connects input to its error message
// aria-invalid signals the invalid state to screen readers
<input
  id="email"
  type="email"
  aria-describedby="email-error"
  aria-invalid={!!error}
/>
{error && (
  <span id="email-error" role="alert">
    {error}
  </span>
)}
```

### Complete Accessible Form

```tsx
interface LoginFormProps {
  onSubmit: (email: string, password: string) => void;
}

export function LoginForm({ onSubmit }: LoginFormProps) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({});

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const newErrors: typeof errors = {};
    if (!email) newErrors.email = 'Email is required';
    if (!password) newErrors.password = 'Password is required';
    if (Object.keys(newErrors).length) {
      setErrors(newErrors);
      return;
    }
    onSubmit(email, password);
  };

  return (
    <form onSubmit={handleSubmit} noValidate>
      <div>
        <label htmlFor="email">
          Email <span aria-hidden="true">*</span>
        </label>
        <input
          id="email"
          type="email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          aria-required="true"
          aria-describedby={errors.email ? 'email-error' : undefined}
          aria-invalid={!!errors.email}
          autoComplete="email"
        />
        {errors.email && (
          <span id="email-error" role="alert">
            {errors.email}
          </span>
        )}
      </div>

      <div>
        <label htmlFor="password">
          Password <span aria-hidden="true">*</span>
        </label>
        <input
          id="password"
          type="password"
          value={password}
          onChange={e => setPassword(e.target.value)}
          aria-required="true"
          aria-describedby={errors.password ? 'password-error' : undefined}
          aria-invalid={!!errors.password}
          autoComplete="current-password"
        />
        {errors.password && (
          <span id="password-error" role="alert">
            {errors.password}
          </span>
        )}
      </div>

      <button type="submit">Log in</button>
    </form>
  );
}
```

## Semantic HTML

Use the element that matches the intent — screen readers and keyboard users depend on native
semantics.

```tsx
// BAD: div has no role, no keyboard support, no accessible name
<div onClick={handleClick}>Submit</div>
// GOOD: button is focusable, activates on Enter/Space, announces as "button"
<button type="button" onClick={handleClick}>Submit</button>

// BAD: non-semantic navigation — no right-click, middle-click, or keyboard support
<div onClick={() => navigate('/home')}>Home</div>
// GOOD: anchor supports all of those natively
<a href="/home">Home</a>

// BAD: heading hierarchy skipped (h1 to h4)
<h1>Dashboard</h1>
<h4>Recent Activity</h4>
// GOOD: sequential heading levels
<h1>Dashboard</h1>
<h2>Recent Activity</h2>
```

## ARIA Attribute Reference

Use ARIA only when native HTML semantics are insufficient — wrong ARIA is worse than no ARIA.

```tsx
// aria-label: inline string label — use when no visible label text exists
<button aria-label="Close modal"><XIcon /></button>

// aria-labelledby: references another element's text — use when a visible label exists
<section aria-labelledby="section-title">
  <h2 id="section-title">Recent Orders</h2>
</section>

// aria-describedby: supplementary description beyond the label
<button aria-describedby="delete-warning" onClick={handleDelete}>Delete account</button>
<p id="delete-warning">This action cannot be undone.</p>
```

### `aria-live` for dynamic content

`role="status"` carries an implicit `aria-live="polite"` and waits for the user to finish their
current action before announcing; `role="alert"` carries an implicit `aria-live="assertive"` and
interrupts immediately — reserve it for urgent errors. Switch the role itself rather than
overriding `aria-live` on a fixed role — `status` is spec-defined as advisory info that isn't
urgent enough to interrupt, so forcing `assertive` onto it fights the role's own semantics.

```tsx
export function StatusMessage({ message, isError }: { message: string; isError?: boolean }) {
  return (
    <div role={isError ? 'alert' : 'status'} aria-atomic="true">
      {message}
    </div>
  );
}
```

### `aria-expanded` / `aria-controls`

```tsx
export function Accordion({ title, children }: { title: string; children: React.ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);
  const contentId = useId();

  return (
    <div>
      <button aria-expanded={isOpen} aria-controls={contentId} onClick={() => setIsOpen(p => !p)}>
        {title}
      </button>
      <div id={contentId} hidden={!isOpen}>{children}</div>
    </div>
  );
}
```

## Images and Icons

```tsx
// BAD: decorative icon announced as unlabeled image
<img src="/icon.svg" />
// GOOD: decorative image hidden from screen readers
<img src="/decoration.png" alt="" aria-hidden="true" />
// GOOD: meaningful image with descriptive alt text
<img src="/chart.png" alt="Monthly revenue increased 23% from January to March" />
// GOOD: icon button with accessible label
<button aria-label="Delete item"><TrashIcon aria-hidden="true" /></button>
```

## Reduced Motion

```tsx
export function useReducedMotion(): boolean {
  const [prefersReduced, setPrefersReduced] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    setPrefersReduced(mq.matches);
    const handler = (e: MediaQueryListEvent) => setPrefersReduced(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  return prefersReduced;
}
```

## Code-Level Anti-Patterns

```tsx
// BAD: onClick on non-interactive element with no keyboard support
<div onClick={handleClick}>Click me</div>
// BAD: aria-label on a div that has no role
<div aria-label="Navigation">...</div>
// BAD: placeholder used as a substitute for a real label
<input placeholder="Enter your email" />
// BAD: positive tabIndex creates unpredictable tab order
<button tabIndex={3}>Submit</button>
// BAD: aria-hidden on a focusable element — keyboard users get trapped
<button aria-hidden="true">Open</button>
// BAD: role="button" on a div without a keyboard handler (missing tabIndex={0}, onKeyDown)
<div role="button" onClick={handleClick}>Submit</div>
```

## Checklist

- [ ] Every `<input>`, `<select>`, `<textarea>` has a connected `<label>` via `htmlFor`/`id`.
- [ ] Error messages are linked with `aria-describedby` and marked `role="alert"`.
- [ ] No `onClick` on `<div>`/`<span>` without `role`, `tabIndex`, and `onKeyDown`.
- [ ] Icon-only buttons have `aria-label`.
- [ ] Decorative images use `alt=""` and `aria-hidden="true"`.
- [ ] Dynamic content updates use `aria-live`.
- [ ] `prefers-reduced-motion` is respected for animations.
