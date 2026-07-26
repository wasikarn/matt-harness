---
name: typescript-patterns
description: "TypeScript patterns: type-modeling idioms and tsconfig choices compatible across 5.9-7.x. Use for compiler-option or type-shape decisions. Don't use for routine .ts edits or backend architecture."
---

# TypeScript Language Patterns

This covers the **language and compiler** layer — type-system idioms and `tsconfig.json`
choices — underneath whichever framework skill also applies. It composes with those; it
doesn't replace them. A service using both `backend-patterns` and Drizzle loads
`kbg:backend-patterns` and `kbg:drizzle-patterns` for their frameworks, plus this skill for
the TypeScript underneath.

**Not this skill's job:** API/DB architecture on a plain Node/Express/Next.js backend —
that's `kbg:backend-patterns`. Post-hoc review of a diff — that's `kbg:typescript-reviewer`.
This skill is what informs the code at write time; the reviewer checks it afterward.

## When to Activate

This is gated on a decision, not a file extension — most `.ts` edits touch neither a
`tsconfig.json` nor a type-modeling choice and don't need this skill loaded.

- Creating or changing a `tsconfig.json`
- Choosing between `any`, `unknown`, or a generic for a new type
- Modeling a value that can be one of several distinct shapes (state machines, API
  responses, discriminated payloads)
- Deciding compiler strictness or module settings for a new project or package

## The version line: what "5.9–7.x compatible" actually means

TypeScript 7 is not a new language — it's the same TypeScript 6.0 semantics running on a
compiler rewritten in Go (codename Corsa). **This is no longer a future concern: TypeScript
7.0 reached general availability on the main `typescript` npm package** (7.0.2, with 7.1.0
already in nightly `-dev` builds), and the old JavaScript-hosted compiler's own repository
states plainly that TypeScript 6.0 was its last release — all TypeScript development now
happens in the Go rewrite. `npx tsc --version` today resolves to the Go-built binary; the
`@typescript/native-preview` package (binary `tsgo`) continues in parallel as the bleeding-edge
nightly channel. A fixed list of legacy compiler options already failed the build **by
default** on TypeScript 6.0 — confirmed directly against a real 6.0.3 install, these were
`error TS5107`/`TS5101`, not warnings, with `"ignoreDeprecations": "6.0"` as the only escape
hatch — and TypeScript 7.0 removes that escape hatch entirely, confirmed the same way against
the actual GA release. So "compatible across 5.9–7.x" reduces to one rule: avoid this set, and
every version from 5.9 onward accepts the same code and config unchanged, no
`ignoreDeprecations` flag required.

Source: TypeScript's own `checkDeprecations("6.0", "7.0", ...)` in `src/compiler/program.ts`
(the 6.0-era JS-hosted compiler) and `typescript-go`'s `SkipUnsupportedCompilerOptions` test
helper — both lists match exactly, and both were verified by actually running
`typescript@6.0.3` and current `typescript` (7.0.2) against a deliberately non-compliant
`tsconfig.json`.

| Compiler option | Status in 6.0 | Status in 7.0 (GA) | Use instead |
|---|---|---|---|
| `target: "ES5"` | error by default (`ignoreDeprecations` opts out) | hard error, no opt-out | `"es2022"` or `"esnext"` |
| `moduleResolution: "node10"` | error by default | hard error, no opt-out | `"bundler"` or `"nodenext"` |
| `moduleResolution: "classic"` | error by default | hard error, no opt-out | `"bundler"` or `"nodenext"` |
| `baseUrl` | error by default | hard error, no opt-out | `"paths"` without `baseUrl` — path values then resolve relative to the `tsconfig.json` directory, but must start with `./` or `../` (e.g. `"@/*": ["./src/*"]`, not `["src/*"]`) |
| `outFile` | error by default | hard error, no opt-out | per-file emit, or a bundler |
| `module: "amd" \| "umd" \| "system"` | error by default | hard error, no opt-out | `"esnext"`, `"commonjs"`, or `"nodenext"` |
| `esModuleInterop: false` | error by default | must be `true` | `esModuleInterop: true` |
| `allowSyntheticDefaultImports: false` | error by default | hard error, no opt-out | drop the override — `esModuleInterop: true` implies it |
| `alwaysStrict: false` | error by default | hard error, no opt-out | drop the override; `strict: true` implies it |
| `downlevelIteration` | error by default | moot | a modern `target` (ES2015+) makes it unnecessary |

**Migrating an existing project off `baseUrl`:** the `paths` values need the `./`/`../` prefix
added at the same time — dropping `baseUrl` without fixing the paths is a second, separate
compile error (`TS5090: Non-relative paths are not allowed. Did you forget a leading './'?`).
Both fixes ship in the same change: `"@/*": ["src/*"]` becomes `"@/*": ["./src/*"]`.

A minimal future-proof `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "es2022",
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  }
}
```

Swap `"nodenext"` for `"bundler"` when a bundler (Vite, esbuild, webpack) owns the build —
everything else in the table still applies.

**Real migration risk, not a style nit:** if the project has `.js` files that lean on
JSDoc-typed Closure-style annotations, or emits `.d.ts` declarations from `.js` sources,
flag it before touching that code. `tsgo`'s JavaScript support is intentionally trimmed
relative to the JS-hosted compiler — Closure header support and much of the declaration-emit
behavior for `.js` input differ on purpose. That gap is an architecture decision (rewrite the
annotations in TypeScript, or stay on the JS-hosted compiler for that package) above this
skill's scope — surface it, don't silently paper over it.

## Type-system idioms

### `unknown`, not `any`, at boundaries

```typescript
// FAIL: any disables checking for everything downstream of payload
function handleAny(payload: any) {
  return payload.items.map((i: any) => i.id)
}

// PASS: unknown forces a narrowing step before any property access
function handleUnknown(payload: unknown) {
  if (!isItemPayload(payload)) throw new Error('invalid payload')
  return payload.items.map((i) => i.id)
}
```

### Discriminated unions need a compile-time exhaustiveness check

A `switch` over a discriminated union that doesn't assign the unmatched case to `never` will
compile even after a new variant is added and forgotten — the missing branch fails silently
at runtime instead of at build time.

```typescript
type Result =
  | { status: 'ok'; data: string }
  | { status: 'error'; message: string }
  | { status: 'pending' }

function render(r: Result): string {
  switch (r.status) {
    case 'ok':
      return r.data
    case 'error':
      return r.message
    case 'pending':
      return 'Loading...'
    default:
      // If a new Result variant is added and this switch isn't updated, `r`
      // is no longer `never` here — the assignment fails to compile.
      const exhaustive: never = r
      return exhaustive
  }
}
```

### `satisfies` checks the shape without widening the type

```typescript
// FAIL: the explicit annotation widens every value to `string`,
// losing the literal keys for autocomplete
const paletteAnnotated: Record<string, string> = { red: '#f00', green: '#0f0' }

// PASS: satisfies validates against Record<string, string> but keeps
// the inferred literal type, so palette.red still narrows correctly
const palette = { red: '#f00', green: '#0f0' } satisfies Record<string, string>
```

### Branded types for values that share a runtime shape but not a domain

Two IDs that are both plain strings at runtime are still different things — a branded type
makes passing one where the other belongs a compile error instead of a production incident.

```typescript
type UserId = string & { readonly __brand: 'UserId' }
type OrderId = string & { readonly __brand: 'OrderId' }

function toUserId(id: string): UserId {
  return id as UserId
}

function loadUser(id: UserId) {
  /* ... */
}

// FAIL: passing an OrderId here is a real bug, and a plain `string`
// parameter would let it through silently. The branded parameter type
// makes it a compile error instead.
```

## Verify before use

1. A pattern that reads as forward-compatible on paper can still hit an edge this table
   doesn't cover. Before relying on a version-compatibility claim from this file, run
   `tsc --noEmit` against the actual code with the actual `typescript` version the project
   pins (`npm view typescript version` for current GA; pin an exact version rather than
   trusting a floating range on a compiler line this young) — don't take the table on faith
   for anything load-bearing.
2. `npm view typescript versions` shows the real GA history if a project needs to know
   exactly when a given deprecation became a hard error, or whether a newer `7.x` has shipped
   since this was written.

Done when the chosen idiom or tsconfig change compiles clean under `tsc --noEmit` on the
project's actual pinned `typescript` version — that's the check this skill can't do for you.
